import Foundation

/// Wire shape of the backend's error response.
///
///   { "error": { "code": "...", "message": "...", "details": ... }, "requestId": "..." }
///
/// Success responses don't use this envelope — they're the route's Zod
/// `response` schema directly. We only decode an envelope when the HTTP
/// status is ≥ 400.
struct APIErrorEnvelope: Decodable, Sendable {
    let error: APIErrorBody
    let requestId: String?

    struct APIErrorBody: Decodable, Sendable {
        let code: String
        let message: String
        /// The backend uses `details: unknown` — we keep it as a raw
        /// JSON string so it survives without a strict schema.
        let details: String?

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            code = try c.decode(String.self, forKey: .code)
            message = try c.decode(String.self, forKey: .message)
            if c.contains(.details) {
                if let raw = try? c.decode(String.self, forKey: .details) {
                    details = raw
                } else if let any = try? c.decode(AnyJSONValue.self, forKey: .details) {
                    details = any.jsonString
                } else {
                    details = nil
                }
            } else {
                details = nil
            }
        }

        private enum CodingKeys: String, CodingKey {
            case code, message, details
        }
    }
}

/// Minimal `any`-JSON box. Used only to round-trip `details` into a string
/// for inclusion in `APIError.ServerError`.
private enum AnyJSONValue: Decodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: AnyJSONValue])
    case array([AnyJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let n = try? c.decode(Double.self) { self = .number(n); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([AnyJSONValue].self) { self = .array(a); return }
        if let o = try? c.decode([String: AnyJSONValue].self) { self = .object(o); return }
        self = .null
    }

    var jsonString: String {
        switch self {
        case .string(let s): return "\"\(s.replacingOccurrences(of: "\"", with: "\\\""))\""
        case .number(let n): return String(n)
        case .bool(let b): return b ? "true" : "false"
        case .null: return "null"
        case .array(let a): return "[" + a.map(\.jsonString).joined(separator: ",") + "]"
        case .object(let o):
            return "{" + o.map { "\"\($0.key)\":\($0.value.jsonString)" }.joined(separator: ",") + "}"
        }
    }
}
