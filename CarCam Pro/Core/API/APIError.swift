import Foundation

/// Error returned by every `APIClient` call. Mirrors the backend's error
/// envelope (`{ error: { code, message, details }, requestId }`) plus
/// client-side failure modes.
///
/// Conforming to `LocalizedError` lets views surface these directly via
/// `error.localizedDescription`.
public enum APIError: LocalizedError, Sendable {
    /// Transport-layer failure — no response reached us.
    case transport(URLError)
    /// Server responded but the body wasn't valid JSON / the envelope
    /// shape was unexpected.
    case decoding(underlying: Error)
    /// Server returned a recognized error envelope.
    case server(ServerError)
    /// Generic non-2xx response whose body didn't parse as an envelope.
    case unexpectedStatus(Int, body: String)
    /// Caller attempted an authenticated request without a valid token.
    case notAuthenticated
    /// Caller's tier is below the endpoint's minimum.
    case subscriptionRequired(min: APISubscriptionTier)
    /// Presigned upload / download failed.
    case storageTransfer(status: Int, body: String)

    public struct ServerError: Sendable, Equatable {
        public let code: String
        public let message: String
        public let status: Int
        public let requestId: String?
        public let details: String?

        public init(code: String, message: String, status: Int, requestId: String?, details: String?) {
            self.code = code
            self.message = message
            self.status = status
            self.requestId = requestId
            self.details = details
        }
    }

    public var errorDescription: String? {
        switch self {
        case .transport(let err):
            return "Network error: \(err.localizedDescription)"
        case .decoding(let underlying):
            return "Couldn't parse the server response (\(underlying.localizedDescription))"
        case .server(let server):
            return server.message
        case .unexpectedStatus(let status, _):
            return "Server returned status \(status)"
        case .notAuthenticated:
            return "Sign in required."
        case .subscriptionRequired(let min):
            return "This feature requires the \(min.displayName) plan."
        case .storageTransfer(let status, _):
            return "Upload failed (HTTP \(status))"
        }
    }

    /// Convenience — is this a 401 that a refresh-retry might rescue?
    public var isUnauthorized: Bool {
        switch self {
        case .notAuthenticated: return true
        case .server(let server) where server.status == 401: return true
        default: return false
        }
    }
}
