import Fluent

public struct CreateRefreshToken: AsyncMigration {
    public init() {}

    public func prepare(on database: Database) async throws {
        try await database.schema(RefreshToken.schema)
            .id()
            .field("user_id", .uuid, .required, .references(User.schema, "id", onDelete: .cascade))
            .field("token_hash", .string, .required)
            .field("family_id", .uuid, .required)
            .field("expires_at", .datetime, .required)
            .field("revoked_at", .datetime)
            .field("replaced_by_hash", .string)
            .field("created_at", .datetime)
            .unique(on: "token_hash")
            .create()
    }

    public func revert(on database: Database) async throws {
        try await database.schema(RefreshToken.schema).delete()
    }
}

public struct CreatePasswordResetToken: AsyncMigration {
    public init() {}

    public func prepare(on database: Database) async throws {
        try await database.schema(PasswordResetToken.schema)
            .id()
            .field("email", .string, .required)
            .field("token_hash", .string, .required)
            .field("expires_at", .datetime, .required)
            .field("used_at", .datetime)
            .field("created_at", .datetime)
            .unique(on: "token_hash")
            .create()
    }

    public func revert(on database: Database) async throws {
        try await database.schema(PasswordResetToken.schema).delete()
    }
}

public struct CreateEmailVerificationToken: AsyncMigration {
    public init() {}

    public func prepare(on database: Database) async throws {
        try await database.schema(EmailVerificationToken.schema)
            .id()
            .field("user_id", .uuid, .required, .references(User.schema, "id", onDelete: .cascade))
            .field("token_hash", .string, .required)
            .field("expires_at", .datetime, .required)
            .field("used_at", .datetime)
            .field("created_at", .datetime)
            .unique(on: "token_hash")
            .create()
    }

    public func revert(on database: Database) async throws {
        try await database.schema(EmailVerificationToken.schema).delete()
    }
}

public struct CreateMfaChallenge: AsyncMigration {
    public init() {}

    public func prepare(on database: Database) async throws {
        try await database.schema(MfaChallenge.schema)
            .id()
            .field("user_id", .uuid, .required, .references(User.schema, "id", onDelete: .cascade))
            .field("token_hash", .string, .required)
            .field("expires_at", .datetime, .required)
            .field("used_at", .datetime)
            .field("created_at", .datetime)
            .unique(on: "token_hash")
            .create()
    }

    public func revert(on database: Database) async throws {
        try await database.schema(MfaChallenge.schema).delete()
    }
}

public struct CreateRolesAndPermissions: AsyncMigration {
    public init() {}

    public func prepare(on database: Database) async throws {
        try await database.schema(Role.schema)
            .id()
            .field("name", .string, .required)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .unique(on: "name")
            .create()

        try await database.schema(Permission.schema)
            .id()
            .field("name", .string, .required)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .unique(on: "name")
            .create()

        try await database.schema(UserRole.schema)
            .id()
            .field("user_id", .uuid, .required, .references(User.schema, "id", onDelete: .cascade))
            .field("role_id", .uuid, .required, .references(Role.schema, "id", onDelete: .cascade))
            .unique(on: "user_id", "role_id")
            .create()

        try await database.schema(RolePermission.schema)
            .id()
            .field("role_id", .uuid, .required, .references(Role.schema, "id", onDelete: .cascade))
            .field("permission_id", .uuid, .required, .references(Permission.schema, "id", onDelete: .cascade))
            .unique(on: "role_id", "permission_id")
            .create()

        try await database.schema(UserPermission.schema)
            .id()
            .field("user_id", .uuid, .required, .references(User.schema, "id", onDelete: .cascade))
            .field("permission_id", .uuid, .required, .references(Permission.schema, "id", onDelete: .cascade))
            .unique(on: "user_id", "permission_id")
            .create()
    }

    public func revert(on database: Database) async throws {
        try await database.schema(UserPermission.schema).delete()
        try await database.schema(RolePermission.schema).delete()
        try await database.schema(UserRole.schema).delete()
        try await database.schema(Permission.schema).delete()
        try await database.schema(Role.schema).delete()
    }
}
