import Fluent

public struct CreateAuthToken: AsyncMigration {
    public init() {}

    public func prepare(on database: Database) async throws {
        try await database.schema(AuthToken.schema)
            .id()
            .field("user_id", .uuid, .required, .references(User.schema, "id", onDelete: .cascade))
            .field("token_hash", .string, .required)
            .field("expires_at", .datetime, .required)
            .field("created_at", .datetime)
            .unique(on: "token_hash")
            .create()
    }

    public func revert(on database: Database) async throws {
        try await database.schema(AuthToken.schema).delete()
    }
}
