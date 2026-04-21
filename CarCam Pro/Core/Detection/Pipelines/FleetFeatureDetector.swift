import Foundation
import Vision
import CoreML
import CoreImage
import OSLog

/// Detects fleet-specific visual tells on a cropped vehicle image.
///
/// CORE ML MODEL REQUIRED: `FleetFeatureClassifier.mlmodelc`
///   - Architecture: small multi-head CNN (MobileNetV3-small, ~3 M params)
///   - Input: 256×256 RGB full-vehicle crop
///   - Output: four independent sigmoid heads:
///       * `has_push_bar`, `has_spotlight`,
///         `has_blackout_wheels`, `has_multiple_antennas`
///
/// Training data sources: GovDeals / Municibid (decommissioned fleet
/// vehicles), Ford/GM fleet marketing, stock civilian images for negatives.
///
/// Fallback: return zero scores when the model is missing. The fleet-capable
/// model guess alone is never enough to fire an alert, so absence is safe.
final class FleetFeatureDetector: @unchecked Sendable {
    private var visionModel: VNCoreMLModel?

    /// Whether the Core ML model loaded. Missing → all-zero scores on every
    /// call; fusion treats fleet-capable-model-alone as insufficient, so a
    /// missing model is safe but reduces pipeline recall.
    var isModelLoaded: Bool { visionModel != nil }

    init() {
        loadModel()
    }

    private func loadModel() {
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all
            guard let url = Bundle.main.url(forResource: "FleetFeatureClassifier",
                                            withExtension: "mlmodelc") else {
                AppLogger.detection.notice("Fleet-feature model not bundled — zero scores")
                return
            }
            let model = try MLModel(contentsOf: url, configuration: config)
            self.visionModel = try VNCoreMLModel(for: model)
        } catch {
            AppLogger.detection.error("FleetFeatureDetector.loadModel: \(error.localizedDescription)")
        }
    }

    func analyze(
        pixelBuffer: CVPixelBuffer,
        vehicleBox: CGRect,
        imageSize: CGSize
    ) async -> FleetFeatureSignal {
        guard let model = visionModel else { return .zero }

        let pixelRect = PixelBufferUtilities.pixelRect(from: vehicleBox, imageSize: imageSize)
        let ci = CIImage(cvPixelBuffer: pixelBuffer).cropped(to: pixelRect)

        return await withCheckedContinuation { (continuation: CheckedContinuation<FleetFeatureSignal, Never>) in
            let request = VNCoreMLRequest(model: model) { req, _ in
                guard let results = req.results as? [VNCoreMLFeatureValueObservation] else {
                    continuation.resume(returning: .zero)
                    return
                }
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
                continuation.resume(returning: FleetFeatureSignal(
                    pushBarScore: push, spotlightScore: spot,
                    blackoutWheelsScore: wheels, antennaScore: ant
                ))
            }
            request.imageCropAndScaleOption = .scaleFill

            let handler = VNImageRequestHandler(ciImage: ci)
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    AppLogger.detection.error("FleetFeatureDetector.perform: \(error.localizedDescription)")
                    continuation.resume(returning: .zero)
                }
            }
        }
    }
}
