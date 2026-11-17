import Fluent
import Vapor

public struct AuthController: Controller {
    public init() {}

    // MARK: Registro e login

    public func register(req: Request) async throws -> Response {
        let input = try req.content.decode(RegisterInput.self)
        try input.validate()

        let email = input.email.lowercased()
        guard try await User.on(req.db).where("email", email).first() == nil else {
            throw Abort(.conflict, reason: "Email already registered")
        }

        let passwordHash = try await req.password.async.hash(input.password).get()
        let user = User(name: input.name, email: email)

        try await req.db.transaction { database in
            try await user.save(on: database)
            try await UserCredential(
                userId: try user.requireID(),
                passwordHash: passwordHash
            ).save(on: database)
            if try await Role.on(database).count() == 0 {
                try await AuthorizationSeeder.seed(on: database, logger: req.logger)
            }
            _ = try await user.assignRole(AuthConfig.defaultRole, on: database)
        }

        let verificationToken = try await EmailVerificationService.issue(for: user, on: req.db)
        try? await Mail.sendEmailVerification(to: email, token: verificationToken, logger: req.logger)

        if AuthConfig.requireVerifiedEmail {
            return try await RegisterPendingVerificationResponse(
                message: "Registration complete. Verify your email to continue.",
                user: UserResource(user),
                verificationToken: AppConfig.isTesting ? verificationToken : nil
            ).encodeResponse(status: .created, for: req)
        }

        let tokens = try await TokenService.issue(for: user, on: req.db)
        return try await AuthResponse(tokens: tokens, user: user).encodeResponse(status: .created, for: req)
    }

    public func login(req: Request) async throws -> Response {
        let input = try req.content.decode(LoginInput.self)
        guard let user = try await User.on(req.db).where("email", input.email.lowercased()).first(),
              let userId = user.id,
              let credential = try await UserCredential.on(req.db).where("user_id", userId).first(),
              try await req.password.async.verify(input.password, created: credential.passwordHash).get() else {
            throw Abort(.unauthorized, reason: "Invalid credentials")
        }

        if AuthConfig.requireVerifiedEmail && !user.emailVerified {
            throw Abort(.forbidden, reason: "Email address is not verified")
        }

        if credential.mfaEnabled {
            let challenge = try await MfaService.issueChallenge(for: user, on: req.db)
            return try await MfaRequiredResponse(
                mfaRequired: true,
                challengeToken: challenge,
                expiresAt: Date().addingTimeInterval(TimeInterval(AuthConfig.mfaChallengeTTLMinutes) * 60)
            ).encodeResponse(for: req)
        }

        let tokens = try await TokenService.issue(for: user, on: req.db)
        return try await AuthResponse(tokens: tokens, user: user).encodeResponse(for: req)
    }

    // MARK: MFA

    /// Segunda etapa do login: valida TOTP ou código de recuperação.
    public func mfaChallenge(req: Request) async throws -> Response {
        let input = try req.content.decode(MfaChallengeInput.self)
        let user = try await MfaService.consumeChallenge(token: input.challengeToken, code: input.code, on: req.db)
        let tokens = try await TokenService.issue(for: user, on: req.db)
        return try await AuthResponse(tokens: tokens, user: user).encodeResponse(for: req)
    }

    /// Inicia a configuração do MFA: devolve segredo e URI (uma única vez).
    public func mfaSetup(req: Request) async throws -> Response {
        let user = try Auth.requireUser()
        let credential = try await credential(for: user, on: req.db)
        let secret = TOTP.generateSecret()
        credential.totpSecret = secret
        credential.totpConfirmedAt = nil
        try await credential.save(on: req.db)
        return try await MfaSetupResponse(
            secret: secret,
            otpauthUri: TOTP.provisioningURI(secret: secret, account: user.email, issuer: AppConfig.name)
        ).encodeResponse(for: req)
    }

    /// Confirma o MFA com um código do autenticador e emite códigos de recuperação.
    public func mfaEnable(req: Request) async throws -> Response {
        let user = try Auth.requireUser()
        let input = try req.content.decode(MfaCodeInput.self)
        let credential = try await credential(for: user, on: req.db)
        guard let secret = credential.totpSecret, TOTP.verify(input.code, secret: secret) else {
            throw Abort(.unprocessableEntity, reason: "Invalid MFA code")
        }
        let codes = OneTimeToken.recoveryCodes()
        credential.totpConfirmedAt = Date()
        credential.recoveryCodes = codes.stored
        try await credential.save(on: req.db)
        return try await MfaEnabledResponse(mfaEnabled: true, recoveryCodes: codes.plain).encodeResponse(for: req)
    }

