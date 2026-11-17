import Fluent
import Vapor

// MARK: - Contexto

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

// MARK: - Erros (sem preconditionFailure)

/// Erro de programação em consultas string-based.
///
/// Operadores, direções e colunas inválidos **não** derrubam o processo:
/// o erro é registrado na query e lançado pelo primeiro método terminal
/// (`get`, `first`, `count`, `paginate`...), como uma exceção comum.
public enum EloquentError: AbortError, Equatable {
    case invalidOperator(String)
    case invalidDirection(String)
    case invalidColumn(String)
    case invalidPagination(page: Int, perPage: Int)
    case modelNotFound(String)

    public var status: HTTPResponseStatus { .internalServerError }

    public var reason: String {
        switch self {
        case .invalidOperator(let value): "Unsupported where operator: \(value)"
        case .invalidDirection(let value): "Unsupported order direction: \(value)"
        case .invalidColumn(let value): "Invalid column name: \(value)"
        case .invalidPagination(let page, let perPage): "Invalid pagination: page=\(page), perPage=\(perPage)"
        case .modelNotFound(let model): "\(model) not found"
        }
    }
}

/// Operadores tipados — alternativa com verificação em compilação às strings.
public enum QueryOperator: String, Sendable {
    case equal = "="
    case notEqual = "!="
    case greaterThan = ">"
    case greaterThanOrEqual = ">="
    case lessThan = "<"
    case lessThanOrEqual = "<="
    case like = "like"
    case notLike = "not like"
    case ilike = "ilike"
    case startsWith = "starts_with"
    case endsWith = "ends_with"
}

/// Direção tipada de ordenação.
public enum SortDirection: Sendable {
    case asc, desc

    var fluent: DatabaseQuery.Sort.Direction {
        self == .asc ? .ascending : .descending
    }
}

// MARK: - Model

public protocol EloquentModel: Model {}

/// Model com soft deletes (`deleted_at`), no estilo do Laravel.
///
/// O Fluent já exclui registros apagados das consultas quando existe um
/// `@Timestamp(key: "deleted_at", on: .delete)`; este protocolo adiciona a
/// API declarativa (`restore`, `forceDelete`, `trashed`, `withTrashed`...).
public protocol SoftDeletableModel: EloquentModel {
    var deletedAt: Date? { get }
}

public extension SoftDeletableModel {
    var trashed: Bool { deletedAt != nil }

    func restore() async throws {
        try await restore(on: EloquentContext.requireDatabase())
    }

    func forceDelete() async throws {
        try await delete(force: true, on: EloquentContext.requireDatabase())
    }
}

public extension EloquentModel {
    static func on(_ database: any Database) -> EloquentQuery<Self> {
        EloquentQuery(builder: Fluent.QueryBuilder<Self>(database: database))
    }

    static func query() -> EloquentQuery<Self> {
        on(EloquentContext.requireDatabase())
    }

    /// Escape hatch: acesso direto ao `QueryBuilder` do Fluent.
    static func fluentQuery() -> QueryBuilder<Self> {
        query().fluentQuery
    }

    static func all() async throws -> [Self] { try await query().get() }

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

    static func `where`<Value: Codable & Sendable>(
        _ column: String,
        _ operation: QueryOperator,
        _ value: Value
    ) -> EloquentQuery<Self> {
        query().where(column, operation, value)
    }

    static func `where`<Value>(
        _ field: KeyPath<Self, FieldProperty<Self, Value>>,
        _ value: Value
    ) -> EloquentQuery<Self> where Value: Codable & Sendable {
        query().where(field, value)
    }

    static func whereIn<Value: Codable & Sendable>(_ column: String, _ values: [Value]) -> EloquentQuery<Self> {
        query().whereIn(column, values)
    }

    static func `where`<Value>(
        _ field: KeyPath<Self, FieldProperty<Self, Value>>,
        _ operation: QueryOperator,
        _ value: Value
    ) -> EloquentQuery<Self> where Value: Codable & Sendable {
        query().where(field, operation, value)
    }

    static func whereIn<Value>(
        _ field: KeyPath<Self, FieldProperty<Self, Value>>,
        _ values: [Value]
    ) -> EloquentQuery<Self> where Value: Codable & Sendable {
        query().whereIn(field, values)
    }

