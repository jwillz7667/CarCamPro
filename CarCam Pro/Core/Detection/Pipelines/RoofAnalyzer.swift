import Foundation
import Vision
import CoreML
import CoreImage
import OSLog

/// Analyzes the roof region of a detected vehicle for:
///   - Light-bar presence (marked cruiser)
///   - Civilian roof-rails presence (absence = suspicious on fleet-capable models)
///
/// CORE ML MODEL REQUIRED: `RoofFeatureClassifier.mlmodelc`
///   - Architecture: small CNN (MobileNetV3-small or similar), ~2–4 M params
///   - Input: 224×224 RGB crop of the roof region
///   - Output: two independent sigmoid heads:
///       * `has_light_bar`: Float 0…1
///       * `has_roof_rails`: Float 0…1
///   - Training data:
///       * Light-bar positives: marked cruisers (all bar styles).
///       * Roof-rails positives: civilian SUVs/trucks with factory rails.
///       * Negatives: fleet-spec vehicles with bare flat roofs.
///
/// Fallback: if the model is absent, use a basic saturation-variance
/// heuristic. Weaker than a trained model, but useful for bootstrapping.
final class RoofAnalyzer: @unchecked Sendable {
    private var visionModel: VNCoreMLModel?

    init() {
        loadModel()
    }

    private func loadModel() {
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all
            guard let url = Bundle.main.url(forResource: "RoofFeatureClassifier",
                                            withExtension: "mlmodelc") else {
                AppLogger.detection.notice("Roof model not bundled — heuristic fallback")
                return
            }
            let model = try MLModel(contentsOf: url, configuration: config)
            self.visionModel = try VNCoreMLModel(for: model)
        } catch {
            AppLogger.detection.error("RoofAnalyzer.loadModel: \(error.localizedDescription)")
        }
    }

    func analyze(
        pixelBuffer: CVPixelBuffer,
        vehicleBox: CGRect,
        imageSize: CGSize
    ) async -> RoofSignal {
        guard let crop = PixelBufferUtilities.roofCropImage(
            from: pixelBuffer,
            vehicleBox: vehicleBox,
            imageSize: imageSize
        ) else {
            return RoofSignal(lightBarScore: 0, roofRailsScore: 0.5)
        }

        if let model = visionModel {
            return await runModel(model, crop: crop) ?? heuristicFallback(crop: crop)
        }
        return heuristicFallback(crop: crop)
    }

    private func runModel(_ model: VNCoreMLModel, crop: CIImage) async -> RoofSignal? {
        await withCheckedContinuation { (continuation: CheckedContinuation<RoofSignal?, Never>) in
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
                continuation.resume(returning: RoofSignal(
                    lightBarScore: lightBar, roofRailsScore: roofRails
                ))
            }
            request.imageCropAndScaleOption = .scaleFill

            let handler = VNImageRequestHandler(ciImage: crop)
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    AppLogger.detection.error("RoofAnalyzer.perform: \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    /// Heuristic fallback — saturation-variance proxy for light-bar presence.
    private func heuristicFallback(crop: CIImage) -> RoofSignal {
        guard let channels = PixelBufferUtilities.meanChannels(of: crop) else {
            return RoofSignal(lightBarScore: 0, roofRailsScore: 0.5)
        }
        let saturation = max(
            abs(channels.red - channels.green),
            max(
                abs(channels.green - channels.blue),
                abs(channels.red - channels.blue)
            )
        )
        let lightBarScore = min(1.0, saturation * 2.0)
        return RoofSignal(lightBarScore: lightBarScore, roofRailsScore: 0.5)
    }
}
