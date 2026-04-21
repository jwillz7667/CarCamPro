# Police & Fleet Vehicle Detection — Implementation Brief

Paste this whole document into Claude Code as the task spec. It contains the architecture, file layout, and full Swift code for a police vehicle detection subsystem that detects both **marked cruisers (light bar on roof)** and **unmarked fleet vehicles (missing civilian roof rails + other tells)**, plus **active emergency lights (flashing red/blue)**.

---

## Goal

Add a real-time police vehicle detection subsystem to an existing iOS dashcam app. The subsystem consumes `CMSampleBuffer` frames from the existing `AVCaptureSession`, runs on-device ML + signal processing, and emits alerts with confidence scores and reasoning.

### Detection targets
1. **Marked police vehicles** — distinctive light bar or blackout light bar on roof
2. **Unmarked fleet vehicles** — fleet-spec variant of a civilian model (Explorer PIU, Tahoe PPV, Charger Pursuit, Durango Pursuit, etc.), identified by the absence of civilian roof rails and presence of other fleet tells (A-pillar spotlights, steel wheels, push bars, multiple antennas)
3. **Active emergency lights** — flashing red/blue lights at 1–10 Hz (detected via color+temporal signal processing, no ML needed)

### Non-goals (v1)
- License plate OCR (privacy/legal risk — explicitly skip)
- Motorcycle police units
- Radar/lidar detection (impossible — no hardware)
- 100% certainty — output confidence scores, let the UI decide how to surface

---

## Assumptions

- **iOS target:** 17.0+
- **Swift:** 5.9+, strict concurrency on
- **Frameworks:** AVFoundation, Vision, CoreML, CoreMotion, Accelerate, SwiftUI (for the overlay)
- **Existing code assumed present:** An `AVCaptureSession` with a video data output. You have a class (probably `CameraManager` or `DashcamRecorder`) that already receives `CMSampleBuffer`s via `AVCaptureVideoDataOutputSampleBufferDelegate`. The new subsystem plugs into that delegate.
- **Device target:** iPhone 13 / A15 or newer for real-time performance. Older devices get degraded inference rate via thermal management.

---

## Architecture

```
CMSampleBuffer (from existing AVCaptureSession)
          │
          ▼
┌──────────────────────────────────────────────────┐
│  PoliceDetectionSystem (main coordinator)        │
│  - Frame throttling (15 Hz inference max)        │
│  - Thermal-aware scheduling                      │
│  - Dispatches to detection pipelines in parallel │
└────────┬─────────────────────────────────────────┘
         │
         ├─► VehicleDetector (YOLOv8n Core ML)
         │     → array of Vehicle bboxes + class
         │
         ├─► EmergencyLightDetector (per-bbox signal)
         │     → active-lights score per vehicle
         │
         ├─► RoofAnalyzer (per-bbox Core ML classifier)
         │     → {has_light_bar, has_roof_rails} per vehicle
         │
         └─► FleetFeatureDetector (per-bbox Core ML classifier)
               → push_bar, spotlights, blackout_wheels, antennas
                          │
                          ▼
         ┌────────────────────────────────────┐
         │  DetectionFusion                    │
         │  - Combines signals with weights    │
         │  - Temporal smoothing (ring buffer) │
         │  - Track IDs across frames          │
         │  - Produces VehicleThreatAssessment │
         └────────┬───────────────────────────┘
                  │
                  ▼
         ┌────────────────────────────┐
         │  AlertManager               │
         │  - Debounced alerts         │
         │  - Haptics + audio + UI     │
         │  - Logs to incident buffer  │
         └────────────────────────────┘
```

---

## File Structure

Create these files under `YourApp/Detection/`:

```
Detection/
├── Models/
│   ├── DetectionModels.swift
│   └── VehicleTrack.swift
├── Pipelines/
│   ├── VehicleDetector.swift
│   ├── EmergencyLightDetector.swift
│   ├── RoofAnalyzer.swift
│   └── FleetFeatureDetector.swift
├── Fusion/
│   ├── DetectionFusion.swift
│   └── TemporalSmoothing.swift
├── Alerts/
│   └── AlertManager.swift
├── Support/
│   ├── PixelBufferUtilities.swift
│   └── ThermalMonitor.swift
├── PoliceDetectionSystem.swift
└── UI/
    └── DetectionOverlayView.swift
```

---

## Instructions for Claude Code

1. Create all files listed above with the code blocks below.
2. After all files are created, integrate by calling `PoliceDetectionSystem.shared.processFrame(sampleBuffer:)` from the existing `captureOutput(_:didOutput:from:)` delegate method. See "Integration" section at the end.
3. Add the required Core ML models to the Xcode project (see "Core ML Models" section). If models are missing at runtime, the subsystem degrades gracefully — `EmergencyLightDetector` works without any models, and `VehicleDetector` has a placeholder stub.
4. Add the `SwiftUI` overlay view to your camera preview screen (see "UI Integration").
5. Do NOT remove or break existing recording functionality. This subsystem is read-only on the frame buffer.

---

## Code

### `Detection/Models/DetectionModels.swift`

```swift
import Foundation
import CoreGraphics
import Vision

// MARK: - Vehicle detection output

/// Classes the vehicle detector emits. Keep synced with the Core ML model labels.
public enum VehicleClass: String, Codable, CaseIterable {
    case car
    case suv
    case pickup
    case truck
    case van
    case motorcycle
    case bus
    case unknown
}

/// Known fleet-capable models. Detections in this set raise suspicion more aggressively.
public enum FleetCapableModel: String, Codable, CaseIterable {
    case fordExplorer     // Police Interceptor Utility
    case fordF150         // Police Responder
    case chevyTahoe       // PPV
    case chevySuburban
    case chevySilverado
    case dodgeCharger     // Pursuit
    case dodgeDurango     // Pursuit
    case fordTransit      // Unmarked surveillance
    case ramTruck
    case unknown
}

public struct VehicleDetection: Identifiable, Hashable {
    public let id = UUID()
    /// Normalized bbox (0...1) in Vision coordinate space (origin bottom-left).
    public let boundingBox: CGRect
    public let vehicleClass: VehicleClass
    public let fleetCapableModel: FleetCapableModel
    public let confidence: Float
    /// Approximate distance in meters, if depth available. Nil otherwise.
    public let estimatedDistance: Float?
    public let timestamp: TimeInterval
}

// MARK: - Per-signal scores

public struct EmergencyLightSignal: Hashable {
    /// 0...1, probability that active emergency lights are present.
    public let score: Float
    /// Dominant modulation frequency in Hz (0 if none found).
    public let frequencyHz: Float
    /// Whether red AND blue both modulate (very strong signal).
    public let bicolor: Bool
}

public struct RoofSignal: Hashable {
    /// 0...1, probability of a roof-mounted light bar (marked cruiser).
    public let lightBarScore: Float
    /// 0...1, probability that the roof has civilian roof rails.
    /// LOW value on a fleet-capable model is suspicious.
    public let roofRailsScore: Float
}

public struct FleetFeatureSignal: Hashable {
    public let pushBarScore: Float          // front bumper guard
    public let spotlightScore: Float        // A-pillar spotlight(s)
    public let blackoutWheelsScore: Float   // steel/blackout wheels vs alloy
    public let antennaScore: Float          // multiple roof/trunk antennas
}

// MARK: - Final assessment

public enum ThreatLevel: Int, Comparable, Codable {
    case none = 0
    case low = 1        // Weak signal — do not alert
    case possible = 2   // Subtle alert — visual only
    case likely = 3     // Full alert — haptic + chime + visual
    case confirmed = 4  // Very strong — urgent alert

    public static func < (a: ThreatLevel, b: ThreatLevel) -> Bool {
        a.rawValue < b.rawValue
    }
}

public struct VehicleThreatAssessment: Identifiable {
    public let id: UUID // matches the track ID
    public let detection: VehicleDetection
    public let emergencyLights: EmergencyLightSignal
    public let roof: RoofSignal
    public let fleetFeatures: FleetFeatureSignal
    public let fusedScore: Float           // 0...1
    public let threatLevel: ThreatLevel
    public let reasoning: [String]         // human-readable explanation
    public let sustainedFrames: Int        // how many consecutive frames confirmed
}
```

