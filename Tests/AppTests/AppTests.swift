import App
import Fluent
import Testing
import VaporTesting

@Suite("Swiftra application")
struct AppTests {
    @Test("Welcome page renders SwiftBlade variables")
    func welcome() async throws {
        try await withApp { app in
            let response = try await app.testing().sendRequest(.GET, "")
            #expect(response.status == .ok)
            #expect(response.body.string.contains("Swiftra"))
            #expect(response.body.string.contains("It works!"))
        }
    }

    @Test("Controller renders a view using compact data")
    func controllerView() async throws {
        try await withApp { app in
            let response = try await app.testing().sendRequest(.GET, "users")
            #expect(response.status == .ok)
            #expect(response.body.string.contains("Usuários"))
            #expect(response.body.string.contains("view(..., compact(...))"))
        }
    }

    @Test("User CRUD")
    func userCRUD() async throws {
        try await withApp { app in
            let created = try await app.testing().sendRequest(.POST, "api/users", beforeRequest: { request async throws in
                try request.content.encode(UserInput(name: "Taylor", email: "taylor@example.com"))
            })
            #expect(created.status == .created)
            let user = try created.content.decode(User.self)
            let id = try #require(user.id)

            let response = try await app.testing().sendRequest(.GET, "api/users")
            #expect(response.status == .ok)
            #expect(response.body.string.contains("taylor@example.com"))

            let shown = try await app.testing().sendRequest(.GET, "api/users/\(id)")
            #expect(shown.status == .ok)

            let updated = try await app.testing().sendRequest(.PUT, "api/users/\(id)", beforeRequest: { request async throws in
                try request.content.encode(UserInput(name: "Taylor Updated", email: "taylor@example.com"))
            })
            #expect(updated.status == .ok)
            #expect(updated.body.string.contains("Taylor Updated"))

            let deleted = try await app.testing().sendRequest(.DELETE, "api/users/\(id)")
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
        let app = try await Application.make(.testing)
        app.databases.use(.sqlite(.memory), as: .sqlite)
        try await configure(app)
        app.databases.use(.sqlite(.memory), as: .sqlite)
        try await app.autoMigrate()
        defer { Task { try await app.asyncShutdown() } }
        try await test(app)
    }
}
