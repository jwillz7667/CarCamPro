import Foundation

/// Hazard classifications. Mirrors the backend `hazard_type` Postgres enum.
public enum APIHazardType: String, Codable, Sendable, Hashable, CaseIterable {
    case emergencyVehicle = "EMERGENCY_VEHICLE"
    case policeStop       = "POLICE_STOP"
    case accident         = "ACCIDENT"
    case roadHazard       = "ROAD_HAZARD"
    case construction     = "CONSTRUCTION"
    case weather          = "WEATHER"

    public var displayName: String {
        switch self {
        case .emergencyVehicle: return "Emergency Vehicle"
        case .policeStop:       return "Police Stop"
        case .accident:         return "Accident"
        case .roadHazard:       return "Road Hazard"
        case .construction:     return "Construction"
        case .weather:          return "Weather"
        }
    }
}

/// Hazard sighting returned by `GET /v1/hazards/nearby`.
public struct APIHazardSighting: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let type: APIHazardType
    public let severity: Int
    public let confidence: Double
    public let upvotes: Int
    public let downvotes: Int
    public let expiresAt: Date
    public let createdAt: Date
    public let distanceMeters: Double
    public let latitude: Double
    public let longitude: Double
}

/// `{ sightings: [...] }` wrapper.
public struct APIHazardNearbyResponse: Codable, Sendable, Equatable {
    public let sightings: [APIHazardSighting]
}

/// Body for `POST /v1/hazards`.
public struct APIReportHazardPayload: Codable, Sendable {
    public let type: APIHazardType
    public let latitude: Double
    public let longitude: Double
    public let severity: Int
    public let confidence: Double

    public init(type: APIHazardType, latitude: Double, longitude: Double, severity: Int = 2, confidence: Double) {
        self.type = type
        self.latitude = latitude
        self.longitude = longitude
        self.severity = severity
        self.confidence = confidence
    }
}

/// Response from `POST /v1/hazards` (201 Created).
public struct APIReportHazardResponse: Codable, Sendable, Equatable {
    public let id: String
    public let expiresAt: Date
}

/// Body for `POST /v1/hazards/:id/vote`.
public struct APIHazardVotePayload: Codable, Sendable, Equatable {
    public let direction: Int

    public init(direction: HazardVoteDirection) {
        self.direction = direction.rawValue
    }
}

public enum HazardVoteDirection: Int, Codable, Sendable {
    case up   = 1
    case down = -1
}
