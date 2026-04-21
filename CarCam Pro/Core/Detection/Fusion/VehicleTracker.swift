import Foundation
import CoreGraphics

/// Matches current-frame detections to existing tracks by IoU, and manages
/// the track pool (evicts tracks not seen in `trackTimeoutSeconds`).
final class VehicleTracker: @unchecked Sendable {
    private var tracks: [UUID: VehicleTrack] = [:]
    private let iouThreshold: CGFloat = 0.3
    private let trackTimeoutSeconds: TimeInterval = 1.5

    /// Match incoming detections to tracks (creating new ones as needed) and
    /// evict tracks stale beyond the timeout.
    func update(
        detections: [VehicleDetection],
        now: TimeInterval
    ) -> [(VehicleTrack, VehicleDetection)] {
        var matched: [(VehicleTrack, VehicleDetection)] = []
        var usedTrackIDs = Set<UUID>()

        for det in detections {
            if let track = bestMatch(for: det.boundingBox, excluding: usedTrackIDs) {
                track.update(detection: det)
                matched.append((track, det))
                usedTrackIDs.insert(track.id)
            } else {
                let newTrack = VehicleTrack(detection: det)
                tracks[newTrack.id] = newTrack
                matched.append((newTrack, det))
                usedTrackIDs.insert(newTrack.id)
            }
        }

        let stale = tracks.values.filter { now - $0.lastSeen > trackTimeoutSeconds }
        for t in stale { tracks.removeValue(forKey: t.id) }

        return matched
    }

    private func bestMatch(for bbox: CGRect, excluding used: Set<UUID>) -> VehicleTrack? {
        var best: VehicleTrack?
        var bestIoU: CGFloat = iouThreshold
        for track in tracks.values where !used.contains(track.id) {
            let i = iou(bbox, track.lastBBox)
            if i > bestIoU {
                bestIoU = i
                best = track
            }
        }
        return best
    }

    private func iou(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let inter = a.intersection(b)
        if inter.isNull || inter.isEmpty { return 0 }
        let interArea = inter.width * inter.height
        let unionArea = a.width * a.height + b.width * b.height - interArea
        return interArea / max(unionArea, .leastNonzeroMagnitude)
    }

    func allTracks() -> [VehicleTrack] { Array(tracks.values) }
}
