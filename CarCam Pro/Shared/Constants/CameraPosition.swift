import AVFoundation

enum CameraPosition: String, Codable, CaseIterable, Sendable {
    case backWide = "Back (Wide)"
    case backUltraWide = "Back (Ultra Wide)"
    case front = "Front (Cabin)"

    var capturePosition: AVCaptureDevice.Position {
        switch self {
        case .backWide, .backUltraWide: .back
        case .front: .front
        }
    }

    var deviceType: AVCaptureDevice.DeviceType {
        switch self {
        case .backWide: .builtInWideAngleCamera
        case .backUltraWide: .builtInUltraWideCamera
        case .front: .builtInWideAngleCamera
        }
    }
}
