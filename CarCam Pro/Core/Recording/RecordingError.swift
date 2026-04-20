import Foundation

enum RecordingError: LocalizedError, Equatable, Sendable {
    case notReady
    case alreadyRecording
    case writerSetupFailed(String)
    case segmentRotationFailed
    case invalidStateTransition(String)

    var errorDescription: String? {
        switch self {
        case .notReady:
            "Recording engine is not ready to record"
        case .alreadyRecording:
            "A recording is already in progress"
        case .writerSetupFailed(let detail):
            "Video writer setup failed: \(detail)"
        case .segmentRotationFailed:
            "Failed to rotate recording segment"
        case .invalidStateTransition(let detail):
            "Invalid state transition: \(detail)"
        }
    }
}
