import CoreMedia

enum VideoResolution: String, Codable, CaseIterable, Sendable {
    case hd720 = "720p"
    case hd1080 = "1080p"
    case uhd4k = "4K"

    var dimensions: CMVideoDimensions {
        switch self {
        case .hd720: CMVideoDimensions(width: 1280, height: 720)
        case .hd1080: CMVideoDimensions(width: 1920, height: 1080)
        case .uhd4k: CMVideoDimensions(width: 3840, height: 2160)
        }
    }

    var bitrate: Int {
        switch self {
        case .hd720: 2_000_000
        case .hd1080: 5_000_000
        case .uhd4k: 15_000_000
        }
    }

    var displayName: String { rawValue }
}
