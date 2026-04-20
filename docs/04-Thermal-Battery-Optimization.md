# Thermal & Battery Optimization Strategy
## DashCam Pro

**Version:** 1.0
**Date:** April 12, 2026

---

## 1. Why This Is The #1 Technical Challenge

Every competing dashcam app on the App Store has the same 1-star reviews: "Phone overheated after 20 minutes" and "Drains battery even when plugged in." This document defines the engineering strategy that makes DashCam Pro the first app to solve this reliably.

The physics are simple: continuous video encoding generates heat. A phone mounted on a dashboard in a car may also be exposed to sunlight and warm cabin air. We cannot change physics, but we can be dramatically smarter about how much work we ask the GPU/CPU to do.

---

## 2. Thermal State Monitoring

iOS exposes four thermal states via `ProcessInfo.ThermalState`. Our `ThermalMonitor` service observes the `.thermalStateDidChangeNotification` and publishes state changes.

### Thermal Tiers & Response

**Tier 0 — Nominal (.nominal)**
Everything runs at full configured quality. No intervention needed.
- Resolution: User setting (default 1080p)
- Frame rate: User setting (default 30fps)
- Bitrate: Full (5 Mbps for 1080p HEVC)
- Display: Normal brightness
- Action: None

**Tier 1 — Fair (.fair)**
Device is getting warm. Begin proactive mitigation before the user notices.
- Resolution: Maintain current
- Frame rate: Drop to 24fps if currently at 30fps
- Bitrate: Reduce by 20%
- Display: Dim to 30% if `dimDisplayWhileRecording` is enabled
- Flash/torch: Disable if active
- Action: Log event, no user notification

**Tier 2 — Serious (.serious)**
Device is hot. Aggressive mitigation to prevent reaching critical.
- Resolution: Force 720p regardless of setting
- Frame rate: Force 24fps
- Bitrate: Reduce to 1.5 Mbps
- Display: Dim to minimum (but not off)
- CPU: Reduce Core Motion sampling rate from 60Hz to 10Hz
- GPS: Reduce location update frequency
- Action: Show subtle UI indicator ("Reducing quality to manage temperature"), log event

**Tier 3 — Critical (.critical)**
Device is about to throttle or shut down. Last resort to keep recording alive.
- Resolution: Force 720p
- Frame rate: Force 15fps
- Bitrate: Reduce to 800 Kbps
- Display: Turn off display entirely (recording continues)
- CPU: Pause incident detection temporarily
- GPS: Significant location changes only
- Action: Post notification ("Recording at minimum quality — device is hot. Consider moving phone out of direct sunlight."), vibrate alert, log event

### Recovery Behavior
When thermal state improves, quality is restored gradually (not instantly) to avoid thermal oscillation. The system waits 60 seconds at a lower thermal state before stepping quality back up one tier.

---

## 3. Encoding Optimization

### 3.1 HEVC (H.265) as Default

HEVC produces equivalent visual quality at 40-50% lower bitrate compared to H.264. On iPhone 11+, HEVC encoding is fully hardware-accelerated via the Apple Neural Engine / Video Encoder.

The difference: a 3-minute 1080p clip at H.264 is roughly 112 MB. The same clip at HEVC is roughly 56 MB. This means half the storage used, half the write I/O, and significantly less thermal output from encoding.

### 3.2 AVAssetWriter Configuration for Thermal Efficiency

```swift
// Key settings for thermal-efficient encoding
let videoSettings: [String: Any] = [
    AVVideoCodecKey: AVVideoCodecType.hevc,
    AVVideoWidthKey: resolution.dimensions.width,
    AVVideoHeightKey: resolution.dimensions.height,
    AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: currentBitrate,
        AVVideoExpectedSourceFrameRateKey: currentFrameRate,
        AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
        // CRITICAL: Allow frame reordering for better compression
        AVVideoAllowFrameReorderingKey: true,
        // Use hardware encoder
        AVVideoEncoderSpecificationKey: [
            kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder: true
        ],
        // B-frames for better compression at same quality
        AVVideoMaxKeyFrameIntervalKey: currentFrameRate * 2,
    ]
]
```

### 3.3 Frame Rate vs. Quality Trade-off

For dashcam use, 24fps is visually indistinguishable from 30fps for road footage. The encoding workload difference is significant — roughly 20% less GPU work. This is our first lever to pull when thermals increase.

