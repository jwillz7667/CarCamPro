import Foundation
import CoreImage
import CoreVideo
import Accelerate

/// Utilities for cropping + color-analyzing `CVPixelBuffer`s without going
/// through UIKit. Used by every pipeline stage to slice the roof / upper-body
/// regions out of the full-frame buffer.
enum PixelBufferUtilities {
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// Convert a Vision-coordinate bbox (origin bottom-left, normalized) to a
    /// pixel rect in image coordinates (origin top-left).
    static func pixelRect(from visionBox: CGRect, imageSize: CGSize) -> CGRect {
        let x = visionBox.origin.x * imageSize.width
        let h = visionBox.size.height * imageSize.height
        let y = (1 - visionBox.origin.y - visionBox.size.height) * imageSize.height
        let w = visionBox.size.width * imageSize.width
        return CGRect(x: x, y: y, width: w, height: h).integral
    }

    /// Crop to the roof region — top 35% of the vehicle bbox. Used by
    /// `RoofAnalyzer` to isolate the region where light bars live.
    static func roofCropImage(
        from pixelBuffer: CVPixelBuffer,
        vehicleBox: CGRect,
        imageSize: CGSize
    ) -> CIImage? {
        let rect = pixelRect(from: vehicleBox, imageSize: imageSize)
        let roofHeight = rect.height * 0.35
        let roofRect = CGRect(
            x: rect.minX, y: rect.minY,
            width: rect.width, height: roofHeight
        )
        return CIImage(cvPixelBuffer: pixelBuffer).cropped(to: roofRect)
    }

    /// Crop to the upper-body region — top 55% — where both the roof and the
    /// upper-window glass sit. Used by `EmergencyLightDetector` because
    /// emergency lights spill into the upper windows.
    static func upperBodyCrop(
        from pixelBuffer: CVPixelBuffer,
        vehicleBox: CGRect,
        imageSize: CGSize
    ) -> CIImage? {
        let rect = pixelRect(from: vehicleBox, imageSize: imageSize)
        let upperHeight = rect.height * 0.55
        let upperRect = CGRect(
            x: rect.minX, y: rect.minY,
            width: rect.width, height: upperHeight
        )
        return CIImage(cvPixelBuffer: pixelBuffer).cropped(to: upperRect)
    }

    /// Mean red / green / blue / luma over a CIImage region via
    /// `CIAreaAverage` — GPU-accelerated single-pixel output.
    static func meanChannels(of image: CIImage) -> (red: Float, green: Float, blue: Float, luma: Float)? {
        guard let filter = CIFilter(name: "CIAreaAverage") else { return nil }
        let extent = CIVector(
            x: image.extent.origin.x, y: image.extent.origin.y,
            z: image.extent.size.width, w: image.extent.size.height
        )
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(extent, forKey: kCIInputExtentKey)
        guard let output = filter.outputImage else { return nil }

        var bitmap = [UInt8](repeating: 0, count: 4)
        ciContext.render(
            output, toBitmap: &bitmap, rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        let r = Float(bitmap[0]) / 255.0
        let g = Float(bitmap[1]) / 255.0
        let b = Float(bitmap[2]) / 255.0
        // Rec. 709 luma approximation.
        let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
        return (r, g, b, luma)
    }
}
