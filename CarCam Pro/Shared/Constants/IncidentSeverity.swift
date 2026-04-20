enum IncidentSeverity: String, Codable, Sendable {
    case minor
    case moderate
    case severe

    var displayName: String {
        switch self {
        case .minor: "Minor"
        case .moderate: "Moderate"
        case .severe: "Severe"
        }
    }
}
