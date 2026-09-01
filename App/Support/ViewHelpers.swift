import Vapor

public struct ViewData: Encodable, Sendable {
    fileprivate var values: [String: AnyEncodableValue]

    public static let empty = ViewData(values: [:])

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

private struct AnyEncodableValue: Encodable, @unchecked Sendable {
    private let encodeValue: (Encoder) throws -> Void

    init<Value: Encodable & Sendable>(_ value: Value) {
        self.encodeValue = value.encode(to:)
    }

    func encode(to encoder: Encoder) throws { try encodeValue(encoder) }
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

public func view(
    _ name: String,
    _ data: ViewData = .empty,
    for request: Request
) async throws -> Response {
    try await request.view.render(name, data).encodeResponse(for: request)
}