    static func whereNotIn<Value>(
        _ field: KeyPath<Self, FieldProperty<Self, Value>>,
        _ values: [Value]
    ) -> EloquentQuery<Self> where Value: Codable & Sendable {
        query().whereNotIn(field, values)
    }

    static func whereNull<Value>(_ field: KeyPath<Self, FieldProperty<Self, Value>>) -> EloquentQuery<Self> {
        query().whereNull(field)
    }

    static func whereNotNull<Value>(_ field: KeyPath<Self, FieldProperty<Self, Value>>) -> EloquentQuery<Self> {
        query().whereNotNull(field)
    }

    static func whereBetween<Value>(
        _ field: KeyPath<Self, FieldProperty<Self, Value>>,
        _ range: ClosedRange<Value>
    ) -> EloquentQuery<Self> where Value: Codable & Sendable {
        query().whereBetween(field, range)
    }

    static func whereNull(_ column: String) -> EloquentQuery<Self> { query().whereNull(column) }
    static func whereNotNull(_ column: String) -> EloquentQuery<Self> { query().whereNotNull(column) }

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

    static func orderBy(_ column: String, _ direction: SortDirection) -> EloquentQuery<Self> {
        query().orderBy(column, direction)
    }

    static func latest(_ column: String = "created_at") -> EloquentQuery<Self> {
        query().latest(column)
    }

    static func oldest(_ column: String = "created_at") -> EloquentQuery<Self> {
        query().oldest(column)
    }

    static func limit(_ amount: Int) -> EloquentQuery<Self> { query().limit(amount) }

    static func get() async throws -> [Self] { try await query().get() }
    static func first() async throws -> Self? { try await query().first() }

    static func firstOrFail() async throws -> Self {
        try await query().firstOrFail()
    }

    static func find(_ id: IDValue) async throws -> Self? {
        try await Self.find(id, on: EloquentContext.requireDatabase())
    }

    static func findOrFail(_ id: IDValue) async throws -> Self {
        guard let model = try await find(id) else {
            throw EloquentError.modelNotFound(String(describing: Self.self))
        }
        return model
    }

    static func count() async throws -> Int { try await query().count() }

    /// Cria e persiste uma model em uma linha: `try await User.create(user)`.
    @discardableResult
    static func create(_ model: Self) async throws -> Self {
        try await model.save(on: EloquentContext.requireDatabase())
        return model
    }

    func save() async throws {
        try await save(on: EloquentContext.requireDatabase())
    }

    func delete() async throws {
        try await delete(on: EloquentContext.requireDatabase())
    }
}

public extension EloquentQuery where M: SoftDeletableModel {
    /// Inclui registros com soft delete na consulta.
    @discardableResult
    func withTrashed() -> Self {
        builder.withDeleted()
        return self
    }

    /// Somente registros com soft delete.
    @discardableResult
    func onlyTrashed() -> Self {
        builder.withDeleted()
        builder.filter(.value(queryField("deleted_at"), .notEqual, .null))
        return self
    }

    /// Restaura todos os registros filtrados.
    func restoreAll() async throws {
        for model in try await withTrashed().get() {
            try await model.restore(on: builder.database)
        }
    }
}

// MARK: - Query

public struct EloquentQuery<M: Model>: @unchecked Sendable {
    final class State: @unchecked Sendable {
        var recordedError: (any Error)?
    }

    private let state = State()

    public let builder: QueryBuilder<M>

    /// Escape hatch para toda a API do Fluent (`with`, `group`, `set`, ...).
    public var fluentQuery: QueryBuilder<M> { builder }

    public init(builder: QueryBuilder<M>) { self.builder = builder }

    private func record(_ error: any Error) {
        if state.recordedError == nil { state.recordedError = error }
    }

    private func validate() throws {
        if let error = state.recordedError { throw error }
    }

    // MARK: where

    @discardableResult
    public func `where`<Value: Codable & Sendable>(_ column: String, _ value: Value) -> Self {
        guard validateColumn(column) else { return self }
        builder.filter(queryField(column), .equal, .bind(value))
        return self
    }

