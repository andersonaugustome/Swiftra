import Foundation

/// Avaliador de expressões do SwiftBlade, inspirado na sintaxe do Blade (Laravel).
///
/// Suporta caminhos (`user.name`), literais, comparações, lógica booleana,
/// operador `??`, ternário, negação e funções auxiliares (`count`, `upper`, ...).
enum BladeExpression {
    static func evaluate(_ source: String, in context: [String: Any]) -> Any? {
        var parser = Parser(tokens: tokenize(source), context: context)
        return parser.parseExpression()
    }

    static func evaluateBool(_ source: String, in context: [String: Any]) -> Bool {
        isTruthy(evaluate(source, in: context))
    }

    static func boolValue(_ value: Any?) -> Bool? {
        guard let value else { return nil }
        if let number = value as? NSNumber {
            // NSNumber de JSON também faz cast para Bool; só é booleano
            // se o tipo subjacente for CFBoolean.
            return CFGetTypeID(number) == CFBooleanGetTypeID() ? number.boolValue : nil
        }
        return value as? Bool
    }

    static func isTruthy(_ value: Any?) -> Bool {
        guard let value, !(value is NSNull) else { return false }
        if let bool = boolValue(value) { return bool }
        if let number = numeric(value) { return number != 0 }
        if let string = value as? String { return !string.isEmpty && string != "0" && string.lowercased() != "false" }
        if let array = value as? [Any] { return !array.isEmpty }
        if let dictionary = value as? [String: Any] { return !dictionary.isEmpty }
        return true
    }

    static func stringify(_ value: Any?) -> String {
        guard let value, !(value is NSNull) else { return "" }
        if let string = value as? String { return string }
        if let bool = boolValue(value) { return bool ? "true" : "false" }
        if let number = numeric(value) {
            return number == number.rounded() && abs(number) < 1e15
                ? String(Int64(number))
                : String(number)
        }
        if let array = value as? [Any] {
            return array.map { stringify($0) }.joined(separator: ", ")
        }
        if let dictionary = value as? [String: Any] {
            if let data = try? JSONSerialization.data(withJSONObject: dictionary, options: [.sortedKeys]),
               let json = String(data: data, encoding: .utf8) { return json }
            return String(describing: dictionary)
        }
        return String(describing: value)
    }

    static func numeric(_ value: Any?) -> Double? {
        guard let value else { return nil }
        if let number = value as? NSNumber { return number.doubleValue }
        if let int = value as? Int { return Double(int) }
        if let double = value as? Double { return double }
        if let string = value as? String { return Double(string) }
        return nil
    }

    static func resolve(path: String, in context: [String: Any]) -> Any? {
        var current: Any = context
        for rawComponent in path.split(separator: ".", omittingEmptySubsequences: false).map(String.init) {
            let component = rawComponent.trimmingCharacters(in: .whitespaces)
            if let dictionary = current as? [String: Any] {
                // Chave real tem precedência sobre as pseudo-propriedades.
                if let next = dictionary[component] {
                    current = next
                    continue
                }
                if component == "count" || component == "length" { return dictionary.count }
                return nil
            } else if let array = current as? [Any] {
                if component == "count" || component == "length" { return array.count }
                if component == "first" { return array.first as Any? }
                if component == "last" { return array.last as Any? }
                guard let index = Int(component), array.indices.contains(index) else { return nil }
                current = array[index]
            } else if let string = current as? String {
                if component == "count" || component == "length" { return string.count }
                return nil
            } else {
                return nil
            }
        }
        return current is NSNull ? nil : current
    }

    static func valuesEqual(_ lhs: Any?, _ rhs: Any?) -> Bool {
        if lhs == nil && rhs == nil { return true }
        if let l = numeric(lhs), let r = numeric(rhs) { return l == r }
        if let l = boolValue(lhs), let r = boolValue(rhs) { return l == r }
        return stringify(lhs) == stringify(rhs)
    }



