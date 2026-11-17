import Fluent
import Foundation

/// Refresh token rotativo. O valor bruto nunca é persistido — só o hash SHA-256.
///
/// Cada emissão pertence a uma `family`: ao reutilizar um token já rotacionado,
/// toda a família é revogada (detecção de reuso, como no OAuth 2.0 Security BCP).
public final class RefreshToken: EloquentModel, @unchecked Sendable {
    public static let schema = "refresh_tokens"

    @ID(key: .id) public var id: UUID?
    @Field(key: "user_id") public var userId: UUID
    @Field(key: "token_hash") public var tokenHash: String
    @Field(key: "family_id") public var familyId: UUID
    @Field(key: "expires_at") public var expiresAt: Date
    @OptionalField(key: "revoked_at") public var revokedAt: Date?
    @OptionalField(key: "replaced_by_hash") public var replacedByHash: String?
    @Timestamp(key: "created_at", on: .create) public var createdAt: Date?

    public init() {}

    public init(id: UUID? = nil, userId: UUID, tokenHash: String, familyId: UUID, expiresAt: Date) {
        self.id = id
        self.userId = userId
        self.tokenHash = tokenHash
        self.familyId = familyId
        self.expiresAt = expiresAt
    }

    public var isActive: Bool { revokedAt == nil && expiresAt > Date() }
}

public final class PasswordResetToken: EloquentModel, @unchecked Sendable {
    public static let schema = "password_reset_tokens"

    @ID(key: .id) public var id: UUID?
    @Field(key: "email") public var email: String
    @Field(key: "token_hash") public var tokenHash: String
    @Field(key: "expires_at") public var expiresAt: Date
    @OptionalField(key: "used_at") public var usedAt: Date?
    @Timestamp(key: "created_at", on: .create) public var createdAt: Date?

    public init() {}

    public init(id: UUID? = nil, email: String, tokenHash: String, expiresAt: Date) {
        self.id = id
        self.email = email
        self.tokenHash = tokenHash
        self.expiresAt = expiresAt
    }

    public var isUsable: Bool { usedAt == nil && expiresAt > Date() }
}

public final class EmailVerificationToken: EloquentModel, @unchecked Sendable {
    public static let schema = "email_verification_tokens"

    @ID(key: .id) public var id: UUID?
    @Field(key: "user_id") public var userId: UUID
    @Field(key: "token_hash") public var tokenHash: String
    @Field(key: "expires_at") public var expiresAt: Date
    @OptionalField(key: "used_at") public var usedAt: Date?
    @Timestamp(key: "created_at", on: .create) public var createdAt: Date?

    public init() {}

    public init(id: UUID? = nil, userId: UUID, tokenHash: String, expiresAt: Date) {
        self.id = id
        self.userId = userId
        self.tokenHash = tokenHash
        self.expiresAt = expiresAt
    }

    public var isUsable: Bool { usedAt == nil && expiresAt > Date() }
}

/// Desafio de segundo fator criado no login quando o MFA está ativo.
public final class MfaChallenge: EloquentModel, @unchecked Sendable {
    public static let schema = "mfa_challenges"

    @ID(key: .id) public var id: UUID?
    @Field(key: "user_id") public var userId: UUID
    @Field(key: "token_hash") public var tokenHash: String
    @Field(key: "expires_at") public var expiresAt: Date
    @OptionalField(key: "used_at") public var usedAt: Date?
    @Timestamp(key: "created_at", on: .create) public var createdAt: Date?

    public init() {}

    public init(id: UUID? = nil, userId: UUID, tokenHash: String, expiresAt: Date) {
        self.id = id
        self.userId = userId
        self.tokenHash = tokenHash
        self.expiresAt = expiresAt
    }

    public var isUsable: Bool { usedAt == nil && expiresAt > Date() }
}
