import Fluent
import Vapor

/// Exemplo de relação polimórfica: um comentário pode pertencer a um
/// `User` ou a um `Post` (`commentable_type`/`commentable_id`).
public final class Comment: PolymorphicChild, Content, @unchecked Sendable {
    public static let schema = "comments"

    @ID(key: .id) public var id: UUID?
    @Field(key: "body") public var body: String
    @Field(key: "commentable_type") public var commentableType: String
    @Field(key: "commentable_id") public var commentableId: UUID
    @Timestamp(key: "created_at", on: .create) public var createdAt: Date?

    public init() {}

    public init(body: String) {
        self.body = body
        self.commentableType = ""
        self.commentableId = UUID()
    }

    public init(id: UUID? = nil, body: String, commentableType: String, commentableId: UUID) {
        self.id = id
        self.body = body
        self.commentableType = commentableType
        self.commentableId = commentableId
    }

    public convenience init<Parent: PolymorphicParent>(body: String, parent: Parent) throws where Parent.IDValue == UUID {
        self.init(body: body, commentableType: Parent.morphType, commentableId: try parent.requireID())
    }

    // PolymorphicChild
    public var morphTypeValue: String {
        get { commentableType }
        set { commentableType = newValue }
    }

    public var morphIDValue: UUID {
        get { commentableId }
        set { commentableId = newValue }
    }
}

extension User: PolymorphicParent {}
extension Post: PolymorphicParent {}
