import Foundation
import Vapor

/// Engine de templates SwiftBlade, inspirada no Blade do Laravel.
///
/// Recursos: `{{ }}` escapado, `{!! !!}` cru, comentários `{{-- --}}`,
/// `@if/@elseif/@else`, `@unless`, `@isset`, `@empty`, `@foreach`, `@forelse`,
/// `@for`, `@switch/@case/@default`, `@extends/@section/@yield/@parent`,
/// `@include`, `@component`/`<x-...>`, `@push/@stack`, `@auth/@guest`,
/// `@csrf`, `@method`, `@swift` (declarações no template), `@break/@continue` e expressões.
public struct SwiftBladeRenderer: ViewRenderer {
    public let rootDirectory: String

    public init(rootDirectory: String) {
        self.rootDirectory = rootDirectory
    }

    public func `for`(_ request: Request) -> ViewRenderer { self }

    public func render<E: Encodable>(_ name: String, _ context: E) -> EventLoopFuture<View> {
        let promise = eventLoop.makePromise(of: View.self)
        do {
            let data = try JSONEncoder().encode(context)
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            let rendered = try render(view: name, context: object)
            promise.succeed(View(data: ByteBuffer(string: rendered)))
        } catch {
            promise.fail(error)
        }
        return promise.futureResult
    }

    /// Renderiza uma view pelo nome (`users.index` ou `users/index`).
    public func render(view name: String, context: [String: Any]) throws -> String {
        let engine = BladeEngine(rootDirectory: rootDirectory)
        return try engine.render(view: name, context: context)
    }

    /// Renderiza um template em memória — útil em testes e componentes.
    public func renderString(_ template: String, context: [String: Any] = [:]) throws -> String {
        let engine = BladeEngine(rootDirectory: rootDirectory)
        return try engine.renderString(template, context: context)
    }

    private var eventLoop: EventLoop { MultiThreadedEventLoopGroup.singleton.any() }
}

extension Application.Views.Provider {
    public static func swiftBlade(rootDirectory: String) -> Self {
        .init { app in app.views.use { _ in SwiftBladeRenderer(rootDirectory: rootDirectory) } }
    }
}

// MARK: - Erros

public enum SwiftBladeError: Error, CustomStringConvertible {
    case viewNotFound(String)
    case syntax(String)

    public var description: String {
        switch self {
        case .viewNotFound(let name): "SwiftBlade view not found: \(name)"
        case .syntax(let message): "SwiftBlade syntax error: \(message)"
        }
    }
}

// MARK: - Engine

struct BladeEngine {
    let rootDirectory: String

