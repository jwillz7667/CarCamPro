import Foundation
import AVFoundation
import CoreVideo
import CoreMedia
import OSLog

/// Top-level coordinator for the police / emergency-vehicle detection
/// subsystem. Feed it `CMSampleBuffer`s from the existing camera delegate
/// via `processFrame(sampleBuffer:)`. The coordinator throttles itself via
/// the thermal gate, drops frames if still busy, and publishes per-vehicle
/// assessments into `AlertManager`.
///
/// Robustness guarantees:
///   • **Bounded concurrency.** At most one inference pass runs at a time;
///     additional frames are dropped (never queued) so the pipeline can
///     never accumulate backlog.
///   • **Self-recovering.** If the in-flight detached task ever fails to
///     release the busy flag (unexpected trap, cancellation, …) a watchdog
///     clears it automatically after `busyWatchdogSeconds` so the pipeline
///     resumes instead of silently locking up.
///   • **Observable.** Every interesting event is reported to
///     `DetectionTelemetry` — frame counts, drop reasons, per-frame
///     inference latency, model-load state, last-alert timestamp — so a
///     HUD or test can verify the pipeline is alive without waiting for a
///     real cruiser to show up on camera.
final class PoliceDetectionSystem: @unchecked Sendable {
    static let shared = PoliceDetectionSystem()

    private let vehicleDetector = VehicleDetector()
    private let emergencyDetector = EmergencyLightDetector()
    private let roofAnalyzer = RoofAnalyzer()
    private let fleetDetector = FleetFeatureDetector()
    private let tracker = VehicleTracker()
    private let fusion = DetectionFusion()
    private let thermalGate = DetectionThermalGate.shared
    private let telemetry = DetectionTelemetry.shared

    // Busy-state guard. Uses a timestamp so a stale flag (caused by an
    // unexpected task death) is detectable + auto-recovered.
    private var isProcessing = false
    private var processingStartedAt: CFAbsoluteTime = 0
    private let busyLock = NSLock()

    /// Maximum inference pass duration before the watchdog force-releases
    /// the busy flag. Real inference (4 detectors in parallel + Vision
    /// overhead) completes well under 1 s on A15+, so 3 s is generous.
    private let busyWatchdogSeconds: CFAbsoluteTime = 3.0

    /// Enabled flag — flipped by `SettingsCoordinator` when the user toggles
    /// the detection setting. When false, `processFrame` short-circuits.
    private(set) var isEnabled: Bool = false

    /// Cap on concurrent per-vehicle analyses per frame to keep the ML work
    /// bounded. Extra vehicles are skipped (not queued).
    private let maxVehiclesPerFrame = 4

    private init() {
        telemetry.recordModelLoadState(
            vehicle: vehicleDetector.isModelLoaded,
            roof: roofAnalyzer.isModelLoaded,
            fleetFeature: fleetDetector.isModelLoaded
        )
    }

