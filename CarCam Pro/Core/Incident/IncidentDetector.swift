import Foundation
import CoreMotion
import OSLog

/// Core Motion-backed impact detector.
///
/// Runs `CMMotionManager` updates on a dedicated `OperationQueue` at 60 Hz
/// (tier-throttled down to 10 Hz or paused for `.serious` / `.critical`).
/// Emits both raw samples (for the live HUD's g-force target) and debounced
/// incident events (for recording-pipeline locking).
///
/// Algorithm:
///   - Compute total g = `√(x² + y² + z²) - 1.0` (gravity-subtracted)
///   - Fire an event when total ≥ threshold (default 1.5g)
///   - 10-second debounce between events prevents double-counting
actor IncidentDetector: IncidentDetectorProtocol {
    /// Minimum gap between consecutive events.
    nonisolated static let debounce: TimeInterval = 10

    private let motion = CMMotionManager()
    private let queue: OperationQueue

    private var running = false
    private var sampleRateHz: Double = 60
    private var threshold: Double = 1.5
    private var lastEventTime: Date?

    private var eventContinuation: AsyncStream<IncidentEvent>.Continuation?
    private var sampleContinuation: AsyncStream<GForceSample>.Continuation?

    init() {
        let q = OperationQueue()
        q.name = "Res.CarCam-Pro.motion"
        q.qualityOfService = .userInitiated
        q.maxConcurrentOperationCount = 1
        self.queue = q
    }

    func events() -> AsyncStream<IncidentEvent> {
        AsyncStream { continuation in
            self.eventContinuation = continuation
            continuation.onTermination = { _ in
                Task { await self.clearEventContinuation() }
            }
        }
    }

    func liveGForce() -> AsyncStream<GForceSample> {
        AsyncStream { continuation in
            self.sampleContinuation = continuation
            continuation.onTermination = { _ in
                Task { await self.clearSampleContinuation() }
            }
        }
    }

    func start() async throws {
        guard motion.isAccelerometerAvailable else {
            throw IncidentDetectorError.accelerometerUnavailable
        }
        guard !running else { return }

        motion.accelerometerUpdateInterval = 1.0 / sampleRateHz
        motion.startAccelerometerUpdates(to: queue) { [weak self] data, error in
            guard let self, let data else {
                if let error { AppLogger.incident.error("CoreMotion error: \(error.localizedDescription)") }
                return
            }
            Task { await self.ingest(data) }
        }
        running = true
        AppLogger.incident.info("Incident detector started @ \(self.sampleRateHz) Hz, threshold \(self.threshold)g")
    }

    func stop() {
        guard running else { return }
        motion.stopAccelerometerUpdates()
        running = false
        AppLogger.incident.info("Incident detector stopped")
    }

    func setSampleRateHz(_ hz: Double?) {
        if let hz {
            sampleRateHz = hz
            if motion.isAccelerometerActive {
                motion.accelerometerUpdateInterval = 1.0 / hz
            }
        } else {
            // nil = pause motion updates entirely (critical thermal tier).
            stop()
        }
    }

    func setThreshold(_ g: Double) {
        threshold = max(0.3, g)
    }

    // MARK: - Private

    private func ingest(_ data: CMAccelerometerData) {
        let x = data.acceleration.x
        let y = data.acceleration.y
        let z = data.acceleration.z
        let magnitude = (x * x + y * y + z * z).squareRoot()
        let netG = abs(magnitude - 1.0)

        let sample = GForceSample(timestamp: Date(), x: x, y: y, z: z, total: netG)
        sampleContinuation?.yield(sample)

        guard netG >= threshold else { return }
        let now = Date()
        if let last = lastEventTime, now.timeIntervalSince(last) < Self.debounce {
            return
        }
        lastEventTime = now

        let severity: IncidentSeverity = {
            switch netG {
            case 6.0...: return .severe
            case 3.0..<6.0: return .moderate
            default: return .minor
            }
        }()

        let event = IncidentEvent(
            timestamp: now,
            totalG: netG,
            lateralG: x,
            longitudinalG: y,
            verticalG: z,
            severity: severity
        )
        eventContinuation?.yield(event)
        AppLogger.incident.notice("Incident detected: \(netG, format: .fixed(precision: 2))g (\(severity.rawValue))")
    }

    private func clearEventContinuation() { eventContinuation = nil }
    private func clearSampleContinuation() { sampleContinuation = nil }
}

enum IncidentDetectorError: LocalizedError {
    case accelerometerUnavailable

    var errorDescription: String? {
        switch self {
        case .accelerometerUnavailable: return "Accelerometer is not available on this device."
        }
    }
}
