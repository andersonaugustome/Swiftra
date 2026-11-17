import Fluent
import Foundation

public final class UserCredential: EloquentModel, @unchecked Sendable {
    public static let schema = "user_credentials"

    @ID(key: .id) public var id: UUID?
    @Field(key: "user_id") public var userId: UUID
    @Field(key: "password_hash") public var passwordHash: String
    @OptionalField(key: "totp_secret") public var totpSecret: String?
    @OptionalField(key: "totp_confirmed_at") public var totpConfirmedAt: Date?
    /// Códigos de recuperação MFA (hashes SHA-256 separados por vírgula).
    @OptionalField(key: "recovery_codes") public var recoveryCodes: String?
    @Timestamp(key: "created_at", on: .create) public var createdAt: Date?
    @Timestamp(key: "updated_at", on: .update) public var updatedAt: Date?

    public init() {}

    public init(id: UUID? = nil, userId: UUID, passwordHash: String) {
        self.id = id
        self.userId = userId
        self.passwordHash = passwordHash
    }

    public var mfaEnabled: Bool { totpSecret != nil && totpConfirmedAt != nil }
    public var mfaPending: Bool { totpSecret != nil && totpConfirmedAt == nil }
}
