import Fluent
import Vapor

// MARK: - Models de papéis e permissões (estilo Spatie/laravel-permission)

public final class Role: EloquentModel, Content, @unchecked Sendable {
    public static let schema = "roles"

    @ID(key: .id) public var id: UUID?
    @Field(key: "name") public var name: String
    @Timestamp(key: "created_at", on: .create) public var createdAt: Date?
    @Timestamp(key: "updated_at", on: .update) public var updatedAt: Date?

    @Siblings(through: RolePermission.self, from: \.$role, to: \.$permission) public var permissions: [Permission]
    @Siblings(through: UserRole.self, from: \.$role, to: \.$user) public var users: [User]

    public init() {}
    public init(id: UUID? = nil, name: String) {
        self.id = id
        self.name = name
    }
}

public final class Permission: EloquentModel, Content, @unchecked Sendable {
    public static let schema = "permissions"

    @ID(key: .id) public var id: UUID?
    @Field(key: "name") public var name: String
    @Timestamp(key: "created_at", on: .create) public var createdAt: Date?
    @Timestamp(key: "updated_at", on: .update) public var updatedAt: Date?

    public init() {}
    public init(id: UUID? = nil, name: String) {
        self.id = id
        self.name = name
    }
}

public final class UserRole: EloquentModel, @unchecked Sendable {
    public static let schema = "user_roles"

    @ID(key: .id) public var id: UUID?
    @Parent(key: "user_id") public var user: User
    @Parent(key: "role_id") public var role: Role

    public init() {}
    public init(id: UUID? = nil, userId: UUID, roleId: UUID) {
        self.id = id
        self.$user.id = userId
        self.$role.id = roleId
    }
}

public final class RolePermission: EloquentModel, @unchecked Sendable {
    public static let schema = "role_permissions"

    @ID(key: .id) public var id: UUID?
    @Parent(key: "role_id") public var role: Role
    @Parent(key: "permission_id") public var permission: Permission

    public init() {}
    public init(id: UUID? = nil, roleId: UUID, permissionId: UUID) {
        self.id = id
        self.$role.id = roleId
        self.$permission.id = permissionId
    }
}

public final class UserPermission: EloquentModel, @unchecked Sendable {
    public static let schema = "user_permissions"

    @ID(key: .id) public var id: UUID?
    @Parent(key: "user_id") public var user: User
    @Parent(key: "permission_id") public var permission: Permission

    public init() {}
    public init(id: UUID? = nil, userId: UUID, permissionId: UUID) {
        self.id = id
        self.$user.id = userId
        self.$permission.id = permissionId
    }
}

// MARK: - API no User (hasRole / can)

public extension User {
    /// Papéis do usuário (exige o banco; usa as tabelas pivô).
    func roleNames(on database: any Database) async throws -> [String] {
        try await $roles.query(on: database).all().map(\.name)
    }

    func hasRole(_ name: String, on database: any Database) async throws -> Bool {
        try await roleNames(on: database).contains(name)
    }

    func hasAnyRole(_ names: [String], on database: any Database) async throws -> Bool {
        try await !Set(roleNames(on: database)).isDisjoint(with: names)
    }

    /// Permissões efetivas: diretas + herdadas dos papéis.
    func permissionNames(on database: any Database) async throws -> Set<String> {
        var names = try await Set($permissions.query(on: database).all().map(\.name))
        let roles = try await $roles.query(on: database).with(\.$permissions).all()
        for role in roles {
            names.formUnion(role.permissions.map(\.name))
        }
        return names
    }

    func hasPermissionTo(_ name: String, on database: any Database) async throws -> Bool {
        try await permissionNames(on: database).contains(name)
    }

    /// Atalho no estilo Laravel: `user.can("users.update")`.
    func can(_ permission: String, on database: any Database) async throws -> Bool {
        try await hasPermissionTo(permission, on: database)
    }

    @discardableResult
    func assignRole(_ name: String, on database: any Database) async throws -> Role {
        let role: Role
        if let existing = try await Role.on(database).where("name", name).first() {
            role = existing
        } else {
            role = try await Role.create(Role(name: name), on: database)
        }
        let userId = try requireID()
        let roleId = try role.requireID()
        if try await UserRole.on(database).where("user_id", userId).where("role_id", roleId).first() == nil {
            try await UserRole(userId: userId, roleId: roleId).save(on: database)
        }
        return role
    }

