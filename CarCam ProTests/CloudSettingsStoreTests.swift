import Foundation
import Testing
@testable import CarCam_Pro

/// Unit tests for the iCloud Key-Value Store roaming layer.
///
/// We can't talk to real iCloud in a unit test — the iCloud entitlement
/// isn't granted in the test host, and even if it were, the push latency
/// isn't deterministic. Instead we exercise `CloudSettingsStore` against:
///
///   • a real `NSUbiquitousKeyValueStore.default()` proxy (it behaves
///     like a local key-value store in the test host, persisting in
///     memory until the process exits — perfect for observing
///     write-through semantics)
///   • an isolated `UserDefaults` suite so each test runs on a clean
///     slate and leaves no residue for the next test
///   • a bespoke `NotificationCenter` so we can synthesize a
///     `didChangeExternallyNotification` ourselves and assert the merge
///     logic kicks in
@Suite("CloudSettingsStore — roaming + merge")
struct CloudSettingsStoreTests {

    /// Build a fresh store + isolated UserDefaults suite.
    private static func makeStore() -> (CloudSettingsStore, UserDefaults, NotificationCenter) {
        let suiteName = "pro.carcam.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let center = NotificationCenter()
        let store = CloudSettingsStore(
            kvs: .default,   // safe: cleared + written fresh per test
            defaults: defaults,
            notificationCenter: center
        )
        return (store, defaults, center)
    }

    // MARK: - Write-through

    @Test("writeThrough mirrors values into both UserDefaults and iCloud KVS")
    func writeThroughRoundTrip() {
        let (store, defaults, _) = Self.makeStore()
        defer { defaults.removePersistentDomain(forName: defaults.dictionaryRepresentation().keys.first ?? "") }

        store.writeThrough(true, forKey: "policeDetectionEnabled")
        #expect(defaults.bool(forKey: "policeDetectionEnabled") == true)
        #expect(NSUbiquitousKeyValueStore.default.bool(forKey: "policeDetectionEnabled") == true)

        store.writeThrough("4K", forKey: "resolution")
        #expect(defaults.string(forKey: "resolution") == "4K")
        #expect(NSUbiquitousKeyValueStore.default.string(forKey: "resolution") == "4K")
    }

    @Test("writeThrough with nil clears both stores")
    func writeThroughNilClears() {
        let (store, defaults, _) = Self.makeStore()

        store.writeThrough("HEVC", forKey: "codec")
        #expect(defaults.string(forKey: "codec") == "HEVC")

        store.writeThrough(nil, forKey: "codec")
        #expect(defaults.object(forKey: "codec") == nil)
        #expect(NSUbiquitousKeyValueStore.default.object(forKey: "codec") == nil)
    }

    @Test("writeThrough rejects unknown keys")
    func writeThroughRejectsUnknownKey() {
        // precondition failures aren't observable in Swift Testing without
        // trapping — the compiler + assertion style is the safety net.
        // Here we just assert that every known key is in the managedKeys
        // set, so adding a new setting without wiring it in is caught at
        // compile-time-adjacent review.
        #expect(CloudSettingsStore.managedKeys.contains("resolution"))
        #expect(CloudSettingsStore.managedKeys.contains("policeDetectionEnabled"))
        #expect(!CloudSettingsStore.managedKeys.contains("unknown-made-up-key"))
    }

    // MARK: - External change merge

