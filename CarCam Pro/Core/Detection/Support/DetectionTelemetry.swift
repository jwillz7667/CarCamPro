import Foundation
import Observation
import OSLog

/// Live telemetry for the on-device ML detection pipeline.
///
/// Exposes enough state for a diagnostic HUD (or an automated test) to answer
/// *"is detection actually working right now?"* without waiting for a real
/// emergency-vehicle to drive by:
///
///   • **Frame throughput:** frames received vs. frames processed — if the
///     camera is piping samples but the pipeline shows zero processed frames,
///     something is broken upstream of the ML models.
///   • **Drop reasons:** split between thermal gating (expected on hot
///     devices) and busy-drops (pipeline back-pressure).
///   • **Latency:** per-frame inference time plus a rolling p50 / p95 so
///     thermal regressions surface immediately.
///   • **Model load state:** did each Core ML model actually load at launch?
///     A missing model silently degrades the entire pipeline — surfacing it
///     as a boolean lets QA verify the detection ship bundle.
///   • **Stall heartbeat:** if frames keep arriving but nothing has been
///     processed for `stallThresholdSeconds`, flag a stall. The pipeline's
///     watchdog uses this signal to recover a stuck `isProcessing` flag.
///
/// All mutations hop to the main actor so SwiftUI binds cleanly to every
/// property via `@Observable`. Writes from the detection pipeline's
/// detached tasks are cheap — they post into a Task and return.
@Observable
@MainActor
final class DetectionTelemetry {
    static let shared = DetectionTelemetry()

    // MARK: - Frame counters (monotonic across process lifetime)

    private(set) var framesReceived: Int = 0
    private(set) var framesProcessed: Int = 0
    private(set) var framesDroppedThermal: Int = 0
    private(set) var framesDroppedBusy: Int = 0

    // MARK: - Inference timing (milliseconds)

    /// Latency of the most recently completed inference pass.
    private(set) var lastInferenceLatencyMs: Double = 0
    /// Rolling p50 latency across the last `latencyWindowSize` frames.
    private(set) var rollingP50LatencyMs: Double = 0
    /// Rolling p95 latency across the last `latencyWindowSize` frames.
    private(set) var rollingP95LatencyMs: Double = 0
    /// Effective processed-frame rate (EMA), Hz.
    private(set) var effectiveFPS: Double = 0

    // MARK: - Model load state

    private(set) var vehicleModelLoaded: Bool = false
    private(set) var roofModelLoaded: Bool = false
    private(set) var fleetFeatureModelLoaded: Bool = false

    // MARK: - Detection state

    /// Last time the pipeline produced *any* assessment (even `.none`).
    private(set) var lastAssessmentAt: Date?
    /// Last time the pipeline produced a tracked vehicle (count > 0).
    private(set) var lastVehicleSeenAt: Date?
    /// Last time a `likely` or `confirmed` alert actually fired.
    private(set) var lastAlertFiredAt: Date?
    private(set) var activeTrackCount: Int = 0
    private(set) var lastError: String?

    // MARK: - Stall detection

    /// True when frames keep arriving but nothing has been processed for
    /// longer than `stallThresholdSeconds`. `PoliceDetectionSystem`'s
    /// watchdog uses this to recover a stuck `isProcessing` flag.
    private(set) var isStalled: Bool = false
    private var lastFrameArrivedAt: Date?
    private var lastProcessedAt: Date?

    // MARK: - Configuration

    /// Number of recent latency samples retained for p50 / p95.
    private let latencyWindowSize = 60
    /// How long the pipeline can have frames coming in with nothing
    /// completing before we call it stalled. Real inference (even on a cold
    /// pipeline) completes in < 500 ms; 3 s is generous.
    private let stallThresholdSeconds: TimeInterval = 3.0
    /// EMA smoothing factor for `effectiveFPS`. α closer to 1 = snappier,
    /// closer to 0 = smoother.
    private let fpsAlpha: Double = 0.2

    // Internal rolling window. Sorted lazily when percentiles are queried.
    private var latencySamples: [Double] = []

    private init() {}

    // MARK: - Recording API (called from the detection pipeline)

    nonisolated func recordFrameReceived() {
        Task { @MainActor in self.bumpReceived() }
    }

    nonisolated func recordFrameDroppedThermal() {
        Task { @MainActor in self.framesDroppedThermal += 1 }
    }

    nonisolated func recordFrameDroppedBusy() {
        Task { @MainActor in self.framesDroppedBusy += 1 }
    }

    nonisolated func recordFrameProcessed(latencySeconds: Double, activeTracks: Int, hadVehicles: Bool) {
        Task { @MainActor in
            self.applyProcessed(
                latencyMs: latencySeconds * 1000,
                activeTracks: activeTracks,
                hadVehicles: hadVehicles
            )
        }
    }

