import Fluent
import Foundation
import Vapor

/// Tokens emitidos: valores brutos são devolvidos uma única vez ao cliente;
/// no banco ficam apenas hashes SHA-256.
public struct IssuedTokens: Sendable {
    public let accessToken: String
    public let accessExpiresAt: Date
    public let refreshToken: String
    public let refreshExpiresAt: Date
    public let familyId: UUID
}

/// Emissão, rotação (com detecção de reuso) e revogação de tokens.
public enum TokenService {
    public static func issue(for user: User, on database: any Database, familyId: UUID? = nil) async throws -> IssuedTokens {
        let userId = try user.requireID()
        let family = familyId ?? UUID()

        let rawAccess = TokenGenerator.make()
        let accessExpiresAt = Date().addingTimeInterval(TimeInterval(AuthConfig.accessTokenTTLMinutes) * 60)
        try await AuthToken(
            userId: userId,
            tokenHash: TokenGenerator.hash(rawAccess),
            expiresAt: accessExpiresAt
        ).save(on: database)

        let rawRefresh = TokenGenerator.make()
        let refreshExpiresAt = Date().addingTimeInterval(TimeInterval(AuthConfig.refreshTokenTTLDays) * 24 * 60 * 60)
        try await RefreshToken(
            userId: userId,
            tokenHash: TokenGenerator.hash(rawRefresh),
            familyId: family,
            expiresAt: refreshExpiresAt
        ).save(on: database)

        return IssuedTokens(
            accessToken: rawAccess,
            accessExpiresAt: accessExpiresAt,
            refreshToken: rawRefresh,
            refreshExpiresAt: refreshExpiresAt,
            familyId: family
        )
    }

    /// Rotaciona o refresh token. Reusar um token já rotacionado revoga a família.
    public static func rotate(refreshToken raw: String, on database: any Database) async throws -> (user: User, tokens: IssuedTokens) {
        let hash = TokenGenerator.hash(raw)
        guard let stored = try await RefreshToken.on(database).where("token_hash", hash).first() else {
            throw Abort(.unauthorized, reason: "Refresh token is invalid")
        }
        if stored.revokedAt != nil {
            // Reuso de token rotacionado: possível roubo — revoga tudo da família.
            try await revokeFamily(stored.familyId, on: database)
            throw Abort(.unauthorized, reason: "Refresh token reuse detected; session revoked")
        }
        guard stored.expiresAt > Date() else {
            throw Abort(.unauthorized, reason: "Refresh token expired")
        }
        guard let user = try await User.find(stored.userId, on: database) else {
            throw Abort(.unauthorized, reason: "Refresh token is invalid")
        }

        let issued = try await issue(for: user, on: database, familyId: stored.familyId)
        stored.revokedAt = Date()
        stored.replacedByHash = TokenGenerator.hash(issued.refreshToken)
        try await stored.save(on: database)
        return (user, issued)
    }

    public static func revoke(refreshToken raw: String, on database: any Database) async throws {
        if let stored = try await RefreshToken.on(database).where("token_hash", TokenGenerator.hash(raw)).first() {
            stored.revokedAt = Date()
            try await stored.save(on: database)
        }
    }

    public static func revokeFamily(_ familyId: UUID, on database: any Database) async throws {
        let tokens = try await RefreshToken.on(database).where("family_id", familyId).get()
        for token in tokens where token.revokedAt == nil {
            token.revokedAt = Date()
            try await token.save(on: database)
        }
    }

    /// Logout de todos os dispositivos: apaga access tokens e revoga refresh tokens.
    public static func revokeAll(for userId: UUID, on database: any Database) async throws {
        try await AuthToken.on(database).where("user_id", userId).deleteAll()
        let tokens = try await RefreshToken.on(database).where("user_id", userId).get()
        for token in tokens where token.revokedAt == nil {
            token.revokedAt = Date()
            try await token.save(on: database)
        }
    }
}

/// Tokens de uso único (reset de senha, verificação de email, desafio MFA).
public enum OneTimeToken {
    public static func nextExpiry(minutes: Int) -> Date {
        Date().addingTimeInterval(TimeInterval(minutes) * 60)
    }

    public static func make() -> (raw: String, hash: String) {
        let raw = TokenGenerator.make()
        return (raw, TokenGenerator.hash(raw))
    }

    /// Códigos de recuperação MFA: devolve os brutos uma vez e os hashes para persistir.
    public static func recoveryCodes(count: Int = 8) -> (plain: [String], stored: String) {
        let plain: [String] = (0..<count).map { _ in
            String(TokenGenerator.make().replacingOccurrences(of: "-", with: "").prefix(10)).uppercased()
        }
        let stored = plain.map { TokenGenerator.hash(normalizeRecoveryCode($0)) }.joined(separator: ",")
        return (plain, stored)
    }

    public static func normalizeRecoveryCode(_ code: String) -> String {
        code.uppercased().filter { $0.isLetter || $0.isNumber }
    }
}
