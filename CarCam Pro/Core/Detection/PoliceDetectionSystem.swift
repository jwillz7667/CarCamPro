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
final class PoliceDetectionSystem: @unchecked Sendable {
    static let shared = PoliceDetectionSystem()

    private let vehicleDetector = VehicleDetector()
    private let emergencyDetector = EmergencyLightDetector()
    private let roofAnalyzer = RoofAnalyzer()
    private let fleetDetector = FleetFeatureDetector()
    private let tracker = VehicleTracker()
    private let fusion = DetectionFusion()
    private let thermalGate = DetectionThermalGate.shared

    private var isProcessing = false
    private let isProcessingLock = NSLock()

    /// Enabled flag — flipped by `SettingsCoordinator` when the user toggles
    /// the detection setting. When false, `processFrame` short-circuits.
    private(set) var isEnabled: Bool = false

    /// Cap on concurrent per-vehicle analyses per frame to keep the ML work
    /// bounded. Extra vehicles are skipped (not queued).
    private let maxVehiclesPerFrame = 4

    private init() {}

    // MARK: - Lifecycle

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if !enabled {
            Task { @MainActor in AlertManager.shared.reset() }
        }
    }

    /// Call from the camera's sample-buffer delegate.
    func processFrame(sampleBuffer: CMSampleBuffer) {
        guard isEnabled else { return }
        guard thermalGate.shouldProcessThisFrame() else { return }

        // Drop frames if still busy — never queue backlog.
        isProcessingLock.lock()
        if isProcessing {
            isProcessingLock.unlock()
            return
        }
        isProcessing = true
        isProcessingLock.unlock()

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            markDone()
            return
        }
        let timestamp = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        let imageSize = CGSize(
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer)
        )

        let sendablePixelBuffer = SendablePixelBuffer(value: pixelBuffer)

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
        }
    }

    private func markDone() {
        isProcessingLock.lock()
        isProcessing = false
        isProcessingLock.unlock()
    }
}

/// Thin shim to pass `CVPixelBuffer` across a `Task.detached` boundary
/// without Swift 6 concurrency complaining. The buffer is ref-counted by
/// CoreVideo and thread-safe for read access.
private struct SendablePixelBuffer: @unchecked Sendable {
    let value: CVPixelBuffer
}
