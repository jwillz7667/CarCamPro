import Foundation

/// A single detected incident — produced by `IncidentDetector`, consumed by
/// the recording pipeline to protect the current clip + surrounding context.
struct IncidentEvent: Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let totalG: Double
    let lateralG: Double
    let longitudinalG: Double
    let verticalG: Double
    let severity: IncidentSeverity

    nonisolated init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        totalG: Double,
        lateralG: Double,
        longitudinalG: Double,
        verticalG: Double,
        severity: IncidentSeverity
    ) {
        self.id = id
        self.timestamp = timestamp
        self.totalG = totalG
        self.lateralG = lateralG
        self.longitudinalG = longitudinalG
        self.verticalG = verticalG
        self.severity = severity
    }
}
