import App
import Fluent
import Foundation
import Testing
import VaporTesting

@Suite("Auth security")
struct AuthSecurityTests {
    @Test("Refresh token rotates and reuse revokes the family")
    func refreshRotation() async throws {
        try await withSwiftraApp { app in
            let session = try await registerSession(on: app, email: "refresh@example.com")

            let refreshed = try await app.testing().sendRequest(.POST, "api/auth/refresh", beforeRequest: { request async throws in
                try request.content.encode(RefreshInput(refreshToken: session.refreshToken))
            })
            #expect(refreshed.status == .ok)
            let rotated = try refreshed.content.decode(AuthResponse.self)
            #expect(rotated.refreshToken != session.refreshToken)
            #expect(rotated.token != session.token)

            // Reuso do refresh antigo: revoga a família inteira.
            let reuse = try await app.testing().sendRequest(.POST, "api/auth/refresh", beforeRequest: { request async throws in
                try request.content.encode(RefreshInput(refreshToken: session.refreshToken))
            })
            #expect(reuse.status == .unauthorized)

            let afterReuse = try await app.testing().sendRequest(.POST, "api/auth/refresh", beforeRequest: { request async throws in
                try request.content.encode(RefreshInput(refreshToken: rotated.refreshToken))
            })
            #expect(afterReuse.status == .unauthorized)
        }
    }

    @Test("Password reset flow changes the password and revokes sessions")
    func passwordReset() async throws {
        try await withSwiftraApp { app in
            let session = try await registerSession(on: app, email: "reset@example.com", password: "old-secret-1")

            // Email inexistente recebe a mesma resposta genérica.
            let unknown = try await app.testing().sendRequest(.POST, "api/auth/forgot-password", beforeRequest: { request async throws in
                try request.content.encode(ForgotPasswordInput(email: "nobody@example.com"))
            })
            #expect(unknown.status == .ok)

            let forgot = try await app.testing().sendRequest(.POST, "api/auth/forgot-password", beforeRequest: { request async throws in
                try request.content.encode(ForgotPasswordInput(email: "reset@example.com"))
            })
            #expect(forgot.status == .ok)
            let forgotBody = try forgot.content.decode(MessageResponse.self)
            let resetToken = try #require(forgotBody.resetToken)

            let reset = try await app.testing().sendRequest(.POST, "api/auth/reset-password", beforeRequest: { request async throws in
                try request.content.encode(ResetPasswordInput(
                    token: resetToken,
                    email: "reset@example.com",
                    password: "new-secret-1",
                    passwordConfirmation: "new-secret-1"
                ))
            })
            #expect(reset.status == .ok)

            // Sessão anterior foi revogada.
            let me = try await app.testing().sendRequest(.GET, "api/auth/me", headers: bearer(session))
            #expect(me.status == .unauthorized)

            // Token de reset é de uso único.
            let secondUse = try await app.testing().sendRequest(.POST, "api/auth/reset-password", beforeRequest: { request async throws in
                try request.content.encode(ResetPasswordInput(
                    token: resetToken,
                    email: "reset@example.com",
                    password: "another-secret-1",
                    passwordConfirmation: "another-secret-1"
                ))
            })
            #expect(secondUse.status == .unprocessableEntity)

            let login = try await app.testing().sendRequest(.POST, "api/auth/login", beforeRequest: { request async throws in
                try request.content.encode(LoginInput(email: "reset@example.com", password: "new-secret-1"))
            })
            #expect(login.status == .ok)
        }
    }

