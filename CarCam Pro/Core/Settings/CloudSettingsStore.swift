import Foundation
import OSLog

/// Sync layer that roams user settings across a customer's iCloud-bound
/// devices via `NSUbiquitousKeyValueStore` (iCloud Key-Value Store).
///
/// Design:
///   • **Dual-write.** Every setting write lands on BOTH `UserDefaults`
///     (fast local reads, works offline, survives iCloud sign-out) and
///     `NSUbiquitousKeyValueStore` (roams across devices + survives
///     app reinstall on the same Apple ID).
///   • **UserDefaults is authoritative for reads.** The `AppSettings`
///     getters don't change; they always consult the local cache.
///   • **iCloud is authoritative for external updates.** When another
///     device writes and Apple pushes us
///     `NSUbiquitousKeyValueStore.didChangeExternallyNotification`, we
///     merge the changed keys into `UserDefaults` and invoke the
///     `onExternalChange` handler so downstream services
///     (`SettingsCoordinator`, `PoliceDetectionSystem`, etc.) can
///     re-apply their side-effects.
///   • **No silent data loss.** If the user turns off iCloud or we
///     hit the 1 MB quota, local `UserDefaults` still works fine.
///     `synchronize()` returns `false` but we don't treat that as an
///     error; the next successful write will re-sync the queued blob.
///
/// Thread safety: methods are `nonisolated` and safe to call from any
/// context. Notification delivery happens on the main queue.
///
/// Keys mirror `AppSettings.Keys` exactly — never rename one without
/// thinking about customers whose iCloud blob already has the old key.
public final class CloudSettingsStore: @unchecked Sendable {

    /// The list of keys this store owns. Exposed so the dual-write helper
    /// can route only known settings into iCloud and ignore unrelated
    /// `UserDefaults` domains (analytics, feature flags, etc.).
    public static let managedKeys: Set<String> = [
        "resolution", "frameRate", "codec", "bitrateMultiplier",
        "audioEnabled", "selectedCamera", "segmentDuration",
        "storageCap", "autoExportToPhotos", "iCloudBackupEnabled",
        "incidentDetectionEnabled", "incidentSensitivity",
        "parkingSentryEnabled", "hardBrakeDetectionEnabled",
        "showSpeedOverlay", "showGPSOverlay", "showGForceOverlay",
        "watermarkEnabled", "watermarkText", "autoStartOnLaunch",
        "dimDisplayWhileRecording", "allowThermalThrottling",
        "hapticsEnabled", "policeDetectionEnabled",
        "detectionAudioEnabled",
    ]

    nonisolated public static let shared = CloudSettingsStore()

