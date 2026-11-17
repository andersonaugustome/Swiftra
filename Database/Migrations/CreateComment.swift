import Fluent

public struct CreateComment: AsyncMigration {
    public init() {}

    public func prepare(on database: Database) async throws {
        try await database.schema(Comment.schema)
            .id()
            .field("body", .string, .required)
            .field("commentable_type", .string, .required)
            .field("commentable_id", .uuid, .required)
            .field("created_at", .datetime)
            .create()
    }

    public func revert(on database: Database) async throws {
        try await database.schema(Comment.schema).delete()
    }
}
