import Fluent
import Foundation
import Vapor

public enum AuthContext {
    @TaskLocal public static var user: User?
    @TaskLocal public static var token: AuthToken?
}

public enum Auth {
    public static func user() -> User? { AuthContext.user }
    public static func id() -> UUID? { AuthContext.user?.id }
    public static func check() -> Bool { AuthContext.user != nil }

    public static func requireUser() throws -> User {
        guard let user = AuthContext.user else { throw Abort(.unauthorized) }
        return user
    }
}

public struct AuthMiddleware: AsyncMiddleware {
    public init() {}

    public func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        guard let rawToken = request.headers.bearerAuthorization?.token else {
            throw Abort(.unauthorized, reason: "Authentication token is required")
        }

        let hash = TokenGenerator.hash(rawToken)
        guard let token = try await AuthToken.on(request.db)
            .where("token_hash", hash)
            .where("expires_at", ">", Date())
            .first(),
              let user = try await User.find(token.userId, on: request.db) else {
            throw Abort(.unauthorized, reason: "Authentication token is invalid or expired")
        }

        return try await AuthContext.$user.withValue(user) {
            try await AuthContext.$token.withValue(token) {
                try await next.respond(to: request)
            }
        }
    }
}

enum TokenGenerator {
    static func make() -> String {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func hash(_ token: String) -> String {
        SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
