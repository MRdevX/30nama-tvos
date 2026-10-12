import Foundation

/// Loosely typed JSON value.
///
/// The 30nama API is not consistent between endpoints: numbers arrive as strings, a field is an
/// object in one response and an array in another, and optional fields are `null`, `""` or
/// missing. Models read through this type instead of strict `Codable` so one odd field never
/// fails a whole screen.
enum JSON: Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSON])
    case object([String: JSON])

    init(_ any: Any?) {
        switch any {
        case let n as NSNumber:
            self = CFGetTypeID(n) == CFBooleanGetTypeID() ? .bool(n.boolValue) : .number(n.doubleValue)
        case let s as String:
            self = .string(s)
        case let a as [Any]:
            self = .array(a.map { JSON($0) })
        case let d as [String: Any]:
            self = .object(d.mapValues { JSON($0) })
        default:
            self = .null
        }
    }

    static func parse(_ data: Data) throws -> JSON {
        JSON(try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]))
    }

    /// Foundation representation, for re-serialising a value we want to persist.
    var any: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let b): return b
        case .number(let n): return n
        case .string(let s): return s
        case .array(let a): return a.map(\.any)
        case .object(let o): return o.mapValues(\.any)
        }
    }

    func data() -> Data? {
        try? JSONSerialization.data(withJSONObject: any, options: [.fragmentsAllowed])
    }

    subscript(key: String) -> JSON {
        if case .object(let o) = self { return o[key] ?? .null }
        return .null
    }

    subscript(index: Int) -> JSON {
        if case .array(let a) = self, a.indices.contains(index) { return a[index] }
        return .null
    }

    var isNull: Bool { self == .null }

    var array: [JSON] {
        if case .array(let a) = self { return a }
        return []
    }

    var object: [String: JSON]? {
        if case .object(let o) = self { return o }
        return nil
    }

    /// String value; numbers are rendered without a trailing `.0`.
    var string: String? {
        switch self {
        case .string(let s): return s
        case .number(let n):
            return n == n.rounded() && abs(n) < 1e15 ? String(Int(n)) : String(n)
        default: return nil
        }
    }

    /// Trimmed, non-empty string.
    var text: String? {
        guard let s = string?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }

    var double: Double? {
        switch self {
        case .number(let n): return n
        case .string(let s): return Double(s.trimmingCharacters(in: .whitespaces))
        default: return nil
        }
    }

    var int: Int? {
        guard let d = double, d.isFinite, abs(d) < 1e15 else { return nil }
        return Int(d)
    }

    var bool: Bool {
        switch self {
        case .bool(let b): return b
        case .number(let n): return n != 0
        case .string(let s): return ["1", "true", "yes"].contains(s.lowercased())
        default: return false
        }
    }

    var url: URL? {
        guard let s = text else { return nil }
        return URL(string: s) ?? s.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed).flatMap(URL.init(string:))
    }
}
