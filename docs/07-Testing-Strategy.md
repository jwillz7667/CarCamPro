# Testing Strategy
## DashCam Pro

**Version:** 1.0
**Date:** April 12, 2026

---

## 1. Testing Pyramid

```
         ┌──────────┐
         │  Manual   │  ← Real-device, in-car testing
         │  E2E      │     (small number, high value)
        ─┼──────────┼─
         │  UI Tests │  ← XCUITest automated flows
         │           │     (medium number)
       ──┼──────────┼──
         │  Integration │ ← Service interactions
         │  Tests       │    (medium number)
      ───┼──────────────┼───
         │  Unit Tests     │ ← Individual services
         │                 │    (large number, fast)
      ───┴─────────────────┴───
```

---

## 2. Unit Tests

### 2.1 What to Test

**ThermalMonitor / AdaptiveQualityController**
- Verify correct quality tier for each thermal state
- Verify recovery delay (60s before stepping back up)
- Verify display dimming triggers at correct tier
- Verify no quality change when thermals disabled in settings
- Mock: `ProcessInfo.thermalState` via protocol wrapper

**IncidentDetector**
- Verify detection at each sensitivity threshold
- Verify debounce: second event within 10s is ignored
- Verify no false positives from normal driving vibrations (provide sample data)
- Verify g-force calculation from raw (x, y, z) accelerometer data
- Mock: `CMMotionManager` via protocol wrapper

**StorageManager**
- Verify FIFO deletion order (oldest first)
- Verify protected clips are skipped during FIFO
- Verify correct storage calculation
- Verify behavior when all clips are protected (warning, no deletion)
- Verify behavior at exact cap boundary
- Mock: File system via `FileManagerProtocol`

**SegmentManager**
- Verify segment rotation at correct duration
- Verify segment numbering is sequential
- Verify file naming convention
- Verify metadata saved after each rotation
- Mock: `AVAssetWriter` via protocol wrapper

**RecordingEngine State Machine**
- Verify all valid state transitions
- Verify invalid transitions throw errors
- Verify error state → reset → idle
- Verify state consistency after interruption

**Settings / AppSettings**
- Verify defaults for each device class
- Verify persistence round-trip (save → load)
- Verify settings changes propagate to active services

### 2.2 Testing Approach

```swift
// Example: IncidentDetector unit test
final class IncidentDetectorTests: XCTestCase {
    var sut: IncidentDetector!
    var mockMotionManager: MockMotionManager!
    
    override func setUp() {
        mockMotionManager = MockMotionManager()
        sut = IncidentDetector(motionManager: mockMotionManager)
    }
    
    func testDetectsHardBrakingAtMediumSensitivity() async {
        await sut.startDetecting(sensitivity: .medium)
        
        let expectation = expectation(description: "Incident detected")
        let cancellable = sut.incidentPublisher.sink { event in
            XCTAssertEqual(event.severity, .moderate)
            XCTAssertGreaterThan(event.peakGForce, 3.0)
            expectation.fulfill()
        }
        
        // Simulate 4g deceleration
        mockMotionManager.simulateAcceleration(x: 0, y: 0, z: -4.0)
        
        await fulfillment(of: [expectation], timeout: 1.0)
        cancellable.cancel()
    }
    
    func testIgnoresNormalDrivingVibrations() async {
        await sut.startDetecting(sensitivity: .medium)
        
        var incidentCount = 0
        let cancellable = sut.incidentPublisher.sink { _ in
            incidentCount += 1
        }
        
        // Simulate normal driving: small vibrations over 10 seconds
        for _ in 0..<100 {
            let randomG = Double.random(in: -0.3...0.3)
            mockMotionManager.simulateAcceleration(x: randomG, y: randomG, z: -1.0 + randomG)
        }
        
        try? await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(incidentCount, 0, "Should not detect incidents from normal vibrations")
        cancellable.cancel()
    }
}
```

### 2.3 Coverage Targets

| Layer | Target | Rationale |
|---|---|---|
| Core/Thermal/ | 90%+ | Safety-critical — wrong thermal response = thermal shutdown |
| Core/Incident/ | 90%+ | Correctness-critical — false positives = annoyed users |
| Core/Storage/ | 85%+ | Data-critical — wrong deletion = lost footage |
| Core/Recording/ | 80%+ | Complex but partially hardware-dependent |
| Core/Camera/ | 60% | Heavy hardware dependency, hard to mock completely |
| Features/ (ViewModels) | 70%+ | Business logic in VMs should be tested |
| Features/ (Views) | Covered by UI tests | SwiftUI views tested via XCUITest |

---

## 3. Integration Tests

These test how services work together without mocking.

**Recording + Storage integration:** Start a recording with a 5-second segment duration and a 50 KB storage cap. Verify segments rotate, FIFO kicks in, and storage stays within cap.

