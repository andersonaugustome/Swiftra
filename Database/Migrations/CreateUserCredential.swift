import Fluent

public struct CreateUserCredential: AsyncMigration {
    public init() {}

    public func prepare(on database: Database) async throws {
        try await database.schema(UserCredential.schema)
            .id()
            .field("user_id", .uuid, .required, .references(User.schema, "id", onDelete: .cascade))
            .field("password_hash", .string, .required)
            .field("totp_secret", .string)
            .field("totp_confirmed_at", .datetime)
            .field("recovery_codes", .string)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .unique(on: "user_id")
            .create()
    }

    public func revert(on database: Database) async throws {
        try await database.schema(UserCredential.schema).delete()
    }
}
