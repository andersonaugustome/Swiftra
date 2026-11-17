import App
import Fluent
import Foundation
import Testing
import VaporTesting

/// Integração contra um MySQL real. Só executa com `SWIFTRA_MYSQL_TEST=1`
/// (ver `scripts/test-mysql.sh` e o job de CI). Sem a variável, é ignorada —
/// a suíte padrão continua rápida com SQLite em memória.
@Suite(
    "MySQL integration",
    .enabled(if: ProcessInfo.processInfo.environment["SWIFTRA_MYSQL_TEST"] == "1")
)
struct MySQLIntegrationTests {
    @Test("Migrations, auth, CRUD, joins and pagination on real MySQL")
    func mysqlSmoke() async throws {
        setenv("APP_ENV", "testing", 1)
        setenv("DB_CONNECTION", "mysql", 1)
        setenv("DB_HOST", ProcessInfo.processInfo.environment["DB_HOST"] ?? "127.0.0.1", 1)
        setenv("DB_PORT", ProcessInfo.processInfo.environment["DB_PORT"] ?? "3306", 1)
        setenv("DB_DATABASE", ProcessInfo.processInfo.environment["DB_DATABASE"] ?? "swiftra_test", 1)
        setenv("DB_USERNAME", ProcessInfo.processInfo.environment["DB_USERNAME"] ?? "root", 1)
        setenv("DB_PASSWORD", ProcessInfo.processInfo.environment["DB_PASSWORD"] ?? "", 1)
        setenv("RATE_LIMIT_AUTH_MAX", "1000", 1)
        setenv("RATE_LIMIT_API_MAX", "1000", 1)

        let databaseName = ProcessInfo.processInfo.environment["DB_DATABASE"] ?? "swiftra_test"
        #expect(databaseName.contains("test"), "Integration tests must use a test database")

        let app = try await Application.make(.testing)
        try await configure(app)
        try await app.autoMigrate()
        defer { Task { try await app.asyncShutdown() } }

        let suffix = UUID().uuidString.prefix(8).lowercased()
        let session = try await registerSession(on: app, email: "mysql-\(suffix)@example.com")

        let created = try await app.testing().sendRequest(.POST, "api/users", headers: bearer(session), beforeRequest: { request async throws in
            try request.content.encode(UserInput(name: "MySQL User", email: "mysql-user-\(suffix)@example.com"))
        })
        #expect(created.status == .created)
        let createdUser = try created.content.decode(UserResource.self)
        let userId = try #require(createdUser.id)

        try await Post(userId: userId, title: "Hello MySQL").save(on: app.db)

        let rows = try await User.on(app.db)
            .join(Post.self, "posts.user_id", "=", "users.id")
            .where("posts.title", "Hello MySQL")
            .getJoined(Post.self)
        #expect(rows.count == 1)

        let page = try await User.on(app.db).orderBy("name").paginate(page: 1, perPage: 10)
        #expect(page.total >= 2)

        let me = try await app.testing().sendRequest(.GET, "api/auth/me", headers: bearer(session))
        #expect(me.status == .ok)

        try await app.autoRevert()
    }
}
