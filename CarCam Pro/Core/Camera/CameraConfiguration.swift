import Foundation

struct CameraConfiguration: Sendable {
    let resolution: VideoResolution
    let frameRate: Int
    let codec: VideoCodec
    let cameraPosition: CameraPosition
    let audioEnabled: Bool

    static var `default`: CameraConfiguration {
        CameraConfiguration(
            resolution: AppSettings.shared.resolution,
            frameRate: AppSettings.shared.frameRate,
            codec: AppSettings.shared.codec,
            cameraPosition: AppSettings.shared.selectedCamera,
            audioEnabled: AppSettings.shared.audioEnabled
        )
    }
}
