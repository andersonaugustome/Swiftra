import Fluent
import Vapor

public enum EloquentContext {
    @TaskLocal public static var database: (any Database)?

    static func requireDatabase() -> any Database {
        guard let database else {
            preconditionFailure("No database is available. Use this query inside a request or start it with Model.on(database).")
        }
        return database
    }
}

public struct EloquentMiddleware: AsyncMiddleware {
    public init() {}

    public func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        try await EloquentContext.$database.withValue(request.db) {
            try await next.respond(to: request)
        }
    }
}

public protocol EloquentModel: Model {}

public extension EloquentModel {
    static func on(_ database: any Database) -> EloquentQuery<Self> {
        EloquentQuery(builder: Fluent.QueryBuilder<Self>(database: database))
    }

    static func query() -> EloquentQuery<Self> {
        on(EloquentContext.requireDatabase())
    }

    static func `where`<Value: Codable & Sendable>(_ column: String, _ value: Value) -> EloquentQuery<Self> {
        query().where(column, value)
    }

    static func `where`<Value: Codable & Sendable>(
        _ column: String,
        _ operation: String,
        _ value: Value
    ) -> EloquentQuery<Self> {
        query().where(column, operation, value)
    }

    static func whereIn<Value: Codable & Sendable>(_ column: String, _ values: [Value]) -> EloquentQuery<Self> {
        query().whereIn(column, values)
    }

    static func join<Joined: Model>(
        _ model: Joined.Type,
        _ firstColumn: String,
        _ operation: String,
        _ secondColumn: String
    ) -> EloquentQuery<Self> {
        query().join(model, firstColumn, operation, secondColumn)
    }

    static func join<Joined: Model>(
        _ model: Joined.Type,
        _ firstColumn: String,
        _ secondColumn: String
    ) -> EloquentQuery<Self> {
        join(model, firstColumn, "=", secondColumn)
    }

    static func leftJoin<Joined: Model>(
        _ model: Joined.Type,
        _ firstColumn: String,
        _ operation: String,
        _ secondColumn: String
    ) -> EloquentQuery<Self> {
        query().leftJoin(model, firstColumn, operation, secondColumn)
    }

    static func leftJoin<Joined: Model>(
        _ model: Joined.Type,
        _ firstColumn: String,
        _ secondColumn: String
    ) -> EloquentQuery<Self> {
        leftJoin(model, firstColumn, "=", secondColumn)
    }

    static func orderBy(_ column: String, _ direction: String = "asc") -> EloquentQuery<Self> {
        query().orderBy(column, direction)
    }

    static func get() async throws -> [Self] { try await query().get() }
    static func first() async throws -> Self? { try await query().first() }

    static func find(_ id: IDValue) async throws -> Self? {
        try await Self.find(id, on: EloquentContext.requireDatabase())
    }

    func save() async throws {
        try await save(on: EloquentContext.requireDatabase())
    }

    func delete() async throws {
        try await delete(on: EloquentContext.requireDatabase())
    }
}

public struct EloquentQuery<M: Model>: @unchecked Sendable {
    private let builder: QueryBuilder<M>

    public init(builder: QueryBuilder<M>) { self.builder = builder }

    @discardableResult
    public func `where`<Value: Codable & Sendable>(_ column: String, _ value: Value) -> Self {
        builder.filter(queryField(column), .equal, .bind(value))
        return self
    }

    @discardableResult
    public func `where`<Value: Codable & Sendable>(
        _ column: String,
        _ operation: String,
        _ value: Value
    ) -> Self {
        builder.filter(queryField(column), filterMethod(operation), .bind(value))
        return self
    }

    @discardableResult
    public func `where`<Value>(
        _ field: KeyPath<M, FieldProperty<M, Value>>,
        _ value: Value
    ) -> Self where Value: Codable & Sendable {
        builder.filter(field == value)
        return self
    }

    @discardableResult
    public func whereIn<Value: Codable & Sendable>(_ column: String, _ values: [Value]) -> Self {
        builder.filter(queryField(column), .subset(inverse: false), .bind(values))
        return self
    }

    @discardableResult
    public func join<Joined: Model>(
        _ model: Joined.Type,
        _ firstColumn: String,
        _ operation: String,
        _ secondColumn: String
    ) -> Self {
        addJoin(model, firstColumn, operation, secondColumn, method: .inner)
    }

