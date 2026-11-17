import Vapor

/// Dados de uma view, no espírito do `view('nome', [...])` do Laravel.
///
/// Diferente da primeira versão, não há limite de pares: use a forma
/// variádica com tuplas, os overloads posicionais ou o builder.
public struct ViewData: Encodable, Sendable {
    fileprivate var values: [String: AnyEncodableValue]

    public static let empty = ViewData(values: [:])

    init(values: [String: AnyEncodableValue]) {
        self.values = values
    }

    public init() {
        values = [:]
    }

    public init(_ pairs: (String, any Encodable & Sendable)...) {
        values = pairs.reduce(into: [:]) { result, pair in
            result[pair.0] = AnyEncodableValue(pair.1)
        }
    }

    public init(dictionary: [String: any Encodable & Sendable]) {
        values = dictionary.mapValues { AnyEncodableValue($0) }
    }

    public mutating func set<Value: Encodable & Sendable>(_ key: String, _ value: Value) {
        values[key] = AnyEncodableValue(value)
    }

    public func merging(_ other: ViewData) -> ViewData {
        ViewData(values: values.merging(other.values) { _, new in new })
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKey.self)
        for (key, value) in values {
            try container.encode(value, forKey: DynamicCodingKey(stringValue: key))
        }
    }
}

private struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

struct AnyEncodableValue: Encodable, @unchecked Sendable {
    private let encodeValue: (Encoder) throws -> Void

    init<Value: Encodable & Sendable>(_ value: Value) {
        self.encodeValue = value.encode(to:)
    }

    func encode(to encoder: Encoder) throws { try encodeValue(encoder) }
}

// MARK: - compact (ilimitado)

/// Forma ilimitada, recomendada:
/// `compact(("title", "Usuários"), ("users", users), ("total", total))`
public func compact(_ pairs: (String, any Encodable & Sendable)...) -> ViewData {
    ViewData(values: pairs.reduce(into: [:]) { result, pair in
        result[pair.0] = AnyEncodableValue(pair.1)
    })
}

public func compact<Value: Encodable & Sendable>(_ key: String, _ value: Value) -> ViewData {
    ViewData(values: [key: AnyEncodableValue(value)])
}

public func compact<A: Encodable & Sendable, B: Encodable & Sendable>(
    _ firstKey: String, _ firstValue: A,
    _ secondKey: String, _ secondValue: B
) -> ViewData {
    ViewData(values: [
        firstKey: AnyEncodableValue(firstValue),
        secondKey: AnyEncodableValue(secondValue),
    ])
}

public func compact<A: Encodable & Sendable, B: Encodable & Sendable, C: Encodable & Sendable>(
    _ firstKey: String, _ firstValue: A,
    _ secondKey: String, _ secondValue: B,
    _ thirdKey: String, _ thirdValue: C
) -> ViewData {
    ViewData(values: [
        firstKey: AnyEncodableValue(firstValue),
        secondKey: AnyEncodableValue(secondValue),
        thirdKey: AnyEncodableValue(thirdValue),
    ])
}

public func compact<A: Encodable & Sendable, B: Encodable & Sendable, C: Encodable & Sendable, D: Encodable & Sendable>(
    _ firstKey: String, _ firstValue: A,
    _ secondKey: String, _ secondValue: B,
    _ thirdKey: String, _ thirdValue: C,
    _ fourthKey: String, _ fourthValue: D
) -> ViewData {
    ViewData(values: [
        firstKey: AnyEncodableValue(firstValue),
        secondKey: AnyEncodableValue(secondValue),
        thirdKey: AnyEncodableValue(thirdValue),
        fourthKey: AnyEncodableValue(fourthValue),
    ])
}

public func compact<A: Encodable & Sendable, B: Encodable & Sendable, C: Encodable & Sendable, D: Encodable & Sendable, E: Encodable & Sendable>(
    _ firstKey: String, _ firstValue: A,
    _ secondKey: String, _ secondValue: B,
    _ thirdKey: String, _ thirdValue: C,
    _ fourthKey: String, _ fourthValue: D,
    _ fifthKey: String, _ fifthValue: E
) -> ViewData {
    ViewData(values: [
        firstKey: AnyEncodableValue(firstValue),
        secondKey: AnyEncodableValue(secondValue),
        thirdKey: AnyEncodableValue(thirdValue),
        fourthKey: AnyEncodableValue(fourthValue),
        fifthKey: AnyEncodableValue(fifthValue),
    ])
}

public func compact<A: Encodable & Sendable, B: Encodable & Sendable, C: Encodable & Sendable, D: Encodable & Sendable, E: Encodable & Sendable, F: Encodable & Sendable>(
    _ firstKey: String, _ firstValue: A,
    _ secondKey: String, _ secondValue: B,
    _ thirdKey: String, _ thirdValue: C,
    _ fourthKey: String, _ fourthValue: D,
    _ fifthKey: String, _ fifthValue: E,
    _ sixthKey: String, _ sixthValue: F
) -> ViewData {
    ViewData(values: [
        firstKey: AnyEncodableValue(firstValue),
        secondKey: AnyEncodableValue(secondValue),
        thirdKey: AnyEncodableValue(thirdValue),
        fourthKey: AnyEncodableValue(fourthValue),
        fifthKey: AnyEncodableValue(fifthValue),
        sixthKey: AnyEncodableValue(sixthValue),
    ])
}

// MARK: - view

public func view(
    _ name: String,
    _ data: ViewData = .empty,
    for request: Request
) async throws -> Response {
    try await request.view.render(name, data).encodeResponse(for: request)
}

/// Atalho no estilo Laravel: `view("users.index", with: ["users": users])`.
public func view(
    _ name: String,
    with data: [String: any Encodable & Sendable],
    for request: Request
) async throws -> Response {
    try await view(name, ViewData(dictionary: data), for: request)
}
