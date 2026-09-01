import Foundation
import Vapor

public func registerCommands(_ app: Application) {
    app.asyncCommands.use(RouteListCommand(), as: "route:list")
    app.asyncCommands.use(MakeControllerCommand(), as: "make:controller")
    app.asyncCommands.use(MakeModelCommand(), as: "make:model")
    app.asyncCommands.use(MakeMigrationCommand(), as: "make:migration")
}

struct RouteListCommand: AsyncCommand {
    struct Signature: CommandSignature {}
    var help: String { "List all registered routes" }

    func run(using context: CommandContext, signature: Signature) async throws {
        let routes = context.application.routes.all.sorted { path(for: $0) < path(for: $1) }
        context.console.output("METHOD   PATH")
        for route in routes {
            let methods = route.method.rawValue.padding(toLength: 8, withPad: " ", startingAt: 0)
            context.console.output("\(methods) \(path(for: route))")
        }
    }

    private func path(for route: Route) -> String {
        "/" + route.path.map(\.description).joined(separator: "/")
    }
}

struct NameSignature: CommandSignature {
    @Argument(name: "name", help: "Type name, optionally with subdirectories")
    var name: String
}

struct MakeControllerCommand: AsyncCommand {
    typealias Signature = NameSignature
    var help: String { "Create a controller in App/Http/Controllers" }

    func run(using context: CommandContext, signature: Signature) async throws {
        let name = sanitized(signature.name, suffix: "Controller")
        let contents = """
        import Vapor

        struct \(name): Sendable {
            func index(req: Request) async throws -> Response {
                try await ["message": "\(name)"] .encodeResponse(for: req)
            }
        }
        """
        try create(contents, at: "App/Http/Controllers/\(name).swift", console: context.console)
    }
}

struct MakeModelCommand: AsyncCommand {
    typealias Signature = NameSignature
    var help: String { "Create a Fluent model in App/Models" }

    func run(using context: CommandContext, signature: Signature) async throws {
        let name = sanitized(signature.name)
        let schema = pluralSnakeCase(name)
        let contents = """
        import Fluent
        import Vapor

        final class \(name): EloquentModel, Content, @unchecked Sendable {
            static let schema = "\(schema)"
            @ID(key: .id) var id: UUID?
            @Field(key: "name") var name: String
            init() {}
            init(id: UUID? = nil, name: String) { self.id = id; self.name = name }
        }
        """
        try create(contents, at: "App/Models/\(name).swift", console: context.console)
    }
}

struct MakeMigrationCommand: AsyncCommand {
    typealias Signature = NameSignature
    var help: String { "Create a migration in Database/Migrations" }

    func run(using context: CommandContext, signature: Signature) async throws {
        let name = sanitized(signature.name)
        let contents = """
        import Fluent

        struct \(name): AsyncMigration {
            func prepare(on database: Database) async throws {
                // Define schema changes here.
            }

            func revert(on database: Database) async throws {
                // Revert schema changes here.
            }
        }
        """
        try create(contents, at: "Database/Migrations/\(name).swift", console: context.console)
    }
}

private func sanitized(_ raw: String, suffix: String = "") -> String {
    let base = raw.split(separator: "/").last.map(String.init) ?? raw
    let clean = base.filter { $0.isLetter || $0.isNumber || $0 == "_" }
    return clean.hasSuffix(suffix) ? clean : clean + suffix
}

private func pluralSnakeCase(_ value: String) -> String {
    let snake = value.enumerated().map { index, character in
        character.isUppercase && index > 0 ? "_\(character.lowercased())" : character.lowercased()
    }.joined()
    return snake.hasSuffix("s") ? snake : snake + "s"
}

private func create(_ contents: String, at path: String, console: Console) throws {
    let url = URL(fileURLWithPath: path)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard !FileManager.default.fileExists(atPath: path) else { throw Abort(.conflict, reason: "File already exists: \(path)") }
    try (contents + "\n").write(to: url, atomically: true, encoding: .utf8)
    console.success("Created \(path)")
}
