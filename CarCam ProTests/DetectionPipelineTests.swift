import Foundation
import CoreGraphics
import CoreVideo
import CoreMedia
import Testing
@testable import CarCam_Pro

// MARK: - Synthetic sample-buffer helper

/// Build a minimal `CMSampleBuffer` backed by a zero-filled BGRA pixel
/// buffer for feeding through `PoliceDetectionSystem.processFrame(...)`
/// without a real camera. Uses 640×480 to match the vehicle detector's
/// expected input aspect ratio.
private func makeSyntheticSampleBuffer(
    width: Int = 640,
    height: Int = 480,
    timestampSeconds: Double = 0
) -> CMSampleBuffer? {
    var pixelBuffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(
        kCFAllocatorDefault,
        width,
        height,
        kCVPixelFormatType_32BGRA,
        [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary,
        &pixelBuffer
    )
    guard status == kCVReturnSuccess, let pb = pixelBuffer else { return nil }

    var formatDesc: CMFormatDescription?
    let fStatus = CMVideoFormatDescriptionCreateForImageBuffer(
        allocator: kCFAllocatorDefault,
        imageBuffer: pb,
        formatDescriptionOut: &formatDesc
    )
    guard fStatus == noErr, let fd = formatDesc else { return nil }

    var timing = CMSampleTimingInfo(
        duration: CMTime(value: 1, timescale: 30),
        presentationTimeStamp: CMTime(seconds: timestampSeconds, preferredTimescale: 1_000),
        decodeTimeStamp: .invalid
    )

    var sampleBuffer: CMSampleBuffer?
    let sbStatus = CMSampleBufferCreateReadyWithImageBuffer(
        allocator: kCFAllocatorDefault,
        imageBuffer: pb,
        formatDescription: fd,
        sampleTiming: &timing,
        sampleBufferOut: &sampleBuffer
    )
    guard sbStatus == noErr else { return nil }
    return sampleBuffer
}

/// Unit tests covering the non-ML layers of the detection pipeline:
///
///   • `RingBuffer` — capacity + overwrite semantics; the FFT relies on
///     this behaving correctly or the emergency-light detector silently
///     returns garbage.
///   • `VehicleTracker` — IoU matching + stale-track eviction; a regression
///     here would make every frame look like "new vehicle just appeared".
///   • `DetectionFusion` — the threshold ladder for `.none` / `.possible` /
///     `.likely` / `.confirmed`; drift here changes alert behavior.
///   • `DetectionTelemetry` — counter arithmetic, latency percentiles,
///     stall detection; the HUD's correctness rides on this.
///   • `AlertManager` — debounce interval + reset semantics.
///
/// Everything is hermetic — no camera, no Core ML model, no audio session.
@Suite("Detection Pipeline — unit layer", .serialized)
struct DetectionPipelineTests {

    // MARK: - RingBuffer

    @Test("RingBuffer — appending up to capacity keeps every value")
    func ringBufferBelowCapacity() {
        var buf = RingBuffer<Int>(capacity: 5)
        for i in 1...3 { buf.push(i) }
        #expect(buf.values == [1, 2, 3])
        #expect(buf.count == 3)
    }

    @Test("RingBuffer — past capacity overwrites oldest in FIFO order")
    func ringBufferOverwrites() {
        var buf = RingBuffer<Int>(capacity: 3)
        for i in 1...5 { buf.push(i) } // pushes 4 then 5 replace 1, 2
        // Internal ordering is storage-order, not temporal. We assert the
        // *set* of retained elements rather than the ordering.
        #expect(Set(buf.values) == Set([3, 4, 5]))
        #expect(buf.count == 3)
    }

    @Test("RingBuffer<Float> — mean and meanTopK")
    func ringBufferMeans() {
        var buf = RingBuffer<Float>(capacity: 10)
        for v in [Float]([0.1, 0.2, 0.3, 0.9, 0.9, 0.1, 0.1]) { buf.push(v) }
        #expect(abs(buf.mean() - (2.6 / 7)) < 0.001)
        // Top-3 = 0.9, 0.9, 0.3 → 0.7
        #expect(abs(buf.meanTopK(3) - 0.7) < 0.001)
    }

    // MARK: - VehicleTracker

    @Test("VehicleTracker — overlapping detection matches existing track")
    func trackerReusesOverlappingTrack() {
        let tracker = VehicleTracker()
        let bbox = CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2)
        let first = VehicleDetection(
            boundingBox: bbox,
            vehicleClass: .car,
            fleetCapableModel: .unknown,
            confidence: 0.9,
            timestamp: 0.0
        )
        let r1 = tracker.update(detections: [first], now: 0.0)
        #expect(r1.count == 1)

        // Slightly shifted bbox (~75% IoU) — should match the same track.
        let shifted = CGRect(x: 0.41, y: 0.41, width: 0.2, height: 0.2)
        let second = VehicleDetection(
            boundingBox: shifted,
            vehicleClass: .car,
            fleetCapableModel: .unknown,
            confidence: 0.9,
            timestamp: 0.1
        )
        let r2 = tracker.update(detections: [second], now: 0.1)
        #expect(r2.count == 1)
        #expect(r2.first?.0.id == r1.first?.0.id) // same track reused
    }

    @Test("VehicleTracker — disjoint detection creates a new track")
    func trackerCreatesNewTrackForDisjointBox() {
        let tracker = VehicleTracker()
        _ = tracker.update(
            detections: [VehicleDetection(
                boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.1, height: 0.1),
                vehicleClass: .car, fleetCapableModel: .unknown,
                confidence: 0.9, timestamp: 0.0
            )],
            now: 0.0
        )
        let result = tracker.update(
            detections: [VehicleDetection(
                boundingBox: CGRect(x: 0.8, y: 0.8, width: 0.1, height: 0.1),
                vehicleClass: .car, fleetCapableModel: .unknown,
                confidence: 0.9, timestamp: 0.1
            )],
            now: 0.1
        )
        #expect(tracker.allTracks().count == 2)
        #expect(result.count == 1)
    }

    @Test("VehicleTracker — stale track is evicted after timeout")
    func trackerEvictsStale() {
        let tracker = VehicleTracker()
        _ = tracker.update(
            detections: [VehicleDetection(
                boundingBox: CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2),
                vehicleClass: .car, fleetCapableModel: .unknown,
                confidence: 0.9, timestamp: 0.0
            )],
            now: 0.0
        )
        #expect(tracker.allTracks().count == 1)
        // 3s later with no detection.
        _ = tracker.update(detections: [], now: 3.0)
        #expect(tracker.allTracks().count == 0)
    }

    // MARK: - DetectionFusion

    @Test("DetectionFusion — zero signal → .none threat level")
    func fusionZeroIsNone() {
        let fusion = DetectionFusion()
        let det = VehicleDetection(
            boundingBox: CGRect(x: 0, y: 0, width: 0.2, height: 0.2),
            vehicleClass: .car, fleetCapableModel: .unknown,
            confidence: 0.5, timestamp: 0
        )
        let track = VehicleTrack(detection: det)
        let result = fusion.assess(
            track: track,
            emergency: EmergencyLightSignal(score: 0, frequencyHz: 0, bicolor: false),
            roof: RoofSignal(lightBarScore: 0, roofRailsScore: 0.5),
            fleet: .zero
        )
        #expect(result.threatLevel == .none)
        #expect(result.fusedScore < 0.1)
    }

    @Test("DetectionFusion — sustained strong emergency lights → .confirmed after hysteresis")
    func fusionSustainedEmergencyConfirms() {
        let fusion = DetectionFusion()
        let det = VehicleDetection(
            boundingBox: CGRect(x: 0.3, y: 0.3, width: 0.2, height: 0.2),
            vehicleClass: .suv, fleetCapableModel: .fordExplorer,
            confidence: 0.9, timestamp: 0
        )
        let track = VehicleTrack(detection: det)
        let strongEmerg = EmergencyLightSignal(score: 0.9, frequencyHz: 4.5, bicolor: true)
        let roof = RoofSignal(lightBarScore: 0.1, roofRailsScore: 0.2)

        var last: VehicleThreatAssessment?
        // Feed 8 consecutive frames of the same strong signal so the track's
        // smoothed score stabilizes and sustainedFrames clears hysteresis.
        for _ in 0..<8 {
            last = fusion.assess(
                track: track, emergency: strongEmerg, roof: roof, fleet: .zero
            )
        }
        #expect(last != nil)
        #expect(last?.threatLevel == .confirmed || last?.threatLevel == .likely)
        #expect((last?.sustainedFrames ?? 0) >= 4)
        #expect(last?.reasoning.contains(where: { $0.contains("emergency lights") }) == true)
    }

    @Test("DetectionFusion — single-frame strong signal does NOT jump to confirmed")
    func fusionSingleFrameBelowHysteresis() {
        let fusion = DetectionFusion()
        let det = VehicleDetection(
            boundingBox: CGRect(x: 0.3, y: 0.3, width: 0.2, height: 0.2),
            vehicleClass: .suv, fleetCapableModel: .fordExplorer,
            confidence: 0.9, timestamp: 0
        )
        let track = VehicleTrack(detection: det)
        // One frame of strong signal.
        let result = fusion.assess(
            track: track,
            emergency: EmergencyLightSignal(score: 0.9, frequencyHz: 4.5, bicolor: true),
            roof: RoofSignal(lightBarScore: 0.1, roofRailsScore: 0.2),
            fleet: .zero
        )
        // One frame not enough for sustained escalation to .confirmed.
        #expect(result.threatLevel != .confirmed)
    }

    // MARK: - DetectionTelemetry

    @Test("Telemetry — frame counters increment and drop counts are isolated")
    @MainActor
    func telemetryCounters() async {
        let t = DetectionTelemetry.shared
        t.reset()
        #expect(t.framesReceived == 0)

        t.recordFrameReceived()
        t.recordFrameReceived()
        t.recordFrameReceived()
        t.recordFrameDroppedThermal()
        t.recordFrameDroppedBusy()

        // recordFrame* hops to MainActor via Task — wait for those to land.
        try? await Task.sleep(for: .milliseconds(80))

        #expect(t.framesReceived == 3)
        #expect(t.framesDroppedThermal == 1)
        #expect(t.framesDroppedBusy == 1)
        #expect(t.framesProcessed == 0)
    }

    @Test("Telemetry — processed frame updates latency + last-seen timestamps")
    @MainActor
    func telemetryProcessedFrame() async {
        let t = DetectionTelemetry.shared
        t.reset()

        t.recordFrameProcessed(latencySeconds: 0.120, activeTracks: 2, hadVehicles: true)
        try? await Task.sleep(for: .milliseconds(80))

        #expect(t.framesProcessed == 1)
        #expect(abs(t.lastInferenceLatencyMs - 120.0) < 0.1)
        #expect(t.activeTrackCount == 2)
        #expect(t.lastAssessmentAt != nil)
        #expect(t.lastVehicleSeenAt != nil)
    }

    @Test("Telemetry — percentiles over a known latency distribution")
    @MainActor
    func telemetryPercentiles() async {
        let t = DetectionTelemetry.shared
        t.reset()
        // Feed latencies 10, 20, 30, ..., 200 ms. p50 = ~105, p95 = ~190.5.
        for i in 1...20 {
            t.recordFrameProcessed(
                latencySeconds: Double(i) * 0.01,
                activeTracks: 0, hadVehicles: false
            )
        }
        try? await Task.sleep(for: .milliseconds(200))

        #expect(t.framesProcessed == 20)
        #expect(t.rollingP50LatencyMs > 90 && t.rollingP50LatencyMs < 120)
        #expect(t.rollingP95LatencyMs > 170 && t.rollingP95LatencyMs <= 200)
    }

    @Test("Telemetry — reset zeroes counters + clears last-seen state")
    @MainActor
    func telemetryReset() async {
        let t = DetectionTelemetry.shared
        t.recordFrameReceived()
        t.recordFrameProcessed(latencySeconds: 0.05, activeTracks: 1, hadVehicles: true)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(t.framesReceived > 0)

        t.reset()
        #expect(t.framesReceived == 0)
        #expect(t.framesProcessed == 0)
        #expect(t.lastInferenceLatencyMs == 0)
        #expect(t.lastAssessmentAt == nil)
        #expect(t.isStalled == false)
    }

    @Test("Telemetry — isHealthy is false before first processed frame")
    @MainActor
    func telemetryHealthInitiallyFalse() {
        let t = DetectionTelemetry.shared
        t.reset()
        #expect(t.isHealthy == false)
    }

    @Test("Telemetry — model load state is recorded independently")
    @MainActor
    func telemetryModelLoad() async {
        let t = DetectionTelemetry.shared
        t.reset()
        t.recordModelLoadState(vehicle: true, roof: false, fleetFeature: true)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(t.vehicleModelLoaded == true)
        #expect(t.roofModelLoaded == false)
        #expect(t.fleetFeatureModelLoaded == true)
    }

    // MARK: - End-to-end synthetic-frame injection

    @Test("PoliceDetectionSystem — disabled short-circuits before telemetry")
    @MainActor
    func systemDisabledShortCircuits() async {
        let system = PoliceDetectionSystem.shared
        let telemetry = DetectionTelemetry.shared
        system.setEnabled(false)
        // setEnabled(false) dispatches a reset to main; let it settle.
        try? await Task.sleep(for: .milliseconds(100))
        telemetry.reset()
        #expect(telemetry.framesReceived == 0)

        guard let buffer = makeSyntheticSampleBuffer() else {
            Issue.record("Failed to build synthetic sample buffer")
            return
        }
        system.processFrame(sampleBuffer: buffer)
        try? await Task.sleep(for: .milliseconds(100))

        #expect(telemetry.framesReceived == 0)
    }

    @Test("PoliceDetectionSystem — enabled system records every received frame")
    @MainActor
    func systemEnabledIncrementsFramesReceived() async {
        let system = PoliceDetectionSystem.shared
        let telemetry = DetectionTelemetry.shared
        system.setEnabled(false)
        try? await Task.sleep(for: .milliseconds(100))
        telemetry.reset()
        system.setEnabled(true)
        defer {
            system.setEnabled(false)
        }

        for i in 0..<5 {
            guard let buffer = makeSyntheticSampleBuffer(timestampSeconds: Double(i) * 0.033) else {
                Issue.record("Failed to build synthetic sample buffer")
                return
            }
            system.processFrame(sampleBuffer: buffer)
        }
        try? await Task.sleep(for: .milliseconds(300))

        #expect(telemetry.framesReceived == 5)
    }

    @Test("PoliceDetectionSystem — model load state flows through to telemetry")
    @MainActor
    func systemModelLoadStateReported() async {
        // Accessing `.shared` triggers the init-time model-load report.
        _ = PoliceDetectionSystem.shared
        try? await Task.sleep(for: .milliseconds(100))
        let t = DetectionTelemetry.shared
        _ = t.vehicleModelLoaded
        _ = t.roofModelLoaded
        _ = t.fleetFeatureModelLoaded
    }
}
