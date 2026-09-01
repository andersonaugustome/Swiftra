import Fluent
import Vapor

public struct AuthController: Controller {
    public init() {}

    public func register(req: Request) async throws -> Response {
        let input = try req.content.decode(RegisterInput.self)
        try input.validate()

        guard try await User.on(req.db).where("email", input.email.lowercased()).first() == nil else {
            throw Abort(.conflict, reason: "Email already registered")
        }

        let passwordHash = try await req.password.async.hash(input.password).get()
        let user = User(name: input.name, email: input.email.lowercased())

        try await req.db.transaction { database in
            try await user.save(on: database)
            let credential = UserCredential(
                userId: try user.requireID(),
                passwordHash: passwordHash
            )
            try await credential.save(on: database)
        }

        let response = try await issueToken(for: user, on: req.db)
        return try await response.encodeResponse(status: .created, for: req)
    }

    public func login(req: Request) async throws -> Response {
        let input = try req.content.decode(LoginInput.self)
        guard let user = try await User.on(req.db).where("email", input.email.lowercased()).first(),
              let userId = user.id,
              let credential = try await UserCredential.on(req.db).where("user_id", userId).first(),
              try await req.password.async.verify(input.password, created: credential.passwordHash).get() else {
            throw Abort(.unauthorized, reason: "Invalid credentials")
        }

        return try await issueToken(for: user, on: req.db).encodeResponse(for: req)
    }

    public func me(req: Request) async throws -> Response {
        try await UserResource(try Auth.requireUser()).encodeResponse(for: req)
    }

    public func logout(req: Request) async throws -> Response {
        guard let token = AuthContext.token else { throw Abort(.unauthorized) }
        try await token.delete(on: req.db)
        return Response(status: .noContent)
    }

    private func issueToken(for user: User, on database: any Database) async throws -> AuthResponse {
        let rawToken = TokenGenerator.make()
        let token = AuthToken(
            userId: try user.requireID(),
            tokenHash: TokenGenerator.hash(rawToken),
            expiresAt: Date().addingTimeInterval(60 * 60 * 24 * 30)
        )
        try await token.save(on: database)
        return AuthResponse(token: rawToken, tokenType: "Bearer", expiresAt: token.expiresAt, user: UserResource(user))
    }
}

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

public struct UserResource: Content {
    public let id: UUID?
    public let name: String
    public let email: String
    public let createdAt: Date?
    public let updatedAt: Date?

    public init(_ user: User) {
        id = user.id
        name = user.name
        email = user.email
        createdAt = user.createdAt
        updatedAt = user.updatedAt
    }
}

public struct AuthResponse: Content {
    public let token: String
    public let tokenType: String
    public let expiresAt: Date
    public let user: UserResource
}