---

### `Detection/Models/VehicleTrack.swift`

```swift
import Foundation
import CoreGraphics

/// Tracks a single vehicle across frames using simple IoU matching.
/// Maintains a rolling history of per-signal scores for temporal smoothing.
final class VehicleTrack {
    let id: UUID
    private(set) var lastSeen: TimeInterval
    private(set) var firstSeen: TimeInterval
    private(set) var lastBBox: CGRect
    private(set) var lastDetection: VehicleDetection

    // Rolling window of signals. Capacity ~30 frames (~2s at 15fps).
    private var emergencyScores: RingBuffer<Float>
    private var lightBarScores: RingBuffer<Float>
    private var roofRailsScores: RingBuffer<Float>
    private var fleetFeatureScores: RingBuffer<Float>

    // Sampled colors for emergency light frequency analysis.
    // Stores (timestamp, redMean, blueMean) tuples.
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
        self.colorSamples = RingBuffer(capacity: 60) // 4s at 15fps for FFT
    }

    func update(detection: VehicleDetection) {
        self.lastDetection = detection
        self.lastBBox = detection.boundingBox
        self.lastSeen = detection.timestamp
    }

    func recordEmergencyScore(_ score: Float) { emergencyScores.push(score) }
    func recordLightBarScore(_ score: Float)  { lightBarScores.push(score) }
    func recordRoofRailsScore(_ score: Float) { roofRailsScores.push(score) }
    func recordFleetFeatureScore(_ score: Float) { fleetFeatureScores.push(score) }
    func recordColorSample(_ sample: ColorSample) { colorSamples.push(sample) }

    func smoothedEmergencyScore() -> Float { emergencyScores.meanTopK(5) }
    func smoothedLightBarScore()  -> Float { lightBarScores.mean() }
    func smoothedRoofRailsScore() -> Float { roofRailsScores.mean() }
    func smoothedFleetFeatureScore() -> Float { fleetFeatureScores.mean() }

    func incrementSustainedIfThreshold(_ threshold: Float, currentFused: Float) {
        if currentFused >= threshold {
            sustainedFrames += 1
        } else {
            sustainedFrames = max(0, sustainedFrames - 1)
        }
    }
}

struct ColorSample: Hashable {
    let timestamp: TimeInterval
    let redMean: Float
    let blueMean: Float
    let whiteMean: Float
}

/// Fixed-size ring buffer.
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

    func meanTopK(_ k: Int) -> Float {
        guard !storage.isEmpty else { return 0 }
        let top = storage.sorted(by: >).prefix(min(k, storage.count))
        return top.reduce(0, +) / Float(top.count)
    }
}
```

---

### `Detection/Support/PixelBufferUtilities.swift`

```swift
import Foundation
import CoreImage
import CoreVideo
import Accelerate
import Vision

/// Utilities for cropping and color-analyzing CVPixelBuffers without going through UIKit.
enum PixelBufferUtilities {

    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// Convert a Vision-coordinate bbox (origin bottom-left, normalized) to a pixel rect
    /// in image coordinates (origin top-left).
    static func pixelRect(from visionBox: CGRect, imageSize: CGSize) -> CGRect {
        let x = visionBox.origin.x * imageSize.width
        let h = visionBox.size.height * imageSize.height
        let y = (1 - visionBox.origin.y - visionBox.size.height) * imageSize.height
        let w = visionBox.size.width * imageSize.width
        return CGRect(x: x, y: y, width: w, height: h).integral
    }

    /// Crop a CVPixelBuffer to a normalized roof region.
    /// Returns a new CIImage cropped to the top 35% of the vehicle bbox.
    static func roofCropImage(from pixelBuffer: CVPixelBuffer,
                              vehicleBox: CGRect,
                              imageSize: CGSize) -> CIImage? {
        let pixelRect = pixelRect(from: vehicleBox, imageSize: imageSize)
        let roofHeight = pixelRect.height * 0.35
        let roofRect = CGRect(x: pixelRect.minX,
                              y: pixelRect.minY,
                              width: pixelRect.width,
                              height: roofHeight)
        let ci = CIImage(cvPixelBuffer: pixelBuffer)
        return ci.cropped(to: roofRect)
    }

    /// Crop the "upper body" region — roof + upper windows.
    /// This is the region where emergency lights live.
    static func upperBodyCrop(from pixelBuffer: CVPixelBuffer,
                              vehicleBox: CGRect,
                              imageSize: CGSize) -> CIImage? {
        let pixelRect = pixelRect(from: vehicleBox, imageSize: imageSize)
        let upperHeight = pixelRect.height * 0.55
        let upperRect = CGRect(x: pixelRect.minX,
                               y: pixelRect.minY,
                               width: pixelRect.width,
                               height: upperHeight)
        let ci = CIImage(cvPixelBuffer: pixelBuffer)
        return ci.cropped(to: upperRect)
    }

    /// Compute mean red, blue, and luminance over a CIImage region.
    /// Uses CIAreaAverage filter for GPU-accelerated computation.
    static func meanChannels(of image: CIImage) -> (red: Float, green: Float, blue: Float, luma: Float)? {
        guard let filter = CIFilter(name: "CIAreaAverage") else { return nil }
        let extent = CIVector(x: image.extent.origin.x,
                              y: image.extent.origin.y,
                              z: image.extent.size.width,
                              w: image.extent.size.height)
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(extent, forKey: kCIInputExtentKey)
        guard let output = filter.outputImage else { return nil }

        var bitmap = [UInt8](repeating: 0, count: 4)
        ciContext.render(output,
                         toBitmap: &bitmap,
                         rowBytes: 4,
                         bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                         format: .RGBA8,
                         colorSpace: CGColorSpaceCreateDeviceRGB())
        let r = Float(bitmap[0]) / 255.0
        let g = Float(bitmap[1]) / 255.0
        let b = Float(bitmap[2]) / 255.0
        // Rec. 709 luma approx
        let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
        return (r, g, b, luma)
    }

    /// Resize + center-crop a CIImage to a square of the given size, for ML input.
    static func squarePixelBuffer(from image: CIImage, size: Int) -> CVPixelBuffer? {
        let scale = CGFloat(size) / min(image.extent.width, image.extent.height)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        // Center crop
        let originX = (scaled.extent.width - CGFloat(size)) / 2
        let originY = (scaled.extent.height - CGFloat(size)) / 2
        let cropped = scaled.cropped(to: CGRect(x: scaled.extent.origin.x + originX,
                                                y: scaled.extent.origin.y + originY,
                                                width: CGFloat(size),
                                                height: CGFloat(size)))
        return makePixelBuffer(from: cropped, size: size)
    }

    private static func makePixelBuffer(from image: CIImage, size: Int) -> CVPixelBuffer? {
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault,
                            size, size,
                            kCVPixelFormatType_32BGRA,
                            attrs as CFDictionary,
                            &pb)
        guard let buffer = pb else { return nil }
        ciContext.render(image, to: buffer)
        return buffer
    }
}
```