    @discardableResult
    public func `where`<Value: Codable & Sendable>(
        _ column: String,
        _ operation: String,
        _ value: Value
    ) -> Self {
        guard validateColumn(column) else { return self }
        guard let method = filterMethod(operation) else {
            record(EloquentError.invalidOperator(operation))
            return self
        }
        builder.filter(queryField(column), method, .bind(value))
        return self
    }

    @discardableResult
    public func `where`<Value: Codable & Sendable>(
        _ column: String,
        _ operation: QueryOperator,
        _ value: Value
    ) -> Self {
        `where`(column, operation.rawValue, value)
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
    public func `where`<Value>(
        _ field: KeyPath<M, FieldProperty<M, Value>>,
        _ operation: QueryOperator,
        _ value: Value
    ) -> Self where Value: Codable & Sendable {
        guard let method = filterMethod(operation.rawValue) else {
            record(EloquentError.invalidOperator(operation.rawValue))
            return self
        }
        builder.filter(field, method, value)
        return self
    }

    /// Grupo `AND` aninhado: `where { $0.where("a", 1).where("b", 2) }`.
    @discardableResult
    public func `where`(_ closure: (EloquentQuery<M>) -> EloquentQuery<M>) -> Self {
        builder.group(.and) { fluent in
            _ = closure(EloquentQuery(builder: fluent))
        }
        return self
    }

    /// Grupo `OR`: `orWhere("email", email)`.
    @discardableResult
    public func orWhere<Value: Codable & Sendable>(_ column: String, _ value: Value) -> Self {
        guard validateColumn(column) else { return self }
        builder.group(.or) { fluent in
            fluent.filter(queryField(column), .equal, .bind(value))
        }
        return self
    }

    @discardableResult
    public func orWhere<Value: Codable & Sendable>(
        _ column: String,
        _ operation: String,
        _ value: Value
    ) -> Self {
        guard validateColumn(column) else { return self }
        guard let method = filterMethod(operation) else {
            record(EloquentError.invalidOperator(operation))
            return self
        }
        builder.group(.or) { fluent in
            fluent.filter(queryField(column), method, .bind(value))
        }
        return self
    }

    @discardableResult
    public func whereIn<Value: Codable & Sendable>(_ column: String, _ values: [Value]) -> Self {
        guard validateColumn(column) else { return self }
        builder.filter(queryField(column), .subset(inverse: false), .array(values.map { .bind($0) }))
        return self
    }

    @discardableResult
    public func whereNotIn<Value: Codable & Sendable>(_ column: String, _ values: [Value]) -> Self {
        guard validateColumn(column) else { return self }
        builder.filter(queryField(column), .subset(inverse: true), .array(values.map { .bind($0) }))
        return self
    }

    @discardableResult
    public func whereNull(_ column: String) -> Self {
        guard validateColumn(column) else { return self }
        builder.filter(.value(queryField(column), .equal, .null))
        return self
    }

    @discardableResult
    public func whereNotNull(_ column: String) -> Self {
        guard validateColumn(column) else { return self }
        builder.filter(.value(queryField(column), .notEqual, .null))
        return self
    }

    @discardableResult
    public func whereBetween<Value: Codable & Sendable>(_ column: String, _ range: ClosedRange<Value>) -> Self {
        `where`(column, ">=", range.lowerBound).where(column, "<=", range.upperBound)
    }

    @discardableResult
    public func whereNotBetween<Value: Codable & Sendable>(_ column: String, _ range: ClosedRange<Value>) -> Self {
        builder.group(.or) { fluent in
            fluent.filter(queryField(column), .lessThan, .bind(range.lowerBound))
            fluent.filter(queryField(column), .greaterThan, .bind(range.upperBound))
        }
        return self
    }

    // MARK: where tipado por key path (verificação em compilação)

    private func fieldPath<Value>(_ field: KeyPath<M, FieldProperty<M, Value>>) -> DatabaseQuery.Field {
        .extendedPath(M.path(for: field), schema: M.schemaOrAlias, space: M.spaceIfNotAliased)
    }

    @discardableResult
    public func whereIn<Value>(
        _ field: KeyPath<M, FieldProperty<M, Value>>,
        _ values: [Value]
    ) -> Self where Value: Codable & Sendable {
        builder.filter(fieldPath(field), .subset(inverse: false), .array(values.map { .bind($0) }))
        return self
    }

    @discardableResult
    public func whereNotIn<Value>(
        _ field: KeyPath<M, FieldProperty<M, Value>>,
        _ values: [Value]
    ) -> Self where Value: Codable & Sendable {
        builder.filter(fieldPath(field), .subset(inverse: true), .array(values.map { .bind($0) }))
        return self
    }

    @discardableResult
    public func whereNull<Value>(_ field: KeyPath<M, FieldProperty<M, Value>>) -> Self {
        builder.filter(.value(fieldPath(field), .equal, .null))
        return self
    }

    @discardableResult
    public func whereNotNull<Value>(_ field: KeyPath<M, FieldProperty<M, Value>>) -> Self {
        builder.filter(.value(fieldPath(field), .notEqual, .null))
        return self
    }

    @discardableResult
    public func whereBetween<Value>(
        _ field: KeyPath<M, FieldProperty<M, Value>>,
        _ range: ClosedRange<Value>
    ) -> Self where Value: Codable & Sendable {
        builder.filter(fieldPath(field), .greaterThanOrEqual, .bind(range.lowerBound))
        builder.filter(fieldPath(field), .lessThanOrEqual, .bind(range.upperBound))
        return self
    }

    @discardableResult
    public func whereColumn<Value, Other>(
        _ field: KeyPath<M, FieldProperty<M, Value>>,
        _ operation: QueryOperator,
        _ other: KeyPath<M, FieldProperty<M, Other>>
    ) -> Self where Value: Codable & Sendable, Other: Codable & Sendable {
        guard let method = filterMethod(operation.rawValue) else {
            record(EloquentError.invalidOperator(operation.rawValue))
            return self
        }
        builder.filter(field, method, other)
        return self
    }

    @discardableResult
    public func whereLike(_ column: String, _ pattern: String) -> Self {
        `where`(column, "like", pattern)
    }

    @discardableResult
    public func whereColumn(_ firstColumn: String, _ operation: String, _ secondColumn: String) -> Self {
        guard validateColumn(firstColumn), validateColumn(secondColumn) else { return self }
        guard let method = filterMethod(operation) else {
            record(EloquentError.invalidOperator(operation))
            return self
        }
        builder.filter(.field(queryField(firstColumn), method, queryField(secondColumn)))
        return self
    }

    // MARK: joins

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

    // MARK: eager loading e ordenação

    /// Eager loading declarativo do Fluent: `User.query().with(\.$posts)`.
    @discardableResult
    public func with<Relation>(_ relation: KeyPath<M, Relation>) -> Self
        where Relation: EagerLoadable, Relation.From == M {
        builder.with(relation)
        return self
    }

    /// Eager loading aninhado: `with(\.$posts) { $0.with(\.$author) }`.
    @discardableResult
    public func with<Relation>(
        _ relation: KeyPath<M, Relation>,
        _ nested: (NestedEagerLoadBuilder<QueryBuilder<M>, Relation>) throws -> Void
    ) rethrows -> Self where Relation: EagerLoadable, Relation.From == M {
        try builder.with(relation, nested)
        return self
    }

    @discardableResult
    public func orderBy(_ column: String, _ direction: String = "asc") -> Self {
        guard validateColumn(column) else { return self }
        guard let resolved = sortDirection(direction) else {
            record(EloquentError.invalidDirection(direction))
            return self
        }
        builder.sort(queryField(column), resolved)
        return self
    }

    @discardableResult
    public func orderBy(_ column: String, _ direction: SortDirection) -> Self {
        guard validateColumn(column) else { return self }
        builder.sort(queryField(column), direction.fluent)
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
    public func orderByDesc(_ column: String) -> Self { orderBy(column, .desc) }

    @discardableResult
    public func orderByAsc(_ column: String) -> Self { orderBy(column, .asc) }

    @discardableResult
    public func latest(_ column: String = "created_at") -> Self { orderBy(column, .desc) }

    @discardableResult
    public func oldest(_ column: String = "created_at") -> Self { orderBy(column, .asc) }

    // MARK: limites e paginação

    @discardableResult
    public func limit(_ amount: Int) -> Self {
        builder.limit(amount)
        return self
    }

    @discardableResult
    public func take(_ amount: Int) -> Self { limit(amount) }

    @discardableResult
    public func offset(_ amount: Int) -> Self {
        builder.range(lower: amount)
        return self
    }

    @discardableResult
    public func skip(_ amount: Int) -> Self { offset(amount) }

    @discardableResult
    public func forPage(page: Int, perPage: Int) -> Self {
        builder.range(lower: max(page - 1, 0) * perPage, upper: max(page - 1, 0) * perPage + perPage)
        return self
    }

    // MARK: terminais

    public func first() async throws -> M? {
        try validate()
        return try await builder.first()
    }

    public func firstOrFail() async throws -> M {
        guard let model = try await first() else {
            throw EloquentError.modelNotFound(String(describing: M.self))
        }
        return model
    }

    /// Como `firstOrFail`, mas exige exatamente um resultado.
    public func sole() async throws -> M {
        let results = try await limit(2).get()
        guard results.count == 1, let model = results.first else {
            throw EloquentError.modelNotFound(String(describing: M.self))
        }
        return model
    }

    public func get() async throws -> [M] {
        try validate()
        return try await builder.all()
    }

    public func getJoined<Joined: Model>(_ model: Joined.Type) async throws -> [JoinedRow<M, Joined>] {
        try await get().map { base in
            JoinedRow(base: base, joined: try base.joined(model))
        }
    }

    public func getJoinedOptional<Joined: Model>(_ model: Joined.Type) async throws -> [OptionalJoinedRow<M, Joined>] {
        try await get().map { base in
            OptionalJoinedRow(base: base, joined: try? base.joined(model))
        }
    }

    /// Join com **duas** models relacionadas.
    public func getJoined<First: Model, Second: Model>(
        _ first: First.Type,
        _ second: Second.Type
    ) async throws -> [JoinedRow3<M, First, Second>] {
        try await get().map { base in
            JoinedRow3(base: base, first: try base.joined(first), second: try base.joined(second))
        }
    }

    /// Join com duas models, ambas opcionais (útil com `leftJoin`).
    public func getJoinedOptional<First: Model, Second: Model>(
        _ first: First.Type,
        _ second: Second.Type
    ) async throws -> [OptionalJoinedRow3<M, First, Second>] {
        try await get().map { base in
            OptionalJoinedRow3(base: base, first: try? base.joined(first), second: try? base.joined(second))
        }
    }

    public func count() async throws -> Int {
        try validate()
        return try await builder.count()
    }

    public func exists() async throws -> Bool { try await first() != nil }
    public func doesntExist() async throws -> Bool { try await !exists() }
    public func isEmpty() async throws -> Bool { try await !exists() }
    public func isNotEmpty() async throws -> Bool { try await exists() }

    /// Um único valor de uma propriedade tipada: `value(\.$name)`.
    public func value<Value>(_ field: KeyPath<M, FieldProperty<M, Value>>) async throws -> Value? {
        try await first().map { $0[keyPath: field].wrappedValue }
    }

    /// Lista de valores de uma propriedade: `pluck(\.$email)`.
    public func pluck<Value>(_ field: KeyPath<M, FieldProperty<M, Value>>) async throws -> [Value]
        where Value: Codable & Sendable {
        try await get().map { $0[keyPath: field].wrappedValue }
    }

    /// Processa os resultados em lotes, como o `chunk` do Laravel.
    public func chunk(_ size: Int, _ handler: ([M]) async throws -> Bool) async throws {
        try validate()
        var page = 1
        while true {
            let fluentPage = try await builder.paginate(PageRequest(page: page, per: size))
            if fluentPage.items.isEmpty { return }
            if try await handler(fluentPage.items) == false { return }
            if fluentPage.items.count < size { return }
            page += 1
        }
    }

    /// Executa o closure somente quando a condição é verdadeira.
    @discardableResult
    public func when<Value>(
        _ condition: Value?,
        then: (EloquentQuery<M>, Value) -> EloquentQuery<M>,
        otherwise: ((EloquentQuery<M>) -> EloquentQuery<M>)? = nil
    ) -> Self {
        if let condition {
            return then(self, condition)
        }
        return otherwise?(self) ?? self
    }

    @discardableResult
    public func tap(_ closure: (EloquentQuery<M>) -> Void) -> Self {
        closure(self)
        return self
    }

    // MARK: escrita em massa

    /// Atualiza todos os registros filtrados. Retorna a query para `update()`.
    @discardableResult
    public func set<Value: Codable & Sendable>(_ column: String, to value: Value) -> Self {
        guard validateColumn(column) else { return self }
        builder.set([fieldKey(lastComponent(column)): .bind(value)])
        return self
    }

    public func update() async throws {
        try validate()
        try await builder.update()
    }

    /// Exclui (ou soft-deleta) todos os registros filtrados.
    public func deleteAll(force: Bool = false) async throws {
        try validate()
        try await builder.delete(force: force)
    }

    @discardableResult
    public func create(_ model: M) async throws -> M {
        try validate()
        try await model.save(on: builder.database)
        return model
    }

    // MARK: - internos

    private func addJoin<Joined: Model>(
        _ model: Joined.Type,
        _ firstColumn: String,
        _ operation: String,
        _ secondColumn: String,
        method: DatabaseQuery.Join.Method
    ) -> Self {
        guard validateColumn(firstColumn), validateColumn(secondColumn) else { return self }
        guard let resolved = filterMethod(operation) else {
            record(EloquentError.invalidOperator(operation))
            return self
        }
        builder.join(
            model,
            on: .advancedJoin(
                schema: Joined.schema,
                space: Joined.space,
                alias: Joined.alias,
                method,
                filters: [.field(queryField(firstColumn), resolved, queryField(secondColumn))]
            )
        )
        return self
    }

    private func validateColumn(_ column: String) -> Bool {
        let parts = column.split(separator: ".").map(String.init)
        let valid = (1...2).contains(parts.count) && parts.allSatisfy { part in
            part.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil || part == "*"
        }
        if !valid { record(EloquentError.invalidColumn(column)) }
        return valid
    }

    private func queryField(_ column: String) -> DatabaseQuery.Field {
        let parts = column.split(separator: ".", maxSplits: 1).map(String.init)
        if parts.count == 2 {
            return .extendedPath([fieldKey(parts[1])], schema: parts[0], space: nil)
        }
        return .extendedPath([fieldKey(column)], schema: M.schemaOrAlias, space: M.spaceIfNotAliased)
    }

    private func lastComponent(_ column: String) -> String {
        column.split(separator: ".").last.map(String.init) ?? column
    }

    private func fieldKey(_ column: String) -> FieldKey {
        column == "id" || column == "_id" ? .id : .string(column)
    }

    private func filterMethod(_ value: String) -> DatabaseQuery.Filter.Method? {
        switch value.trimmingCharacters(in: .whitespaces).lowercased() {
        case "=", "==": .equal
        case "!=", "<>": .notEqual
        case ">": .greaterThan
        case ">=": .greaterThanOrEqual
        case "<": .lessThan
        case "<=": .lessThanOrEqual
        case "like", "ilike": .contains(inverse: false, .anywhere)
        case "not like": .contains(inverse: true, .anywhere)
        case "starts_with": .contains(inverse: false, .prefix)
        case "ends_with": .contains(inverse: false, .suffix)
        default: nil
        }
    }

    private func sortDirection(_ value: String) -> DatabaseQuery.Sort.Direction? {
        switch value.lowercased() {
        case "asc", "ascending": .ascending
        case "desc", "descending": .descending
        default: nil
        }
    }
}


public extension EloquentQuery where M: Content {
    /// Paginação no formato do Laravel (`data`, `current_page`, `last_page`...).
    func paginate(page: Int = 1, perPage: Int = 15) async throws -> Paginator<M> {
        try validate()
        guard page >= 1, perPage >= 1, perPage <= 500 else {
            throw EloquentError.invalidPagination(page: page, perPage: perPage)
        }
        let fluentPage = try await builder.paginate(PageRequest(page: page, per: perPage))
        return Paginator(fluentPage: fluentPage)
    }

    /// Como `paginate`, sem contar o total (uma query a menos).
    func simplePaginate(page: Int = 1, perPage: Int = 15) async throws -> SimplePaginator<M> {
        try validate()
        guard page >= 1, perPage >= 1, perPage <= 500 else {
            throw EloquentError.invalidPagination(page: page, perPage: perPage)
        }
        let items = try await builder
            .range(lower: (page - 1) * perPage, upper: (page - 1) * perPage + perPage + 1)
            .all()
        return SimplePaginator(
            data: Array(items.prefix(perPage)),
            currentPage: page,
            perPage: perPage,
            hasMorePages: items.count > perPage
        )
    }
}

public extension EloquentModel where Self: Content {
    static func paginate(page: Int = 1, perPage: Int = 15) async throws -> Paginator<Self> {
        try await query().paginate(page: page, perPage: perPage)
    }
}

// MARK: - Resultados de join

public struct JoinedRow<Base: Model, Joined: Model>: @unchecked Sendable {
    public let base: Base
    public let joined: Joined

    public init(base: Base, joined: Joined) {
        self.base = base
        self.joined = joined
    }
}

public struct OptionalJoinedRow<Base: Model, Joined: Model>: @unchecked Sendable {
    public let base: Base
    public let joined: Joined?

    public init(base: Base, joined: Joined?) {
        self.base = base
        self.joined = joined
    }
}

public struct JoinedRow3<Base: Model, First: Model, Second: Model>: @unchecked Sendable {
    public let base: Base
    public let first: First
    public let second: Second

    public init(base: Base, first: First, second: Second) {
        self.base = base
        self.first = first
        self.second = second
    }
}

public struct OptionalJoinedRow3<Base: Model, First: Model, Second: Model>: @unchecked Sendable {
    public let base: Base
    public let first: First?
    public let second: Second?

    public init(base: Base, first: First?, second: Second?) {
        self.base = base
        self.first = first
        self.second = second
    }
}

// MARK: - Paginação (formato Laravel)

/// Equivalente ao `LengthAwarePaginator` do Laravel.
public struct Paginator<T: Content>: Content {
    public let data: [T]
    public let currentPage: Int
    public let perPage: Int
    public let total: Int
    public let lastPage: Int
    public let from: Int?
    public let to: Int?
    public let hasMorePages: Bool

    enum CodingKeys: String, CodingKey {
        case data
        case currentPage = "current_page"
        case perPage = "per_page"
        case total
        case lastPage = "last_page"
        case from, to
        case hasMorePages = "has_more_pages"
    }

    init(fluentPage: Page<T>) {
        data = fluentPage.items
        currentPage = fluentPage.metadata.page
        perPage = fluentPage.metadata.per
        total = fluentPage.metadata.total
        lastPage = fluentPage.metadata.pageCount
        from = data.isEmpty ? nil : (currentPage - 1) * perPage + 1
        to = data.isEmpty ? nil : (currentPage - 1) * perPage + data.count
        hasMorePages = currentPage < lastPage
    }

    public init(data: [T], currentPage: Int, perPage: Int, total: Int) {
        self.data = data
        self.currentPage = currentPage
        self.perPage = perPage
        self.total = total
        lastPage = max(Int((Double(total) / Double(max(perPage, 1))).rounded(.up)), 1)
        from = data.isEmpty ? nil : (currentPage - 1) * perPage + 1
        to = data.isEmpty ? nil : (currentPage - 1) * perPage + data.count
        hasMorePages = currentPage < lastPage
    }

    public func map<U: Content>(_ transform: (T) throws -> U) rethrows -> Paginator<U> {
        Paginator<U>(data: try data.map(transform), currentPage: currentPage, perPage: perPage, total: total)
    }
}

/// Equivalente ao `simplePaginate` do Laravel (sem total).
public struct SimplePaginator<T: Content>: Content {
    public let data: [T]
    public let currentPage: Int
    public let perPage: Int
    public let hasMorePages: Bool

    enum CodingKeys: String, CodingKey {
        case data
        case currentPage = "current_page"
        case perPage = "per_page"
        case hasMorePages = "has_more_pages"
    }

    public init(data: [T], currentPage: Int, perPage: Int, hasMorePages: Bool) {
        self.data = data
        self.currentPage = currentPage
        self.perPage = perPage
        self.hasMorePages = hasMorePages
    }

    public func map<U: Content>(_ transform: (T) throws -> U) rethrows -> SimplePaginator<U> {
        SimplePaginator<U>(data: try data.map(transform), currentPage: currentPage, perPage: perPage, hasMorePages: hasMorePages)
    }
}