    /// Interpolação estilo Swift dentro de strings com aspas duplas:
    /// `"Olá \\(name), você tem \\(count(items)) itens"`.
    static func interpolate(_ value: String, in context: [String: Any]) -> String {
        guard value.contains("\\(") else { return value }
        var output = ""
        let chars = Array(value)
        var i = 0
        while i < chars.count {
            if chars[i] == "\\", i + 1 < chars.count, chars[i + 1] == "(" {
                var depth = 0
                var j = i + 1
                var expression = ""
                while j < chars.count {
                    if chars[j] == "(" { depth += 1; if depth > 1 { expression.append(chars[j]) } }
                    else if chars[j] == ")" {
                        depth -= 1
                        if depth == 0 { break }
                        expression.append(chars[j])
                    } else { expression.append(chars[j]) }
                    j += 1
                }
                output += stringify(evaluate(expression, in: context))
                i = j + 1
            } else {
                output.append(chars[i])
                i += 1
            }
        }
        return output
    }

    /// Métodos chamáveis sobre valores: `user.name.uppercased()`,
    /// `items.count()`, `name.contains('a')`, `tags.join(', ')`.
    static func applyMethod(_ value: Any?, _ method: String, arguments: [Any?]) -> Any? {
        let first = arguments.first ?? nil
        switch method.lowercased() {
        case "upper", "uppercase", "uppercased", "touppercase":
            return stringify(value).uppercased()
        case "lower", "lowercase", "lowercased", "tolowercase":
            return stringify(value).lowercased()
        case "capitalized", "ucfirst":
            let text = stringify(value)
            return text.prefix(1).uppercased() + text.dropFirst()
        case "lcfirst":
            let text = stringify(value)
            return text.prefix(1).lowercased() + text.dropFirst()
        case "trim", "trimmed":
            return stringify(value).trimmingCharacters(in: .whitespacesAndNewlines)
        case "contains":
            if let array = value as? [Any] {
                return array.contains { valuesEqual($0, first) }
            }
            return stringify(value).contains(stringify(first))
        case "startswith", "hasprefix":
            return stringify(value).hasPrefix(stringify(first))
        case "endswith", "hassuffix":
            return stringify(value).hasSuffix(stringify(first))
        case "replace", "replacing", "replacingoccurrences":
            let replacement = arguments.count > 1 ? stringify(arguments[1]) : ""
            return stringify(value).replacingOccurrences(of: stringify(first), with: replacement)
        case "split":
            let separator = first.map { stringify($0) } ?? " "
            return stringify(value).components(separatedBy: separator)
        case "count", "length", "size":
            return (value as? [Any])?.count ?? (value as? [String: Any])?.count ?? stringify(value).count
        case "isempty":
            return !isTruthy(value)
        case "isnotempty":
            return isTruthy(value)
        case "first":
            return (value as? [Any])?.first as Any?
        case "last":
            return (value as? [Any])?.last as Any?
        case "join", "implode":
            let separator = first.map { stringify($0) } ?? ","
            return ((value as? [Any]) ?? []).map { stringify($0) }.joined(separator: separator)
        case "sum":
            return ((value as? [Any]) ?? []).reduce(0.0) { $0 + (numeric($1) ?? 0) }
        case "keys":
            return ((value as? [String: Any]) ?? [:]).keys.sorted()
        case "values":
            let dictionary = (value as? [String: Any]) ?? [:]
            return dictionary.keys.sorted().map { dictionary[$0] as Any }
        case "get", "has":
            guard let dictionary = value as? [String: Any], let key = first.map({ stringify($0) }) else { return nil }
            if method.lowercased() == "has" { return dictionary[key] != nil }
            return dictionary[key] ?? (arguments.count > 1 ? arguments[1] : nil)
        case "abs":
            return abs(numeric(value) ?? 0)
        case "round":
            return (numeric(value) ?? 0).rounded()
        case "int", "integer":
            return Int(numeric(value) ?? 0)
        default:
            return value
        }
    }

    // MARK: - Tokenização

    private enum Token: Equatable {
        case number(Double)
        case string(String, interpolated: Bool)
        case identifier(String)
        case op(String)
        case lParen, rParen, comma, question, colon
    }