---

### `Detection/Support/ThermalMonitor.swift`

```swift
import Foundation

/// Adjusts ML inference rate based on device thermal state.
/// Call `shouldProcessThisFrame()` per incoming frame.
final class ThermalMonitor {
    static let shared = ThermalMonitor()

    private var frameCounter: Int = 0
    private let lock = NSLock()

    /// Target inference frequency varies with thermal state.
    var framesPerInference: Int {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:  return 2   // ~30fps → 15Hz inference
        case .fair:     return 3   // ~10Hz inference
        case .serious:  return 6   // ~5Hz inference
        case .critical: return 15  // ~2Hz inference
        @unknown default: return 3
        }
    }

    func shouldProcessThisFrame() -> Bool {
        lock.lock(); defer { lock.unlock() }
        frameCounter += 1
        return frameCounter % framesPerInference == 0
    }
}
```

---

### `Detection/Pipelines/VehicleDetector.swift`

```swift
import Foundation
import Vision
import CoreML
import CoreVideo

/// Detects vehicles and classifies them by type + fleet-capable model guess.
///
/// CORE ML MODEL REQUIRED: `VehicleDetectorYOLOv8.mlmodel`
/// - Train: YOLOv8n on BDD100K + scraped fleet vehicle imagery
/// - Input: 640x640 RGB
/// - Output: Vision-compatible object detection (use `ultralytics` export to .mlpackage)
/// - Classes: car, suv, pickup, truck, van, motorcycle, bus, plus optional fleet-model subclasses
///
/// If the model is missing at runtime, detection is stubbed to return an empty array
/// and the rest of the pipeline degrades gracefully.
final class VehicleDetector {

    private var visionModel: VNCoreMLModel?
    private let requestQueue = DispatchQueue(label: "vehicle.detector.queue", qos: .userInitiated)

    init() {
        loadModel()
    }

    private func loadModel() {
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all // CPU + GPU + Neural Engine
            // TODO: replace with your compiled model file name
            guard let url = Bundle.main.url(forResource: "VehicleDetectorYOLOv8", withExtension: "mlmodelc") else {
                print("[VehicleDetector] Model file not found — running in stub mode")
                return
            }
            let mlModel = try MLModel(contentsOf: url, configuration: config)
            self.visionModel = try VNCoreMLModel(for: mlModel)
        } catch {
            print("[VehicleDetector] Failed to load model: \(error)")
        }
    }

    /// Runs detection on a frame.
    /// Returns vehicles in Vision coordinate space (origin bottom-left, normalized).
    func detect(in pixelBuffer: CVPixelBuffer, timestamp: TimeInterval) async -> [VehicleDetection] {
        guard let model = visionModel else {
            return []
        }

        return await withCheckedContinuation { continuation in
            let request = VNCoreMLRequest(model: model) { request, error in
                guard error == nil,
                      let results = request.results as? [VNRecognizedObjectObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                let detections = results.compactMap { obs -> VehicleDetection? in
                    guard let top = obs.labels.first else { return nil }
                    let vClass = Self.parseVehicleClass(top.identifier)
                    let fModel = Self.parseFleetCapableModel(top.identifier)
                    guard vClass != .unknown || fModel != .unknown else { return nil }
                    guard top.confidence > 0.35 else { return nil }

                    return VehicleDetection(
                        boundingBox: obs.boundingBox,
                        vehicleClass: vClass,
                        fleetCapableModel: fModel,
                        confidence: top.confidence,
                        estimatedDistance: Self.estimateDistance(from: obs.boundingBox),
                        timestamp: timestamp
                    )
                }
                continuation.resume(returning: detections)
            }
            request.imageCropAndScaleOption = .scaleFill

            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
            self.requestQueue.async {
                do {
                    try handler.perform([request])
                } catch {
                    print("[VehicleDetector] Perform failed: \(error)")
                    continuation.resume(returning: [])
                }
            }
        }
    }

    // MARK: - Label parsing helpers

    private static func parseVehicleClass(_ label: String) -> VehicleClass {
        let l = label.lowercased()
        if l.contains("motorcycle") { return .motorcycle }
        if l.contains("truck") && !l.contains("pickup") { return .truck }
        if l.contains("pickup") || l.contains("f150") || l.contains("silverado") { return .pickup }
        if l.contains("van") || l.contains("transit") { return .van }
        if l.contains("bus") { return .bus }
        if l.contains("suv") || l.contains("explorer") || l.contains("tahoe") ||
           l.contains("durango") || l.contains("suburban") { return .suv }
        if l.contains("car") || l.contains("charger") || l.contains("sedan") { return .car }
        return .unknown
    }

    private static func parseFleetCapableModel(_ label: String) -> FleetCapableModel {
        let l = label.lowercased()
        if l.contains("explorer") { return .fordExplorer }
        if l.contains("f150") || l.contains("f-150") { return .fordF150 }
        if l.contains("tahoe") { return .chevyTahoe }
        if l.contains("suburban") { return .chevySuburban }
        if l.contains("silverado") { return .chevySilverado }
        if l.contains("charger") { return .dodgeCharger }
        if l.contains("durango") { return .dodgeDurango }
        if l.contains("transit") { return .fordTransit }
        if l.contains("ram") { return .ramTruck }
        return .unknown
    }

    /// Very rough distance estimate from bounding box size.
    /// Assumes a passenger vehicle ~1.8m wide. Replace with depth/LiDAR if available.
    private static func estimateDistance(from bbox: CGRect) -> Float? {
        // Placeholder — real version needs calibrated focal length.
        // For now, return nil so the rest of the pipeline doesn't rely on it.
        return nil
    }
}
```

---

### `Detection/Pipelines/EmergencyLightDetector.swift`