    func removeRole(_ name: String, on database: any Database) async throws {
        guard let role = try await Role.on(database).where("name", name).first(),
              let roleId = role.id else { return }
        try await UserRole.on(database)
            .where("user_id", try requireID())
            .where("role_id", roleId)
            .deleteAll()
    }

    @discardableResult
    func givePermissionTo(_ name: String, on database: any Database) async throws -> Permission {
        let permission: Permission
        if let existing = try await Permission.on(database).where("name", name).first() {
            permission = existing
        } else {
            permission = try await Permission.create(Permission(name: name), on: database)
        }
        let userId = try requireID()
        let permissionId = try permission.requireID()
        if try await UserPermission.on(database).where("user_id", userId).where("permission_id", permissionId).first() == nil {
            try await UserPermission(userId: userId, permissionId: permissionId).save(on: database)
        }
        return permission
    }
}

private extension EloquentModel {
    static func create(_ model: Self, on database: any Database) async throws -> Self {
        try await model.save(on: database)
        return model
    }
}

// MARK: - Middleware de autorização

/// Exige um dos papéis: `route.middleware(AuthMiddleware(), RequireRoleMiddleware("admin"))`.
public struct RequireRoleMiddleware: AsyncMiddleware {
    public let roles: [String]

    public init(_ roles: String...) { self.roles = roles }
    public init(roles: [String]) { self.roles = roles }

    public func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        let user = try Auth.requireUser()
        guard try await user.hasAnyRole(roles, on: request.db) else {
            throw Abort(.forbidden, reason: "This action requires one of the roles: \(roles.joined(separator: ", "))")
        }
        return try await next.respond(to: request)
    }
}

/// Exige uma permissão: `RequirePermissionMiddleware("users.delete")`.
public struct RequirePermissionMiddleware: AsyncMiddleware {
    public let permission: String

    public init(_ permission: String) { self.permission = permission }

    public func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        let user = try Auth.requireUser()
        guard try await user.hasPermissionTo(permission, on: request.db) else {
            throw Abort(.forbidden, reason: "This action requires the permission: \(permission)")
        }
        return try await next.respond(to: request)
    }
}

/// Exige email verificado.
public struct EnsureEmailVerifiedMiddleware: AsyncMiddleware {
    public init() {}

    public func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        guard try Auth.requireUser().emailVerified else {
            throw Abort(.forbidden, reason: "Email address is not verified")
        }
        return try await next.respond(to: request)
    }
}

// MARK: - Seed padrão

public enum AuthorizationSeeder {
    public static let defaultPermissions = [
        "users.view", "users.create", "users.update", "users.delete",
        "posts.view", "posts.create", "posts.update", "posts.delete",
    ]

    /// Cria `admin` (tudo) e `user` (leitura/escrita de posts, leitura de usuários).
    public static func seed(on database: any Database, logger: Logger? = nil) async throws {
        let permissions = try await defaultPermissions.asyncMap { name -> Permission in
            if let existing = try await Permission.on(database).where("name", name).first() {
                return existing
            }
            let permission = Permission(name: name)
            try await permission.save(on: database)
            return permission
        }

        let admin = try await ensureRole("admin", on: database)
        let user = try await ensureRole("user", on: database)

        for permission in permissions {
            try await attach(permission: permission, to: admin, on: database)
        }
        for name in ["users.view", "posts.view", "posts.create", "posts.update", "posts.delete"] {
            if let permission = permissions.first(where: { $0.name == name }) {
                try await attach(permission: permission, to: user, on: database)
            }
        }
        logger?.info("Authorization seeded: roles admin/user, \(permissions.count) permissions")
    }

    private static func ensureRole(_ name: String, on database: any Database) async throws -> Role {
        if let existing = try await Role.on(database).where("name", name).first() {
            return existing
        }
        let role = Role(name: name)
        try await role.save(on: database)
        return role
    }

    private static func attach(permission: Permission, to role: Role, on database: any Database) async throws {
        let roleId = try role.requireID()
        let permissionId = try permission.requireID()
        if try await RolePermission.on(database).where("role_id", roleId).where("permission_id", permissionId).first() == nil {
            try await RolePermission(roleId: roleId, permissionId: permissionId).save(on: database)
        }
    }
}

extension Sequence {
    func asyncMap<T>(_ transform: (Element) async throws -> T) async throws -> [T] {
        var results: [T] = []
        for element in self { results.append(try await transform(element)) }
        return results
    }
}
