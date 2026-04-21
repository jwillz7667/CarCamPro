import Foundation
import AVFoundation
import OSLog

/// Stitches every on-disk segment of a `RecordingSession` into a single
/// playable `AVPlayerItem` backed by an `AVMutableComposition`.
///
/// Why: a recording session is chopped into N short segments (default 60 s)
/// for durability — if the app crashes only the in-flight segment is lost.
/// But when the user taps a trip in the Trips tab they expect a single
/// continuous timeline they can scrub through, not a list of 60-second
/// clips. `SessionPlaybackComposition` builds that timeline lazily at
/// playback time, no re-encoding, no extra disk usage.
///
/// Also exposes per-clip start offsets so the playback UI can render a
/// marker strip that jumps the scrubber to a specific segment / locked
/// incident.
struct SessionPlaybackComposition {
    struct ClipCue: Identifiable, Hashable {
        let id: UUID
        let clipID: UUID
        let startOffset: TimeInterval   // where this clip starts in the composition timeline
        let duration: TimeInterval
        let isProtected: Bool
        let hasIncident: Bool
        let thumbnailURL: URL?
    }

    let playerItem: AVPlayerItem
    let totalDuration: TimeInterval
    let cues: [ClipCue]

    /// Build a composition for the given clips (must already be sorted by
    /// `startDate`). Missing files on disk are skipped — the UI renders
    /// partial playback rather than failing outright. Returns `nil` if
    /// every clip is missing.
    @MainActor
    static func build(clips: [VideoClip]) async -> SessionPlaybackComposition? {
        let composition = AVMutableComposition()
        guard
            let videoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        else { return nil }

        // Audio track is optional — we still want video-only playback if the
        // session was recorded with audio disabled.
        let audioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )

        var cues: [ClipCue] = []
        var cursor = CMTime.zero

        for clip in clips {
            let url = clip.fileURL
            guard FileManager.default.fileExists(atPath: url.path) else {
                AppLogger.ui.notice("Playback composition: skipping missing clip \(clip.fileName)")
                continue
            }

            let asset = AVURLAsset(url: url, options: [
                AVURLAssetPreferPreciseDurationAndTimingKey: true
            ])

            // Load tracks async (Swift 6 requires the new async loader for
            // `.tracks` on AVURLAsset).
            let videoTracks = try? await asset.loadTracks(withMediaType: .video)
            guard let assetVideoTrack = videoTracks?.first else { continue }

            let duration = (try? await asset.load(.duration)) ?? .zero
            guard duration.seconds > 0 else { continue }

            let range = CMTimeRange(start: .zero, duration: duration)
            do {
                try videoTrack.insertTimeRange(range, of: assetVideoTrack, at: cursor)
                // Preserve per-asset preferred transform (camera-orientation
                // bake-in). Without this the stitched track plays sideways.
                if let pt = try? await assetVideoTrack.load(.preferredTransform) {
                    videoTrack.preferredTransform = pt
                }
            } catch {
                AppLogger.ui.error(
                    "Playback composition: video insert failed for \(clip.fileName): \(error.localizedDescription)"
                )
                continue
            }

            if let audioTrack {
                let assetAudioTracks = try? await asset.loadTracks(withMediaType: .audio)
                if let assetAudioTrack = assetAudioTracks?.first {
                    try? audioTrack.insertTimeRange(range, of: assetAudioTrack, at: cursor)
                }
            }

            cues.append(ClipCue(
                id: clip.id,
                clipID: clip.id,
                startOffset: cursor.seconds,
                duration: duration.seconds,
                isProtected: clip.isProtected,
                hasIncident: clip.hasIncident,
                thumbnailURL: clip.thumbnailURL
            ))

            cursor = CMTimeAdd(cursor, duration)
        }

        guard !cues.isEmpty else { return nil }

        let item = AVPlayerItem(asset: composition)
        return SessionPlaybackComposition(
            playerItem: item,
            totalDuration: cursor.seconds,
            cues: cues
        )
    }
}
