import Foundation

// MARK: - Nós da árvore do template

enum BladeNode {
    case text(String)
    case echo(expression: String, escaped: Bool)
    case ifBlock(branches: [(condition: String?, body: [BladeNode])])
    case unless(condition: String, body: [BladeNode], elseBody: [BladeNode])
    case isset(expression: String, body: [BladeNode], elseBody: [BladeNode], negate: Bool)
    case foreach(variable: String, index: String?, collection: String, body: [BladeNode], emptyBody: [BladeNode])
    case switchBlock(expression: String, cases: [(condition: String?, body: [BladeNode])])
    case section(name: String, body: [BladeNode], show: Bool)
    case inlineSection(name: String, value: String)
    case yield(name: String, defaultValue: String?)
    case parent
    case include(view: String, extra: [(key: String, expression: String)])
    case component(name: String, attributes: [(key: String, expression: String?, isBound: Bool)], body: [BladeNode])
    case push(name: String, body: [BladeNode])
    case stack(name: String)
    case authBlock(body: [BladeNode], elseBody: [BladeNode], guest: Bool)
    case csrf
    case method(String)
    case extends(String)
    case swiftCode([(name: String, expression: String)])
    case breakDirective
    case continueDirective
}

// MARK: - Tokens

private enum BladeToken {
    case text(String)
    case echo(String, Bool)
    case directive(name: String, args: String?)
    case componentStart(name: String, attributes: [(key: String, expression: String?, isBound: Bool)], selfClosing: Bool)
    case componentEnd(name: String)
}

private let knownDirectives: Set<String> = [
    "if", "elseif", "else", "endif", "unless", "endunless", "isset", "endisset",
    "empty", "endempty", "foreach", "endforeach", "forelse", "endforelse", "for", "endfor",
    "switch", "case", "default", "break", "continue", "endswitch",
    "extends", "section", "endsection", "show", "yield", "parent",
    "include", "component", "endcomponent", "push", "endpush", "stack",
    "auth", "endauth", "guest", "endguest", "csrf", "method", "verbatim", "endverbatim", "swift", "endswift",
]

// MARK: - Parser

enum BladeParser {
    static func parse(_ template: String) -> [BladeNode] {
        var parser = Parser(tokens: tokenize(template))
        return parser.parseNodes(stopAt: [])
    }

    // MARK: Tokenização

    private static func tokenize(_ template: String) -> [BladeToken] {
        var tokens: [BladeToken] = []
        let chars = Array(template)
        var i = 0
        var text = ""

        func flushText() {
            guard !text.isEmpty else { return }
            tokens.append(.text(text))
            text = ""
        }
        func substring(_ range: Range<Int>) -> String { String(chars[range]) }
        func find(_ needle: String, from start: Int) -> Int? {
            let target = Array(needle)
            guard start + target.count <= chars.count else { return nil }
            for index in start...(chars.count - target.count) {
                if Array(chars[index..<(index + target.count)]) == target { return index }
            }
            return nil
        }

        while i < chars.count {
            // Comentário {{-- --}}
            if substring(i..<min(i + 4, chars.count)) == "{{--", let end = find("--}}", from: i + 4) {
                i = end + 4
                continue
            }
            // Echo cru {!! !!}
            if substring(i..<min(i + 3, chars.count)) == "{!!", let end = find("!!}", from: i + 3) {
                flushText()
                tokens.append(.echo(substring((i + 3)..<end).trimmingCharacters(in: .whitespacesAndNewlines), false))
                i = end + 3
                continue
            }
            // Echo escapado {{ }}
            if substring(i..<min(i + 2, chars.count)) == "{{", let end = find("}}", from: i + 2) {
                flushText()
                tokens.append(.echo(substring((i + 2)..<end).trimmingCharacters(in: .whitespacesAndNewlines), true))
                i = end + 2
                continue
            }
            // Componente <x-nome ...>
            if substring(i..<min(i + 3, chars.count)) == "<x-", let end = find(">", from: i) {
                let inner = substring((i + 3)..<end)
                let selfClosing = inner.hasSuffix("/")
                let parts = inner.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                let nameEnd = parts.firstIndex(where: { $0.isWhitespace }) ?? parts.endIndex
                let name = String(parts[..<nameEnd])
                flushText()
                tokens.append(.componentStart(
                    name: name,
                    attributes: parseAttributes(String(parts[nameEnd...])),
                    selfClosing: selfClosing
                ))
                i = end + 1
                continue
            }
            if substring(i..<min(i + 4, chars.count)) == "</x-", let end = find(">", from: i) {
                flushText()
                tokens.append(.componentEnd(name: substring((i + 4)..<end).trimmingCharacters(in: .whitespaces)))
                i = end + 1
                continue
            }
            // Diretiva @nome(args)
            if chars[i] == "@", i + 1 < chars.count, chars[i + 1].isLetter {
                var j = i + 1
                var word = ""
                while j < chars.count && chars[j].isLetter { word.append(chars[j]); j += 1 }
                if word == "verbatim", let end = find("@endverbatim", from: j) {
                    text += substring(j..<end)
                    i = end + "@endverbatim".count
                    continue
                }
                if knownDirectives.contains(word) {
                    flushText()
                    var args: String?
                    var k = j
                    while k < chars.count && (chars[k] == " " || chars[k] == "\t") { k += 1 }
                    if k < chars.count && chars[k] == "(" {
                        var depth = 0
                        var m = k
                        var quote: Character?
                        while m < chars.count {
                            let ch = chars[m]
                            if let active = quote {
                                if ch == active { quote = nil }
                            } else if ch == "'" || ch == "\"" {
                                quote = ch
                            } else if ch == "(" { depth += 1 }
                            else if ch == ")" {
                                depth -= 1
                                if depth == 0 { break }
                            }
                            m += 1
                        }
                        args = substring((k + 1)..<m)
                        j = m + 1
                    }
                    tokens.append(.directive(name: word, args: args))
                    i = j
                    continue
                }
            }
            text.append(chars[i])
            i += 1
        }
        flushText()
        return tokens
    }

