import Foundation
import Testing
@testable import CarCam_Pro

/// Contract tests for the API client's Codable models.
///
/// The fixtures mirror the exact wire shapes the Fastify backend emits, so
/// if the backend's Zod schema changes in a breaking way these tests fail
/// and surface the drift before it reaches production.
@Suite("API Client — wire contract")
struct APIClientTests {

    // MARK: - Decoder

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        // Matches the APIClient's own decoder: tolerate fractional seconds.
        decoder.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let raw = try c.decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = fractional.date(from: raw) { return d }
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            if let d = plain.date(from: raw) { return d }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "bad date: \(raw)")
        }
        return decoder
    }

    // MARK: - Enum parity

    @Test("SubscriptionTier wire values match backend enum")
    func tierRoundTrip() throws {
        for tier in APISubscriptionTier.allCases {
            let json = Data("\"\(tier.rawValue)\"".utf8)
            let decoded = try Self.decoder().decode(APISubscriptionTier.self, from: json)
            #expect(decoded == tier)
        }
    }

    @Test("HazardType wire values match backend enum")
    func hazardTypeRoundTrip() throws {
        for type in APIHazardType.allCases {
            let json = Data("\"\(type.rawValue)\"".utf8)
            let decoded = try Self.decoder().decode(APIHazardType.self, from: json)
            #expect(decoded == type)
        }
    }

    @Test("SubscriptionTier.meets respects rank")
    func tierMeetsOrdering() {
        #expect(APISubscriptionTier.premium.meets(.pro))
        #expect(APISubscriptionTier.premium.meets(.premium))
        #expect(APISubscriptionTier.pro.meets(.pro))
        #expect(!APISubscriptionTier.pro.meets(.premium))
        #expect(!APISubscriptionTier.free.meets(.pro))
    }

    // MARK: - User

    @Test("APIUser decodes backend /me response")
    func userDecodes() throws {
        let payload = """
        {
          "id": "01JP5R9FC0DZTJQQR83QV46S8W",
          "email": "seed.alex.chen0@example.com",
          "displayName": "Alex Chen",
          "avatarUrl": "https://cdn.example.com/avatars/alex.png",
          "locale": "en-US",
          "timezone": "America/Los_Angeles",
          "subscriptionTier": "PREMIUM",
          "storageQuotaBytes": "109951162777600",
          "createdAt": "2025-04-21T02:30:42.621Z"
        }
        """.data(using: .utf8)!

        let user = try Self.decoder().decode(APIUser.self, from: payload)
        #expect(user.id == "01JP5R9FC0DZTJQQR83QV46S8W")
        #expect(user.email == "seed.alex.chen0@example.com")
        #expect(user.subscriptionTier == .premium)
        #expect(user.storageQuota == 109_951_162_777_600)
    }

    // MARK: - Auth login

    @Test("APILoginResponse decodes + exposes tokens")
    func loginDecodes() throws {
        let payload = """
        {
          "accessToken": "eyJ.stub.jwt",
          "refreshToken": "ZmFrZS1yZWZyZXNo",
          "accessTokenExpiresIn": 900,
          "refreshTokenExpiresAt": "2026-05-21T02:30:42.621Z",
          "user": {
            "id": "01JP5R9FC0DZTJQQR83QV46S8W",
            "email": "alex@example.com",
            "displayName": "Alex Chen",
            "subscriptionTier": "PREMIUM"
          }
        }
        """.data(using: .utf8)!

        let login = try Self.decoder().decode(APILoginResponse.self, from: payload)
        #expect(login.user.subscriptionTier == .premium)
        #expect(login.tokens.accessTokenExpiresIn == 900)
        #expect(login.accessToken == "eyJ.stub.jwt")
    }

    // MARK: - Clip

    @Test("APIClip decodes with BigInt size + optional incident fields")
    func clipDecodes() throws {
        let payload = """
        {
          "id": "01JP5R9FC0DZTJQQR83QV46S8W",
          "sizeBytes": "162000000",
          "durationSeconds": 180.5,
          "resolution": "1080p",
          "frameRate": 30,
          "codec": "HEVC",
          "startedAt": "2026-04-19T12:00:00.000Z",
          "endedAt": "2026-04-19T12:03:00.500Z",
          "isProtected": true,
          "hasIncident": true,
          "incidentSeverity": "moderate",
          "peakGForce": 4.2,
          "uploadStatus": "UPLOADED",
          "uploadedAt": "2026-04-19T12:03:30.000Z",
          "createdAt": "2026-04-19T12:00:00.000Z"
        }
        """.data(using: .utf8)!

        let clip = try Self.decoder().decode(APIClip.self, from: payload)
        #expect(clip.uploadStatus == .uploaded)
        #expect(clip.hasIncident)
        #expect(clip.sizeInBytes == 162_000_000)
        #expect(clip.peakGForce == 4.2)
    }

    @Test("APIClip handles nullable incident fields")
    func clipWithoutIncidentDecodes() throws {
        let payload = """
        {
          "id": "01JP5R9FC0DZTJQQR83QV46S8W",
          "sizeBytes": "120000000",
          "durationSeconds": 60,
          "resolution": "720p",
          "frameRate": 30,
          "codec": "HEVC",
          "startedAt": "2026-04-19T12:00:00.000Z",
          "endedAt": "2026-04-19T12:01:00.000Z",
          "isProtected": false,
          "hasIncident": false,
          "incidentSeverity": null,
          "peakGForce": null,
          "uploadStatus": "PENDING",
          "uploadedAt": null,
          "createdAt": "2026-04-19T12:00:00.000Z"
        }
        """.data(using: .utf8)!

        let clip = try Self.decoder().decode(APIClip.self, from: payload)
        #expect(clip.uploadStatus == .pending)
        #expect(clip.incidentSeverity == nil)
        #expect(clip.peakGForce == nil)
        #expect(clip.uploadedAt == nil)
    }

    // MARK: - Subscription

    @Test("APISubscription decodes a free-tier no-subscription response")
    func subscriptionFreeDecodes() throws {
        let payload = """
        {
          "tier": "FREE",
          "status": null,
          "productId": null,
          "currentPeriodEndsAt": null,
          "autoRenew": null
        }
        """.data(using: .utf8)!

        let sub = try Self.decoder().decode(APISubscription.self, from: payload)
        #expect(sub.tier == .free)
        #expect(sub.status == nil)
    }

    @Test("APISubscription decodes an active PRO subscription")
    func subscriptionActiveDecodes() throws {
        let payload = """
        {
          "tier": "PRO",
          "status": "ACTIVE",
          "productId": "com.carcampro.sub.pro.monthly",
          "currentPeriodEndsAt": "2026-05-19T12:00:00.000Z",
          "autoRenew": true
        }
        """.data(using: .utf8)!

        let sub = try Self.decoder().decode(APISubscription.self, from: payload)
        #expect(sub.tier == .pro)
        #expect(sub.status == .active)
        #expect(sub.autoRenew == true)
    }

    // MARK: - Hazards

    @Test("APIHazardSighting decodes a nearby result")
    func hazardDecodes() throws {
        let payload = """
        {
          "id": "01JP5R9FC0DZTJQQR83QV46S8W",
          "type": "POLICE_STOP",
          "severity": 2,
          "confidence": 0.87,
          "upvotes": 5,
          "downvotes": 1,
          "expiresAt": "2026-04-21T04:30:00.000Z",
          "createdAt": "2026-04-21T02:30:00.000Z",
          "distanceMeters": 412.5,
          "latitude": 37.7749,
          "longitude": -122.4194
        }
        """.data(using: .utf8)!

        let sighting = try Self.decoder().decode(APIHazardSighting.self, from: payload)
        #expect(sighting.type == .policeStop)
        #expect(sighting.distanceMeters == 412.5)
    }

    // MARK: - Error envelope

    @Test("APIError.ServerError formats the message for the UI")
    func errorMessage() {
        let err = APIError.server(.init(
            code: "PAYMENT_REQUIRED",
            message: "This feature requires the PREMIUM tier.",
            status: 402,
            requestId: "req-123",
            details: nil
        ))
        #expect(err.errorDescription == "This feature requires the PREMIUM tier.")
        #expect(!err.isUnauthorized)
    }

    @Test("APIError.server 401 is marked unauthorized")
    func unauthorizedDetection() {
        let err = APIError.server(.init(
            code: "UNAUTHORIZED",
            message: "Authentication required",
            status: 401,
            requestId: nil,
            details: nil
        ))
        #expect(err.isUnauthorized)
    }

    // MARK: - Incident report

    @Test("APIIncidentReportStatusResponse — QUEUED shape")
    func incidentQueuedDecodes() throws {
        let payload = """
        {
          "reportId": "01JP5R9FC0DZTJQQR83QV46S8W",
          "status": "QUEUED",
          "downloadUrl": null,
          "expiresInSeconds": null
        }
        """.data(using: .utf8)!

        let r = try Self.decoder().decode(APIIncidentReportStatusResponse.self, from: payload)
        #expect(r.status == .queued)
        #expect(r.downloadUrl == nil)
    }

    @Test("APIIncidentReportStatusResponse — READY shape")
    func incidentReadyDecodes() throws {
        let payload = """
        {
          "reportId": "01JP5R9FC0DZTJQQR83QV46S8W",
          "status": "READY",
          "downloadUrl": "https://s3.example.com/signed?sig=abc",
          "expiresInSeconds": 900
        }
        """.data(using: .utf8)!

        let r = try Self.decoder().decode(APIIncidentReportStatusResponse.self, from: payload)
        #expect(r.status == .ready)
        #expect(r.downloadUrl != nil)
        #expect(r.expiresInSeconds == 900)
    }

    // MARK: - Auth token store

    @Test("AuthTokenStore round-trips a snapshot via an isolated service")
    func tokenStoreRoundTrip() throws {
        // Use a unique service name so we don't collide with the shared store.
        let store = AuthTokenStore(service: "pro.carcam.tests.\(UUID().uuidString)")
        defer { store.clear() }

        let snapshot = AuthTokenStore.Snapshot(
            tokens: APISessionTokens(
                accessToken: "access",
                refreshToken: "refresh",
                accessTokenExpiresIn: 900,
                refreshTokenExpiresAt: Date(timeIntervalSince1970: 2_000_000_000)
            ),
            user: APIAuthUser(
                id: "01JP5R9FC0DZTJQQR83QV46S8W",
                email: "user@example.com",
                displayName: "Tester",
                subscriptionTier: .pro
            )
        )
        store.save(snapshot)
        let loaded = store.load()
        #expect(loaded == snapshot)
        store.clear()
        #expect(store.load() == nil)
    }
}
