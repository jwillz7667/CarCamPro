import Foundation

/// Static configuration for the backend client.
///
/// The base URL is read from the `CARCAM_API_BASE_URL` Info.plist key so the
/// same binary can target dev / staging / production without a recompile.
/// Falls back to a localhost URL so simulator builds "just work" when the
/// local backend is running via `pnpm dev`.
///
/// All paths are appended under `baseURL.appendingPathComponent(...)` —
/// never string-concatenated, so a trailing slash in the configured URL
/// doesn't create `//` segments that some S3-compatible services reject.
public struct APIConfiguration: Sendable {
    public let baseURL: URL
    public let adminAPIKey: String?

    public init(baseURL: URL, adminAPIKey: String? = nil) {
        self.baseURL = baseURL
        self.adminAPIKey = adminAPIKey
    }

    /// Default configuration — reads from Info.plist at load time, falls
    /// back to `http://localhost:4000` for simulator dev.
    public static let `default`: APIConfiguration = {
        let bundle = Bundle.main
        let urlString = bundle.object(forInfoDictionaryKey: "CARCAM_API_BASE_URL") as? String
            ?? "http://localhost:4000"
        let url = URL(string: urlString) ?? URL(string: "http://localhost:4000")!
        let adminKey = bundle.object(forInfoDictionaryKey: "CARCAM_ADMIN_API_KEY") as? String
        return APIConfiguration(baseURL: url, adminAPIKey: adminKey)
    }()
}