    private static func parseAttributes(_ source: String) -> [(key: String, expression: String?, isBound: Bool)] {
        var attributes: [(String, String?, Bool)] = []
        let chars = Array(source)
        var i = 0
        while i < chars.count {
            while i < chars.count && chars[i].isWhitespace { i += 1 }
            guard i < chars.count else { break }
            var bound = false
            if chars[i] == ":" { bound = true; i += 1 }
            var key = ""
            while i < chars.count && (chars[i].isLetter || chars[i].isNumber || chars[i] == "-" || chars[i] == "_") {
                key.append(chars[i]); i += 1
            }
            while i < chars.count && chars[i].isWhitespace { i += 1 }
            var value: String?
            if i < chars.count && chars[i] == "=" {
                i += 1
                while i < chars.count && chars[i].isWhitespace { i += 1 }
                if i < chars.count && (chars[i] == "\"" || chars[i] == "'") {
                    let quote = chars[i]
                    i += 1
                    var collected = ""
                    while i < chars.count && chars[i] != quote { collected.append(chars[i]); i += 1 }
                    i += 1
                    value = collected
                }
            }
            if !key.isEmpty { attributes.append((key, value, bound)) }
        }
        return attributes
    }

    // MARK: Construção da árvore

    private struct Parser {
        let tokens: [BladeToken]
        var position = 0

        mutating func parseNodes(stopAt: Set<String>) -> [BladeNode] {
            var nodes: [BladeNode] = []
            while position < tokens.count {
                switch tokens[position] {
                case .text(let text):
                    nodes.append(.text(text)); position += 1
                case .echo(let expression, let escaped):
                    nodes.append(.echo(expression: expression, escaped: escaped)); position += 1
                case .componentEnd:
                    return nodes
                case .componentStart(let name, let attributes, let selfClosing):
                    position += 1
                    let body = selfClosing ? [] : parseNodes(stopAt: ["componentEnd"])
                    if position < tokens.count, case .componentEnd = tokens[position] { position += 1 }
                    nodes.append(.component(name: name, attributes: attributes, body: body))
                case .directive(let name, let args):
                    if stopAt.contains(name) { return nodes }
                    position += 1
                    if let node = parseDirective(name: name, args: args) {
                        nodes.append(node)
                    }
                }
            }
            return nodes
        }

        private mutating func consumeDirective(_ names: Set<String>) -> (name: String, args: String?)? {
            guard position < tokens.count, case .directive(let name, let args) = tokens[position], names.contains(name) else {
                return nil
            }
            position += 1
            return (name, args)
        }

