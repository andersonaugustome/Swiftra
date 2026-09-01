import Fluent
import Vapor

public final class Post: EloquentModel, Content, @unchecked Sendable {
    public static let schema = "posts"

    @ID(key: .id) public var id: UUID?
    @Field(key: "user_id") public var userId: UUID
    @Field(key: "title") public var title: String
    @Timestamp(key: "created_at", on: .create) public var createdAt: Date?

    public init() {}

    public init(id: UUID? = nil, userId: UUID, title: String) {
        self.id = id
        self.userId = userId
        self.title = title
    }
}
