import Foundation
import NIOCore
import NIOPosix
import NIOSSL
import Vapor

public enum SMTPEncryption: String, Sendable {
    case none
    case starttls
    case tls
}

/// Mailer SMTP real (RFC 5321), sobre NIO + NIOSSL.
///
/// ```env
/// MAIL_MAILER=smtp
/// MAIL_HOST=smtp.example.com
/// MAIL_PORT=587
/// MAIL_USERNAME=user
/// MAIL_PASSWORD=secret
/// MAIL_ENCRYPTION=starttls
/// ```
public struct SMTPMailer: Mailer {
    public let host: String
    public let port: Int
    public let username: String?
    public let password: String?
    public let encryption: SMTPEncryption
    public let fromAddress: String
    public let clientName: String

    public init(
        host: String,
        port: Int = 587,
        username: String? = nil,
        password: String? = nil,
        encryption: SMTPEncryption = .starttls,
        fromAddress: String = MailConfig.fromAddress,
        clientName: String = "swiftra.local"
    ) {
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.encryption = encryption
        self.fromAddress = fromAddress
        self.clientName = clientName
    }

    public static func fromEnvironment() -> SMTPMailer {
        SMTPMailer(
            host: MailConfig.smtpHost,
            port: MailConfig.smtpPort,
            username: MailConfig.smtpUsername,
            password: MailConfig.smtpPassword,
            encryption: SMTPEncryption(rawValue: MailConfig.smtpEncryption.lowercased()) ?? .starttls,
            fromAddress: MailConfig.fromAddress
        )
    }

    public func send(to: String, subject: String, body: String, logger: Logger) async throws {
        let group = MultiThreadedEventLoopGroup.singleton
        let client = try await SMTPClient.connect(
            host: host, port: port, encryption: encryption, clientName: clientName, group: group
        )
        do {
            if let username, let password {
                try await client.authenticate(username: username, password: password)
            }
            try await client.sendMail(from: fromAddress, to: to, subject: subject, body: body)
            try await client.quit()
        } catch {
            try? await client.close()
            throw error
        }
        logger.debug("SMTP mail sent to \(to) via \(host):\(port)")
    }
}

public enum SMTPError: Error, CustomStringConvertible {
    case unexpectedResponse(String)
    case connectionClosed

    public var description: String {
        switch self {
        case .unexpectedResponse(let response): "SMTP unexpected response: \(response)"
        case .connectionClosed: "SMTP connection closed"
        }
    }
}

// MARK: - Cliente SMTP (NIO)

private final class SMTPLineHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer

    private var buffer = ""
    private var lines: [String] = []
    private var waiters: [EventLoopPromise<String>] = []

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var input = unwrapInboundIn(data)
        if let text = input.readString(length: input.readableBytes) {
            buffer += text
        }
        while let range = buffer.range(of: "\r\n") ?? buffer.range(of: "\n") {
            let line = String(buffer[..<range.lowerBound])
            buffer.removeSubrange(..<range.upperBound)
            if waiters.isEmpty {
                lines.append(line)
            } else {
                waiters.removeFirst().succeed(line)
            }
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        waiters.forEach { $0.fail(SMTPError.connectionClosed) }
        waiters = []
        context.fireChannelInactive()
    }

    func nextLine(on eventLoop: EventLoop) -> EventLoopFuture<String> {
        if !lines.isEmpty {
            return eventLoop.makeSucceededFuture(lines.removeFirst())
        }
        let promise = eventLoop.makePromise(of: String.self)
        waiters.append(promise)
        return promise.futureResult
    }
}

private final class SMTPClient: @unchecked Sendable {
    private let channel: Channel
    private let handler: SMTPLineHandler
    private let clientName: String

    private init(channel: Channel, handler: SMTPLineHandler, clientName: String) {
        self.channel = channel
        self.handler = handler
        self.clientName = clientName
    }

    static func connect(
        host: String,
        port: Int,
        encryption: SMTPEncryption,
        clientName: String,
        group: EventLoopGroup
    ) async throws -> SMTPClient {
        let handler = SMTPLineHandler()
        let bootstrap = ClientBootstrap(group: group)
            .channelOption(.socketOption(.so_reuseaddr), value: 1)
            .channelInitializer { channel in
                let handlers: [ChannelHandler]
                if encryption == .tls {
                    do {
                        let context = try NIOSSLContext(configuration: .makeClientConfiguration())
                        handlers = [try NIOSSLClientHandler(context: context, serverHostname: host), handler]
                    } catch {
                        return channel.eventLoop.makeFailedFuture(error)
                    }
                } else {
                    handlers = [handler]
                }
                return channel.pipeline.addHandlers(handlers)
            }

        let channel = try await bootstrap.connect(host: host, port: port).get()
        let client = SMTPClient(channel: channel, handler: handler, clientName: clientName)
        do {
            _ = try await client.readResponse() // 220 greeting
            try await client.ehlo()
            if encryption == .starttls {
                try await client.send("STARTTLS", expecting: "220")
                let context = try NIOSSLContext(configuration: .makeClientConfiguration())
                let sslHandler = try NIOSSLClientHandler(context: context, serverHostname: host)
                try await channel.pipeline.addHandler(sslHandler, position: .first).get()
                try await client.ehlo()
            }
        } catch {
            try? await channel.close().get()
            throw error
        }
        return client
    }

    func close() async throws {
        try await channel.close().get()
    }

    func quit() async throws {
        _ = try? await send("QUIT")
        try? await channel.close().get()
    }

    func authenticate(username: String, password: String) async throws {
        _ = try await send("AUTH LOGIN", expecting: "334")
        _ = try await send(Data(username.utf8).base64EncodedString(), expecting: "334")
        _ = try await send(Data(password.utf8).base64EncodedString(), expecting: "235")
    }

    func sendMail(from: String, to: String, subject: String, body: String) async throws {
        _ = try await send("MAIL FROM:<\(from)>", expecting: "250")
        _ = try await send("RCPT TO:<\(to)>", expecting: "250")
        _ = try await send("DATA", expecting: "354")

        let headers = [
            "From: \(from)",
            "To: \(to)",
            "Subject: \(subject)",
            "MIME-Version: 1.0",
            "Content-Type: text/plain; charset=utf-8",
            "",
        ]
        let stuffedBody = body
            .components(separatedBy: "\n")
            .map { $0.hasPrefix(".") ? "." + $0 : $0 }
            .joined(separator: "\r\n")
        _ = try await send(headers.joined(separator: "\r\n") + "\r\n" + stuffedBody + "\r\n.", expecting: "250")
    }

    private func ehlo() async throws {
        _ = try await send("EHLO \(clientName)", expecting: "250")
    }

    @discardableResult
    private func send(_ command: String, expecting prefix: String? = nil) async throws -> String {
        var buffer = channel.allocator.buffer(capacity: command.utf8.count + 2)
        buffer.writeString(command + "\r\n")
        try await channel.writeAndFlush(buffer).get()
        let response = try await readResponse()
        if let prefix, !response.hasPrefix(prefix) {
            throw SMTPError.unexpectedResponse(response)
        }
        return response
    }

    /// Lê uma resposta SMTP completa (linhas `250-...` até `250 ...`).
    private func readResponse() async throws -> String {
        var collected: [String] = []
        while true {
            let line = try await handler.nextLine(on: channel.eventLoop).get()
            collected.append(line)
            if line.count < 4 || line[line.index(line.startIndex, offsetBy: 3)] != "-" {
                return collected.joined(separator: "\n")
            }
        }
    }
}
