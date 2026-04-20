import Foundation

enum CameraError: LocalizedError, Sendable {
    case notAuthorized
    case configurationFailed(String)
    case deviceUnavailable(CameraPosition)
    case captureSessionFailed

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            "Camera access is not authorized. Enable it in Settings."
        case .configurationFailed(let detail):
            "Camera configuration failed: \(detail)"
        case .deviceUnavailable(let position):
            "Camera not available: \(position.rawValue)"
        case .captureSessionFailed:
            "Failed to start the camera capture session"
        }
    }
}