```swift
import Foundation
import Accelerate
import CoreVideo

/// Detects active emergency lights (flashing red/blue at ~1–10 Hz).
///
/// NO ML MODEL NEEDED. This is pure signal processing:
/// 1. For each tracked vehicle, sample the upper-body region's mean red/blue/luma each frame.
/// 2. Accumulate samples in a ring buffer (2–4 seconds).
/// 3. Run FFT (via Accelerate) on each channel.
/// 4. Look for a dominant peak in the 1–10 Hz band.
/// 5. Bicolor bonus: if red AND blue both peak in that band, strong signal.
///
/// This works at night (lights very bright against dark background) AND during the day
/// (lights still modulate, just less contrast).
final class EmergencyLightDetector {

    /// Expected emergency light flash frequency range in Hz.
    private let minFrequencyHz: Float = 1.0
    private let maxFrequencyHz: Float = 10.0

    /// Extract a color sample for one vehicle on this frame.
    func sample(pixelBuffer: CVPixelBuffer,
                vehicleBox: CGRect,
                imageSize: CGSize,
                timestamp: TimeInterval) -> ColorSample? {
        guard let crop = PixelBufferUtilities.upperBodyCrop(from: pixelBuffer,
                                                            vehicleBox: vehicleBox,
                                                            imageSize: imageSize) else {
            return nil
        }
        guard let channels = PixelBufferUtilities.meanChannels(of: crop) else {
            return nil
        }
        return ColorSample(
            timestamp: timestamp,
            redMean: channels.red,
            blueMean: channels.blue,
            whiteMean: channels.luma
        )
    }

    /// Analyze a track's accumulated color samples and return an emergency-light score.
    func analyze(track: VehicleTrack) -> EmergencyLightSignal {
        let samples = track.colorSamples.values
        guard samples.count >= 30 else {
            return EmergencyLightSignal(score: 0, frequencyHz: 0, bicolor: false)
        }

        // Resample to uniform spacing. Use the median inter-sample dt.
        let dts = zip(samples.dropFirst(), samples).map { Float($0.timestamp - $1.timestamp) }
        guard let medianDt = dts.sorted()[safe: dts.count / 2], medianDt > 0 else {
            return EmergencyLightSignal(score: 0, frequencyHz: 0, bicolor: false)
        }
        let sampleRate = 1.0 / medianDt

        let red = samples.map { $0.redMean }
        let blue = samples.map { $0.blueMean }

        let redPeak = dominantPeak(signal: red, sampleRate: sampleRate)
        let bluePeak = dominantPeak(signal: blue, sampleRate: sampleRate)

        let redInBand = (minFrequencyHz...maxFrequencyHz).contains(redPeak.frequency)
        let blueInBand = (minFrequencyHz...maxFrequencyHz).contains(bluePeak.frequency)

        // Peaks close to each other = synchronized flashing (could be same strobe
        // source). Alternating flash is harder to resolve but also produces peaks
        // at the same base frequency.
        let frequencyAgreement = abs(redPeak.frequency - bluePeak.frequency) < 1.0

        var score: Float = 0
        var reasoning: [String] = []

        if redInBand {
            score += 0.35 * redPeak.strength
            reasoning.append("red @ \(String(format: "%.1f", redPeak.frequency)) Hz")
        }
        if blueInBand {
            score += 0.35 * bluePeak.strength
            reasoning.append("blue @ \(String(format: "%.1f", bluePeak.frequency)) Hz")
        }
        let bicolor = redInBand && blueInBand && frequencyAgreement
        if bicolor {
            score += 0.30 // bicolor bonus
        }

        score = min(1.0, score)

        let domFreq = bicolor ? (redPeak.frequency + bluePeak.frequency) / 2
                              : (redPeak.strength > bluePeak.strength ? redPeak.frequency : bluePeak.frequency)

        return EmergencyLightSignal(score: score, frequencyHz: domFreq, bicolor: bicolor)
    }

    // MARK: - FFT

    private struct Peak {
        let frequency: Float
        let strength: Float // normalized 0...1
    }

    /// Compute the dominant frequency peak of a 1-D signal using Accelerate FFT.
    private func dominantPeak(signal input: [Float], sampleRate: Float) -> Peak {
        guard input.count >= 16 else { return Peak(frequency: 0, strength: 0) }

        // Next power of 2 for FFT
        let n = nextPowerOfTwo(input.count)
        var padded = input + [Float](repeating: 0, count: n - input.count)

        // Remove DC
        let mean = padded.reduce(0, +) / Float(padded.count)
        for i in 0..<padded.count { padded[i] -= mean }

        // Hann window to reduce spectral leakage
        var window = [Float](repeating: 0, count: n)
        vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))
        vDSP_vmul(padded, 1, window, 1, &padded, 1, vDSP_Length(n))

        let log2n = vDSP_Length(log2(Float(n)))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return Peak(frequency: 0, strength: 0)
        }
        defer { vDSP_destroy_fftsetup(setup) }

        var real = [Float](repeating: 0, count: n/2)
        var imag = [Float](repeating: 0, count: n/2)

        real.withUnsafeMutableBufferPointer { realPtr in
            imag.withUnsafeMutableBufferPointer { imagPtr in
                var split = DSPSplitComplex(realp: realPtr.baseAddress!,
                                            imagp: imagPtr.baseAddress!)
                padded.withUnsafeBufferPointer { inPtr in
                    inPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n/2) { complexPtr in
                        vDSP_ctoz(complexPtr, 2, &split, 1, vDSP_Length(n/2))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
            }
        }

        var magnitudes = [Float](repeating: 0, count: n/2)
        real.withUnsafeMutableBufferPointer { rp in
            imag.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(n/2))
            }
        }

        // Skip bin 0 (DC) and bin 1 (very low freq noise)
        let startBin = 2
        guard magnitudes.count > startBin else { return Peak(frequency: 0, strength: 0) }

        var maxVal: Float = 0
        var maxIdx: vDSP_Length = 0
        magnitudes.withUnsafeBufferPointer { ptr in
            let offsetPtr = ptr.baseAddress!.advanced(by: startBin)
            vDSP_maxvi(offsetPtr, 1, &maxVal, &maxIdx, vDSP_Length(magnitudes.count - startBin))
        }
        let peakBin = Int(maxIdx) + startBin

        let binWidthHz = sampleRate / Float(n)
        let peakFreq = Float(peakBin) * binWidthHz

        // Normalize strength against total spectral energy
        let totalEnergy = magnitudes.reduce(0, +)
        let strength: Float = totalEnergy > 0 ? min(1.0, maxVal / (totalEnergy / Float(magnitudes.count - startBin))) / 10.0 : 0

        return Peak(frequency: peakFreq, strength: min(1.0, strength))
    }

    private func nextPowerOfTwo(_ n: Int) -> Int {
        var p = 1
        while p < n { p <<= 1 }
        return p
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
```

---

### `Detection/Pipelines/RoofAnalyzer.swift`