    public func mfaDisable(req: Request) async throws -> Response {
        let user = try Auth.requireUser()
        let input = try req.content.decode(MfaCodeInput.self)
        let credential = try await credential(for: user, on: req.db)
        guard credential.mfaEnabled, let secret = credential.totpSecret else {
            throw Abort(.unprocessableEntity, reason: "Invalid MFA code")
        }
        var mfaValid = TOTP.verify(input.code, secret: secret)
        if !mfaValid {
            mfaValid = try await MfaService.consumeRecoveryCode(input.code, credential: credential, on: req.db)
        }
        guard mfaValid else {
            throw Abort(.unprocessableEntity, reason: "Invalid MFA code")
        }
        credential.totpSecret = nil
        credential.totpConfirmedAt = nil
        credential.recoveryCodes = nil
        try await credential.save(on: req.db)
        return Response(status: .noContent)
    }

    // MARK: Tokens

    public func refresh(req: Request) async throws -> Response {
        let input = try req.content.decode(RefreshInput.self)
        let rotated = try await TokenService.rotate(refreshToken: input.refreshToken, on: req.db)
        return try await AuthResponse(tokens: rotated.tokens, user: rotated.user).encodeResponse(for: req)
    }

    public func me(req: Request) async throws -> Response {
        try await UserResource(try Auth.requireUser()).encodeResponse(for: req)
    }

    public func logout(req: Request) async throws -> Response {
        guard let token = AuthContext.token else { throw Abort(.unauthorized) }
        try await token.delete(on: req.db)
        if let input = try? req.content.decode(RefreshInput.self) {
            try await TokenService.revoke(refreshToken: input.refreshToken, on: req.db)
        }
        return Response(status: .noContent)
    }

    public func logoutAll(req: Request) async throws -> Response {
        let user = try Auth.requireUser()
        try await TokenService.revokeAll(for: try user.requireID(), on: req.db)
        return Response(status: .noContent)
    }

    // MARK: Senha

    /// Resposta sempre genérica: não revela se o email existe.
    public func forgotPassword(req: Request) async throws -> Response {
        let input = try req.content.decode(ForgotPasswordInput.self)
        let email = input.email.lowercased()
        var debugToken: String?
        if try await User.on(req.db).where("email", email).first() != nil {
            let token = try await PasswordResetService.issue(for: email, on: req.db)
            try? await Mail.sendPasswordReset(to: email, token: token, logger: req.logger)
            debugToken = AppConfig.isTesting ? token : nil
        }
        return try await MessageResponse(
            message: "If the email exists, a password reset link was sent.",
            resetToken: debugToken
        ).encodeResponse(for: req)
    }

    public func resetPassword(req: Request) async throws -> Response {
        let input = try req.content.decode(ResetPasswordInput.self)
        try input.validate()
        let user = try await PasswordResetService.consume(
            token: input.token,
            email: input.email.lowercased(),
            on: req.db
        )
        let credential = try await credential(for: user, on: req.db)
        credential.passwordHash = try await req.password.async.hash(input.password).get()
        try await credential.save(on: req.db)
        // Troca de senha encerra todas as sessões.
        try await TokenService.revokeAll(for: try user.requireID(), on: req.db)
        return try await MessageResponse(message: "Password reset successfully.").encodeResponse(for: req)
    }

    // MARK: Verificação de email

    public func verifyEmail(req: Request) async throws -> Response {
        let input = try req.content.decode(VerifyEmailInput.self)
        let user = try await EmailVerificationService.consume(token: input.token, on: req.db)
        return try await UserResource(user).encodeResponse(for: req)
    }

    public func resendVerification(req: Request) async throws -> Response {
        let user = try Auth.requireUser()
        guard !user.emailVerified else {
            return try await MessageResponse(message: "Email already verified.").encodeResponse(for: req)
        }
        let token = try await EmailVerificationService.issue(for: user, on: req.db)
        try? await Mail.sendEmailVerification(to: user.email, token: token, logger: req.logger)
        return try await MessageResponse(
            message: "Verification email sent.",
            resetToken: AppConfig.isTesting ? token : nil
        ).encodeResponse(for: req)
    }

    // MARK: helpers

    private func credential(for user: User, on database: any Database) async throws -> UserCredential {
        guard let credential = try await UserCredential.on(database).where("user_id", try user.requireID()).first() else {
            throw Abort(.unauthorized, reason: "Invalid credentials")
        }
        return credential
    }
}

// MARK: - Serviços

public enum PasswordResetService {
    @discardableResult
    public static func issue(for email: String, on database: any Database) async throws -> String {
        try await PasswordResetToken.on(database).where("email", email).deleteAll()
        let (raw, hash) = OneTimeToken.make()
        try await PasswordResetToken(
            email: email,
            tokenHash: hash,
            expiresAt: OneTimeToken.nextExpiry(minutes: AuthConfig.passwordResetTTLMinutes)
        ).save(on: database)
        return raw
    }

