import Foundation
import Vision
import CoreML
import CoreVideo
import OSLog

/// Detects vehicles and classifies them by type + fleet-capable model guess.
///
/// CORE ML MODEL REQUIRED: `VehicleDetectorYOLOv8.mlmodelc`
///   - Train YOLOv8n on BDD100K + scraped fleet-vehicle imagery.
///   - Input: 640×640 RGB.
///   - Output: Vision-compatible object detection (use `ultralytics` export).
///   - Classes: car, suv, pickup, truck, van, motorcycle, bus, plus optional
///     fleet-model subclasses (explorer, tahoe, charger, durango, …).
///
/// If the model is missing at runtime, detection returns an empty array and
/// the rest of the pipeline degrades gracefully.
final class VehicleDetector: @unchecked Sendable {
    private var visionModel: VNCoreMLModel?
    private let requestQueue = DispatchQueue(label: "res.carcam-pro.detection.vehicle",
                                             qos: .userInitiated)

    /// Whether the Core ML model was bundled + loaded at init time. Read by
    /// the telemetry layer so QA/HUD can surface "model missing" at a glance.
    var isModelLoaded: Bool { visionModel != nil }

    init() {
        loadModel()
    }

    private func loadModel() {
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all // CPU + GPU + Neural Engine
            guard let url = Bundle.main.url(forResource: "VehicleDetectorYOLOv8",
                                            withExtension: "mlmodelc") else {
                AppLogger.detection.notice("Vehicle model not bundled — stub mode")
                return
            }
            let mlModel = try MLModel(contentsOf: url, configuration: config)
            self.visionModel = try VNCoreMLModel(for: mlModel)
        } catch {
            AppLogger.detection.error("VehicleDetector.loadModel: \(error.localizedDescription)")
        }
    }

    /// Run detection on a frame. Returns vehicles in Vision coordinate space
    /// (origin bottom-left, normalized).
    func detect(in pixelBuffer: CVPixelBuffer, timestamp: TimeInterval) async -> [VehicleDetection] {
        guard let model = visionModel else { return [] }

        return await withCheckedContinuation { (continuation: CheckedContinuation<[VehicleDetection], Never>) in
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
                    AppLogger.detection.error("VehicleDetector.perform: \(error.localizedDescription)")
                    continuation.resume(returning: [])
                }
            }
        }
    }

    // MARK: - Label parsing

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

    /// Placeholder distance estimate from bbox size. Returns `nil` until a
    /// proper calibrated focal-length model is wired in — the fusion layer
    /// does not currently rely on this value.
    private static func estimateDistance(from bbox: CGRect) -> Float? {
        nil
    }
}
