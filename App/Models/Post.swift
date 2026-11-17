import Fluent
import Vapor

public final class Post: SoftDeletableModel, Content, @unchecked Sendable {
    public static let schema = "posts"

    @ID(key: .id) public var id: UUID?

    /// Relação declarativa: um post pertence a um usuário (`Post.with(\.$user)`).
    @Parent(key: "user_id") public var user: User

    @Field(key: "title") public var title: String
    @Timestamp(key: "created_at", on: .create) public var createdAt: Date?
    @Timestamp(key: "deleted_at", on: .delete) public var deletedAt: Date?

    public init() {}

    public init(id: UUID? = nil, userId: UUID, title: String) {
        self.id = id
        self.$user.id = userId
        self.title = title
    }

    /// Atalho de leitura compatível com o campo `user_id`.
    public var userId: UUID { $user.id }

    public static func factory() -> PostFactory {
        PostFactory()
    }
}

public final class PostFactory: ModelFactory<Post>, @unchecked Sendable {
    public override func definition() -> Post {
        Post(userId: UUID(), title: Faker.sentence())
    }
}