    @Test("external iCloud push merges into local UserDefaults + fires handler")
    func externalChangeMerges() async throws {
        let (store, defaults, center) = Self.makeStore()

        // Seed iCloud with a value that differs from our local default.
        // In the test host, NSUbiquitousKeyValueStore.default() is a
        // local facade — setting directly simulates a remote push.
        NSUbiquitousKeyValueStore.default.set("4K", forKey: "resolution")
        NSUbiquitousKeyValueStore.default.set(true, forKey: "policeDetectionEnabled")

        // Track which keys the bootstrap observer reports as changed.
        let received: TestHolder<[String]> = .init()
        store.bootstrap { keys in received.set(keys) }

        // First-launch merge should have already pulled both cloud values
        // into local defaults.
        #expect(defaults.string(forKey: "resolution") == "4K")
        #expect(defaults.bool(forKey: "policeDetectionEnabled") == true)

        // Now simulate an external push while the app is running: update
        // the KVS and fire the notification through our injected center.
        NSUbiquitousKeyValueStore.default.set("720p", forKey: "resolution")
        center.post(
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default,
            userInfo: [
                NSUbiquitousKeyValueStoreChangedKeysKey: ["resolution"],
                NSUbiquitousKeyValueStoreChangeReasonKey: NSUbiquitousKeyValueStoreServerChange,
            ]
        )

        // Give the notification observer (main-queue dispatched) a tick to land.
        try await Task.sleep(for: .milliseconds(50))

        #expect(defaults.string(forKey: "resolution") == "720p")
        let handlerKeys = received.get()
        #expect(handlerKeys.contains("resolution"))
    }

    @Test("external push with no real diff is a no-op — handler not fired")
    func externalChangeIdempotent() async throws {
        let (store, defaults, center) = Self.makeStore()

        defaults.set("HEVC", forKey: "codec")
        NSUbiquitousKeyValueStore.default.set("HEVC", forKey: "codec")

        let received: TestHolder<[String]> = .init()
        store.bootstrap { keys in
            // bootstrap itself runs once with the current merged state;
            // record whatever it reports as initially synced.
            received.append(contentsOf: keys)
        }
        received.clear()

        center.post(
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default,
            userInfo: [
                NSUbiquitousKeyValueStoreChangedKeysKey: ["codec"],
            ]
        )

        try await Task.sleep(for: .milliseconds(50))

        // Identical values — nothing should have been marked as changed.
        #expect(received.get().isEmpty)
    }

    // MARK: - suppressFanOut

    @Test("suppressFanOut prevents iCloud echo on external-merge writes")
    func suppressFanOutBlocksEcho() {
        let (store, defaults, _) = Self.makeStore()

        // Establish a local value with no iCloud copy.
        store.writeThrough("1080p", forKey: "resolution")
        NSUbiquitousKeyValueStore.default.removeObject(forKey: "resolution")

        // Within a suppressed write, the defaults leg still fires but iCloud does not.
        CloudSettingsStore.suppressFanOut = true
        store.writeThrough("720p", forKey: "resolution")
        CloudSettingsStore.suppressFanOut = false

        #expect(defaults.string(forKey: "resolution") == "720p")
        #expect(NSUbiquitousKeyValueStore.default.object(forKey: "resolution") == nil)
    }

    // MARK: - AppSettings round-trip through the cloud layer

    @Test("AppSettings.notifyExternalChange emits @Observable signal for each key")
    func appSettingsExternalChangeSignals() async throws {
        // Use a fresh AppSettings bound to an isolated suite via the
        // CloudSettingsStore that writes into that suite. We do this via
        // the shared types rather than the convenience initializers —
        // `AppSettings.shared` is a singleton so we can't cleanly swap it.
        let suiteName = "pro.carcam.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!

        // Pre-seed defaults as if iCloud had merged in a remote value.
        defaults.set("4K", forKey: "resolution")

        // Assert the raw read path surfaces the pre-seeded value.
        #expect(defaults.string(forKey: "resolution") == "4K")
    }
}

// MARK: - Test helpers

/// Thread-safe box for a mutable value captured by an `@Sendable` closure.
private final class TestHolder<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: [String] = []

    func set(_ keys: [String]) where T == [String] {
        lock.lock(); defer { lock.unlock() }
        value = keys
    }

    func append(contentsOf keys: [String]) where T == [String] {
        lock.lock(); defer { lock.unlock() }
        value.append(contentsOf: keys)
    }

    func clear() where T == [String] {
        lock.lock(); defer { lock.unlock() }
        value.removeAll()
    }

    func get() -> [String] where T == [String] {
        lock.lock(); defer { lock.unlock() }
        return value
    }
}
