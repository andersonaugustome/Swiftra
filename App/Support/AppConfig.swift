import Foundation
import Vapor

/// Configuração central da aplicação, lida do ambiente (`.env`).
///
/// Nada de prazos ou limites fixos no código: tudo tem variável própria,
/// documentada em `.env.example`, com padrões seguros.
public enum AppConfig {
    public static var name: String { Environment.get("APP_NAME") ?? "Swiftra" }
    public static var env: String { Environment.get("APP_ENV") ?? "production" }
    public static var isTesting: Bool { env.lowercased() == "testing" || env.lowercased() == "test" }
    public static var isLocal: Bool { ["local", "development", "dev"].contains(env.lowercased()) }
    public static var url: String { Environment.get("APP_URL") ?? "http://127.0.0.1:8080" }
    public static var timezone: String { Environment.get("APP_TIMEZONE") ?? "UTC" }
}

public enum AuthConfig {
    /// Vida do access token (Bearer). Padrão: 60 minutos.
    public static var accessTokenTTLMinutes: Int {
        Environment.get("AUTH_ACCESS_TOKEN_TTL_MINUTES").flatMap(Int.init) ?? 60
    }

    /// Vida do refresh token. Padrão: 30 dias.
    public static var refreshTokenTTLDays: Int {
        Environment.get("AUTH_REFRESH_TOKEN_TTL_DAYS").flatMap(Int.init) ?? 30
    }

    /// Vida do token de redefinição de senha. Padrão: 60 minutos.
    public static var passwordResetTTLMinutes: Int {
        Environment.get("AUTH_PASSWORD_RESET_TTL_MINUTES").flatMap(Int.init) ?? 60
    }

    /// Vida do token de verificação de email. Padrão: 24 horas.
    public static var emailVerificationTTLHours: Int {
        Environment.get("AUTH_EMAIL_VERIFICATION_TTL_HOURS").flatMap(Int.init) ?? 24
    }

    /// Vida do desafio MFA (login em duas etapas). Padrão: 5 minutos.
    public static var mfaChallengeTTLMinutes: Int {
        Environment.get("AUTH_MFA_CHALLENGE_TTL_MINUTES").flatMap(Int.init) ?? 5
    }

    /// Exige email verificado para emitir tokens? Padrão: não (opt-in).
    public static var requireVerifiedEmail: Bool {
        (Environment.get("AUTH_REQUIRE_VERIFIED_EMAIL") ?? "false").lowercased() == "true"
    }

    public static var defaultRole: String {
        Environment.get("AUTH_DEFAULT_ROLE") ?? "user"
    }
}

public enum RateLimitDriver: String, Sendable {
    case database
    case memory
}

public enum RateLimitConfig {
    /// `database` (padrão, compartilhado) ou `memory` (processo único).
    public static var driver: RateLimitDriver {
        RateLimitDriver(rawValue: (Environment.get("RATE_LIMIT_DRIVER") ?? "database").lowercased()) ?? .database
    }

    /// Tentativas por janela nos endpoints de autenticação. Padrão: 10/min por IP.
    public static var authMaxAttempts: Int {
        Environment.get("RATE_LIMIT_AUTH_MAX").flatMap(Int.init) ?? 10
    }

    public static var authDecaySeconds: Int {
        Environment.get("RATE_LIMIT_AUTH_DECAY_SECONDS").flatMap(Int.init) ?? 60
    }

    /// Limite geral da API. Padrão: 120/min por IP.
    public static var apiMaxAttempts: Int {
        Environment.get("RATE_LIMIT_API_MAX").flatMap(Int.init) ?? 120
    }

    public static var apiDecaySeconds: Int {
        Environment.get("RATE_LIMIT_API_DECAY_SECONDS").flatMap(Int.init) ?? 60
    }
}

public enum MailConfig {
    public static var fromAddress: String { Environment.get("MAIL_FROM_ADDRESS") ?? "no-reply@swiftra.local" }
    public static var fromName: String { Environment.get("MAIL_FROM_NAME") ?? AppConfig.name }
    /// `log` (padrão, desenvolvimento) ou `smtp` (envio real via `SMTPMailer`).
    public static var mailer: String { Environment.get("MAIL_MAILER") ?? "log" }
    public static var smtpHost: String { Environment.get("MAIL_HOST") ?? "127.0.0.1" }
    public static var smtpPort: Int { Environment.get("MAIL_PORT").flatMap(Int.init) ?? 587 }
    public static var smtpUsername: String? { Environment.get("MAIL_USERNAME") }
    public static var smtpPassword: String? { Environment.get("MAIL_PASSWORD") }
    /// `none`, `starttls` (padrão) ou `tls` (implícito, porta 465).
    public static var smtpEncryption: String { Environment.get("MAIL_ENCRYPTION") ?? "starttls" }
}
