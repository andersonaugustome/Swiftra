import Fluent

public struct CreateUser: AsyncMigration {
    public init() {}

    public func prepare(on database: Database) async throws {
        try await database.schema(User.schema)
            .id()
            .field("name", .string, .required)
            .field("email", .string, .required)
            .field("email_verified_at", .datetime)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .field("deleted_at", .datetime)
            .unique(on: "email")
            .create()
    }

    public func revert(on database: Database) async throws {
        try await database.schema(User.schema).delete()
    }
}
