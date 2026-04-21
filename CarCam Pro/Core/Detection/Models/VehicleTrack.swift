import Foundation
import CoreGraphics

/// Sample of the averaged color channels over a vehicle's upper-body region.
/// The emergency-light detector accumulates these into a ring buffer and
/// runs FFT on them to find 1–10 Hz modulation.
struct ColorSample: Hashable, Sendable {
    let timestamp: TimeInterval
    let redMean: Float
    let blueMean: Float
    let whiteMean: Float
}

/// Fixed-size ring buffer. Pushing past capacity overwrites the oldest entry.
struct RingBuffer<Element> {
    private var storage: [Element] = []
    let capacity: Int
    private var head: Int = 0

    init(capacity: Int) {
        self.capacity = capacity
        self.storage.reserveCapacity(capacity)
    }

    mutating func push(_ element: Element) {
        if storage.count < capacity {
            storage.append(element)
        } else {
            storage[head] = element
            head = (head + 1) % capacity
        }
    }

    var values: [Element] { storage }
    var count: Int { storage.count }
}

extension RingBuffer where Element == Float {
    func mean() -> Float {
        guard !storage.isEmpty else { return 0 }
        return storage.reduce(0, +) / Float(storage.count)
    }

    /// Mean of the top-K values — used for emergency-light scoring so one
    /// bright flash pulls the average up instead of being drowned out by the
    /// many "dark" frames between pulses.
    func meanTopK(_ k: Int) -> Float {
        guard !storage.isEmpty else { return 0 }
        let top = storage.sorted(by: >).prefix(min(k, storage.count))
        return top.reduce(0, +) / Float(top.count)
    }
}

/// Tracks a single vehicle across frames using simple IoU matching.
/// Maintains a rolling history of per-signal scores for temporal smoothing.
///
/// Intentionally a reference type so `VehicleTracker` and `DetectionFusion`
/// share the same underlying buffers between frames.
final class VehicleTrack {
    let id: UUID
    private(set) var lastSeen: TimeInterval
    private(set) var firstSeen: TimeInterval
    private(set) var lastBBox: CGRect
    private(set) var lastDetection: VehicleDetection

    // Rolling window of per-signal scores. Capacity ~30 frames (~2 s at 15 fps).
    private var emergencyScores: RingBuffer<Float>
    private var lightBarScores: RingBuffer<Float>
    private var roofRailsScores: RingBuffer<Float>
    private var fleetFeatureScores: RingBuffer<Float>

    private(set) var colorSamples: RingBuffer<ColorSample>
    private(set) var sustainedFrames: Int = 0

    init(detection: VehicleDetection) {
        self.id = detection.id
        self.firstSeen = detection.timestamp
        self.lastSeen = detection.timestamp
        self.lastBBox = detection.boundingBox
        self.lastDetection = detection
        self.emergencyScores = RingBuffer(capacity: 30)
        self.lightBarScores = RingBuffer(capacity: 30)
        self.roofRailsScores = RingBuffer(capacity: 30)
        self.fleetFeatureScores = RingBuffer(capacity: 30)
        self.colorSamples = RingBuffer(capacity: 60) // 4 s at 15 fps for FFT
    }

    func update(detection: VehicleDetection) {
        self.lastDetection = detection
        self.lastBBox = detection.boundingBox
        self.lastSeen = detection.timestamp
    }

    func recordEmergencyScore(_ score: Float)    { emergencyScores.push(score) }
    func recordLightBarScore(_ score: Float)     { lightBarScores.push(score) }
    func recordRoofRailsScore(_ score: Float)    { roofRailsScores.push(score) }
    func recordFleetFeatureScore(_ score: Float) { fleetFeatureScores.push(score) }
    func recordColorSample(_ sample: ColorSample) { colorSamples.push(sample) }

    func smoothedEmergencyScore() -> Float     { emergencyScores.meanTopK(5) }
    func smoothedLightBarScore()  -> Float     { lightBarScores.mean() }
    func smoothedRoofRailsScore() -> Float     { roofRailsScores.mean() }
    func smoothedFleetFeatureScore() -> Float  { fleetFeatureScores.mean() }

    func incrementSustainedIfThreshold(_ threshold: Float, currentFused: Float) {
        if currentFused >= threshold {
            sustainedFrames += 1
        } else {
            sustainedFrames = max(0, sustainedFrames - 1)
        }
    }
}
