import Vapor

/// Envio de email. O mailer padrão apenas registra no log (`MAIL_MAILER=log`),
/// como o `log` mailer do Laravel em desenvolvimento — nenhum email sai da
/// máquina sem um provedor real configurado pela aplicação.
public protocol Mailer: Sendable {
    func send(to: String, subject: String, body: String, logger: Logger) async throws
}

public struct LogMailer: Mailer {
    public init() {}

    public func send(to: String, subject: String, body: String, logger: Logger) async throws {
        logger.info("Mail (log mailer) to=\(to) subject=\(subject)\n\(body)")
    }
}

public enum Mail {
    /// Mailer ativo, escolhido por `MAIL_MAILER`: `log` ou `smtp`.
    public static var mailer: any Mailer {
        MailConfig.mailer.lowercased() == "smtp" ? SMTPMailer.fromEnvironment() : LogMailer()
    }

    public static func send(to: String, subject: String, body: String, logger: Logger) async throws {
        try await mailer.send(
            to: to,
            subject: "[\(MailConfig.fromName)] \(subject)",
            body: body,
            logger: logger
        )
    }

    public static func sendPasswordReset(to email: String, token: String, logger: Logger) async throws {
        let url = "\(AppConfig.url)/reset-password?token=\(token)&email=\(email)"
        try await send(
            to: email,
            subject: "Redefinição de senha",
            body: "Use este link dentro de \(AuthConfig.passwordResetTTLMinutes) minutos para redefinir sua senha:\n\(url)\n\nSe você não solicitou, ignore este email.",
            logger: logger
        )
    }

    public static func sendEmailVerification(to email: String, token: String, logger: Logger) async throws {
        let url = "\(AppConfig.url)/verify-email?token=\(token)"
        try await send(
            to: email,
            subject: "Confirme seu email",
            body: "Confirme seu endereço de email dentro de \(AuthConfig.emailVerificationTTLHours) horas:\n\(url)",
            logger: logger
        )
    }
}