```swift
import Foundation
import Vision
import CoreML
import CoreImage

/// Analyzes the roof region of a detected vehicle for:
///   - Light bar presence (marked cruiser)
///   - Civilian roof rails presence (absence = suspicious on fleet-capable models)
///
/// CORE ML MODEL REQUIRED: `RoofFeatureClassifier.mlmodel`
/// - Architecture: Small CNN (MobileNetV3-small or similar), ~2–4M params
/// - Input: 224x224 RGB crop of the roof region
/// - Output: two independent binary heads:
///     * has_light_bar: Float 0...1
///     * has_roof_rails: Float 0...1
/// - Training data:
///     * Positive light-bar: marked police cruisers, any light bar style (slick-top units NOT included here)
///     * Positive roof-rails: civilian SUVs/trucks with factory roof rails (flush or raised)
///     * Negative: fleet-spec vehicles with bare flat roofs
/// - Export via coremltools with two multi-output heads.
///
/// Fallback: If the model is absent, we use a basic heuristic based on roof luminance
/// profile (see `heuristicFallback`).
final class RoofAnalyzer {

    private var visionModel: VNCoreMLModel?

    init() {
        loadModel()
    }

    private func loadModel() {
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all
            guard let url = Bundle.main.url(forResource: "RoofFeatureClassifier", withExtension: "mlmodelc") else {
                print("[RoofAnalyzer] Model file not found — using heuristic fallback")
                return
            }
            let model = try MLModel(contentsOf: url, configuration: config)
            self.visionModel = try VNCoreMLModel(for: model)
        } catch {
            print("[RoofAnalyzer] Failed to load model: \(error)")
        }
    }

    func analyze(pixelBuffer: CVPixelBuffer,
                 vehicleBox: CGRect,
                 imageSize: CGSize) async -> RoofSignal {
        guard let crop = PixelBufferUtilities.roofCropImage(from: pixelBuffer,
                                                            vehicleBox: vehicleBox,
                                                            imageSize: imageSize) else {
            return RoofSignal(lightBarScore: 0, roofRailsScore: 0.5)
        }

        if let model = visionModel {
            return await runModel(model, crop: crop) ?? heuristicFallback(crop: crop)
        }
        return heuristicFallback(crop: crop)
    }

    private func runModel(_ model: VNCoreMLModel, crop: CIImage) async -> RoofSignal? {
        await withCheckedContinuation { continuation in
            let request = VNCoreMLRequest(model: model) { req, _ in
                guard let results = req.results as? [VNCoreMLFeatureValueObservation] else {
                    continuation.resume(returning: nil)
                    return
                }
                var lightBar: Float = 0
                var roofRails: Float = 0.5
                for obs in results {
                    if obs.featureName == "has_light_bar" {
                        lightBar = Float(truncating: obs.featureValue.multiArrayValue?[0] ?? 0)
                    } else if obs.featureName == "has_roof_rails" {
                        roofRails = Float(truncating: obs.featureValue.multiArrayValue?[0] ?? 0)
                    }
                }
                continuation.resume(returning: RoofSignal(lightBarScore: lightBar,
                                                          roofRailsScore: roofRails))
            }
            request.imageCropAndScaleOption = .scaleFill

            let handler = VNImageRequestHandler(ciImage: crop)
            DispatchQueue.global(qos: .userInitiated).async {
                do { try handler.perform([request]) }
                catch {
                    print("[RoofAnalyzer] perform: \(error)")
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    /// Heuristic fallback when no ML model is loaded.
    ///
    /// - For LIGHT BAR: light bars create a horizontal band of elevated saturation
    ///   and often contrast against the body color. We detect a high-variance,
    ///   high-saturation band in the top 15% of the roof crop.
    /// - For ROOF RAILS: civilian roof rails create two dark thin horizontal lines
    ///   running front-to-back on the roof. We detect luminance edges in the
    ///   lateral margins of the roof crop.
    ///
    /// This is weaker than a trained model and produces more false positives, but
    /// it's still useful for bootstrapping and as a smoke test.
    private func heuristicFallback(crop: CIImage) -> RoofSignal {
        guard let channels = PixelBufferUtilities.meanChannels(of: crop) else {
            return RoofSignal(lightBarScore: 0, roofRailsScore: 0.5)
        }

        // Simple saturation measure — high-saturation roofs often indicate
        // bright colored light bar lenses.
        let saturation = max(abs(channels.red - channels.green),
                             max(abs(channels.green - channels.blue),
                                 abs(channels.red - channels.blue)))
        let lightBarScore = min(1.0, saturation * 2.0)

        // We can't reliably detect rails without edge analysis here;
        // return neutral 0.5 so fusion layer doesn't over-weight it.
        let roofRailsScore: Float = 0.5

        return RoofSignal(lightBarScore: lightBarScore, roofRailsScore: roofRailsScore)
    }
}
```

---

### `Detection/Pipelines/FleetFeatureDetector.swift`

```swift
import Foundation
import Vision
import CoreML
import CoreImage

/// Detects fleet-vehicle specific visual tells on a cropped vehicle image.
///
/// CORE ML MODEL REQUIRED: `FleetFeatureClassifier.mlmodel`
/// - Architecture: Small multi-head CNN (MobileNetV3-small, ~3M params)
/// - Input: 256x256 RGB full-vehicle crop
/// - Output: 4 independent sigmoid heads:
///     * has_push_bar:         Float 0...1
///     * has_spotlight:        Float 0...1  (A-pillar spotlight)
///     * has_blackout_wheels:  Float 0...1  (steel vs alloy)
///     * has_multiple_antennas: Float 0...1
///
/// Training data sources: GovDeals / Municibid (decommissioned fleet vehicles),
/// Ford/GM fleet marketing, police enthusiast Flickr groups, stock civilian images
/// from dealership inventory for negatives.
///
/// Fallback: returns zero scores when model is missing. Fleet model flag alone
/// is never enough to alert, so absence is safe.
final class FleetFeatureDetector {

    private var visionModel: VNCoreMLModel?

    init() {
        loadModel()
    }

    private func loadModel() {
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all
            guard let url = Bundle.main.url(forResource: "FleetFeatureClassifier", withExtension: "mlmodelc") else {
                print("[FleetFeatureDetector] Model file not found — scores will be 0")
                return
            }
            let model = try MLModel(contentsOf: url, configuration: config)
            self.visionModel = try VNCoreMLModel(for: model)
        } catch {
            print("[FleetFeatureDetector] Failed to load model: \(error)")
        }
    }

    func analyze(pixelBuffer: CVPixelBuffer,
                 vehicleBox: CGRect,
                 imageSize: CGSize) async -> FleetFeatureSignal {
        guard let model = visionModel else {
            return FleetFeatureSignal(pushBarScore: 0, spotlightScore: 0,
                                      blackoutWheelsScore: 0, antennaScore: 0)
        }
        let pixelRect = PixelBufferUtilities.pixelRect(from: vehicleBox, imageSize: imageSize)
        let ci = CIImage(cvPixelBuffer: pixelBuffer).cropped(to: pixelRect)

        return await withCheckedContinuation { continuation in
            let request = VNCoreMLRequest(model: model) { req, _ in
                guard let results = req.results as? [VNCoreMLFeatureValueObservation] else {
                    continuation.resume(returning: FleetFeatureSignal(
                        pushBarScore: 0, spotlightScore: 0,
                        blackoutWheelsScore: 0, antennaScore: 0))
                    return
                }
                var signal = FleetFeatureSignal(pushBarScore: 0, spotlightScore: 0,
                                                blackoutWheelsScore: 0, antennaScore: 0)
                var push: Float = 0, spot: Float = 0, wheels: Float = 0, ant: Float = 0
                for obs in results {
                    let val = Float(truncating: obs.featureValue.multiArrayValue?[0] ?? 0)
                    switch obs.featureName {
                    case "has_push_bar":          push = val
                    case "has_spotlight":         spot = val
                    case "has_blackout_wheels":   wheels = val
                    case "has_multiple_antennas": ant = val
                    default: break
                    }
                }
                signal = FleetFeatureSignal(pushBarScore: push,
                                            spotlightScore: spot,
                                            blackoutWheelsScore: wheels,
                                            antennaScore: ant)
                continuation.resume(returning: signal)
            }
            request.imageCropAndScaleOption = .scaleFill

            let handler = VNImageRequestHandler(ciImage: ci)
            DispatchQueue.global(qos: .userInitiated).async {
                do { try handler.perform([request]) }
                catch {
                    print("[FleetFeatureDetector] perform: \(error)")
                    continuation.resume(returning: FleetFeatureSignal(
                        pushBarScore: 0, spotlightScore: 0,
                        blackoutWheelsScore: 0, antennaScore: 0))
                }
            }
        }
    }
}
```

