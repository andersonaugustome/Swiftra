import App
import Fluent
import Foundation
import Testing
import VaporTesting

/// App de teste compartilhada: SQLite em memória + limites generosos
/// (o rate limiter tem testes próprios, focados).
func withSwiftraApp(_ test: (Application) async throws -> Void) async throws {
    setenv("APP_ENV", "testing", 1)
    setenv("RATE_LIMIT_AUTH_MAX", "1000", 1)
    setenv("RATE_LIMIT_API_MAX", "1000", 1)
    let app = try await Application.make(.testing)
    try await configure(app)
    try await app.autoMigrate()
    defer { Task { try await app.asyncShutdown() } }
    try await test(app)
}

/// Registra um usuário e devolve a sessão (access + refresh tokens).
func registerSession(
    on app: Application,
    name: String = "Authenticated User",
    email: String,
    password: String = "secret123"
) async throws -> AuthResponse {
    let response = try await app.testing().sendRequest(.POST, "api/auth/register", beforeRequest: { request async throws in
        try request.content.encode(RegisterInput(
            name: name,
            email: email,
            password: password,
            passwordConfirmation: password
        ))
    })
    #expect(response.status == .created)
    return try response.content.decode(AuthResponse.self)
}

func bearer(_ session: AuthResponse) -> HTTPHeaders {
    var headers = HTTPHeaders()
    headers.bearerAuthorization = .init(token: session.token)
    return headers
}

func bearer(token: String) -> HTTPHeaders {
    var headers = HTTPHeaders()
    headers.bearerAuthorization = .init(token: token)
    return headers
}

@Suite("Swiftra application")
struct AppTests {
    @Test("Welcome page renders SwiftBlade variables")
    func welcome() async throws {
        try await withApp { app in
            let response = try await app.testing().sendRequest(.GET, "")
            #expect(response.status == .ok)
            #expect(response.body.string.contains("Swiftra"))
            #expect(response.body.string.contains("It works!"))
            #expect(response.body.string.contains("alert-success"))
        }
    }

    @Test("Controller renders a view using compact data")
    func controllerView() async throws {
        try await withApp { app in
            let user = User(name: "Blade User", email: "blade@example.com")
            try await user.save(on: app.db)

            let response = try await app.testing().sendRequest(.GET, "users")
            #expect(response.status == .ok)
            #expect(response.body.string.contains("Usuários"))
            #expect(response.body.string.contains("Blade User"))
            #expect(response.body.string.contains("blade@example.com"))
            #expect(response.body.string.contains("1 usuário(s)"))
        }
    }

    @Test("User CRUD requires authentication and admin role to delete")
    func userCRUD() async throws {
        try await withApp { app in
            let anonymous = try await app.testing().sendRequest(.GET, "api/users")
            #expect(anonymous.status == .unauthorized)

            let session = try await registerSession(on: app, email: "crud@example.com")
            let headers = bearer(session)

            let created = try await app.testing().sendRequest(.POST, "api/users", headers: headers, beforeRequest: { request async throws in
                try request.content.encode(UserInput(name: "Taylor", email: "taylor@example.com"))
            })
            #expect(created.status == .created)
            let createdUser = try created.content.decode(UserResource.self)
            let id = try #require(createdUser.id)

            let response = try await app.testing().sendRequest(.GET, "api/users", headers: headers)
            #expect(response.status == .ok)
            #expect(response.body.string.contains("taylor@example.com"))
            #expect(response.body.string.contains("\"current_page\":1"))
            #expect(response.body.string.contains("\"total\":2"))

            let shown = try await app.testing().sendRequest(.GET, "api/users/\(id)", headers: headers)
            #expect(shown.status == .ok)

            let updated = try await app.testing().sendRequest(.PUT, "api/users/\(id)", headers: headers, beforeRequest: { request async throws in
                try request.content.encode(UserInput(name: "Taylor Updated", email: "taylor@example.com"))
            })
            #expect(updated.status == .ok)
            #expect(updated.body.string.contains("Taylor Updated"))

            // Usuário comum não pode excluir.
            let forbidden = try await app.testing().sendRequest(.DELETE, "api/users/\(id)", headers: headers)
            #expect(forbidden.status == .forbidden)

            // Admin pode.
            let registeredUser = try #require(try await User.on(app.db).where("email", "crud@example.com").first())
            _ = try await registeredUser.assignRole("admin", on: app.db)

            let deleted = try await app.testing().sendRequest(.DELETE, "api/users/\(id)", headers: headers)
            #expect(deleted.status == .noContent)
        }
    }

