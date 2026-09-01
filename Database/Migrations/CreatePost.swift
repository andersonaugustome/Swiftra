import Fluent

public struct CreatePost: AsyncMigration {
    public init() {}

    public func prepare(on database: Database) async throws {
        try await database.schema(Post.schema)
            .id()
            .field("user_id", .uuid, .required, .references(User.schema, "id", onDelete: .cascade))
            .field("title", .string, .required)
            .field("created_at", .datetime)
            .create()
    }

    public func revert(on database: Database) async throws {
        try await database.schema(Post.schema).delete()
    }
}
