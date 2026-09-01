import Fluent
import Vapor

public final class User: EloquentModel, Content, @unchecked Sendable {
    public static let schema = "users"

    @ID(key: .id) public var id: UUID?
    @Field(key: "name") public var name: String
    @Field(key: "email") public var email: String
    @Timestamp(key: "created_at", on: .create) public var createdAt: Date?
    @Timestamp(key: "updated_at", on: .update) public var updatedAt: Date?

    public init() {}

    public init(id: UUID? = nil, name: String, email: String) {
        self.id = id
        self.name = name
        self.email = email
    }

}
