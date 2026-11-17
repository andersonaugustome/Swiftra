import Fluent
import Foundation
import Vapor

/// Gerador de dados falsos mínimos, no espírito do Faker do Laravel.
public enum Faker {
    private static let firstNames = ["Taylor", "Ada", "Grace", "Linus", "Margaret", "Alan", "Barbara", "Donald", "Edsger", "Radia", "Katherine", "Dennis"]
    private static let lastNames = ["Otwell", "Lovelace", "Hopper", "Torvalds", "Hamilton", "Turing", "Liskov", "Knuth", "Dijkstra", "Perlman", "Johnson", "Ritchie"]
    private static let words = ["swift", "laravel", "vapor", "fluent", "blade", "eloquent", "server", "swiftra", "codigo", "framework", "template", "banco"]

    public static func name() -> String {
        "\(firstNames.randomElement() ?? "Taylor") \(lastNames.randomElement() ?? "Otwell")"
    }

    public static func email() -> String {
        let user = name().lowercased().replacingOccurrences(of: " ", with: ".")
        return "\(user).\(UUID().uuidString.prefix(8))@example.com"
    }

    public static func word() -> String { words.randomElement() ?? "swiftra" }

    public static func sentence(_ count: Int = 6) -> String {
        let text = (0..<count).map { _ in word() }.joined(separator: " ")
        return text.prefix(1).uppercased() + text.dropFirst() + "."
    }

    public static func number(in range: ClosedRange<Int> = 1...1000) -> Int {
        Int.random(in: range)
    }

    public static func boolean() -> Bool { Bool.random() }
}

/// Factory de models, no estilo das factories do Laravel.
///
/// ```swift
/// final class UserFactory: ModelFactory<User> {
///     override func definition() -> User {
///         User(name: Faker.name(), email: Faker.email())
///     }
/// }
/// let users = try await UserFactory().count(3).create(on: db)
/// ```
open class ModelFactory<M: EloquentModel>: @unchecked Sendable {
    private var transformations: [(inout M) -> Void] = []
    private var amount: Int?

    public init() {}

    /// Definição base da model. Sobrescreva nas subclasses.
    open func definition() -> M {
        fatalError("ModelFactory subclasses must override definition()")
    }

    @discardableResult
    public func count(_ amount: Int) -> Self {
        self.amount = amount
        return self
    }

    /// Estado nomeado: `factory.state { $0.name = "Admin" }`.
    @discardableResult
    public func state(_ transform: @escaping (inout M) -> Void) -> Self {
        transformations.append(transform)
        return self
    }

    public func make() -> M {
        var model = definition()
        for transform in transformations { transform(&model) }
        return model
    }

    public func makeMany() -> [M] {
        (0..<(amount ?? 1)).map { _ in make() }
    }

    @discardableResult
    public func create(on database: (any Database)? = nil) async throws -> M {
        let model = make()
        try await model.save(on: database ?? EloquentContext.requireDatabase())
        return model
    }

    public func createMany(on database: (any Database)? = nil) async throws -> [M] {
        let database = database ?? EloquentContext.requireDatabase()
        var models: [M] = []
        for model in makeMany() {
            try await model.save(on: database)
            models.append(model)
        }
        return models
    }
}
