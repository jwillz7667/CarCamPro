import Foundation

enum VideoWriterError: LocalizedError, Sendable {
    case setupFailed(String)
    case writingFailed(String)
    case finishFailed(String)
    case invalidState(String)

    var errorDescription: String? {
        switch self {
        case .setupFailed(let detail):
            "Video writer setup failed: \(detail)"
        case .writingFailed(let detail):
            "Video writing failed: \(detail)"
        case .finishFailed(let detail):
            "Failed to finalize video: \(detail)"
        case .invalidState(let detail):
            "Video writer in invalid state: \(detail)"
        }
    }
}
