enum IncidentSensitivity: String, Codable, CaseIterable, Sendable {
    case low
    case medium
    case high

    var threshold: Double {
        switch self {
        case .low: 6.0
        case .medium: 3.0
        case .high: 1.5
        }
    }

    var displayName: String {
        switch self {
        case .low: "Low (6g+)"
        case .medium: "Medium (3g+)"
        case .high: "High (1.5g+)"
        }
    }

    var description: String {
        switch self {
        case .low: "Detects severe impacts only"
        case .medium: "Detects hard braking and impacts"
        case .high: "Detects any sudden movement"
        }
    }
}