**Recording + Thermal integration:** Start recording, inject a thermal state change, verify the CameraService actually received updated configuration parameters.

**Recording + Incident integration:** Start recording, inject a simulated g-force spike via mock motion manager, verify the correct segments get marked as protected in SwiftData.

**Background + Recording integration:** Start recording, simulate `scenePhase` change to `.background`, verify the `AVCaptureSession` is still running after 30 seconds.

---

## 4. UI Tests (XCUITest)

### 4.1 Automated Flows

**Onboarding flow:** Launch fresh (reset state) → verify each onboarding screen appears → tap through → verify landing on recording screen.

**Record and stop:** Tap record → verify timer appears and counts → wait 5 seconds → tap stop → verify clip appears in library.

**Library browse and play:** Navigate to library → tap first clip → verify video player appears → tap play → verify video is playing (check for player controls).

**Settings persistence:** Navigate to settings → change resolution to 720p → kill app → relaunch → navigate to settings → verify 720p is still selected.

**Delete clip:** Navigate to library → long-press clip → tap delete → confirm → verify clip is removed from grid.

### 4.2 Accessibility Testing

All UI tests should also verify accessibility labels are present, VoiceOver can navigate the recording screen, the record button has a clear accessibility label ("Start recording" / "Stop recording"), and dynamic type support doesn't break layouts at XXL sizes.

---

## 5. Manual Testing Protocol

### 5.1 In-Car Testing Checklist

This MUST be done before App Store submission. Have a passenger (not the driver) run these tests.

**Basic recording test:** Mount phone on dashboard, start recording, drive for 15 minutes on a mix of highway and city streets, stop recording, verify all segments saved correctly, verify video quality is acceptable (sharp, correct orientation, smooth).

**Background recording test:** Start recording, switch to Apple Maps and navigate somewhere, drive for 20 minutes, switch back to app, verify recording was continuous with no gaps.

**Phone call test:** Start recording, have someone call you, answer for 30 seconds, hang up, verify recording resumed.

**Thermal test (warm day):** On a day above 80°F, mount phone in direct sunlight on dashboard, start recording, observe for 45+ minutes, note when/if thermal throttling engages, verify app never crashes or stops recording.

**Incident detection test (PARKED ONLY):** While parked, start recording, firmly tap/shake the phone mount to simulate a jolt, verify incident detection fires, verify the clip is marked as protected.

**Storage cap test:** Set storage cap to 100 MB, record continuously, verify old clips are deleted automatically when cap is hit, verify protected clips survive.

### 5.2 Device Testing Matrix

| Device | iOS Version | Priority | Status |
|---|---|---|---|
| iPhone 11 | iOS 16.x | HIGH (minimum device) | ⏳ |
| iPhone 12 | iOS 17.x | MEDIUM | ⏳ |
| iPhone 13 Pro | iOS 17.x | HIGH (target device) | ⏳ |
| iPhone 14 | iOS 17.x | MEDIUM | ⏳ |
| iPhone 15 Pro | iOS 18.x | HIGH (latest) | ⏳ |
| iPhone SE 3 | iOS 16.x | MEDIUM (small screen) | ⏳ |

---

## 6. Performance Benchmarks

Run these with Instruments and record results before each release.

| Metric | Target | Tool |
|---|---|---|
| App launch to camera preview | < 2 seconds | Time Profiler |
| Recording start latency | < 500ms from button tap | Time Profiler |
| Segment rotation gap | 0 dropped frames | Custom logging |
| Memory usage while recording | < 150 MB | Allocations |
| CPU usage while recording (1080p) | < 30% average | Activity Monitor |
| Battery drain per hour (1080p, screen off) | < 15% | Energy Log |
| Incident detection latency | < 200ms from impact | Custom logging |
| Thermal throttle response time | < 2 seconds from state change | Custom logging |

---

## 7. Crash & Stability Monitoring

For TestFlight and production, rely on Xcode Organizer crash reports (free, built-in). The hidden Developer Stats screen logs recording session outcomes (completed, interrupted, crashed, thermal shutdown). Before considering third-party crash reporting, exhaust Apple's built-in tools — they're surprisingly good and add zero dependencies.

---

## 8. Pre-Submission QA Checklist

Before submitting to App Store, verify all of the following:

- All unit tests pass (0 failures)
- All UI tests pass (0 failures)
- No memory leaks in Instruments Leaks template (1-hour recording)
- No crashes in 10 consecutive recording sessions
- Background recording works for 1+ hour on 3 different devices
- Thermal management prevents shutdown in 1-hour session
- Incident detection has < 10% false positive rate
- Storage cap enforcement is accurate (within 1% of cap)
- All permissions gracefully handle denial
- App works correctly with no network connection
- Dark mode looks correct on all screens
- Supports Dynamic Type (accessibility)
- VoiceOver can navigate all screens
- App Store screenshots are accurate to final build
- Privacy nutrition labels match actual data usage