    // MARK: - Lifecycle

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if !enabled {
            Task { @MainActor in
                AlertManager.shared.reset()
                self.telemetry.reset()
            }
        }
    }

    /// Call from the camera's sample-buffer delegate.
    func processFrame(sampleBuffer: CMSampleBuffer) {
        guard isEnabled else { return }

        telemetry.recordFrameReceived()

        guard thermalGate.shouldProcessThisFrame() else {
            telemetry.recordFrameDroppedThermal()
            return
        }

        // Busy guard + watchdog: if the flag is set but the in-flight pass
        // has been running longer than `busyWatchdogSeconds`, force-clear it.
        // This recovers from the extremely rare case where a detached task
        // dies before hitting its `defer { markDone() }`.
        if !tryAcquireBusy() {
            telemetry.recordFrameDroppedBusy()
            return
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            telemetry.recordError("sample buffer had no image buffer")
            markDone()
            return
        }
        let timestamp = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        let imageSize = CGSize(
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer)
        )

        let sendablePixelBuffer = SendablePixelBuffer(value: pixelBuffer)
        let startedAt = CFAbsoluteTimeGetCurrent()

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            defer { self.markDone() }

            let pb = sendablePixelBuffer.value

            // 1. Detect vehicles.
            let detections = await self.vehicleDetector.detect(in: pb, timestamp: timestamp)

            // 2. Match to tracks.
            let matched = self.tracker.update(detections: detections, now: timestamp)
            let capped = Array(matched.prefix(self.maxVehiclesPerFrame))

            // 3. Sample emergency-light colors per track EVERY processed frame
            //    so the FFT has enough samples to find a peak.
            for (track, det) in capped {
                if let sample = self.emergencyDetector.sample(
                    pixelBuffer: pb,
                    vehicleBox: det.boundingBox,
                    imageSize: imageSize,
                    timestamp: timestamp
                ) {
                    track.recordColorSample(sample)
                }
            }

            // 4. Run per-vehicle detailed analysis in parallel.
            var assessments: [VehicleThreatAssessment] = []
            await withTaskGroup(of: VehicleThreatAssessment.self) { group in
                for (track, det) in capped {
                    group.addTask { [weak self] in
                        guard let self else {
                            return VehicleThreatAssessment(
                                id: track.id,
                                detection: det,
                                emergencyLights: EmergencyLightSignal(score: 0, frequencyHz: 0, bicolor: false),
                                roof: RoofSignal(lightBarScore: 0, roofRailsScore: 0.5),
                                fleetFeatures: .zero,
                                fusedScore: 0,
                                threatLevel: .none,
                                reasoning: [],
                                sustainedFrames: 0
                            )
                        }
                        async let emerg = self.emergencyDetector.analyze(track: track)
                        async let roof = self.roofAnalyzer.analyze(
                            pixelBuffer: pb,
                            vehicleBox: det.boundingBox,
                            imageSize: imageSize
                        )
                        async let fleet = self.fleetDetector.analyze(
                            pixelBuffer: pb,
                            vehicleBox: det.boundingBox,
                            imageSize: imageSize
                        )
                        let (e, r, f) = await (emerg, roof, fleet)
                        return self.fusion.assess(
                            track: track,
                            emergency: e,
                            roof: r,
                            fleet: f
                        )
                    }
                }
                for await assessment in group {
                    assessments.append(assessment)
                }
            }

            AlertManager.shared.publish(assessments: assessments)

            let latency = CFAbsoluteTimeGetCurrent() - startedAt
            self.telemetry.recordFrameProcessed(
                latencySeconds: Double(latency),
                activeTracks: assessments.count,
                hadVehicles: !assessments.isEmpty
            )
        }
    }

    // MARK: - Busy guard + watchdog

    /// Returns `true` iff the caller now holds the busy flag. If a prior
    /// holder has been stuck beyond `busyWatchdogSeconds`, force-release +
    /// log a diagnostic, then grant the flag to the new caller.
    private func tryAcquireBusy() -> Bool {
        busyLock.lock()
        defer { busyLock.unlock() }
        if isProcessing {
            let elapsed = CFAbsoluteTimeGetCurrent() - processingStartedAt
            if elapsed > busyWatchdogSeconds {
                AppLogger.detection.error(
                    "Detection pipeline watchdog: busy flag stuck for \(String(format: "%.2f", elapsed))s — force-releasing"
                )
                telemetry.recordError("pipeline watchdog recovered a stuck busy flag")
                // fall through to re-acquire.
            } else {
                return false
            }
        }
        isProcessing = true
        processingStartedAt = CFAbsoluteTimeGetCurrent()
        return true
    }

    private func markDone() {
        busyLock.lock()
        isProcessing = false
        processingStartedAt = 0
        busyLock.unlock()
    }
}

/// Thin shim to pass `CVPixelBuffer` across a `Task.detached` boundary
/// without Swift 6 concurrency complaining. The buffer is ref-counted by
/// CoreVideo and thread-safe for read access.
private struct SendablePixelBuffer: @unchecked Sendable {
    let value: CVPixelBuffer
}
