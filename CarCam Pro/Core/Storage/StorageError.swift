import Foundation

enum StorageError: LocalizedError, Sendable {
    case insufficientSpace
    case deletionFailed(String)
    case directoryCreationFailed(String)
    case capExceeded(used: Int64, cap: Int64)

    var errorDescription: String? {
        switch self {
        case .insufficientSpace:
            "Insufficient storage space on device"
        case .deletionFailed(let path):
            "Failed to delete file: \(path)"
        case .directoryCreationFailed(let path):
            "Failed to create directory: \(path)"
        case .capExceeded(let used, let cap):
            "Storage cap exceeded: \(used) bytes used of \(cap) bytes allowed"
        }
    }
}
