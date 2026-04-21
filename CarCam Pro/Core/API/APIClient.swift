import Foundation
import OSLog

/// Domain protocol for talking to the CarCam Pro backend. Expressed as a
/// protocol so tests can inject a fake implementation without spinning up
/// a full HTTP stack.
public protocol APIClientProtocol: Sendable {
    // Auth
    func signInWithApple(identityToken: String, displayName: String?) async throws -> APILoginResponse
    func refreshSession() async throws -> APISessionTokens
    func logout() async throws
    func currentUser() async throws -> APIUser

    // Devices
    func registerDevice(_ payload: APIRegisterDevicePayload) async throws -> APIDevice
    func listDevices() async throws -> [APIDevice]
    func deleteDevice(id: String) async throws

    // Clips
    func initClipUpload(_ payload: APIInitClipPayload) async throws -> APIInitClipResponse
    func completeClipUpload(id: String, payload: APICompleteClipPayload) async throws -> APIClip
    func listClips(cursor: String?, limit: Int, protectedOnly: Bool) async throws -> APIClipListResponse
    func getClip(id: String) async throws -> APIClip
    func clipDownloadURL(id: String) async throws -> APIDownloadURLResponse
    func deleteClip(id: String) async throws
    func uploadBytes(_ data: Data, to url: URL, sha256Base64: String, contentType: String) async throws

    // Subscriptions
    func verifySubscription(_ payload: APISubscriptionVerifyPayload) async throws -> APISubscriptionVerifyResponse
    func currentSubscription() async throws -> APISubscription

    // Incidents
    func enqueueIncidentReport(clipId: String) async throws -> APIIncidentReportEnqueueResponse
    func incidentReportStatus(clipId: String) async throws -> APIIncidentReportStatusResponse

    // Hazards
    func reportHazard(_ payload: APIReportHazardPayload) async throws -> APIReportHazardResponse
    func nearbyHazards(latitude: Double, longitude: Double, radiusMeters: Int, type: APIHazardType?) async throws -> [APIHazardSighting]
    func voteOnHazard(id: String, direction: HazardVoteDirection) async throws

    // Health
    func health() async throws -> APIHealthResponse

    // Auth state (for UI bootstrapping).
    var isAuthenticated: Bool { get }
    func authSnapshot() -> AuthTokenStore.Snapshot?
}

public struct APIHealthResponse: Codable, Sendable, Equatable {
    public let ok: Bool
    public let service: String
    public let env: String
    public let time: Date
}

/// Default production implementation of `APIClientProtocol`.
///
/// Responsibilities:
///   • JSON encode/decode with ISO-8601 dates + tolerant-to-fractional-seconds.
///   • Attach bearer token when authenticated.
///   • On 401, attempt a single transparent refresh before surfacing the
///     error — avoids a forced re-login when the access token simply aged out.
///   • Map non-2xx envelope bodies into typed `APIError.server` cases.
///
/// Concurrency: marked `@unchecked Sendable` — the underlying `URLSession`
/// is Sendable and `AuthTokenStore` has its own lock.
public final class APIClient: APIClientProtocol, @unchecked Sendable {

    // MARK: - Dependencies

    private let configuration: APIConfiguration
    private let session: URLSession
    private let tokens: AuthTokenStore
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let logger = Logger(subsystem: "pro.carcam", category: "api")
    /// Serializes token-refresh attempts so parallel 401s don't all fire `/refresh`.
    private let refreshQueue = RefreshCoordinator()

    // MARK: - Init