    func load(view name: String) throws -> String {
        let relativePath = name.hasSuffix(".blade.html")
            ? name
            : name.replacingOccurrences(of: ".", with: "/") + ".blade.html"
        let path = rootDirectory + relativePath
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
            throw SwiftBladeError.viewNotFound(name)
        }
        return contents
    }

    func render(view name: String, context: [String: Any]) throws -> String {
        try renderString(load(view: name), context: context)
    }

    func renderString(_ template: String, context: [String: Any]) throws -> String {
        var state = RenderState()
        return stripParentPlaceholders(try render(template: template, context: context, state: &state))
    }

    static func parentPlaceholder(_ section: String) -> String {
        "\u{01}swiftblade-parent:\(section)\u{02}"
    }

    func stripParentPlaceholders(_ output: String) -> String {
        var result = output
        while let start = result.range(of: "\u{01}swiftblade-parent:"),
              let end = result.range(of: "\u{02}", range: start.upperBound..<result.endIndex) {
            result.replaceSubrange(start.lowerBound..<end.upperBound, with: "")
        }
        return result
    }

    struct RenderState {
        var sections: [String: String] = [:]
        var sectionBodies: [String: [BladeNode]] = [:]
        var stacks: [String: [String]] = [:]
        var currentSection: String?
        var flow: Flow?
    }

    enum Flow { case breakLoop, continueLoop }

    func render(template: String, context: [String: Any], state: inout RenderState) throws -> String {
        let nodes = BladeParser.parse(template)

        // Layout: @extends coleta as seções e renderiza o layout.
        if let extendsIndex = nodes.firstIndex(where: { if case .extends = $0 { return true }; return false }),
           case .extends(let layout) = nodes[extendsIndex] {
            for node in nodes {
                if case .section(let name, let body, _) = node {
                    state.sectionBodies[name] = body
                    let previousSection = state.currentSection
                    state.currentSection = name
                    let rendered = try renderNodes(body, context: context, state: &state)
                    state.currentSection = previousSection
                    if let derived = state.sections[name] {
                        // @parent da seção derivada recebe o conteúdo desta camada.
                        state.sections[name] = derived.replacingOccurrences(
                            of: Self.parentPlaceholder(name), with: rendered)
                    } else {
                        state.sections[name] = rendered
                    }
                }
            }
            return try render(template: load(view: layout), context: context, state: &state)
        }
        return try renderNodes(nodes, context: context, state: &state)
    }

    func renderNodes(_ nodes: [BladeNode], context: [String: Any], state: inout RenderState) throws -> String {
        var output = ""
        var context = context
        for node in nodes {
            if case .swiftCode(let assignments) = node {
                for assignment in assignments {
                    context[assignment.name] = BladeExpression.evaluate(assignment.expression, in: context) ?? NSNull()
                }
                continue
            }
            output += try renderNode(node, context: context, state: &state)
            if state.flow != nil { return output }
        }
        return output
    }

    private func renderNode(_ node: BladeNode, context: [String: Any], state: inout RenderState) throws -> String {
        switch node {
        case .text(let text):
            return text
        case .echo(let expression, let escaped):
            let value = BladeExpression.stringify(BladeExpression.evaluate(expression, in: context))
            return escaped ? escapeHTML(value) : value
        case .ifBlock(let branches):
            for branch in branches {
                if let condition = branch.condition {
                    if BladeExpression.evaluateBool(condition, in: context) {
                        return try renderNodes(branch.body, context: context, state: &state)
                    }
                } else {
                    return try renderNodes(branch.body, context: context, state: &state)
                }
            }
            return ""
        case .unless(let condition, let body, let elseBody):
            if !BladeExpression.evaluateBool(condition, in: context) {
                return try renderNodes(body, context: context, state: &state)
            }
            return try renderNodes(elseBody, context: context, state: &state)
        case .isset(let expression, let body, let elseBody, let negate):
            let present = BladeExpression.evaluate(expression, in: context) != nil
            let condition = negate ? !BladeExpression.isTruthy(BladeExpression.evaluate(expression, in: context)) : present
            return condition
                ? try renderNodes(body, context: context, state: &state)
                : try renderNodes(elseBody, context: context, state: &state)
        case .foreach(let variable, let indexVariable, let collection, let body, let emptyBody):
            return try renderLoop(variable: variable, indexVariable: indexVariable, collection: collection, body: body, emptyBody: emptyBody, context: context, state: &state)
        case .switchBlock(let expression, let cases):
            let subject = BladeExpression.evaluate(expression, in: context)
            var matched = false
            var output = ""
            for entry in cases {
                if let caseExpression = entry.condition {
                    if !matched && BladeExpression.valuesEqual(subject, BladeExpression.evaluate(caseExpression, in: context)) {
                        matched = true
                    }
                } else if !matched {
                    matched = true // @default
                }
                if matched {
                    output += try renderNodes(entry.body, context: context, state: &state)
                    if state.flow == .breakLoop {
                        state.flow = nil
                        break
                    }
                }
            }
            return output
        case .section(let name, let body, let show):
            state.sectionBodies[name] = body
            let previousSection = state.currentSection
            state.currentSection = name
            let rendered = try renderNodes(body, context: context, state: &state)
            state.currentSection = previousSection
            if let derived = state.sections[name], derived != rendered {
                let merged = derived.replacingOccurrences(of: Self.parentPlaceholder(name), with: rendered)
                state.sections[name] = merged
                return show ? merged : ""
            }
            state.sections[name] = rendered
            return show ? rendered : ""
        case .inlineSection(let name, let valueExpression):
            let rendered = BladeExpression.stringify(BladeExpression.evaluate(valueExpression, in: context))
            state.sections[name] = rendered
            state.sectionBodies[name] = [.text(rendered)]
            return ""
        case .yield(let name, let defaultExpression):
            if let section = state.sections[name] {
                return section.replacingOccurrences(of: Self.parentPlaceholder(name), with: "")
            }
            guard let defaultExpression else { return "" }
            return BladeExpression.stringify(BladeExpression.evaluate(defaultExpression, in: context))
        case .parent:
            return Self.parentPlaceholder(state.currentSection ?? "")
        case .include(let view, let extra):
            var merged = context
            for (key, expression) in extra {
                merged[key] = BladeExpression.evaluate(expression, in: context) ?? NSNull()
            }
            return try render(template: load(view: view), context: merged, state: &state)
        case .component(let name, let attributes, let body):
            return try renderComponent(name: name, attributes: attributes, body: body, context: context, state: &state)
        case .push(let name, let body):
            state.stacks[name, default: []].append(try renderNodes(body, context: context, state: &state))
            return ""
        case .stack(let name):
            return state.stacks[name]?.joined() ?? ""
        case .authBlock(let body, let elseBody, let guest):
            let user = context["user"] ?? context["auth_user"] ?? context["authUser"]
            let authenticated = BladeExpression.isTruthy(user)
            let condition = guest ? !authenticated : authenticated
            return condition
                ? try renderNodes(body, context: context, state: &state)
                : try renderNodes(elseBody, context: context, state: &state)
        case .csrf:
            let token = BladeExpression.stringify(context["csrf_token"] ?? context["csrfToken"])
            return "<input type=\"hidden\" name=\"_token\" value=\"\(escapeHTML(token))\">"
        case .method(let verb):
            return "<input type=\"hidden\" name=\"_method\" value=\"\(escapeHTML(verb.uppercased()))\">"
        case .breakDirective:
            state.flow = .breakLoop
            return ""
        case .continueDirective:
            state.flow = .continueLoop
            return ""
        case .extends, .swiftCode:
            return ""
        }
    }

    private func renderLoop(
        variable: String, indexVariable: String?, collection: String,
        body: [BladeNode], emptyBody: [BladeNode], context: [String: Any],
        state: inout RenderState
    ) throws -> String {
        let value = BladeExpression.evaluate(collection, in: context)
        var items: [(index: Any, element: Any)] = []
        if let array = value as? [Any] {
            items = array.enumerated().map { ($0.offset, $0.element) }
        } else if let dictionary = value as? [String: Any] {
            items = dictionary.keys.sorted().map { ($0 as Any, dictionary[$0] as Any) }
        }
        guard !items.isEmpty else {
            return try renderNodes(emptyBody, context: context, state: &state)
        }
        var output = ""
        for (offset, item) in items.enumerated() {
            var loopContext = context
            loopContext[variable] = item.element
            if let indexVariable { loopContext[indexVariable] = item.index }
            loopContext["loop"] = [
                "index": offset,
                "iteration": offset + 1,
                "count": items.count,
                "first": offset == 0,
                "last": offset == items.count - 1,
                "remaining": items.count - offset - 1,
            ] as [String: Any]
            output += try renderNodes(body, context: loopContext, state: &state)
            if state.flow == .breakLoop {
                state.flow = nil
                break
            }
            if state.flow == .continueLoop {
                state.flow = nil
                continue
            }
        }
        return output
    }

    private func renderComponent(
        name: String, attributes: [(key: String, expression: String?, isBound: Bool)],
        body: [BladeNode], context: [String: Any], state: inout RenderState
    ) throws -> String {
        // Slots nomeados: <x-slot name="header">...</x-slot>
        var slots: [String: String] = [:]
        var defaultBody: [BladeNode] = []
        for node in body {
            if case .component(let slotName, let slotAttributes, let slotBody) = node, slotName == "slot" {
                let slotTitle = slotAttributes.first(where: { $0.key == "name" })?.expression ?? "slot"
                slots[BladeExpression.stringify(BladeExpression.evaluate(slotTitle, in: context))] =
                    try renderNodes(slotBody, context: context, state: &state)
            } else {
                defaultBody.append(node)
            }
        }
        var componentContext = context
        for attribute in attributes {
            let key = attribute.key.split(separator: "-").enumerated().map { index, part in
                index == 0 ? String(part) : part.prefix(1).uppercased() + part.dropFirst()
            }.joined()
            if let expression = attribute.expression {
                componentContext[key] = attribute.isBound
                    ? BladeExpression.evaluate(expression, in: context) ?? NSNull()
                    : expression
            } else {
                componentContext[key] = true
            }
        }
        componentContext["slot"] = try renderNodes(defaultBody, context: context, state: &state)
        for (key, value) in slots { componentContext[key] = value }
        let viewName = name.contains("/") || name.contains(".") ? name : "components.\(name)"
        return try render(template: load(view: viewName), context: componentContext, state: &state)
    }

    func escapeHTML(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