At 15fps (critical thermal), footage is still perfectly usable for incident evidence. License plates, road conditions, and impact events are all clearly visible.

---

## 4. Battery Optimization

### 4.1 Power Budget

When a phone is plugged into a typical car USB port (5V/1A = 5W), the available power budget is approximately 5W input minus roughly 2W base system drain, leaving around 3W available for the app.

Camera capture + HEVC encoding at 1080p/30fps uses roughly 2-3W. This means the phone will approximately break even on battery when plugged in, or drain very slowly. At 720p/24fps, it draws approximately 1.5W, meaning the battery will slowly charge.

### 4.2 Display Management

The display is the single largest power consumer on an iPhone — roughly 1-2W depending on brightness. Since the user is driving (not looking at the phone), the display can be:
- Dimmed to minimum brightness after 30 seconds of no touch
- Turned off entirely via `UIApplication.shared.isIdleTimerDisabled = false` (let the system sleep the display while the app continues recording)

However, we keep the display alive during the first 10 seconds after recording starts so the user can confirm it's working. We also wake the display briefly for incident detection alerts.

### 4.3 GPS Optimization

Continuous GPS at full accuracy uses notable power. For a dashcam, we don't need sub-meter accuracy. The strategy is to use `kCLLocationAccuracyHundredMeters` during normal recording (sufficient for speed and general location), switch to `kCLLocationAccuracyBest` only when an incident is detected (to get precise coordinates for the incident), and use `distanceFilter: 10` to avoid processing micro-movements at stop lights.

### 4.4 Core Motion Optimization

The accelerometer for incident detection doesn't need high-frequency sampling during normal driving. We sample at 60Hz initially, then drop to 10Hz in serious thermal state. For incident detection, even 10Hz is sufficient — a car crash event lasts 100-300ms, which 10Hz captures easily. During the window surrounding an incident we temporarily increase to full rate for detailed g-force logging.

---

## 5. Hardware-Specific Considerations

### iPhone 11/12 (A13/A14)
These older supported devices have less thermal headroom. The app should default to 720p on these devices and be more aggressive about thermal tier responses (trigger Tier 1 response at lower temps).

### iPhone 13/14 (A15/A16)
Good thermal performance. 1080p default is fine. HEVC encoding is very efficient.

### iPhone 15/16 (A17/A18)
Excellent thermal performance. Can sustain 1080p/30fps for extended periods. 4K recording is viable for shorter sessions.

### Detection logic:
```swift
func recommendedDefaults() -> AppSettings {
    let chip = ProcessInfo.processInfo.processorDescription
    // Use device capability detection based on 
    // AVCaptureDevice supported formats
    if device.supportsSessionPreset(.hd4K3840x2160) {
        // Modern device — generous defaults
        return .init(resolution: .hd1080, frameRate: 30)
    } else {
        // Older device — conservative defaults
        return .init(resolution: .hd720, frameRate: 24)
    }
}
```

---

## 6. Real-World Testing Targets

| Scenario | Target |
|---|---|
| iPhone 13 Pro, 1080p/30, plugged in, 75°F ambient | 2+ hours without thermal shutdown |
| iPhone 13 Pro, 1080p/30, plugged in, 95°F ambient, direct sun | 1+ hour with adaptive throttling |
| iPhone 11, 720p/24, plugged in, 75°F | 2+ hours without thermal shutdown |
| iPhone 15, 1080p/30, on battery | 45+ minutes before 20% battery warning |
| Any device, background recording while using Maps | Recording never interrupted for 1+ hour |

### How to Test

Use Xcode's "Thermal State Override" in the debug navigator to simulate thermal states. For real-world testing, record in a parked car on a warm day (don't drive while testing). Use Instruments with the "Thermal State" and "Energy Log" profiling templates.

---

## 7. Monitoring & Telemetry (Internal)

During development and TestFlight, log these metrics to evaluate thermal strategy effectiveness:
- Time spent in each thermal tier per session
- Number of thermal tier transitions per session
- Whether the session completed without reaching `.critical`
- Average encoding bitrate over time
- Battery level delta over recording duration
- Number of background recording interruptions

Store these in a local SQLite database during TestFlight, reviewable via a hidden "Developer Stats" screen in settings (triple-tap the version number).
