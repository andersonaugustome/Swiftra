import Fluent
import Vapor

public final class User: SoftDeletableModel, Content, @unchecked Sendable {
    public static let schema = "users"

    @ID(key: .id) public var id: UUID?
    @Field(key: "name") public var name: String
    @Field(key: "email") public var email: String
    @Timestamp(key: "email_verified_at", on: .none) public var emailVerifiedAt: Date?
    @Timestamp(key: "created_at", on: .create) public var createdAt: Date?
    @Timestamp(key: "updated_at", on: .update) public var updatedAt: Date?
    @Timestamp(key: "deleted_at", on: .delete) public var deletedAt: Date?

    /// Relação declarativa: um usuário tem muitos posts (`User.with(\.$posts)`).
    @Children(for: \Post.$user) public var posts: [Post]

    /// Papéis atribuídos diretamente (`user.$roles`).
    @Siblings(through: UserRole.self, from: \.$user, to: \.$role) public var roles: [Role]

    /// Permissões atribuídas diretamente, além das herdadas dos papéis.
    @Siblings(through: UserPermission.self, from: \.$user, to: \.$permission) public var permissions: [Permission]

    public init() {}

    public init(id: UUID? = nil, name: String, email: String) {
        self.id = id
        self.name = name
        self.email = email
    }

    public var emailVerified: Bool { emailVerifiedAt != nil }

    public static func factory() -> UserFactory {
        UserFactory()
    }
}

public final class UserFactory: ModelFactory<User>, @unchecked Sendable {
    public override func definition() -> User {
        User(name: Faker.name(), email: Faker.email())
    }
}