    @Test("Email verification marks the user as verified")
    func emailVerification() async throws {
        try await withSwiftraApp { app in
            let session = try await registerSession(on: app, email: "verify@example.com")
            #expect(session.user.emailVerifiedAt == nil)

            let user = try #require(try await User.on(app.db).where("email", "verify@example.com").first())
            let rawToken = try await EmailVerificationService.issue(for: user, on: app.db)

            let verified = try await app.testing().sendRequest(.POST, "api/auth/verify-email", beforeRequest: { request async throws in
                try request.content.encode(VerifyEmailInput(token: rawToken))
            })
            #expect(verified.status == .ok)
            let resource = try verified.content.decode(UserResource.self)
            #expect(resource.emailVerifiedAt != nil)

            let reused = try await app.testing().sendRequest(.POST, "api/auth/verify-email", beforeRequest: { request async throws in
                try request.content.encode(VerifyEmailInput(token: rawToken))
            })
            #expect(reused.status == .unprocessableEntity)
        }
    }

    @Test("MFA TOTP gates the login and recovery codes work once")
    func mfaFlow() async throws {
        try await withSwiftraApp { app in
            var session = try await registerSession(on: app, email: "mfa@example.com")

            let setup = try await app.testing().sendRequest(.POST, "api/auth/mfa/setup", headers: bearer(session))
            #expect(setup.status == .ok)
            let setupBody = try setup.content.decode(MfaSetupResponse.self)
            #expect(setupBody.otpauthUri.hasPrefix("otpauth://totp/"))

            let code = try #require(TOTP.code(secret: setupBody.secret))
            let enable = try await app.testing().sendRequest(.POST, "api/auth/mfa/enable", headers: bearer(session), beforeRequest: { request async throws in
                try request.content.encode(MfaCodeInput(code: code))
            })
            #expect(enable.status == .ok)
            let enabled = try enable.content.decode(MfaEnabledResponse.self)
            #expect(enabled.recoveryCodes.count == 8)

            // Login agora exige o segundo fator.
            let login = try await app.testing().sendRequest(.POST, "api/auth/login", beforeRequest: { request async throws in
                try request.content.encode(LoginInput(email: "mfa@example.com", password: "secret123"))
            })
            #expect(login.status == .ok)
            let challenge = try login.content.decode(MfaRequiredResponse.self)
            #expect(challenge.mfaRequired)

            let freshCode = try #require(TOTP.code(secret: setupBody.secret))
            let completed = try await app.testing().sendRequest(.POST, "api/auth/mfa/challenge", beforeRequest: { request async throws in
                try request.content.encode(MfaChallengeInput(challengeToken: challenge.challengeToken, code: freshCode))
            })
            #expect(completed.status == .ok)
            session = try completed.content.decode(AuthResponse.self)
            #expect(!session.token.isEmpty)

            // Código de recuperação entra uma única vez.
            let recoveryLogin = try await app.testing().sendRequest(.POST, "api/auth/login", beforeRequest: { request async throws in
                try request.content.encode(LoginInput(email: "mfa@example.com", password: "secret123"))
            })
            let recoveryChallenge = try recoveryLogin.content.decode(MfaRequiredResponse.self)
            let recoveryCode = try #require(enabled.recoveryCodes.first)
            let recovered = try await app.testing().sendRequest(.POST, "api/auth/mfa/challenge", beforeRequest: { request async throws in
                try request.content.encode(MfaChallengeInput(challengeToken: recoveryChallenge.challengeToken, code: recoveryCode))
            })
            #expect(recovered.status == .ok)
        }
    }

    @Test("Roles and permissions are assigned on registration")
    func rolesAndPermissions() async throws {
        try await withSwiftraApp { app in
            _ = try await registerSession(on: app, email: "roles@example.com")

            let user = try #require(try await User.on(app.db).where("email", "roles@example.com").first())
            #expect(try await user.hasRole("user", on: app.db))
            #expect(try await user.can("users.view", on: app.db))
            #expect(try await !user.can("users.delete", on: app.db))

            _ = try await user.assignRole("admin", on: app.db)
            #expect(try await user.hasRole("admin", on: app.db))
            #expect(try await user.can("users.delete", on: app.db))

            _ = try await user.givePermissionTo("reports.export", on: app.db)
            #expect(try await user.hasPermissionTo("reports.export", on: app.db))

            try await user.removeRole("admin", on: app.db)
            #expect(try await !user.hasRole("admin", on: app.db))
        }
    }
}
