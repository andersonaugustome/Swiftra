import App
import Foundation
import NIOCore
import NIOPosix
import Testing
import Vapor

/// Servidor SMTP mínimo em memória: registra os comandos e responde
/// o suficiente para o cliente concluir `MAIL FROM/RCPT/DATA/QUIT`.
private final class FakeSMTPHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    let recorder: Recorder
    private var buffer = ""
    private var inData = false

    final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [String] = []

        func append(_ line: String) { lock.withLock { storage.append(line) } }
        var lines: [String] { lock.withLock { storage } }
    }

    init(recorder: Recorder) { self.recorder = recorder }

    func channelActive(context: ChannelHandlerContext) {
        respond(context, "220 fake.smtp ESMTP ready")
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var input = unwrapInboundIn(data)
        buffer += input.readString(length: input.readableBytes) ?? ""
        while let range = buffer.range(of: "\r\n") ?? buffer.range(of: "\n") {
            let line = String(buffer[..<range.lowerBound])
            buffer.removeSubrange(..<range.upperBound)
            handle(context, line: line)
        }
    }

    private func handle(_ context: ChannelHandlerContext, line: String) {
        if inData {
            recorder.append("DATA-LINE: \(line)")
            if line == "." {
                inData = false
                respond(context, "250 queued")
            }
            return
        }
        recorder.append(line)
        let command = line.uppercased()
        if command.hasPrefix("EHLO") || command.hasPrefix("HELO") {
            respond(context, "250-fake.smtp greets")
            respond(context, "250 AUTH LOGIN")
        } else if command.hasPrefix("AUTH LOGIN") {
            respond(context, "334 VXNlcm5hbWU6")
        } else if command.hasPrefix("MAIL FROM") || command.hasPrefix("RCPT TO") {
            respond(context, "250 ok")
        } else if command.hasPrefix("DATA") {
            inData = true
            respond(context, "354 end with .")
        } else if command.hasPrefix("QUIT") {
            respond(context, "221 bye")
        } else if line == Data("user".utf8).base64EncodedString() {
            respond(context, "334 UGFzc3dvcmQ6")
        } else {
            // Senha em Base64 (ou qualquer outra linha de AUTH).
            respond(context, "235 authenticated")
        }
    }

    private func respond(_ context: ChannelHandlerContext, _ text: String) {
        var buffer = context.channel.allocator.buffer(capacity: text.count + 2)
        buffer.writeString(text + "\r\n")
        context.writeAndFlush(wrapOutboundOut(buffer), promise: nil)
    }
}

@Suite("SMTP mailer")
struct SMTPMailerTests {
    @Test("SMTPMailer delivers mail through a real SMTP conversation")
    func delivers() async throws {
        let recorder = FakeSMTPHandler.Recorder()
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let server = try await ServerBootstrap(group: group)
            .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.addHandler(FakeSMTPHandler(recorder: recorder))
            }
            .bind(host: "127.0.0.1", port: 0)
            .get()
        let port = try #require(server.localAddress?.port)
        defer {
            Task {
                try? await server.close().get()
                try? await group.shutdownGracefully()
            }
        }

        let mailer = SMTPMailer(
            host: "127.0.0.1",
            port: port,
            username: "user",
            password: "secret",
            encryption: .none,
            fromAddress: "no-reply@swiftra.local",
            clientName: "swiftra.test"
        )
        let logger = Logger(label: "smtp-test")
        try await mailer.send(
            to: "dest@example.com",
            subject: "Hello SMTP",
            body: "First line\n.second line dot-stuffed",
            logger: logger
        )

        let lines = recorder.lines
        #expect(lines.contains { $0.hasPrefix("EHLO swiftra.test") })
        #expect(lines.contains("AUTH LOGIN"))
        #expect(lines.contains { $0.hasPrefix("MAIL FROM:<no-reply@swiftra.local>") })
        #expect(lines.contains { $0.hasPrefix("RCPT TO:<dest@example.com>") })
        #expect(lines.contains("DATA-LINE: Subject: Hello SMTP"))
        #expect(lines.contains("DATA-LINE: First line"))
        #expect(lines.contains("DATA-LINE: ..second line dot-stuffed"))
        #expect(lines.contains("QUIT"))
    }

    @Test("MAIL_MAILER=smtp selects the SMTP mailer")
    func selectsSMTP() {
        setenv("MAIL_MAILER", "smtp", 1)
        defer { unsetenv("MAIL_MAILER") }
        #expect(Mail.mailer is SMTPMailer)
        unsetenv("MAIL_MAILER")
        #expect(Mail.mailer is LogMailer)
    }
}