    public static func consume(token: String, email: String, on database: any Database) async throws -> User {
        guard let stored = try await PasswordResetToken.on(database)
                .where("email", email)
                .where("token_hash", TokenGenerator.hash(token))
                .first(),
              stored.isUsable,
              let user = try await User.on(database).where("email", email).first() else {
            throw Abort(.unprocessableEntity, reason: "Invalid or expired password reset token")
        }
        stored.usedAt = Date()
        try await stored.save(on: database)
        return user
    }
}

public enum EmailVerificationService {
    @discardableResult
    public static func issue(for user: User, on database: any Database) async throws -> String {
        let userId = try user.requireID()
        try await EmailVerificationToken.on(database).where("user_id", userId).deleteAll()
        let (raw, hash) = OneTimeToken.make()
        try await EmailVerificationToken(
            userId: userId,
            tokenHash: hash,
            expiresAt: Date().addingTimeInterval(TimeInterval(AuthConfig.emailVerificationTTLHours) * 3600)
        ).save(on: database)
        return raw
    }

    public static func consume(token: String, on database: any Database) async throws -> User {
        guard let stored = try await EmailVerificationToken.on(database)
                .where("token_hash", TokenGenerator.hash(token))
                .first(),
              stored.isUsable,
              let user = try await User.find(stored.userId, on: database) else {
            throw Abort(.unprocessableEntity, reason: "Invalid or expired verification token")
        }
        stored.usedAt = Date()
        try await stored.save(on: database)
        user.emailVerifiedAt = Date()
        try await user.save(on: database)
        return user
    }
}

public enum MfaService {
    @discardableResult
    public static func issueChallenge(for user: User, on database: any Database) async throws -> String {
        let (raw, hash) = OneTimeToken.make()
        try await MfaChallenge(
            userId: try user.requireID(),
            tokenHash: hash,
            expiresAt: OneTimeToken.nextExpiry(minutes: AuthConfig.mfaChallengeTTLMinutes)
        ).save(on: database)
        return raw
    }

    public static func consumeChallenge(token: String, code: String, on database: any Database) async throws -> User {
        guard let challenge = try await MfaChallenge.on(database)
                .where("token_hash", TokenGenerator.hash(token))
                .first(),
              challenge.isUsable,
              let user = try await User.find(challenge.userId, on: database),
              let userId = user.id,
              let credential = try await UserCredential.on(database).where("user_id", userId).first(),
              credential.mfaEnabled, let secret = credential.totpSecret else {
            throw Abort(.unauthorized, reason: "Invalid MFA challenge")
        }
        var valid = TOTP.verify(code, secret: secret)
        if !valid {
            valid = try await consumeRecoveryCode(code, credential: credential, on: database)
        }
        guard valid else {
            throw Abort(.unauthorized, reason: "Invalid MFA code")
        }
        challenge.usedAt = Date()
        try await challenge.save(on: database)
        return user
    }

    /// Código de recuperação de uso único: confere e remove da lista.
    public static func consumeRecoveryCode(_ code: String, credential: UserCredential, on database: any Database) async throws -> Bool {
        guard let stored = credential.recoveryCodes, !stored.isEmpty else { return false }
        let hash = TokenGenerator.hash(OneTimeToken.normalizeRecoveryCode(code))
        var hashes = stored.split(separator: ",").map(String.init)
        guard let index = hashes.firstIndex(of: hash) else { return false }
        hashes.remove(at: index)
        credential.recoveryCodes = hashes.joined(separator: ",")
        try await credential.save(on: database)
        return true
    }
}

// MARK: - DTOs

public struct RegisterInput: Content {
    public let name: String
    public let email: String
    public let password: String
    public let passwordConfirmation: String

    enum CodingKeys: String, CodingKey {
        case name, email, password
        case passwordConfirmation = "password_confirmation"
    }

    public init(name: String, email: String, password: String, passwordConfirmation: String) {
        self.name = name
        self.email = email
        self.password = password
        self.passwordConfirmation = passwordConfirmation
    }

    func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              email.contains("@"), password.count >= 8, password == passwordConfirmation else {
            throw Abort(.unprocessableEntity, reason: "Name, valid email, matching password confirmation, and a password of at least 8 characters are required")
        }
    }
}

public struct LoginInput: Content {
    public let email: String
    public let password: String

    public init(email: String, password: String) {
        self.email = email
        self.password = password
    }
}

public struct RefreshInput: Content {
    public let refreshToken: String