        private mutating func parseDirective(name: String, args: String?) -> BladeNode? {
            switch name {
            case "extends":
                return .extends(unquote(args ?? ""))
            case "csrf":
                return .csrf
            case "method":
                return .method(unquote(args ?? ""))
            case "parent":
                return .parent
            case "break":
                return .breakDirective
            case "continue":
                return .continueDirective
            case "yield":
                let parts = splitTopLevel(args ?? "")
                return .yield(name: unquote(parts.first ?? ""), defaultValue: parts.count > 1 ? parts[1] : nil)
            case "stack":
                return .stack(name: unquote(args ?? ""))
            case "include":
                let parts = splitTopLevel(args ?? "")
                var extra: [(String, String)] = []
                if parts.count > 1 { extra = parseDataArgument(parts[1]) }
                return .include(view: unquote(parts.first ?? ""), extra: extra)
            case "section":
                let parts = splitTopLevel(args ?? "")
                if parts.count > 1 {
                    return .inlineSection(name: unquote(parts[0]), value: parts[1])
                }
                let body = parseNodes(stopAt: ["endsection", "show"])
                let show = consumeDirective(["endsection", "show"])?.name == "show"
                return .section(name: unquote(parts.first ?? ""), body: body, show: show)
            case "push":
                let body = parseNodes(stopAt: ["endpush"])
                _ = consumeDirective(["endpush"])
                return .push(name: unquote(args ?? ""), body: body)
            case "component":
                let parts = splitTopLevel(args ?? "")
                var attributes: [(String, String?, Bool)] = []
                if parts.count > 1 {
                    attributes = parseDataArgument(parts[1]).map { ($0.key, $0.expression, true) }
                }
                let body = parseNodes(stopAt: ["endcomponent"])
                _ = consumeDirective(["endcomponent"])
                return .component(name: unquote(parts.first ?? ""), attributes: attributes, body: body)
            case "swift":
                if let args {
                    return .swiftCode(parseSwiftAssignments(args))
                }
                let body = parseNodes(stopAt: ["endswift"])
                _ = consumeDirective(["endswift"])
                let raw = body.compactMap { node -> String? in
                    if case .text(let text) = node { return text }
                    return nil
                }.joined()
                return .swiftCode(parseSwiftAssignments(raw))
            case "if":
                var branches: [(String?, [BladeNode])] = []
                var condition: String? = args
                while true {
                    let body = parseNodes(stopAt: ["elseif", "else", "endif"])
                    branches.append((condition, body))
                    guard let next = consumeDirective(["elseif", "else", "endif"]) else { break }
                    if next.name == "endif" { break }
                    condition = next.name == "elseif" ? next.args : nil
                }
                return .ifBlock(branches: branches)
            case "unless":
                let body = parseNodes(stopAt: ["else", "endunless"])
                var elseBody: [BladeNode] = []
                if consumeDirective(["else"]) != nil {
                    elseBody = parseNodes(stopAt: ["endunless"])
                }
                _ = consumeDirective(["endunless"])
                return .unless(condition: args ?? "", body: body, elseBody: elseBody)
            case "isset", "empty":
                let body = parseNodes(stopAt: ["else", "endisset", "endempty"])
                var elseBody: [BladeNode] = []
                if consumeDirective(["else"]) != nil {
                    elseBody = parseNodes(stopAt: ["endisset", "endempty"])
                }
                _ = consumeDirective(["endisset", "endempty"])
                return .isset(expression: args ?? "", body: body, elseBody: elseBody, negate: name == "empty")
            case "auth", "guest":
                let end = name == "auth" ? "endauth" : "endguest"
                let body = parseNodes(stopAt: ["else", end])
                var elseBody: [BladeNode] = []
                if consumeDirective(["else"]) != nil {
                    elseBody = parseNodes(stopAt: [end])
                }
                _ = consumeDirective([end])
                return .authBlock(body: body, elseBody: elseBody, guest: name == "guest")
            case "foreach", "for":
                let (variable, index, collection) = parseLoopHeader(args ?? "")
                let body = parseNodes(stopAt: ["endforeach", "endfor"])
                _ = consumeDirective(["endforeach", "endfor"])
                return .foreach(variable: variable, index: index, collection: collection, body: body, emptyBody: [])
            case "forelse":
                let (variable, index, collection) = parseLoopHeader(args ?? "")
                let body = parseNodes(stopAt: ["empty", "endforelse"])
                var emptyBody: [BladeNode] = []
                if consumeDirective(["empty"]) != nil {
                    emptyBody = parseNodes(stopAt: ["endforelse"])
                }
                _ = consumeDirective(["endforelse"])
                return .foreach(variable: variable, index: index, collection: collection, body: body, emptyBody: emptyBody)
            case "switch":
                var cases: [(String?, [BladeNode])] = []
                _ = parseNodes(stopAt: ["case", "default", "endswitch"])
                while let next = consumeDirective(["case", "default", "endswitch"]) {
                    if next.name == "endswitch" { break }
                    let body = parseNodes(stopAt: ["case", "default", "endswitch"])
                    cases.append((next.name == "case" ? next.args : nil, body))
                }
                return .switchBlock(expression: args ?? "", cases: cases)
            default:
                return nil
            }
        }
    }

    // MARK: Utilidades

