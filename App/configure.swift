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

    let viewsDirectory = app.directory.workingDirectory + "Resources/Views/"
    app.views.use(.swiftBlade(rootDirectory: viewsDirectory))

    app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))
    app.middleware.use(ErrorMiddleware.default(environment: app.environment))
    app.middleware.use(EloquentMiddleware())

    registerCommands(app)
    try routes(app)
}

private func configureDatabase(_ app: Application) {
    if app.environment == .testing {
        app.databases.use(.sqlite(.memory), as: .sqlite)
        return
    }

    switch (Environment.get("DB_CONNECTION") ?? "sqlite").lowercased() {
    case "mysql":
        app.databases.use(
            .mysql(
                hostname: Environment.get("DB_HOST") ?? "127.0.0.1",
                port: Environment.get("DB_PORT").flatMap(Int.init) ?? 3306,
                username: Environment.get("DB_USERNAME") ?? "root",
                password: Environment.get("DB_PASSWORD") ?? "",
                database: Environment.get("DB_DATABASE") ?? "swiftra"
            ),
            as: .mysql
        )
    default:
        let databasePath = Environment.get("DB_PATH") ?? "swiftra.sqlite"
        app.databases.use(.sqlite(.file(databasePath)), as: .sqlite)
    }
}
