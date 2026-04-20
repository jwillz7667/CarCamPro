import AVFoundation

enum VideoCodec: String, Codable, Sendable {
    case h264 = "H.264"
    case hevc = "HEVC"

    var avCodecType: AVVideoCodecType {
        switch self {
        case .h264: .h264
        case .hevc: .hevc
        }
    }

    var displayName: String { rawValue }
}