    private static func tokenize(_ source: String) -> [Token] {
        var tokens: [Token] = []
        let chars = Array(source)
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if ch.isWhitespace { i += 1; continue }
            if ch == "'" || ch == "\"" {
                var j = i + 1
                var value = ""
                while j < chars.count && chars[j] != ch {
                    if chars[j] == "\\", j + 1 < chars.count {
                        // Aspas simples preservam a barra (só escapam a própria aspa).
                        if ch == "'" && chars[j + 1] != "'" {
                            value.append(chars[j]); j += 1
                            continue
                        }
                        // Preserva `\\(` para a interpolação em aspas duplas.
                        if chars[j + 1] == "(" && ch == "\"" {
                            value += "\\("
                            j += 2
                            continue
                        }
                        j += 1
                    }
                    value.append(chars[j]); j += 1
                }
                tokens.append(.string(value, interpolated: ch == "\"")); i = j + 1; continue
            }
            if ch.isNumber || (ch == "-" && i + 1 < chars.count && chars[i + 1].isNumber && (tokens.last.map(isValueEnd) != true)) {
                var j = i
                var text = ""
                if chars[j] == "-" { text.append("-"); j += 1 }
                while j < chars.count && (chars[j].isNumber || chars[j] == ".") { text.append(chars[j]); j += 1 }
                if let number = Double(text) { tokens.append(.number(number)) }
                i = j; continue
            }
            if ch.isLetter || ch == "_" || ch == "$" {
                var j = i
                var text = ""
                while j < chars.count && (chars[j].isLetter || chars[j].isNumber || chars[j] == "_" || chars[j] == ".") {
                    text.append(chars[j]); j += 1
                }
                // `$user` no estilo Laravel equivale a `user`.
                tokens.append(.identifier(text.hasPrefix("$") ? String(text.dropFirst()) : text))
                i = j; continue
            }
            let two = i + 1 < chars.count ? String([ch, chars[i + 1]]) : ""
            if ["==", "!=", ">=", "<=", "&&", "||", "??"].contains(two) {
                tokens.append(.op(two)); i += 2; continue
            }
            switch ch {
            case "(": tokens.append(.lParen)
            case ")": tokens.append(.rParen)
            case ",": tokens.append(.comma)
            case "?": tokens.append(.question)
            case ":": tokens.append(.colon)
            case ">", "<", "!", "+", "-", "*", "/", "%", "=":
                tokens.append(.op(ch == "=" ? "==" : String(ch)))
            default: break
            }
            i += 1
        }
        return tokens
    }

    private static func isValueEnd(_ token: Token) -> Bool {
        switch token {
        case .number, .string, .identifier, .rParen: true
        default: false
        }
    }

    // MARK: - Parser (descida recursiva)

    private struct Parser {
        let tokens: [Token]
        let context: [String: Any]
        var position = 0

        mutating func parseExpression() -> Any? { parseTernary() }

        private mutating func peek() -> Token? {
            position < tokens.count ? tokens[position] : nil
        }

        private mutating func advance() -> Token? {
            defer { position += 1 }
            return peek()
        }

        mutating func parseTernary() -> Any? {
            let condition = parseCoalesce()
            guard peek() == .question else { return condition }
            _ = advance()
            let whenTrue = parseTernary()
            if peek() == .colon { _ = advance() }
            let whenFalse = parseTernary()
            return BladeExpression.isTruthy(condition) ? whenTrue : whenFalse
        }

        mutating func parseCoalesce() -> Any? {
            var left = parseOr()
            while peek() == .op("??") {
                _ = advance()
                let right = parseOr()
                // `??` só substitui ausência (nil), como no PHP.
                if left == nil { left = right }
            }
            return left
        }

        mutating func parseOr() -> Any? {
            var left = parseAnd()
            while peek() == .op("||") || peek() == .identifier("or") {
                _ = advance()
                let right = parseAnd()
                left = BladeExpression.isTruthy(left) || BladeExpression.isTruthy(right)
            }
            return left
        }

        mutating func parseAnd() -> Any? {
            var left = parseComparison()
            while peek() == .op("&&") || peek() == .identifier("and") {
                _ = advance()
                let right = parseComparison()
                left = BladeExpression.isTruthy(left) && BladeExpression.isTruthy(right)
            }
            return left
        }

        mutating func parseComparison() -> Any? {
            var left = parseAdditive()
            while let token = peek(), case .op(let symbol) = token,
                  ["==", "!=", ">", "<", ">=", "<="].contains(symbol) {
                _ = advance()
                let right = parseAdditive()
                switch symbol {
                case "==": left = BladeExpression.valuesEqual(left, right)
                case "!=": left = !BladeExpression.valuesEqual(left, right)
                default:
                    let l = BladeExpression.numeric(left) ?? 0
                    let r = BladeExpression.numeric(right) ?? 0
                    left = symbol == ">" ? l > r : symbol == "<" ? l < r : symbol == ">=" ? l >= r : l <= r
                }
            }
            return left
        }

        mutating func parseAdditive() -> Any? {
            var left = parseMultiplicative()
            while let token = peek(), case .op(let symbol) = token, symbol == "+" || symbol == "-" {
                _ = advance()
                let right = parseMultiplicative()
                if symbol == "+", left is String || right is String {
                    left = BladeExpression.stringify(left) + BladeExpression.stringify(right)
                } else {
                    let l = BladeExpression.numeric(left) ?? 0
                    let r = BladeExpression.numeric(right) ?? 0
                    left = symbol == "+" ? l + r : l - r
                }
            }
            return left
        }

        mutating func parseMultiplicative() -> Any? {
            var left = parseUnary()
            while let token = peek(), case .op(let symbol) = token, ["*", "/", "%"].contains(symbol) {
                _ = advance()
                let right = parseUnary()
                let l = BladeExpression.numeric(left) ?? 0
                let r = BladeExpression.numeric(right) ?? 0
                left = symbol == "*" ? l * r : symbol == "/" ? (r == 0 ? 0 : l / r) : l.truncatingRemainder(dividingBy: r == 0 ? 1 : r)
            }
            return left
        }

        mutating func parseUnary() -> Any? {
            if peek() == .op("!") || peek() == .identifier("not") {
                _ = advance()
                return !BladeExpression.isTruthy(parseUnary())
            }
            if peek() == .op("-") {
                _ = advance()
                return -(BladeExpression.numeric(parseUnary()) ?? 0)
            }
            return parsePrimary()
        }

        mutating func parsePrimary() -> Any? {
            guard let token = advance() else { return nil }
            switch token {
            case .number(let value): return parseChained(value)
            case .string(let value, let interpolated):
                return parseChained(interpolated ? BladeExpression.interpolate(value, in: context) : value)
            case .lParen:
                let value = parseTernary()
                if peek() == .rParen { _ = advance() }
                return parseChained(value)
            case .identifier(let name):
                switch name.lowercased() {
                case "true": return true
                case "false": return false
                case "null", "nil": return nil
                default: break
                }
                if peek() == .lParen {
                    let arguments = parseArguments()
                    // Método sobre um caminho: user.name.uppercased()
                    let components = name.split(separator: ".").map(String.init)
                    if components.count > 1 {
                        let base = BladeExpression.resolve(path: components.dropLast().joined(separator: "."), in: context)
                        return parseChained(BladeExpression.applyMethod(base, components.last ?? "", arguments: arguments))
                    }
                    return parseChained(callFunction(name, arguments: arguments))
                }
                return parseChained(BladeExpression.resolve(path: name, in: context))
            default: return nil
            }
        }

        private mutating func parseArguments() -> [Any?] {
            guard peek() == .lParen else { return [] }
            _ = advance()
            var arguments: [Any?] = []
            if peek() != .rParen {
                arguments.append(parseTernary())
                while peek() == .comma {
                    _ = advance()
                    arguments.append(parseTernary())
                }
            }
            if peek() == .rParen { _ = advance() }
            return arguments
        }

        /// Chamadas encadeadas após um valor: `'abc'.upper().lower()`.
        private mutating func parseChained(_ initial: Any?) -> Any? {
            var value = initial
            while let token = peek(), case .identifier(let method) = token,
                  position + 1 < tokens.count, tokens[position + 1] == .lParen,
                  !method.contains(".") {
                _ = advance()
                value = BladeExpression.applyMethod(value, method, arguments: parseArguments())
            }
            return value
        }

        func callFunction(_ name: String, arguments: [Any?]) -> Any? {
            let first = arguments.first ?? nil
            switch name.lowercased() {
            case "count": return (first as? [Any])?.count ?? (first as? [String: Any])?.count ?? (first as? String)?.count ?? 0
            case "isset": return first != nil
            case "empty": return !BladeExpression.isTruthy(first)
            case "upper", "uppercase": return BladeExpression.stringify(first).uppercased()
            case "lower", "lowercase": return BladeExpression.stringify(first).lowercased()
            case "ucfirst": return BladeExpression.stringify(first).prefix(1).uppercased() + BladeExpression.stringify(first).dropFirst()
            case "abs": return abs(BladeExpression.numeric(first) ?? 0)
            case "round": return (BladeExpression.numeric(first) ?? 0).rounded()
            case "default": return BladeExpression.isTruthy(first) ? first : (arguments.count > 1 ? arguments[1] : nil)
            default: return BladeExpression.resolve(path: name, in: context)
            }
        }
    }
}
