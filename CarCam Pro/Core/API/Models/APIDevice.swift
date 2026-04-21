import Foundation

/// Registered device record, as returned by `GET /v1/devices` and
/// `POST /v1/devices/register`.
public struct APIDevice: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let model: String?
    public let osVersion: String?
    public let appVersion: String?
    public let appBuild: String?
    public let lastSeenAt: Date
}

/// Wrapper matching the backend's `{ devices: [...] }` list envelope.
public struct APIDeviceList: Codable, Sendable, Equatable {
    public let devices: [APIDevice]
}

/// Body for `POST /v1/devices/register`. All fields except `name` are
/// optional — the server assigns an ID when `id` is absent.
public struct APIRegisterDevicePayload: Codable, Sendable {
    public let id: String?
    public let name: String
    public let model: String?
    public let osVersion: String?
    public let appVersion: String?
    public let appBuild: String?
    public let apnsToken: String?

    public init(
        id: String? = nil,
        name: String,
        model: String? = nil,
        osVersion: String? = nil,
        appVersion: String? = nil,
        appBuild: String? = nil,
        apnsToken: String? = nil
    ) {
        self.id = id
        self.name = name
        self.model = model
        self.osVersion = osVersion
        self.appVersion = appVersion
        self.appBuild = appBuild
        self.apnsToken = apnsToken
    }
}
