import Fluent
import Foundation

public final class AuthToken: EloquentModel, @unchecked Sendable {
    public static let schema = "auth_tokens"

    @ID(key: .id) public var id: UUID?
    @Field(key: "user_id") public var userId: UUID
    @Field(key: "token_hash") public var tokenHash: String
    @Field(key: "expires_at") public var expiresAt: Date
    @Timestamp(key: "created_at", on: .create) public var createdAt: Date?

    public init() {}

    public init(id: UUID? = nil, userId: UUID, tokenHash: String, expiresAt: Date) {
        self.id = id
        self.userId = userId
        self.tokenHash = tokenHash
        self.expiresAt = expiresAt
    }
}
