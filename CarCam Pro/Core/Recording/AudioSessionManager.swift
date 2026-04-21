import AVFoundation
import OSLog

/// Owns the app's `AVAudioSession` lifecycle for recording.
///
/// Responsibilities:
///   • **Activation.** Switches the shared session into `.playAndRecord`
///     with `.mixWithOthers + .allowBluetoothHFP + .allowBluetoothA2DP +
///     .defaultToSpeaker`. This combination is what makes dashcam recording
///     survive background mode and coexist with Maps / music / calls.
///   • **Interruption recovery.** A phone call, Siri, Smart Stack timer, or
///     another capture app will fire an `.interruptionNotification`. We
///     pause writers on `.began`, reactivate the session on `.ended`, and
///     invoke a caller-provided resume handler so `RecordingEngine` can
///     cut a new segment instead of appending across the gap (which would
///     misalign A/V timestamps).
///   • **Route changes.** Headphones / Bluetooth / CarPlay unplug events
///     fire `.routeChangeNotification`. We log + surface the reason so the
///     engine can react (e.g. mute audio when the new route is `.none`).
///   • **Media-services reset.** `AVAudioSessionMediaServicesWereResetNotification`
///     is a rare but fatal signal — audio+video pipelines must be rebuilt.
///     We forward it via the reset handler.
///
/// Thread safety: public API is `@MainActor`; internal notification
/// callbacks hop back to main before mutating state. Safe to call from
/// any view or coordinator.
@MainActor
final class AudioSessionManager {
    static let shared = AudioSessionManager()

    /// Fires when a recording-critical interruption begins. Recording
    /// engines should pause writers.
    var onInterruptionBegan: (@MainActor () -> Void)?
    /// Fires when an interruption ends. Engines should cut a fresh
    /// segment and resume.
    var onInterruptionEnded: (@MainActor () -> Void)?
    /// Fires on `mediaServicesWereReset`. Engines must fully re-initialize.
    var onMediaServicesReset: (@MainActor () -> Void)?
    /// Fires on route change. `reason` is the raw `AVAudioSession.RouteChangeReason`
    /// for logging; most callers ignore the payload.
    var onRouteChanged: (@MainActor (AVAudioSession.RouteChangeReason) -> Void)?

    private(set) var isActive = false
    private var observers: [NSObjectProtocol] = []

    private init() {}

    // MARK: - Activate / deactivate

    /// Configure + activate the session for recording.
    ///
    /// `allowAudioCapture: true` means the recording engine will write an
    /// audio track. When the user has disabled audio (or we're running
    /// parking-sentry mode which records silent clips), pass `false` —
    /// we'll still use `.playAndRecord` (required for background capture)
    /// but ignore any microphone routing concerns.
    func activate(allowAudioCapture: Bool) throws {
        let session = AVAudioSession.sharedInstance()
        var options: AVAudioSession.CategoryOptions = [
            .mixWithOthers,                   // coexist with Maps / music
            .allowBluetoothHFP,               // BT headsets (hands-free profile)
            .allowBluetoothA2DP,              // BT speakers
            .defaultToSpeaker,                // phone speaker, not ear piece
        ]
        if !allowAudioCapture {
            // No microphone routing — still .playAndRecord so background
            // capture works, but we hint the OS we're play-dominant.
            options.insert(.duckOthers)
        }

        try session.setCategory(
            .playAndRecord,
            mode: .videoRecording,
            options: options
        )

        // `.videoRecording` mode already biases towards the far-field
        // mic if available, but some devices need an explicit hint.
        try session.setPreferredSampleRate(44_100)

        try session.setActive(true, options: [])
        isActive = true

        if observers.isEmpty { installObservers(on: session) }
        AppLogger.recording.info("AudioSession activated (.playAndRecord, audioCapture=\(allowAudioCapture))")
    }

    /// Deactivate the session. `.notifyOthersOnDeactivation` lets Music /
    /// Podcasts resume after we let go.
    func deactivate() {
        guard isActive else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(
                false,
                options: [.notifyOthersOnDeactivation]
            )
        } catch {
            AppLogger.recording.warning(
                "AudioSession deactivate failed: \(error.localizedDescription)"
            )
        }
        isActive = false
        AppLogger.recording.info("AudioSession deactivated")
    }

    // MARK: - Notifications

    private func installObservers(on session: AVAudioSession) {
        let center = NotificationCenter.default

        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session,
            queue: .main
        ) { [weak self] note in
            Task { @MainActor [weak self] in
                self?.handleInterruption(note)
            }
        })

        observers.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: session,
            queue: .main
        ) { [weak self] note in
            Task { @MainActor [weak self] in
                self?.handleRouteChange(note)
            }
        })

        observers.append(center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: session,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleMediaServicesReset()
            }
        })
    }

    private func handleInterruption(_ note: Notification) {
        guard let rawType = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else {
            return
        }
        switch type {
        case .began:
            AppLogger.recording.notice("AudioSession interruption began")
            isActive = false
            onInterruptionBegan?()
        case .ended:
            AppLogger.recording.notice("AudioSession interruption ended")
            // Try to reactivate. If the OS denies (e.g., call still active
            // via CarPlay), the caller's onInterruptionEnded will still run
            // and the next recording start will re-try activation.
            do {
                try AVAudioSession.sharedInstance().setActive(true, options: [])
                isActive = true
            } catch {
                AppLogger.recording.error(
                    "AudioSession reactivation failed: \(error.localizedDescription)"
                )
            }
            onInterruptionEnded?()
        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ note: Notification) {
        guard let rawReason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason) else {
            return
        }
        AppLogger.recording.info("AudioSession route change: \(String(describing: reason))")
        onRouteChanged?(reason)
    }

    private func handleMediaServicesReset() {
        AppLogger.recording.error("AudioSession media services were reset — full re-init required")
        isActive = false
        onMediaServicesReset?()
    }
}