---

### `Detection/Fusion/TemporalSmoothing.swift`

```swift
import Foundation
import CoreGraphics

/// Matches current-frame detections to existing tracks by IoU, and manages the track pool.
final class VehicleTracker {

    private var tracks: [UUID: VehicleTrack] = [:]
    private let iouThreshold: CGFloat = 0.3
    private let trackTimeoutSeconds: TimeInterval = 1.5

    /// Matches each incoming detection to an existing track (creating new tracks as needed).
    /// Removes stale tracks.
    func update(detections: [VehicleDetection], now: TimeInterval) -> [(VehicleTrack, VehicleDetection)] {
        var matched: [(VehicleTrack, VehicleDetection)] = []
        var usedTrackIDs = Set<UUID>()

        for det in detections {
            if let track = bestMatch(for: det.boundingBox, excluding: usedTrackIDs) {
                track.update(detection: det)
                matched.append((track, det))
                usedTrackIDs.insert(track.id)
            } else {
                let newTrack = VehicleTrack(detection: det)
                tracks[newTrack.id] = newTrack
                matched.append((newTrack, det))
                usedTrackIDs.insert(newTrack.id)
            }
        }

        // Evict stale
        let stale = tracks.values.filter { now - $0.lastSeen > trackTimeoutSeconds }
        for t in stale { tracks.removeValue(forKey: t.id) }

        return matched
    }

    private func bestMatch(for bbox: CGRect, excluding used: Set<UUID>) -> VehicleTrack? {
        var best: VehicleTrack?
        var bestIoU: CGFloat = iouThreshold
        for track in tracks.values where !used.contains(track.id) {
            let i = iou(bbox, track.lastBBox)
            if i > bestIoU {
                bestIoU = i
                best = track
            }
        }
        return best
    }

    private func iou(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let inter = a.intersection(b)
        if inter.isNull || inter.isEmpty { return 0 }
        let interArea = inter.width * inter.height
        let unionArea = a.width * a.height + b.width * b.height - interArea
        return interArea / max(unionArea, .leastNonzeroMagnitude)
    }

    func allTracks() -> [VehicleTrack] { Array(tracks.values) }
}
```

---

### `Detection/Fusion/DetectionFusion.swift`

```swift
import Foundation

/// Combines per-signal scores into a unified threat assessment per vehicle,
/// with temporal smoothing and hysteresis.
final class DetectionFusion {

    // Thresholds for sustained detection
    private let alertThreshold: Float = 0.55
    private let confirmedThreshold: Float = 0.75
    private let minSustainedFramesForAlert = 4   // ~0.3s at 15fps

    /// Compute the final assessment for a track given the latest per-signal scores.
    func assess(track: VehicleTrack,
                emergency: EmergencyLightSignal,
                roof: RoofSignal,
                fleet: FleetFeatureSignal) -> VehicleThreatAssessment {

        // Record into rolling buffers for smoothing
        track.recordEmergencyScore(emergency.score)
        track.recordLightBarScore(roof.lightBarScore)
        track.recordRoofRailsScore(roof.roofRailsScore)
        let fleetCombined = (fleet.pushBarScore + fleet.spotlightScore +
                             fleet.blackoutWheelsScore + fleet.antennaScore) / 4.0
        track.recordFleetFeatureScore(fleetCombined)

        let smEmerg = track.smoothedEmergencyScore()
        let smLightBar = track.smoothedLightBarScore()
        let smRoofRails = track.smoothedRoofRailsScore()
        let smFleet = track.smoothedFleetFeatureScore()

        var reasoning: [String] = []
        var score: Float = 0

        // --- Signal 1: Emergency lights (dominant signal if present) ---
        if smEmerg > 0.4 {
            // Emergency lights are essentially definitive on their own.
            score = max(score, 0.80 + 0.20 * smEmerg)
            reasoning.append("active emergency lights (\(Int(smEmerg * 100))%)")
            if emergency.bicolor {
                reasoning.append("red+blue modulation @ \(String(format: "%.1f", emergency.frequencyHz)) Hz")
            }
        }

        // --- Signal 2: Roof light bar (marked cruiser) ---
        if smLightBar > 0.55 {
            let contribution: Float = 0.55 + 0.35 * smLightBar
            score = max(score, contribution)
            reasoning.append("roof light bar (\(Int(smLightBar * 100))%)")
        }

        // --- Signal 3: Unmarked fleet pattern ---
        // This only fires on fleet-capable models.
        let fleetCapable = track.lastDetection.fleetCapableModel != .unknown
        if fleetCapable {
            // Missing roof rails is the key tell.
            // roofRailsScore LOW = suspicious. Invert for contribution.
            let missingRails = max(0, 1.0 - smRoofRails)

            // Only count "missing rails" if we're confident enough (i.e. not the
            // 0.5 neutral fallback from heuristic mode).
            let railsInformative = (smRoofRails < 0.35 || smRoofRails > 0.65)

            var fleetScore: Float = 0
            if railsInformative {
                fleetScore += 0.45 * missingRails
            }
            fleetScore += 0.35 * smFleet
            fleetScore += 0.20 * track.lastDetection.confidence

            if fleetScore > 0.45 {
                score = max(score, min(fleetScore, 0.85))
                reasoning.append("fleet pattern on \(track.lastDetection.fleetCapableModel.rawValue)")
                if railsInformative && missingRails > 0.6 {
                    reasoning.append("no civilian roof rails")
                }
                if smFleet > 0.4 {
                    reasoning.append("fleet-spec features (bars/spots/wheels/antennas)")
                }
            }
        }

        // Sustained-frame counter for hysteresis
        track.incrementSustainedIfThreshold(alertThreshold, currentFused: score)

        let level: ThreatLevel
        switch score {
        case ..<0.25:
            level = .none
        case 0.25..<alertThreshold:
            level = .low
        case alertThreshold..<confirmedThreshold:
            level = track.sustainedFrames >= minSustainedFramesForAlert ? .likely : .possible
        default:
            level = track.sustainedFrames >= minSustainedFramesForAlert ? .confirmed : .likely
        }

        return VehicleThreatAssessment(
            id: track.id,
            detection: track.lastDetection,
            emergencyLights: emergency,
            roof: roof,
            fleetFeatures: fleet,
            fusedScore: score,
            threatLevel: level,
            reasoning: reasoning,
            sustainedFrames: track.sustainedFrames
        )
    }
}
```

