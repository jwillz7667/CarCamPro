import Testing
import Foundation
import SwiftData
@testable import CarCam_Pro

@Suite("StorageManager FIFO Logic")
struct StorageManagerTests {

    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([RecordingSession.self, VideoClip.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func createClip(
        fileName: String,
        fileSize: Int64,
        startDate: Date,
        isProtected: Bool = false,
        isStarred: Bool = false,
        context: ModelContext
    ) -> VideoClip {
        let clip = VideoClip(
            fileName: fileName,
            filePath: "Recordings/test/\(fileName)",
            startDate: startDate,
            duration: 10,
            fileSize: fileSize,
            resolution: .hd1080,
            frameRate: 30,
            codec: .hevc
        )
        clip.isProtected = isProtected
        clip.isStarred = isStarred
        context.insert(clip)
        return clip
    }

    @Test("FIFO deletes oldest clips first")
    func fifoDeletesOldest() async throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)

        let now = Date()
        _ = createClip(fileName: "old.mp4", fileSize: 1000, startDate: now.addingTimeInterval(-300), context: context)
        _ = createClip(fileName: "mid.mp4", fileSize: 1000, startDate: now.addingTimeInterval(-200), context: context)
        _ = createClip(fileName: "new.mp4", fileSize: 1000, startDate: now.addingTimeInterval(-100), context: context)
        try context.save()

        // Verify all 3 exist
        let allClips = try context.fetch(FetchDescriptor<VideoClip>(sortBy: [SortDescriptor(\.startDate, order: .forward)]))
        #expect(allClips.count == 3)
        #expect(allClips[0].fileName == "old.mp4")
        #expect(allClips[1].fileName == "mid.mp4")
        #expect(allClips[2].fileName == "new.mp4")
    }

    @Test("Protected clips survive FIFO")
    func protectedSurvive() async throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)

        let now = Date()
        let protectedClip = createClip(
            fileName: "protected.mp4",
            fileSize: 5000,
            startDate: now.addingTimeInterval(-300),
            isProtected: true,
            context: context
        )
        _ = createClip(fileName: "normal.mp4", fileSize: 5000, startDate: now.addingTimeInterval(-200), context: context)
        try context.save()

        // Fetch unprotected only
        let descriptor = FetchDescriptor<VideoClip>(
            predicate: #Predicate<VideoClip> { clip in
                clip.isProtected == false && clip.isStarred == false
            },
            sortBy: [SortDescriptor(\.startDate, order: .forward)]
        )
        let candidates = try context.fetch(descriptor)
        #expect(candidates.count == 1)
        #expect(candidates[0].fileName == "normal.mp4")

        // Verify protected clip still exists
        let all = try context.fetch(FetchDescriptor<VideoClip>())
        #expect(all.contains { $0.fileName == "protected.mp4" })
    }

    @Test("Starred clips survive FIFO")
    func starredSurvive() async throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)

        let now = Date()
        _ = createClip(
            fileName: "starred.mp4",
            fileSize: 5000,
            startDate: now.addingTimeInterval(-300),
            isStarred: true,
            context: context
        )
        _ = createClip(fileName: "normal.mp4", fileSize: 5000, startDate: now.addingTimeInterval(-200), context: context)
        try context.save()

        let descriptor = FetchDescriptor<VideoClip>(
            predicate: #Predicate<VideoClip> { clip in
                clip.isProtected == false && clip.isStarred == false
            }
        )
        let candidates = try context.fetch(descriptor)
        #expect(candidates.count == 1)
        #expect(candidates[0].fileName == "normal.mp4")
    }

    @Test("VideoClip typed accessors round-trip")
    func clipTypedAccessors() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)

        let clip = VideoClip(
            fileName: "test.mp4",
            filePath: "test/test.mp4",
            resolution: .uhd4k,
            frameRate: 30,
            codec: .h264
        )
        context.insert(clip)

        #expect(clip.resolution == .uhd4k)
        #expect(clip.codec == .h264)
        #expect(clip.resolutionRawValue == "4K")
        #expect(clip.codecRawValue == "H.264")

        clip.resolution = .hd720
        #expect(clip.resolutionRawValue == "720p")

        clip.protectionReason = .incidentDetected
        #expect(clip.protectionReasonRawValue == "incidentDetected")
        #expect(clip.protectionReason == .incidentDetected)
    }

    @Test("RecordingSession cascade deletes clips")
    func sessionCascadeDelete() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)

        let session = RecordingSession()
        context.insert(session)

        let clip = VideoClip(fileName: "clip.mp4", filePath: "test/clip.mp4")
        clip.session = session
        context.insert(clip)
        try context.save()

        // Delete session
        context.delete(session)
        try context.save()

        let remainingClips = try context.fetch(FetchDescriptor<VideoClip>())
        #expect(remainingClips.isEmpty)
    }
}