    @discardableResult
    public func join<Joined: Model>(
        _ model: Joined.Type,
        _ firstColumn: String,
        _ secondColumn: String
    ) -> Self {
        join(model, firstColumn, "=", secondColumn)
    }

    @discardableResult
    public func leftJoin<Joined: Model>(
        _ model: Joined.Type,
        _ firstColumn: String,
        _ operation: String,
        _ secondColumn: String
    ) -> Self {
        addJoin(model, firstColumn, operation, secondColumn, method: .left)
    }

    @discardableResult
    public func leftJoin<Joined: Model>(
        _ model: Joined.Type,
        _ firstColumn: String,
        _ secondColumn: String
    ) -> Self {
        leftJoin(model, firstColumn, "=", secondColumn)
    }

    @discardableResult
    public func orderBy(_ column: String, _ direction: String = "asc") -> Self {
        builder.sort(queryField(column), sortDirection(direction))
        return self
    }

    @discardableResult
    public func orderBy<Value>(
        _ field: KeyPath<M, FieldProperty<M, Value>>,
        _ direction: DatabaseQuery.Sort.Direction = .ascending
    ) -> Self where Value: Codable & Sendable {
        builder.sort(field, direction)
        return self
    }

    @discardableResult
    public func limit(_ amount: Int) -> Self {
        builder.limit(amount)
        return self
    }

    public func first() async throws -> M? { try await builder.first() }

    public func firstOrFail() async throws -> M {
        guard let model = try await first() else { throw Abort(.notFound) }
        return model
    }

    public func get() async throws -> [M] { try await builder.all() }

    public func getJoined<Joined: Model>(_ model: Joined.Type) async throws -> [JoinedRow<M, Joined>] {
        try await builder.all().map { base in
            JoinedRow(base: base, joined: try base.joined(model))
        }
    }

    public func getJoinedOptional<Joined: Model>(_ model: Joined.Type) async throws -> [OptionalJoinedRow<M, Joined>] {
        try await builder.all().map { base in
            OptionalJoinedRow(base: base, joined: try? base.joined(model))
        }
    }
    public func count() async throws -> Int { try await builder.count() }
    public func exists() async throws -> Bool { try await first() != nil }

    private func addJoin<Joined: Model>(
        _ model: Joined.Type,
        _ firstColumn: String,
        _ operation: String,
        _ secondColumn: String,
        method: DatabaseQuery.Join.Method
    ) -> Self {
        builder.join(
            model,
            on: .advancedJoin(
                schema: Joined.schema,
                space: Joined.space,
                alias: Joined.alias,
                method,
                filters: [.field(queryField(firstColumn), filterMethod(operation), queryField(secondColumn))]
            )
        )
        return self
    }

    private func queryField(_ column: String) -> DatabaseQuery.Field {
        let parts = column.split(separator: ".", maxSplits: 1).map(String.init)
        if parts.count == 2 {
            return .extendedPath([fieldKey(parts[1])], schema: parts[0], space: nil)
        }
        return .extendedPath([fieldKey(column)], schema: M.schemaOrAlias, space: M.spaceIfNotAliased)
    }

    private func fieldKey(_ column: String) -> FieldKey {
        column == "id" || column == "_id" ? .id : .string(column)
    }

    private func filterMethod(_ value: String) -> DatabaseQuery.Filter.Method {
        switch value.trimmingCharacters(in: .whitespaces).lowercased() {
        case "=", "==": .equal
        case "!=", "<>": .notEqual
        case ">": .greaterThan
        case ">=": .greaterThanOrEqual
        case "<": .lessThan
        case "<=": .lessThanOrEqual
        case "like": .contains(inverse: false, .anywhere)
        case "not like": .contains(inverse: true, .anywhere)
        default: preconditionFailure("Unsupported where operator: \(value)")
        }
    }

    private func sortDirection(_ value: String) -> DatabaseQuery.Sort.Direction {
        switch value.lowercased() {
        case "asc", "ascending": .ascending
        case "desc", "descending": .descending
        default: preconditionFailure("Unsupported order direction: \(value)")
        }
    }
}

public struct JoinedRow<Base: Model, Joined: Model>: @unchecked Sendable {
    public let base: Base
    public let joined: Joined
}

public struct OptionalJoinedRow<Base: Model, Joined: Model>: @unchecked Sendable {
    public let base: Base
    public let joined: Joined?
}
