import Fluent
import FluentMySQLDriver
import FluentSQLiteDriver
import Vapor

public func configure(_ app: Application) async throws {
    DotEnv.load()

    configureDatabase(app)
    app.http.server.configuration.hostname = Environment.get("APP_HOST") ?? "127.0.0.1"
    if let port = Environment.get("APP_PORT").flatMap(Int.init) {
        app.http.server.configuration.port = port
    }
    app.migrations.add(CreateUser())
    app.migrations.add(CreatePost())
    app.migrations.add(CreateUserCredential())
    app.migrations.add(CreateAuthToken())
    app.migrations.add(CreateRefreshToken())
    app.migrations.add(CreatePasswordResetToken())
    app.migrations.add(CreateEmailVerificationToken())
    app.migrations.add(CreateMfaChallenge())
    app.migrations.add(CreateRolesAndPermissions())
    app.migrations.add(CreateComment())
    app.migrations.add(CreateRateLimitEntry())

    MorphRegistry.register(User.self)
    MorphRegistry.register(Post.self)

    let viewsDirectory = app.directory.workingDirectory + "Resources/Views/"
    app.views.use(.swiftBlade(rootDirectory: viewsDirectory))

    app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))
    app.middleware.use(ErrorMiddleware.default(environment: app.environment))
    app.middleware.use(EloquentMiddleware())

    registerCommands(app)
    try routes(app)
}

private func configureDatabase(_ app: Application) {
    // Testes usam SQLite em memória, exceto a suíte de integração MySQL
    // (SWIFTRA_MYSQL_TEST=1), que executa contra um servidor real.
    if app.environment == .testing && Environment.get("SWIFTRA_MYSQL_TEST") != "1" {
        app.databases.use(.sqlite(.memory), as: .sqlite)
        return
    }

    switch (Environment.get("DB_CONNECTION") ?? "sqlite").lowercased() {
    case "mysql":
        // DB_TLS=required liga TLS verificado (produção). O padrão `disabled`
        // atende servidores locais/docker com certificado autoassinado.
        let tls: TLSConfiguration? = (Environment.get("DB_TLS") ?? "disabled").lowercased() == "required"
            ? .makeClientConfiguration()
            : nil
        app.databases.use(
            .mysql(
                hostname: Environment.get("DB_HOST") ?? "127.0.0.1",
                port: Environment.get("DB_PORT").flatMap(Int.init) ?? 3306,
                username: Environment.get("DB_USERNAME") ?? "root",
                password: Environment.get("DB_PASSWORD") ?? "",
                database: Environment.get("DB_DATABASE") ?? "swiftra",
                tlsConfiguration: tls
            ),
            as: .mysql
        )
    default:
        let databasePath = Environment.get("DB_PATH") ?? "swiftra.sqlite"
        app.databases.use(.sqlite(.file(databasePath)), as: .sqlite)
    }
}
