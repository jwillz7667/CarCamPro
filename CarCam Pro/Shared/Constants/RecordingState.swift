import Foundation

enum RecordingState: Equatable, Sendable {
    case idle
    case starting
    case recording(segment: Int, duration: TimeInterval)
    case rotatingSegment(fromSegment: Int, toSegment: Int)
    case stopping
    case error(RecordingError)

    var isRecording: Bool {
        switch self {
        case .recording, .rotatingSegment: true
        default: false
        }
    }

    var isIdle: Bool {
        if case .idle = self { return true }
        return false
    }

    static func canTransition(from: RecordingState, to: RecordingState) -> Bool {
        switch (from, to) {
        case (.idle, .starting): true
        case (.starting, .recording): true
        case (.starting, .error): true
        case (.recording, .rotatingSegment): true
        case (.recording, .stopping): true
        case (.recording, .error): true
        case (.rotatingSegment, .recording): true
        case (.rotatingSegment, .error): true
        case (.stopping, .idle): true
        case (.stopping, .error): true
        case (.error, .idle): true
        default: false
        }
    }
}
