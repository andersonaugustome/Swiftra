import Fluent
import Foundation

/// Janela de rate limiting persistida (`RATE_LIMIT_DRIVER=database`).
///
/// Compartilhada entre instâncias da aplicação, ao contrário do driver
/// em memória. Limpe linhas expiradas periodicamente se o volume for alto.
public final class RateLimitEntry: EloquentModel, @unchecked Sendable {
    public static let schema = "rate_limit_entries"

    @ID(key: .id) public var id: UUID?
    @Field(key: "key") public var key: String
    @Field(key: "attempts") public var attempts: Int
    @Field(key: "expires_at") public var expiresAt: Date
    @Timestamp(key: "created_at", on: .create) public var createdAt: Date?
    @Timestamp(key: "updated_at", on: .update) public var updatedAt: Date?

    public init() {}

    public init(id: UUID? = nil, key: String, attempts: Int, expiresAt: Date) {
        self.id = id
        self.key = key
        self.attempts = attempts
        self.expiresAt = expiresAt
    }
}

public struct CreateRateLimitEntry: AsyncMigration {
    public init() {}

    public func prepare(on database: Database) async throws {
        try await database.schema(RateLimitEntry.schema)
            .id()
            .field("key", .string, .required)
            .field("attempts", .int, .required)
            .field("expires_at", .datetime, .required)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .unique(on: "key")
            .create()
    }

    public func revert(on database: Database) async throws {
        try await database.schema(RateLimitEntry.schema).delete()
    }
}
