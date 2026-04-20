import Foundation

/// Stream-oriented API for impact detection — the concrete actor implementation
/// polls Core Motion at the rate dictated by the current thermal tier.
protocol IncidentDetectorProtocol: Sendable {
    /// Async sequence of detected events (post-debounce).
    func events() async -> AsyncStream<IncidentEvent>

    /// Async sequence of raw g-force samples for UI visualization (60 Hz max).
    func liveGForce() async -> AsyncStream<GForceSample>

    /// Start/stop motion updates.
    func start() async throws
    func stop() async

    /// Adjust the sample rate (e.g. in response to thermal tier changes).
    func setSampleRateHz(_ hz: Double?) async

    /// Adjust the impact trigger threshold (Gs above gravity).
    func setThreshold(_ g: Double) async
}

/// Lightweight sample for UI rendering (no allocation pressure).
struct GForceSample: Sendable {
    let timestamp: Date
    let x: Double
    let y: Double
    let z: Double
    let total: Double
}
