import Foundation

/// Response payload from `POST /v1/auth/apple` and `POST /v1/auth/refresh`.
///
/// `accessToken` is a short-lived JWT; `refreshToken` is an opaque
/// base64url string the server validates against a SHA-256 hash.
/// `refreshTokenExpiresAt` is the hard cutoff beyond which the client must
/// re-authenticate from scratch.
public struct APISessionTokens: Codable, Sendable, Equatable {
    public let accessToken: String
    public let refreshToken: String
    public let accessTokenExpiresIn: Int
    public let refreshTokenExpiresAt: Date

    public init(
        accessToken: String,
        refreshToken: String,
        accessTokenExpiresIn: Int,
        refreshTokenExpiresAt: Date
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.accessTokenExpiresIn = accessTokenExpiresIn
        self.refreshTokenExpiresAt = refreshTokenExpiresAt
    }

    /// Concrete expiry of the access token, computed at parse time so the
    /// UI layer can decide when to pre-emptively refresh.
    public var accessTokenExpiresAt: Date {
        Date().addingTimeInterval(TimeInterval(accessTokenExpiresIn))
    }
}

/// Login response bundle from `POST /v1/auth/apple`.
public struct APILoginResponse: Codable, Sendable, Equatable {
    public let accessToken: String
    public let refreshToken: String
    public let accessTokenExpiresIn: Int
    public let refreshTokenExpiresAt: Date
    public let user: APIAuthUser

    public var tokens: APISessionTokens {
        APISessionTokens(
            accessToken: accessToken,
            refreshToken: refreshToken,
            accessTokenExpiresIn: accessTokenExpiresIn,
            refreshTokenExpiresAt: refreshTokenExpiresAt
        )
    }
}
