import AVFoundation

protocol CameraServiceProtocol: AnyObject, Sendable {
    var isRunning: Bool { get }
    var captureSession: AVCaptureSession { get }
    func configure(_ config: CameraConfiguration) async throws
    func startCapture() async throws
    func stopCapture() async
    func switchCamera(to position: CameraPosition) async throws
    func updateQuality(resolution: VideoResolution, frameRate: Int, bitrate: Int) async throws
    func setSampleBufferDelegate(_ delegate: any SampleBufferDelegate) async
}

protocol SampleBufferDelegate: AnyObject, Sendable {
    nonisolated func didOutputVideoSampleBuffer(_ sampleBuffer: CMSampleBuffer)
    nonisolated func didOutputAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer)
}
