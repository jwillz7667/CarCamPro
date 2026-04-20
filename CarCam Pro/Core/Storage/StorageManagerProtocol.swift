import Foundation
import SwiftData

protocol StorageManagerProtocol: AnyObject, Sendable {
    func calculateTotalUsage() async -> Int64
    func enforceStorageCap() async throws
    func deleteClip(_ clip: VideoClip, context: ModelContext) async throws
    func deleteAllUnprotected(context: ModelContext) async throws
    func availableDeviceSpace() -> Int64
}