    private let kvs: NSUbiquitousKeyValueStore
    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "pro.carcam", category: "cloud-settings")
    private let notificationCenter: NotificationCenter
    private var observer: NSObjectProtocol?
    private let changeHandlers = ChangeHandlerBag()

    /// Injectable init for tests. In production use `.shared`.
    nonisolated public init(
        kvs: NSUbiquitousKeyValueStore = .default,
        defaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default
    ) {
        self.kvs = kvs
        self.defaults = defaults
        self.notificationCenter = notificationCenter
    }

    deinit {
        if let observer {
            notificationCenter.removeObserver(observer)
        }
    }

    // MARK: - Lifecycle

    /// Call once at app launch (from `DependencyContainer.configure(...)`).
    ///
    /// On first launch with a pre-existing iCloud blob, this copies cloud
    /// values into the local `UserDefaults` BEFORE any `AppSettings`
    /// getter fires — so the app boots with the user's roamed
    /// preferences, not the built-in defaults.
    ///
    /// Also arms the external-change observer so subsequent remote edits
    /// arrive while the app is running.
    public func bootstrap(onExternalChange: @escaping @Sendable ([String]) -> Void) {
        // Ask iCloud to publish whatever it has. No-op if the user isn't
        // signed in; harmless if they are.
        kvs.synchronize()

        // Merge iCloud → local for every managed key the cloud actually
        // has a value for. This loop only runs on keys present in the
        // cloud dictionary, so fresh installs don't blow away local
        // defaults with nil-typed "empty" values.
        mergeCloudIntoDefaults(changedKeys: nil)

        // Arm the observer. Apple fires this notification on the main
        // queue when another device writes + pushes a change.
        observer = notificationCenter.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kvs,
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            let keys = (note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]) ?? []
            let reason = note.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
            self.logger.info("iCloud KVS external change: \(keys.count) key(s), reason=\(String(describing: reason))")
            let applied = self.mergeCloudIntoDefaults(changedKeys: Set(keys))
            if !applied.isEmpty {
                onExternalChange(applied)
                self.changeHandlers.fire(applied)
            }
        }

        changeHandlers.add(onExternalChange)
    }

    /// Register an additional handler for remote-change events. Useful for
    /// scoped observers (e.g. a single viewmodel) without teaching
    /// `DependencyContainer` about them.
    public func onExternalChange(_ handler: @escaping @Sendable ([String]) -> Void) {
        changeHandlers.add(handler)
    }

    // MARK: - Dual-write API

    /// Write-through setter. Call this from every `AppSettings` property
    /// setter — it updates both the local cache and the iCloud blob.
    ///
    /// Type-erased so all `UserDefaults`-compatible property-list types
    /// (`Bool`, `Int`, `Double`, `String`, `Data`, `Date`, arrays,
    /// dictionaries) flow through one path.
    ///
    /// When `suppressFanOut` is set (e.g. during an external-merge
    /// `AppSettings.notifyExternalChange` pass), the iCloud leg is
    /// skipped — we must not echo back values iCloud just pushed to us,
    /// or we create a feedback loop with other devices on the same account.
    public func writeThrough(_ value: Any?, forKey key: String) {
        precondition(
            Self.managedKeys.contains(key),
            "CloudSettingsStore: key '\(key)' is not in managedKeys — add it to the list or don't route through this store."
        )
        if let value {
            defaults.set(value, forKey: key)
            if !Self.suppressFanOut {
                kvs.set(value, forKey: key)
            }
        } else {
            defaults.removeObject(forKey: key)
            if !Self.suppressFanOut {
                kvs.removeObject(forKey: key)
            }
        }
        // `synchronize` is advisory — iCloud will push within ~seconds
        // regardless. We still call it so debug builds see the latency
        // shrink, and so unit tests can assert "it was offered to the
        // store" without monkey-patching the notification.
        if !Self.suppressFanOut {
            kvs.synchronize()
        }
    }

    /// Process-wide flag used by `AppSettings.notifyExternalChange` to
    /// prevent the echo-write that would otherwise fire when the merge
    /// loop calls each setter with its unchanged value. Set → do work
    /// → reset in `defer`; never leave it on across an async boundary.
    ///
    /// Marked `nonisolated(unsafe)` because merges run exclusively on the
    /// main queue (iCloud notifications are main-queue-delivered), so the
    /// flag is effectively single-threaded in practice.
    nonisolated(unsafe) public static var suppressFanOut: Bool = false

    // MARK: - Internals

    /// Copy every managed key that iCloud currently has a value for into
    /// `UserDefaults`. Returns the list of keys actually mutated so the
    /// caller can re-fire side-effects selectively.
    @discardableResult
    private func mergeCloudIntoDefaults(changedKeys: Set<String>?) -> [String] {
        let keysToConsider = changedKeys.map(Array.init) ?? Array(Self.managedKeys)
        var changed: [String] = []
        for key in keysToConsider where Self.managedKeys.contains(key) {
            guard let cloudValue = kvs.object(forKey: key) else { continue }
            let localValue = defaults.object(forKey: key)
            if !valuesMatch(localValue, cloudValue) {
                defaults.set(cloudValue, forKey: key)
                changed.append(key)
            }
        }
        return changed
    }

    /// Property-list-aware equality. NSNumber/Bool/String/Data/Date/NSArray/NSDictionary
    /// all conform to `NSObject`, so `isEqual:` is the safe cross-type
    /// comparison. `nil` on either side means "treat as different".
    private func valuesMatch(_ lhs: Any?, _ rhs: Any?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return true
        case (nil, _), (_, nil): return false
        case let (l as NSObject, r as NSObject): return l.isEqual(r)
        default: return false
        }
    }
}

// MARK: - Change-handler bag

/// Tiny wrapper that lets multiple listeners subscribe to the same cloud
/// change stream. The bag itself is thread-safe via an `NSLock` — we see
/// cloud notifications on the main queue but subscribers may register
/// from background contexts during app boot.
private final class ChangeHandlerBag: @unchecked Sendable {
    private let lock = NSLock()
    private var handlers: [@Sendable ([String]) -> Void] = []

    func add(_ handler: @escaping @Sendable ([String]) -> Void) {
        lock.lock(); defer { lock.unlock() }
        handlers.append(handler)
    }

    func fire(_ keys: [String]) {
        lock.lock()
        let snapshot = handlers
        lock.unlock()
        for handler in snapshot { handler(keys) }
    }
}
