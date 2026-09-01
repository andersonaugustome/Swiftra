import Foundation
import Vapor

public struct SwiftBladeRenderer: ViewRenderer {
    public let rootDirectory: String

    public func `for`(_ request: Request) -> ViewRenderer { self }

    public func render<E: Encodable>(_ name: String, _ context: E) -> EventLoopFuture<View> {
        let promise = eventLoop.makePromise(of: View.self)
        do {
            let relativePath = name.hasSuffix(".blade.html")
                ? name
                : name.replacingOccurrences(of: ".", with: "/") + ".blade.html"
            let path = rootDirectory + relativePath
            var template = try String(contentsOfFile: path, encoding: .utf8)
            let data = try JSONEncoder().encode(context)
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            template = render(template, values: object)
            promise.succeed(View(data: ByteBuffer(string: template)))
        } catch {
            promise.fail(error)
        }
        return promise.futureResult
    }

    private var eventLoop: EventLoop { MultiThreadedEventLoopGroup.singleton.any() }

    private func render(_ template: String, values: [String: Any]) -> String {
        var output = template
        let pattern = #"\{\{\s*([A-Za-z0-9_.]+)\s*\}\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return output }
        let matches = regex.matches(in: output, range: NSRange(output.startIndex..., in: output)).reversed()
        for match in matches {
            guard let range = Range(match.range(at: 0), in: output),
                  let keyRange = Range(match.range(at: 1), in: output) else { continue }
            let value = resolve(String(output[keyRange]), in: values)
            output.replaceSubrange(range, with: escapeHTML(value))
        }
        return output
    }

    private func resolve(_ path: String, in values: [String: Any]) -> String {
        var current: Any = values
        for component in path.split(separator: ".").map(String.init) {
            guard let dictionary = current as? [String: Any], let next = dictionary[component] else { return "" }
            current = next
        }
        return current is NSNull ? "" : String(describing: current)
    }

    private func escapeHTML(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}

extension Application.Views.Provider {
    public static func swiftBlade(rootDirectory: String) -> Self {
        .init { app in app.views.use { _ in SwiftBladeRenderer(rootDirectory: rootDirectory) } }
    }
}