    private static func unquote(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if (trimmed.hasPrefix("'") && trimmed.hasSuffix("'")) || (trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"")) {
            return String(trimmed.dropFirst().dropLast())
        }
        return trimmed
    }

    /// Divide por vírgulas que não estejam dentro de (), [] ou aspas.
    private static func splitTopLevel(_ source: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var depth = 0
        var quote: Character?
        for ch in source {
            if let active = quote {
                current.append(ch)
                if ch == active { quote = nil }
                continue
            }
            if ch == "'" || ch == "\"" { quote = ch; current.append(ch); continue }
            if ch == "(" || ch == "[" || ch == "{" { depth += 1 }
            if ch == ")" || ch == "]" || ch == "}" { depth -= 1 }
            if ch == "," && depth == 0 {
                parts.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                current = ""
                continue
            }
            current.append(ch)
        }
        if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return parts
    }

    /// `['title' => expr, 'user' => user]` (Blade/PHP) ou `{"title": expr}`.
    private static func parseDataArgument(_ source: String) -> [(key: String, expression: String)] {
        var inner = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if (inner.hasPrefix("[") && inner.hasSuffix("]")) || (inner.hasPrefix("{") && inner.hasSuffix("}")) {
            inner = String(inner.dropFirst().dropLast())
        }
        return splitTopLevel(inner).compactMap { pair in
            for separator in ["=>", ":"] {
                if let range = pair.range(of: separator) {
                    let key = unquote(String(pair[..<range.lowerBound]))
                    let value = String(pair[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    return (key, value)
                }
            }
            return nil
        }
    }

    /// Aceita `users as user`, `users as key => user` e `user in users`.
    private static func parseLoopHeader(_ source: String) -> (variable: String, index: String?, collection: String) {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = trimmed.range(of: " as ") {
            let collection = String(trimmed[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            let right = String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            if let arrow = right.range(of: "=>") {
                let key = String(right[..<arrow.lowerBound]).trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "$", with: "")
                let value = String(right[arrow.upperBound...]).trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "$", with: "")
                return (value, key, collection)
            }
            return (right.replacingOccurrences(of: "$", with: ""), nil, collection)
        }
        if let range = trimmed.range(of: " in ") {
            let left = String(trimmed[..<range.lowerBound])
                .trimmingCharacters(in: CharacterSet(charactersIn: "() "))
                .replacingOccurrences(of: "$", with: "")
            let variables = splitTopLevel(left)
            let collection = String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            if variables.count > 1 { return (variables[0], variables[1], collection) }
            return (variables.first ?? "item", nil, collection)
        }
        return ("item", nil, trimmed)
    }

    /// Declarações do `@swift`: `let x = expr`, `var y = count(items)`, `z += 1`.
    private static func parseSwiftAssignments(_ source: String) -> [(name: String, expression: String)] {
        splitStatements(source).compactMap { raw in
            var statement = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            // Estilo Swift: `let total = ...` / `var label = ...` (sem `$`).
            for keyword in ["let ", "var "] where statement.hasPrefix(keyword) {
                statement = String(statement.dropFirst(keyword.count))
                    .trimmingCharacters(in: .whitespaces)
            }
            guard !statement.isEmpty else { return nil }
            if statement.hasSuffix("++") {
                let name = String(statement.dropLast(2)).trimmingCharacters(in: .whitespaces)
                return (name, "\(name) + 1")
            }
            if statement.hasSuffix("--") {
                let name = String(statement.dropLast(2)).trimmingCharacters(in: .whitespaces)
                return (name, "\(name) - 1")
            }
            if let range = statement.range(of: "+=") {
                let name = statement[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
                let value = statement[range.upperBound...].trimmingCharacters(in: .whitespaces)
                return (name, "\(name) + (\(value))")
            }
            if let range = statement.range(of: "-=") {
                let name = statement[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
                let value = statement[range.upperBound...].trimmingCharacters(in: .whitespaces)
                return (name, "\(name) - (\(value))")
            }
            guard let range = statement.range(of: "=") else { return nil }
            let after = statement[range.upperBound...]
            guard !after.hasPrefix("=") else { return nil }
            // Anotação de tipo Swift é aceita e ignorada: `let total: Int = ...`
            let name = statement[..<range.lowerBound]
                .split(separator: ":").first
                .map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
            guard name.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil else { return nil }
            return (name, after.trimmingCharacters(in: .whitespaces))
        }
    }

    private static func splitStatements(_ source: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var depth = 0
        var quote: Character?
        for ch in source {
            if let active = quote {
                current.append(ch)
                if ch == active { quote = nil }
                continue
            }
            if ch == "'" || ch == "\"" { quote = ch; current.append(ch); continue }
            if ch == "(" || ch == "[" { depth += 1 }
            if ch == ")" || ch == "]" { depth -= 1 }
            if (ch == ";" || ch == "\n") && depth == 0 {
                parts.append(current)
                current = ""
                continue
            }
            current.append(ch)
        }
        if !current.isEmpty { parts.append(current) }
        return parts
    }
}