    /// `nonisolated` so the @MainActor `DependencyContainer` can construct
    /// it in its default-parameter position without capturing main-actor
    /// isolation for every request thereafter.
    nonisolated public init(
        configuration: APIConfiguration = .default,
        tokens: AuthTokenStore = .shared,
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.tokens = tokens
        self.session = session

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = []
        self.encoder = encoder

        let decoder = JSONDecoder()
        // Fastify emits `2026-04-21T02:30:42.621Z` — fractional seconds.
        // Default ISO-8601 strategy doesn't accept those, so use a custom formatter.
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = APIClient.fractionalISO8601.date(from: raw) { return date }
            if let date = APIClient.plainISO8601.date(from: raw) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unparseable date: \(raw)")
        }
        self.decoder = decoder
    }

    // MARK: - Auth introspection

    public var isAuthenticated: Bool { tokens.load() != nil }
    public func authSnapshot() -> AuthTokenStore.Snapshot? { tokens.load() }

    // MARK: - Auth endpoints

    public func signInWithApple(identityToken: String, displayName: String?) async throws -> APILoginResponse {
        struct Body: Encodable { let identityToken: String; let displayName: String? }
        let response: APILoginResponse = try await post(
            path: "/v1/auth/apple",
            body: Body(identityToken: identityToken, displayName: displayName),
            authenticated: false
        )
        tokens.save(.init(tokens: response.tokens, user: response.user))
        return response
    }

    public func refreshSession() async throws -> APISessionTokens {
        return try await refreshQueue.coalesce { [self] in
            guard let current = self.tokens.load() else { throw APIError.notAuthenticated }
            struct Body: Encodable { let refreshToken: String }
            let new: APISessionTokens = try await self.post(
                path: "/v1/auth/refresh",
                body: Body(refreshToken: current.tokens.refreshToken),
                authenticated: false
            )
            self.tokens.save(.init(tokens: new, user: current.user))
            return new
        }
    }

    public func logout() async throws {
        do {
            let _: EmptyResponse = try await post(path: "/v1/auth/logout", body: EmptyBody(), authenticated: true)
        } catch {
            // Always clear local state even if the server refuses — the user
            // expects "log me out" to be definitive on the client side.
            logger.error("Logout server-side call failed: \(error.localizedDescription)")
        }
        tokens.clear()
    }

    public func currentUser() async throws -> APIUser {
        try await get(path: "/v1/users/me", authenticated: true)
    }

    // MARK: - Devices

    public func registerDevice(_ payload: APIRegisterDevicePayload) async throws -> APIDevice {
        try await post(path: "/v1/devices/register", body: payload, authenticated: true)
    }

    public func listDevices() async throws -> [APIDevice] {
        let list: APIDeviceList = try await get(path: "/v1/devices", authenticated: true)
        return list.devices
    }

    public func deleteDevice(id: String) async throws {
        try await delete(path: "/v1/devices/\(id)", authenticated: true)
    }

    // MARK: - Clips

    public func initClipUpload(_ payload: APIInitClipPayload) async throws -> APIInitClipResponse {
        try await post(path: "/v1/clips/init", body: payload, authenticated: true)
    }

    public func completeClipUpload(id: String, payload: APICompleteClipPayload) async throws -> APIClip {
        try await post(path: "/v1/clips/\(id)/complete", body: payload, authenticated: true)
    }

    public func listClips(cursor: String?, limit: Int, protectedOnly: Bool) async throws -> APIClipListResponse {
        var items = [URLQueryItem(name: "limit", value: String(limit))]
        if protectedOnly { items.append(URLQueryItem(name: "protectedOnly", value: "true")) }
        if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
        return try await get(path: "/v1/clips", query: items, authenticated: true)
    }

    public func getClip(id: String) async throws -> APIClip {
        try await get(path: "/v1/clips/\(id)", authenticated: true)
    }

    public func clipDownloadURL(id: String) async throws -> APIDownloadURLResponse {
        try await get(path: "/v1/clips/\(id)/download", authenticated: true)
    }

    public func deleteClip(id: String) async throws {
        try await delete(path: "/v1/clips/\(id)", authenticated: true)
    }

    public func uploadBytes(_ data: Data, to url: URL, sha256Base64: String, contentType: String) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(sha256Base64, forHTTPHeaderField: "x-amz-checksum-sha256")
        request.setValue(String(data.count), forHTTPHeaderField: "Content-Length")
        let (respData, response) = try await session.upload(for: request, from: data)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.storageTransfer(status: 0, body: "no response")
        }
        if !(200..<300 ~= http.statusCode) {
            let body = String(data: respData, encoding: .utf8) ?? ""
            throw APIError.storageTransfer(status: http.statusCode, body: body)
        }
    }

    // MARK: - Subscriptions

    public func verifySubscription(_ payload: APISubscriptionVerifyPayload) async throws -> APISubscriptionVerifyResponse {
        try await post(path: "/v1/subscriptions/verify", body: payload, authenticated: true)
    }

    public func currentSubscription() async throws -> APISubscription {
        try await get(path: "/v1/subscriptions/current", authenticated: true)
    }

    // MARK: - Incidents

    public func enqueueIncidentReport(clipId: String) async throws -> APIIncidentReportEnqueueResponse {
        try await post(path: "/v1/incidents/\(clipId)/report", body: EmptyBody(), authenticated: true)
    }

    public func incidentReportStatus(clipId: String) async throws -> APIIncidentReportStatusResponse {
        try await get(path: "/v1/incidents/\(clipId)/report", authenticated: true)
    }

    // MARK: - Hazards

    public func reportHazard(_ payload: APIReportHazardPayload) async throws -> APIReportHazardResponse {
        try await post(path: "/v1/hazards", body: payload, authenticated: true, expectedStatus: 201)
    }

    public func nearbyHazards(
        latitude: Double,
        longitude: Double,
        radiusMeters: Int,
        type: APIHazardType?
    ) async throws -> [APIHazardSighting] {
        var items = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "radiusMeters", value: String(radiusMeters)),
        ]
        if let type {
            items.append(URLQueryItem(name: "type", value: type.rawValue))
        }
        let response: APIHazardNearbyResponse = try await get(path: "/v1/hazards/nearby", query: items, authenticated: true)
        return response.sightings
    }

    public func voteOnHazard(id: String, direction: HazardVoteDirection) async throws {
        let _: EmptyResponse = try await post(
            path: "/v1/hazards/\(id)/vote",
            body: APIHazardVotePayload(direction: direction),
            authenticated: true
        )
    }

    // MARK: - Health

    public func health() async throws -> APIHealthResponse {
        try await get(path: "/health", authenticated: false)
    }

    // MARK: - Request machinery

    private func get<R: Decodable>(
        path: String,
        query: [URLQueryItem] = [],
        authenticated: Bool,
        expectedStatus: Int = 200
    ) async throws -> R {
        try await perform(
            method: "GET",
            path: path,
            query: query,
            body: Optional<EmptyBody>.none,
            authenticated: authenticated,
            expectedStatus: expectedStatus
        )
    }

    private func post<B: Encodable, R: Decodable>(
        path: String,
        body: B,
        authenticated: Bool,
        expectedStatus: Int = 200
    ) async throws -> R {
        try await perform(
            method: "POST",
            path: path,
            query: [],
            body: body,
            authenticated: authenticated,
            expectedStatus: expectedStatus
        )
    }

    private func delete(path: String, authenticated: Bool) async throws {
        let _: EmptyResponse = try await perform(
            method: "DELETE",
            path: path,
            query: [],
            body: Optional<EmptyBody>.none,
            authenticated: authenticated,
            expectedStatus: 204
        )
    }

    /// Core pipeline: build URL, attach body + headers, attempt the call,
    /// transparently refresh on 401 (once), decode response or throw typed
    /// error.
    private func perform<B: Encodable, R: Decodable>(
        method: String,
        path: String,
        query: [URLQueryItem],
        body: B?,
        authenticated: Bool,
        expectedStatus: Int
    ) async throws -> R {
        var components = URLComponents(
            url: configuration.baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )!
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else {
            throw APIError.transport(URLError(.badURL))
        }

        let request = try buildRequest(
            url: url,
            method: method,
            body: body,
            authenticated: authenticated
        )

        do {
            return try await execute(request, expectedStatus: expectedStatus)
        } catch let APIError.server(error) where authenticated && error.status == 401 {
            // One-shot transparent refresh. If the refresh itself 401s, surface.
            logger.info("Access token rejected; attempting refresh")
            _ = try await refreshSession()
            let retry = try buildRequest(
                url: url,
                method: method,
                body: body,
                authenticated: true
            )
            return try await execute(retry, expectedStatus: expectedStatus)
        }
    }

    private func buildRequest<B: Encodable>(
        url: URL,
        method: String,
        body: B?,
        authenticated: Bool
    ) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("CarCam-Pro/1.0 (iOS)", forHTTPHeaderField: "User-Agent")

        if let body, !(body is EmptyBody) {
            request.httpBody = try encoder.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        if authenticated {
            guard let snapshot = tokens.load() else { throw APIError.notAuthenticated }
            request.setValue("Bearer \(snapshot.tokens.accessToken)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func execute<R: Decodable>(_ request: URLRequest, expectedStatus: Int) async throws -> R {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let err as URLError {
            throw APIError.transport(err)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.unexpectedStatus(0, body: "")
        }

        let requestId = http.value(forHTTPHeaderField: "x-request-id")

        if http.statusCode == expectedStatus {
            // 204 / empty body with a void-expected return.
            if R.self == EmptyResponse.self {
                return EmptyResponse() as! R  // swiftlint:disable:this force_cast
            }
            return try decodeBody(data)
        }

        // Attempt to parse the typed error envelope.
        if let envelope = try? decoder.decode(APIErrorEnvelope.self, from: data) {
            let body = APIError.ServerError(
                code: envelope.error.code,
                message: envelope.error.message,
                status: http.statusCode,
                requestId: envelope.requestId ?? requestId,
                details: envelope.error.details
            )
            throw APIError.server(body)
        }

        throw APIError.unexpectedStatus(http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
    }

    private func decodeBody<R: Decodable>(_ data: Data) throws -> R {
        if R.self == EmptyResponse.self { return EmptyResponse() as! R } // swiftlint:disable:this force_cast
        do {
            return try decoder.decode(R.self, from: data)
        } catch {
            throw APIError.decoding(underlying: error)
        }
    }

    // MARK: - Date formatters

    private static let fractionalISO8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let plainISO8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}

// MARK: - Private helpers

/// Sentinel types — used to express `Void` request / response through the
/// generic body/response pipeline without resorting to `Any`.
private struct EmptyBody: Encodable {}
private struct EmptyResponse: Decodable {}

/// Coalesces concurrent refresh attempts onto a single in-flight request.
private actor RefreshCoordinator {
    private var inFlight: Task<APISessionTokens, Error>?

    func coalesce(_ op: @Sendable @escaping () async throws -> APISessionTokens) async throws -> APISessionTokens {
        if let existing = inFlight {
            return try await existing.value
        }
        let task = Task { try await op() }
        inFlight = task
        defer { inFlight = nil }
        return try await task.value
    }
}
