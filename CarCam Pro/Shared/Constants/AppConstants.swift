import Foundation

enum AppConstants {
    static let defaultSegmentDuration: TimeInterval = 180
    static let defaultStorageCap: Int64 = 5_368_709_120 // 5 GB
    static let minimumFreeSpace: Int64 = 500_000_000 // 500 MB
    static let appGroupIdentifier = ""
    static let recordingsDirectoryName = "Recordings"
    static let thumbnailsDirectoryName = "Thumbnails"
    static let tempDirectoryName = "Temp"
    static let preWarmLeadTime: TimeInterval = 2.0
    static let debounceInterval: TimeInterval = 10.0
    static let thermalRecoveryDelay: TimeInterval = 60.0
}