    nonisolated func recordAlertFired() {
        Task { @MainActor in self.lastAlertFiredAt = Date() }
    }

    nonisolated func recordError(_ message: String) {
        Task { @MainActor in
            self.lastError = message
            AppLogger.detection.error("DetectionTelemetry error: \(message, privacy: .public)")
        }
    }

    /// Called once at startup to stamp which models loaded cleanly.
    nonisolated func recordModelLoadState(
        vehicle: Bool,
        roof: Bool,
        fleetFeature: Bool
    ) {
        Task { @MainActor in
            self.vehicleModelLoaded = vehicle
            self.roofModelLoaded = roof
            self.fleetFeatureModelLoaded = fleetFeature
        }
    }

    // MARK: - Queries

    /// Seconds since the pipeline last reported a processed frame.
    /// `.infinity` if nothing has been processed yet.
    var secondsSinceLastProcessed: TimeInterval {
        lastProcessedAt.map { Date().timeIntervalSince($0) } ?? .infinity
    }

    /// Seconds since the pipeline last produced a tracked vehicle.
    var secondsSinceLastVehicle: TimeInterval {
        lastVehicleSeenAt.map { Date().timeIntervalSince($0) } ?? .infinity
    }

    var busyDropRate: Double {
        let total = framesProcessed + framesDroppedBusy
        guard total > 0 else { return 0 }
        return Double(framesDroppedBusy) / Double(total)
    }

    /// True once at least one frame has been processed and the most recent
    /// batch was less than `stallThresholdSeconds` ago. Useful for a "green
    /// dot" indicator in the HUD.
    var isHealthy: Bool {
        guard framesProcessed > 0 else { return false }
        return !isStalled
    }

    // MARK: - Reset (used by tests and when detection is disabled)

    /// Zero all counters but retain model-load state (loading happens once).
    func reset() {
        framesReceived = 0
        framesProcessed = 0
        framesDroppedThermal = 0
        framesDroppedBusy = 0
        lastInferenceLatencyMs = 0
        rollingP50LatencyMs = 0
        rollingP95LatencyMs = 0
        effectiveFPS = 0
        lastAssessmentAt = nil
        lastVehicleSeenAt = nil
        lastAlertFiredAt = nil
        activeTrackCount = 0
        lastError = nil
        isStalled = false
        lastFrameArrivedAt = nil
        lastProcessedAt = nil
        latencySamples.removeAll(keepingCapacity: true)
    }

    // MARK: - Internals

    private func bumpReceived() {
        framesReceived += 1
        lastFrameArrivedAt = Date()
        recomputeStall()
    }

    private func applyProcessed(latencyMs: Double, activeTracks: Int, hadVehicles: Bool) {
        let now = Date()
        framesProcessed += 1
        lastInferenceLatencyMs = latencyMs
        lastAssessmentAt = now
        activeTrackCount = activeTracks
        if hadVehicles {
            lastVehicleSeenAt = now
        }

        // Effective FPS via EMA over inter-arrival time.
        if let prev = lastProcessedAt {
            let dt = now.timeIntervalSince(prev)
            if dt > 0 {
                let instantaneous = 1.0 / dt
                effectiveFPS = fpsAlpha * instantaneous + (1 - fpsAlpha) * effectiveFPS
            }
        }
        lastProcessedAt = now

        // Rolling latency percentiles.
        latencySamples.append(latencyMs)
        if latencySamples.count > latencyWindowSize {
            latencySamples.removeFirst(latencySamples.count - latencyWindowSize)
        }
        let sorted = latencySamples.sorted()
        rollingP50LatencyMs = percentile(sorted, 0.5)
        rollingP95LatencyMs = percentile(sorted, 0.95)

        recomputeStall()
    }

    /// Re-evaluate the stall flag. Stalled = frames are arriving AND either
    /// no frames have ever been processed OR the last processed frame is
    /// stale beyond `stallThresholdSeconds`.
    private func recomputeStall() {
        guard let lastArrived = lastFrameArrivedAt else {
            isStalled = false
            return
        }
        let now = Date()
        // Only consider a stall if frames are still flowing (camera alive).
        let framesFlowing = now.timeIntervalSince(lastArrived) < stallThresholdSeconds
        guard framesFlowing else {
            isStalled = false
            return
        }
        if let lastProc = lastProcessedAt {
            isStalled = now.timeIntervalSince(lastProc) > stallThresholdSeconds
        } else {
            // Frames have been arriving for a while but none completed.
            isStalled = framesReceived >= 30
        }
    }

    private func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        if sorted.count == 1 { return sorted[0] }
        let rank = p * Double(sorted.count - 1)
        let low = Int(rank.rounded(.down))
        let high = Int(rank.rounded(.up))
        if low == high { return sorted[low] }
        let frac = rank - Double(low)
        return sorted[low] * (1 - frac) + sorted[high] * frac
    }
}
