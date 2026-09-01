import Fluent
import Foundation

public final class UserCredential: EloquentModel, @unchecked Sendable {
    public static let schema = "user_credentials"

    @ID(key: .id) public var id: UUID?
    @Field(key: "user_id") public var userId: UUID
    @Field(key: "password_hash") public var passwordHash: String
    @Timestamp(key: "created_at", on: .create) public var createdAt: Date?
    @Timestamp(key: "updated_at", on: .update) public var updatedAt: Date?

    public init() {}

    public init(id: UUID? = nil, userId: UUID, passwordHash: String) {
        self.id = id
        self.userId = userId
        self.passwordHash = passwordHash
    }
}
