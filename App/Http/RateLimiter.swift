import Fluent
import Vapor

/// Rate limiting (janela fixa), no espírito do `throttle` do Laravel.
///
/// Driver configurável por `RATE_LIMIT_DRIVER`:
/// - `database` (padrão): janelas persistidas em `rate_limit_entries`,
///   compartilhadas entre todas as instâncias da aplicação.
/// - `memory`: actor em memória (processo único, testes rápidos).
public actor RateLimiterStore {
    public static let shared = RateLimiterStore()

    public init() {}

    private struct Window {
        var count: Int
        var resetAt: Date
    }

    private var windows: [String: Window] = [:]

    /// Retorna `nil` se permitido, ou os segundos até a janela reiniciar.
    public func hit(key: String, maxAttempts: Int, decaySeconds: Int, now: Date = Date()) -> Int? {
        if windows.count > 10_000 {
            windows = windows.filter { $0.value.resetAt > now }
        }
        var window = windows[key] ?? Window(count: 0, resetAt: now.addingTimeInterval(TimeInterval(decaySeconds)))
        if window.resetAt <= now {
            window = Window(count: 0, resetAt: now.addingTimeInterval(TimeInterval(decaySeconds)))
        }
        window.count += 1
        windows[key] = window
        guard window.count > maxAttempts else { return nil }
        return max(Int(window.resetAt.timeIntervalSince(now).rounded(.up)), 1)
    }

    public func remaining(key: String, maxAttempts: Int) -> Int {
        guard let window = windows[key], window.resetAt > Date() else { return maxAttempts }
        return max(maxAttempts - window.count, 0)
    }
}


/// Driver persistido do rate limiter, compartilhado entre instâncias.
public enum DatabaseRateLimiter {
    /// Retorna `nil` se permitido, ou os segundos até a janela reiniciar.
    public static func hit(
        on database: any Database,
        key: String,
        maxAttempts: Int,
        decaySeconds: Int,
        now: Date = Date()
    ) async throws -> Int? {
        try await database.transaction { transaction in
            let existing = try await RateLimitEntry.on(transaction).where("key", key).first()
            if let existing, existing.expiresAt > now {
                existing.attempts += 1
                try await existing.save(on: transaction)
            } else if let existing {
                existing.attempts = 1
                existing.expiresAt = now.addingTimeInterval(TimeInterval(decaySeconds))
                try await existing.save(on: transaction)
            } else {
                try await RateLimitEntry(
                    key: key,
                    attempts: 1,
                    expiresAt: now.addingTimeInterval(TimeInterval(decaySeconds))
                ).save(on: transaction)
            }
        }
        guard let entry = try await RateLimitEntry.on(database).where("key", key).first(),
              entry.attempts > maxAttempts else { return nil }
        return max(Int(entry.expiresAt.timeIntervalSince(now).rounded(.up)), 1)
    }

    public static func remaining(on database: any Database, key: String, maxAttempts: Int) async throws -> Int {
        guard let entry = try await RateLimitEntry.on(database).where("key", key).first(),
              entry.expiresAt > Date() else { return maxAttempts }
        return max(maxAttempts - entry.attempts, 0)
    }
}

public struct RateLimitMiddleware: AsyncMiddleware {
    public let maxAttempts: Int
    public let decaySeconds: Int
    public let keyPrefix: String

    public init(maxAttempts: Int, decaySeconds: Int = 60, keyPrefix: String = "global") {
        self.maxAttempts = maxAttempts
        self.decaySeconds = decaySeconds
        self.keyPrefix = keyPrefix
    }

    /// Limite dos endpoints de autenticação, configurável por ambiente.
    public static var auth: RateLimitMiddleware {
        RateLimitMiddleware(
            maxAttempts: RateLimitConfig.authMaxAttempts,
            decaySeconds: RateLimitConfig.authDecaySeconds,
            keyPrefix: "auth"
        )
    }

    /// Limite geral da API, configurável por ambiente.
    public static var api: RateLimitMiddleware {
        RateLimitMiddleware(
            maxAttempts: RateLimitConfig.apiMaxAttempts,
            decaySeconds: RateLimitConfig.apiDecaySeconds,
            keyPrefix: "api"
        )
    }

    public func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        let client = request.headers.first(name: "X-Forwarded-For")
            ?? request.remoteAddress?.ipAddress
            ?? "unknown"
        let key = "\(keyPrefix):\(client):\(request.method.rawValue):\(request.url.path)"
        let useDatabase = RateLimitConfig.driver == .database
        let retryAfter: Int?
        if useDatabase {
            retryAfter = try await DatabaseRateLimiter.hit(
                on: request.db, key: key, maxAttempts: maxAttempts, decaySeconds: decaySeconds)
        } else {
            retryAfter = await RateLimiterStore.shared.hit(key: key, maxAttempts: maxAttempts, decaySeconds: decaySeconds)
        }
        if let retryAfter {
            var headers = HTTPHeaders()
            headers.add(name: "Retry-After", value: "\(retryAfter)")
            headers.add(name: "X-RateLimit-Limit", value: "\(maxAttempts)")
            headers.add(name: "X-RateLimit-Remaining", value: "0")
            throw Abort(.tooManyRequests, headers: headers, reason: "Too many requests. Retry in \(retryAfter) seconds.")
        }
        let response = try await next.respond(to: request)
        response.headers.add(name: "X-RateLimit-Limit", value: "\(maxAttempts)")
        let remaining: Int
        if useDatabase {
            remaining = (try? await DatabaseRateLimiter.remaining(on: request.db, key: key, maxAttempts: maxAttempts)) ?? maxAttempts
        } else {
            remaining = await RateLimiterStore.shared.remaining(key: key, maxAttempts: maxAttempts)
        }
        response.headers.add(name: "X-RateLimit-Remaining", value: "\(remaining)")
        return response
    }
}

/// Alias no estilo do Laravel: `ThrottleMiddleware(10, decaySeconds: 60)`.
public typealias ThrottleMiddleware = RateLimitMiddleware