    enum CodingKeys: String, CodingKey { case refreshToken = "refresh_token" }

    public init(refreshToken: String) { self.refreshToken = refreshToken }
}

public struct ForgotPasswordInput: Content {
    public let email: String
    public init(email: String) { self.email = email }
}

public struct ResetPasswordInput: Content {
    public let token: String
    public let email: String
    public let password: String
    public let passwordConfirmation: String

    enum CodingKeys: String, CodingKey {
        case token, email, password
        case passwordConfirmation = "password_confirmation"
    }

    public init(token: String, email: String, password: String, passwordConfirmation: String) {
        self.token = token
        self.email = email
        self.password = password
        self.passwordConfirmation = passwordConfirmation
    }

    func validate() throws {
        guard email.contains("@"), password.count >= 8, password == passwordConfirmation else {
            throw Abort(.unprocessableEntity, reason: "Valid email, matching password confirmation, and a password of at least 8 characters are required")
        }
    }
}

public struct VerifyEmailInput: Content {
    public let token: String
    public init(token: String) { self.token = token }
}

public struct MfaChallengeInput: Content {
    public let challengeToken: String
    public let code: String

    enum CodingKeys: String, CodingKey {
        case challengeToken = "challenge_token"
        case code
    }

    public init(challengeToken: String, code: String) {
        self.challengeToken = challengeToken
        self.code = code
    }
}

public struct MfaCodeInput: Content {
    public let code: String
    public init(code: String) { self.code = code }
}

public struct UserResource: Content {
    public let id: UUID?
    public let name: String
    public let email: String
    public let emailVerifiedAt: Date?
    public let createdAt: Date?
    public let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, email
        case emailVerifiedAt = "email_verified_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(_ user: User) {
        id = user.id
        name = user.name
        email = user.email
        emailVerifiedAt = user.emailVerifiedAt
        createdAt = user.createdAt
        updatedAt = user.updatedAt
    }
}

/// Resposta de autenticação no formato OAuth2/Bearer, com rotação de refresh.
public struct AuthResponse: Content {
    public let token: String
    public let tokenType: String
    public let expiresAt: Date
    public let expiresIn: Int
    public let refreshToken: String
    public let refreshExpiresAt: Date
    public let user: UserResource

    enum CodingKeys: String, CodingKey {
        case token
        case tokenType = "token_type"
        case expiresAt = "expires_at"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case refreshExpiresAt = "refresh_expires_at"
        case user
    }

    public init(tokens: IssuedTokens, user: User) {
        token = tokens.accessToken
        tokenType = "Bearer"
        expiresAt = tokens.accessExpiresAt
        expiresIn = AuthConfig.accessTokenTTLMinutes * 60
        refreshToken = tokens.refreshToken
        refreshExpiresAt = tokens.refreshExpiresAt
        self.user = UserResource(user)
    }

    /// Compatibilidade com o formato anterior (access token avulso).
    public init(token: String, tokenType: String, expiresAt: Date, user: UserResource) {
        self.token = token
        self.tokenType = tokenType
        self.expiresAt = expiresAt
        expiresIn = max(Int(expiresAt.timeIntervalSinceNow), 0)
        refreshToken = ""
        refreshExpiresAt = expiresAt
        self.user = user
    }
}

public struct MfaRequiredResponse: Content {
    public let mfaRequired: Bool
    public let challengeToken: String
    public let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case mfaRequired = "mfa_required"
        case challengeToken = "challenge_token"
        case expiresAt = "expires_at"
    }
}

public struct MfaSetupResponse: Content {
    public let secret: String
    public let otpauthUri: String

    enum CodingKeys: String, CodingKey {
        case secret
        case otpauthUri = "otpauth_uri"
    }
}

public struct MfaEnabledResponse: Content {
    public let mfaEnabled: Bool
    public let recoveryCodes: [String]

    enum CodingKeys: String, CodingKey {
        case mfaEnabled = "mfa_enabled"
        case recoveryCodes = "recovery_codes"
    }
}

public struct RegisterPendingVerificationResponse: Content {
    public let message: String
    public let user: UserResource
    /// Preenchido apenas em ambiente de teste (como um mail catcher local).
    public let verificationToken: String?

    enum CodingKeys: String, CodingKey {
        case message, user
        case verificationToken = "verification_token"
    }
}

public struct MessageResponse: Content {
    public let message: String
    /// Preenchido apenas em ambiente de teste (como um mail catcher local).
    public let resetToken: String?

    enum CodingKeys: String, CodingKey {
        case message
        case resetToken = "reset_token"
    }

    public init(message: String, resetToken: String? = nil) {
        self.message = message
        self.resetToken = resetToken
    }
}