    @Test("Eloquent inner and left joins")
    func joins() async throws {
        try await withApp { app in
            let user = User(name: "Taylor", email: "join@example.com")
            try await user.save(on: app.db)
            let userId = try #require(user.id)
            try await Post(userId: userId, title: "Building Swiftra").save(on: app.db)
            try await User(name: "No Posts", email: "empty@example.com").save(on: app.db)

            let rows = try await User.on(app.db)
                .join(Post.self, "posts.user_id", "=", "users.id")
                .where("posts.title", "Building Swiftra")
                .orderBy("users.name")
                .getJoined(Post.self)

            #expect(rows.count == 1)
            #expect(rows.first?.base.email == "join@example.com")
            #expect(rows.first?.joined.title == "Building Swiftra")

            let leftRows = try await User.on(app.db)
                .leftJoin(Post.self, "posts.user_id", "users.id")
                .orderBy("users.name")
                .getJoinedOptional(Post.self)

            #expect(leftRows.count == 2)
            #expect(leftRows.contains { $0.base.email == "empty@example.com" && $0.joined == nil })
        }
    }

    @Test("Native bearer authentication lifecycle")
    func authentication() async throws {
        try await withApp { app in
            let anonymous = try await app.testing().sendRequest(.GET, "api/auth/me")
            #expect(anonymous.status == .unauthorized)

            let registered = try await app.testing().sendRequest(.POST, "api/auth/register", beforeRequest: { request async throws in
                try request.content.encode(RegisterInput(
                    name: "Authenticated User",
                    email: "AUTH@example.com",
                    password: "secret123",
                    passwordConfirmation: "secret123"
                ))
            })
            #expect(registered.status == .created)
            let registration = try registered.content.decode(AuthResponse.self)
            #expect(registration.tokenType == "Bearer")
            #expect(registration.user.email == "auth@example.com")
            #expect(!registration.refreshToken.isEmpty)
            #expect(registration.expiresIn > 0)

            let storedToken = try await AuthToken.query(on: app.db).first()
            #expect(storedToken?.tokenHash != registration.token)

            let me = try await app.testing().sendRequest(.GET, "api/auth/me", beforeRequest: { request async throws in
                request.headers.bearerAuthorization = .init(token: registration.token)
            })
            #expect(me.status == .ok)
            #expect(me.body.string.contains("auth@example.com"))

            let invalidLogin = try await app.testing().sendRequest(.POST, "api/auth/login", beforeRequest: { request async throws in
                try request.content.encode(LoginInput(email: "auth@example.com", password: "wrong-password"))
            })
            #expect(invalidLogin.status == .unauthorized)

            let loggedIn = try await app.testing().sendRequest(.POST, "api/auth/login", beforeRequest: { request async throws in
                try request.content.encode(LoginInput(email: "auth@example.com", password: "secret123"))
            })
            #expect(loggedIn.status == .ok)

            let logout = try await app.testing().sendRequest(.POST, "api/auth/logout", beforeRequest: { request async throws in
                request.headers.bearerAuthorization = .init(token: registration.token)
            })
            #expect(logout.status == .noContent)

            let afterLogout = try await app.testing().sendRequest(.GET, "api/auth/me", beforeRequest: { request async throws in
                request.headers.bearerAuthorization = .init(token: registration.token)
            })
            #expect(afterLogout.status == .unauthorized)
        }
    }

    private func withApp(_ test: (Application) async throws -> Void) async throws {
        try await withSwiftraApp(test)
    }
}
