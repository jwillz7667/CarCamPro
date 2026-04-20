import Testing
@testable import CarCam_Pro

@Suite("RecordingState Transitions")
struct RecordingStateTests {
    @Test("Valid: idle → starting")
    func idleToStarting() {
        #expect(RecordingState.canTransition(from: .idle, to: .starting))
    }

    @Test("Valid: starting → recording")
    func startingToRecording() {
        #expect(RecordingState.canTransition(from: .starting, to: .recording(segment: 1, duration: 0)))
    }

    @Test("Valid: starting → error")
    func startingToError() {
        #expect(RecordingState.canTransition(from: .starting, to: .error(.notReady)))
    }

    @Test("Valid: recording → rotatingSegment")
    func recordingToRotating() {
        #expect(RecordingState.canTransition(
            from: .recording(segment: 1, duration: 180),
            to: .rotatingSegment(fromSegment: 1, toSegment: 2)
        ))
    }

    @Test("Valid: recording → stopping")
    func recordingToStopping() {
        #expect(RecordingState.canTransition(
            from: .recording(segment: 1, duration: 30),
            to: .stopping
        ))
    }

    @Test("Valid: rotatingSegment → recording")
    func rotatingToRecording() {
        #expect(RecordingState.canTransition(
            from: .rotatingSegment(fromSegment: 1, toSegment: 2),
            to: .recording(segment: 2, duration: 0)
        ))
    }

    @Test("Valid: stopping → idle")
    func stoppingToIdle() {
        #expect(RecordingState.canTransition(from: .stopping, to: .idle))
    }

    @Test("Valid: error → idle (reset)")
    func errorToIdle() {
        #expect(RecordingState.canTransition(from: .error(.notReady), to: .idle))
    }

    @Test("Invalid: idle → stopping")
    func idleToStoppingInvalid() {
        #expect(!RecordingState.canTransition(from: .idle, to: .stopping))
    }

    @Test("Invalid: idle → recording")
    func idleToRecordingInvalid() {
        #expect(!RecordingState.canTransition(
            from: .idle,
            to: .recording(segment: 1, duration: 0)
        ))
    }

    @Test("Invalid: idle → rotatingSegment")
    func idleToRotatingInvalid() {
        #expect(!RecordingState.canTransition(
            from: .idle,
            to: .rotatingSegment(fromSegment: 1, toSegment: 2)
        ))
    }

    @Test("Invalid: stopping → recording")
    func stoppingToRecordingInvalid() {
        #expect(!RecordingState.canTransition(
            from: .stopping,
            to: .recording(segment: 1, duration: 0)
        ))
    }

    @Test("isRecording returns true for recording state")
    func isRecordingTrue() {
        let state = RecordingState.recording(segment: 1, duration: 42)
        #expect(state.isRecording)
    }

    @Test("isRecording returns true for rotatingSegment state")
    func isRecordingTrueForRotating() {
        let state = RecordingState.rotatingSegment(fromSegment: 1, toSegment: 2)
        #expect(state.isRecording)
    }

    @Test("isRecording returns false for idle state")
    func isRecordingFalseForIdle() {
        #expect(!RecordingState.idle.isRecording)
    }

    @Test("isRecording returns false for stopping state")
    func isRecordingFalseForStopping() {
        #expect(!RecordingState.stopping.isRecording)
    }

    @Test("isIdle returns true for idle state")
    func isIdleTrue() {
        #expect(RecordingState.idle.isIdle)
    }

    @Test("isIdle returns false for recording state")
    func isIdleFalseForRecording() {
        #expect(!RecordingState.recording(segment: 1, duration: 0).isIdle)
    }
}