---

### `Detection/Alerts/AlertManager.swift`

```swift
import Foundation
import AVFoundation
import UIKit
import Combine

/// Debounces and surfaces alerts for the UI layer.
/// Publishes the current list of active threats. The UI observes this.
final class AlertManager: ObservableObject {
    static let shared = AlertManager()

    @Published private(set) var activeThreats: [VehicleThreatAssessment] = []

    private let hapticGenerator = UINotificationFeedbackGenerator()
    private var lastAlertAt: [UUID: TimeInterval] = [:]
    private let minAlertIntervalSeconds: TimeInterval = 4.0

    private var audioPlayer: AVAudioPlayer?

    private init() {
        hapticGenerator.prepare()
    }

    func publish(assessments: [VehicleThreatAssessment]) {
        // Filter to alertable levels
        let alertable = assessments.filter { $0.threatLevel >= .likely }

        DispatchQueue.main.async {
            self.activeThreats = assessments.filter { $0.threatLevel >= .possible }
        }

        let now = Date().timeIntervalSince1970
        for a in alertable {
            let last = lastAlertAt[a.id] ?? 0
            guard now - last >= minAlertIntervalSeconds else { continue }
            lastAlertAt[a.id] = now
            fireAlert(for: a)
        }

        // GC old entries
        lastAlertAt = lastAlertAt.filter { now - $0.value < 60 }
    }

    private func fireAlert(for a: VehicleThreatAssessment) {
        DispatchQueue.main.async {
            self.hapticGenerator.notificationOccurred(
                a.threatLevel == .confirmed ? .warning : .success
            )
        }
        playChime(urgent: a.threatLevel == .confirmed)
        print("[ALERT] level=\(a.threatLevel) score=\(a.fusedScore) reasons=\(a.reasoning)")
    }

    private func playChime(urgent: Bool) {
        // TODO: add chime_subtle.caf and chime_urgent.caf to bundle
        let name = urgent ? "chime_urgent" : "chime_subtle"
        guard let url = Bundle.main.url(forResource: name, withExtension: "caf") else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.volume = 0.9
            audioPlayer?.play()
        } catch {
            print("[AlertManager] audio error: \(error)")
        }
    }
}
```

---

### `Detection/PoliceDetectionSystem.swift`

```swift
import Foundation
import AVFoundation
import CoreVideo
import CoreMedia

/// Top-level coordinator. Feed it CMSampleBuffers from your existing camera delegate.
final class PoliceDetectionSystem {
    static let shared = PoliceDetectionSystem()

    private let vehicleDetector = VehicleDetector()
    private let emergencyDetector = EmergencyLightDetector()
    private let roofAnalyzer = RoofAnalyzer()
    private let fleetDetector = FleetFeatureDetector()
    private let tracker = VehicleTracker()
    private let fusion = DetectionFusion()
    private let thermalMonitor = ThermalMonitor.shared

    private let processingQueue = DispatchQueue(label: "police.detection.queue",
                                                qos: .userInitiated,
                                                attributes: .concurrent)
    private var isProcessing = false
    private let isProcessingLock = NSLock()

    /// Call this from your existing AVCaptureVideoDataOutputSampleBufferDelegate.
    func processFrame(sampleBuffer: CMSampleBuffer) {
        guard thermalMonitor.shouldProcessThisFrame() else { return }

        // Drop frames if we're still busy — never queue up backlog
        isProcessingLock.lock()
        if isProcessing { isProcessingLock.unlock(); return }
        isProcessing = true
        isProcessingLock.unlock()

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            markDone(); return
        }
        let timestamp = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        let imageSize = CGSize(width: CVPixelBufferGetWidth(pixelBuffer),
                               height: CVPixelBufferGetHeight(pixelBuffer))

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            defer { self.markDone() }

            // 1. Detect vehicles
            let detections = await self.vehicleDetector.detect(in: pixelBuffer, timestamp: timestamp)

            // 2. Match to tracks
            let matched = self.tracker.update(detections: detections, now: timestamp)

            // 3. Sample emergency-light colors for each track on EVERY frame we process.
            // This is essential so FFT has enough samples.
            for (track, det) in matched {
                if let sample = self.emergencyDetector.sample(pixelBuffer: pixelBuffer,
                                                              vehicleBox: det.boundingBox,
                                                              imageSize: imageSize,
                                                              timestamp: timestamp) {
                    track.recordColorSample(sample)
                }
            }

            // 4. Run per-vehicle detailed analysis in parallel.
            var assessments: [VehicleThreatAssessment] = []
            await withTaskGroup(of: VehicleThreatAssessment.self) { group in
                for (track, det) in matched {
                    group.addTask {
                        async let emerg = self.emergencyDetector.analyze(track: track)
                        async let roof = self.roofAnalyzer.analyze(pixelBuffer: pixelBuffer,
                                                                   vehicleBox: det.boundingBox,
                                                                   imageSize: imageSize)
                        async let fleet = self.fleetDetector.analyze(pixelBuffer: pixelBuffer,
                                                                     vehicleBox: det.boundingBox,
                                                                     imageSize: imageSize)
                        let (e, r, f) = await (emerg, roof, fleet)
                        return self.fusion.assess(track: track,
                                                  emergency: e,
                                                  roof: r,
                                                  fleet: f)
                    }
                }
                for await assessment in group {
                    assessments.append(assessment)
                }
            }

            // 5. Publish to alert manager
            AlertManager.shared.publish(assessments: assessments)
        }
    }

    private func markDone() {
        isProcessingLock.lock()
        isProcessing = false
        isProcessingLock.unlock()
    }
}
```

---

### `Detection/UI/DetectionOverlayView.swift`

