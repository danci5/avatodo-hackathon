import Foundation

/// A sendable JSON boundary. Credentials and framework objects never enter tool payloads.
public enum JSONValue: Codable, Equatable, Sendable {
    case null, bool(Bool), number(Double), string(String), array([JSONValue]), object([String: JSONValue])

    public init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let value = try? c.decode(Bool.self) { self = .bool(value) }
        else if let value = try? c.decode(Double.self) { self = .number(value) }
        else if let value = try? c.decode(String.self) { self = .string(value) }
        else if let value = try? c.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case let .bool(v): try c.encode(v)
        case let .number(v): try c.encode(v)
        case let .string(v): try c.encode(v)
        case let .array(v): try c.encode(v)
        case let .object(v): try c.encode(v)
        }
    }

    public subscript(_ key: String) -> JSONValue { if case let .object(v) = self { return v[key] ?? .null }; return .null }
    public var string: String? { if case let .string(v) = self { return v }; return nil }
    public var bool: Bool? { if case let .bool(v) = self { return v }; return nil }
    public var array: [JSONValue]? { if case let .array(v) = self { return v }; return nil }
    public var object: [String: JSONValue]? { if case let .object(v) = self { return v }; return nil }
    public var int: Int? {
        guard case let .number(v) = self, v.isFinite, v.rounded() == v,
              v >= Double(Int.min), v < Double(Int.max) else { return nil }
        return Int(v)
    }
    public func jsonString() throws -> String { String(decoding: try JSONEncoder().encode(self), as: UTF8.self) }
    public static func encoded<T: Encodable>(_ value: T) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))
    }
}
