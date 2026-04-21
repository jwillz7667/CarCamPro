import Foundation
import CoreGraphics

// MARK: - Vehicle detection output

/// Classes the vehicle detector emits. Keep synced with the Core ML model labels.
enum VehicleClass: String, Codable, CaseIterable, Sendable {
    case car, suv, pickup, truck, van, motorcycle, bus
    case unknown
}

/// Known fleet-capable models. Detections in this set raise suspicion more
/// aggressively via `DetectionFusion`.
enum FleetCapableModel: String, Codable, CaseIterable, Sendable {
    case fordExplorer      // Police Interceptor Utility
    case fordF150          // Police Responder
    case chevyTahoe        // PPV
    case chevySuburban
    case chevySilverado
    case dodgeCharger      // Pursuit
    case dodgeDurango      // Pursuit
    case fordTransit       // Unmarked surveillance
    case ramTruck
    case unknown
}

struct VehicleDetection: Identifiable, Hashable, Sendable {
    let id: UUID
    /// Normalized bbox (0…1) in Vision coordinate space (origin bottom-left).
    let boundingBox: CGRect
    let vehicleClass: VehicleClass
    let fleetCapableModel: FleetCapableModel
    let confidence: Float
    /// Approximate distance in meters, if depth available. Nil otherwise.
    let estimatedDistance: Float?
    let timestamp: TimeInterval

    init(
        id: UUID = UUID(),
        boundingBox: CGRect,
        vehicleClass: VehicleClass,
        fleetCapableModel: FleetCapableModel,
        confidence: Float,
        estimatedDistance: Float? = nil,
        timestamp: TimeInterval
    ) {
        self.id = id
        self.boundingBox = boundingBox
        self.vehicleClass = vehicleClass
        self.fleetCapableModel = fleetCapableModel
        self.confidence = confidence
        self.estimatedDistance = estimatedDistance
        self.timestamp = timestamp
    }
}

// MARK: - Per-signal scores

struct EmergencyLightSignal: Hashable, Sendable {
    /// 0…1, probability that active emergency lights are present.
    let score: Float
    /// Dominant modulation frequency in Hz (0 if none found).
    let frequencyHz: Float
    /// Whether red AND blue both modulate (very strong signal).
    let bicolor: Bool
}

struct RoofSignal: Hashable, Sendable {
    /// 0…1, probability of a roof-mounted light bar (marked cruiser).
    let lightBarScore: Float
    /// 0…1, probability that the roof has civilian roof rails.
    /// LOW value on a fleet-capable model is suspicious.
    let roofRailsScore: Float
}

struct FleetFeatureSignal: Hashable, Sendable {
    let pushBarScore: Float          // front bumper guard
    let spotlightScore: Float        // A-pillar spotlight(s)
    let blackoutWheelsScore: Float   // steel/blackout wheels vs alloy
    let antennaScore: Float          // multiple roof/trunk antennas

    static let zero = FleetFeatureSignal(
        pushBarScore: 0, spotlightScore: 0,
        blackoutWheelsScore: 0, antennaScore: 0
    )
}

// MARK: - Threat assessment

enum ThreatLevel: Int, Comparable, Codable, Sendable {
    case none = 0
    case low = 1        // Weak signal — do not alert
    case possible = 2   // Subtle alert — visual only
    case likely = 3     // Full alert — haptic + chime + visual
    case confirmed = 4  // Very strong — urgent alert

    static func < (lhs: ThreatLevel, rhs: ThreatLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct VehicleThreatAssessment: Identifiable, Sendable {
    let id: UUID // matches the track ID
    let detection: VehicleDetection
    let emergencyLights: EmergencyLightSignal
    let roof: RoofSignal
    let fleetFeatures: FleetFeatureSignal
    let fusedScore: Float               // 0…1
    let threatLevel: ThreatLevel
    let reasoning: [String]             // human-readable explanation
    let sustainedFrames: Int
}