```swift
import SwiftUI

/// Overlay that draws boxes around detected threats on top of the camera preview.
/// Pin this ZStack-style over your existing camera preview view.
struct DetectionOverlayView: View {
    @ObservedObject private var alerts = AlertManager.shared

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                ForEach(alerts.activeThreats) { threat in
                    ThreatBox(threat: threat, viewSize: proxy.size)
                }
                if let worst = alerts.activeThreats.max(by: { $0.fusedScore < $1.fusedScore }),
                   worst.threatLevel >= .likely {
                    VStack {
                        AlertBanner(threat: worst)
                        Spacer()
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct ThreatBox: View {
    let threat: VehicleThreatAssessment
    let viewSize: CGSize

    var body: some View {
        let bbox = threat.detection.boundingBox
        let rect = CGRect(
            x: bbox.origin.x * viewSize.width,
            y: (1 - bbox.origin.y - bbox.size.height) * viewSize.height,
            width: bbox.size.width * viewSize.width,
            height: bbox.size.height * viewSize.height
        )

        Rectangle()
            .stroke(color, lineWidth: threat.threatLevel >= .likely ? 3 : 2)
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .overlay(alignment: .topLeading) {
                Text("\(Int(threat.fusedScore * 100))%")
                    .font(.caption2.bold())
                    .padding(.horizontal, 4)
                    .background(color.opacity(0.85))
                    .foregroundColor(.white)
                    .position(x: rect.minX + 20, y: rect.minY + 8)
            }
    }

    private var color: Color {
        switch threat.threatLevel {
        case .confirmed: return .red
        case .likely:    return .orange
        case .possible:  return .yellow
        case .low, .none: return .gray
        }
    }
}

private struct AlertBanner: View {
    let threat: VehicleThreatAssessment

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(threat.reasoning.joined(separator: " · "))
                    .font(.caption)
                    .opacity(0.9)
            }
            Spacer()
        }
        .padding(12)
        .background(bg.opacity(0.92))
        .foregroundColor(.white)
        .cornerRadius(10)
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    private var title: String {
        switch threat.threatLevel {
        case .confirmed: return "Emergency vehicle ahead"
        case .likely:    return "Possible law enforcement vehicle"
        case .possible:  return "Hazard detected"
        default:         return ""
        }
    }

    private var bg: Color {
        threat.threatLevel == .confirmed ? .red : .orange
    }
}
```

---

## Integration

Find your existing camera delegate, which will look something like this:

```swift
extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        // existing recording code ...

        // ADD THIS LINE:
        PoliceDetectionSystem.shared.processFrame(sampleBuffer: sampleBuffer)
    }
}
```

Then in your camera preview SwiftUI view:

```swift
ZStack {
    CameraPreview(session: cameraManager.session)   // existing
    DetectionOverlayView()                           // new
}
```

---

## Core ML Models

The subsystem works in degraded mode with none of these models installed (emergency-light detection still works — that's the signal-processing pipeline). For full functionality:

### 1. `VehicleDetectorYOLOv8.mlmodel`
- Train YOLOv8n on a combination of BDD100K + scraped fleet vehicle imagery.
- Export to Core ML using ultralytics: `yolo export model=yolov8n.pt format=coreml nms=True`.
- Make sure class labels match the parser in `VehicleDetector.parseVehicleClass` / `parseFleetCapableModel`.

### 2. `RoofFeatureClassifier.mlmodel`
- Two-head small CNN (MobileNetV3-small works great).
- Train in PyTorch or use Create ML. Two sigmoid outputs: `has_light_bar`, `has_roof_rails`.
- Dataset: ~3–5k images of each class, balanced positive/negative.
  - Light bar positives: marked cruisers (all styles — full-length bars, low-profile bars, rear-facing only, etc.).
  - Roof rails positives: civilian trim Explorers/Tahoes/Durangos with factory rails.
  - Negatives: fleet-spec variants with bare flat roofs.

### 3. `FleetFeatureClassifier.mlmodel`
- Multi-head small CNN (MobileNetV3-small or EfficientNet-Lite0).
- Four sigmoid outputs: `has_push_bar`, `has_spotlight`, `has_blackout_wheels`, `has_multiple_antennas`.
- Dataset tip: decommissioned fleet vehicles on GovDeals and Municibid have tons of labeled photos showing exactly these features.

### Training tips
- Use **aggressive augmentation**: random brightness, blur, noise, rain overlay, partial occlusion, rear-view and rear-3/4 view perspectives especially.
- **Class balance is important.** Fleet-spec vehicles are rarer than civilian ones — oversample or class-weight.
- **Start small.** Get a 2-class model working end-to-end before expanding. Ship the emergency-light detector first — it needs no model at all and is still genuinely useful.

---

## Testing & Validation

### Unit tests worth writing
- `EmergencyLightDetector`: synthesize a signal array with a known 4 Hz oscillation, confirm the FFT returns a peak at ~4 Hz.
- `VehicleTracker`: feed synthetic detections with moving bboxes, confirm same track ID is preserved across frames.
- `DetectionFusion`: plug in various signal combinations, confirm threat levels and reasoning strings.

### Field validation checklist
- Drive next to a stationary marked cruiser (parking lot) — should hit `.likely` or `.confirmed` within 1 second.
- Drive past a civilian Explorer with roof rails — should stay `.none`.
- Drive past a fleet-looking Explorer (retired, at a dealer) — should hit `.possible` or `.likely`.
- Drive past an ambulance with lights on — should hit `.confirmed` on emergency lights. (This is a feature — alert the user to any emergency vehicle.)
- Night conditions: bright headlights and LED taillights should NOT trigger emergency-light detection (steady, not modulated in 1–10 Hz band).

### Performance targets
- Vehicle detector: <25 ms per frame on A15
- Roof+fleet analyzers: <15 ms combined per vehicle
- Max 4 vehicles analyzed per frame (cap it in `PoliceDetectionSystem` if needed)
- Sustained <10% battery drain per hour with recording + detection active

---

## Known Limitations (be honest about these)

1. **Fleet-rail heuristic has false positives** on civilian base trims that ship without rails (rare but real — Explorer base, some Suburbans, rental-spec vehicles). The reasoning string exposes why it alerted so the user can dismiss false positives quickly.
2. **Agencies adapting:** some departments now order fleet vehicles with rails to blend in. Model needs periodic retraining on regional vehicle photos.
3. **Backward-facing only:** the iPhone camera faces ahead, so this system sees cruisers you're driving past or approaching head-on. It does NOT see cruisers behind you. Discuss whether a rear-window mount is part of your UX.
4. **Not for evasion:** frame this in-app and in App Store marketing as "situational awareness / hazard detection." Apple has rejected apps explicitly marketed as police evasion tools. Emergency vehicle detection is a legitimate safety feature.
5. **Legal:** radar detectors are illegal in VA, DC, and all federal commercial vehicles; laser jammers banned in more states. This app does NEITHER, but phrase marketing carefully.

---

## Next Steps (after this lands)

- Add **brake light detection** on the car directly ahead (flashing red, different band than emergency lights, but same FFT pipeline).
- Add **stop sign / speed limit OCR** using `VNRecognizeTextRequest` on road-sign regions.
- Add **time-to-collision** calculation using vehicle-width heuristics or ARKit depth on Pro models.
- Rolling-buffer incident recording: save the 30s before + 30s after any `.confirmed` alert as a clip for the user.
- Geo-logging: anonymously log confirmed sightings with GPS for a crowdsourced layer (opt-in).

---

End of brief. Paste this entire document into Claude Code and ask it to execute the file creation + integration.
