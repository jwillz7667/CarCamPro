# UI/UX Wireframe Specifications
## DashCam Pro

**Version:** 1.0
**Date:** April 12, 2026

---

## 1. Design Principles

**Dark-first.** The app is used while driving, often at night. The entire UI is dark mode by default with high-contrast elements. No blinding white screens.

**Minimal cognitive load.** A driver glances at their phone for < 1 second. Every screen must communicate its state instantly. Large icons, bold status text, no tiny buttons.

**One-thumb operation.** All primary actions reachable with one thumb on a mounted phone. Record button is massive and always in the same place.

**Automotive-grade UI.** Inspired by Tesla/CarPlay interfaces — clean, dark, chunky touch targets (minimum 60pt), high contrast text.

---

## 2. App Navigation Structure

```
Tab Bar (3 tabs)
├── Record (default/home tab)
├── Library
└── Settings
```

No hamburger menus, no nested navigation deeper than 2 levels. Simple.

---

## 3. Screen Specifications

### 3.1 Recording Screen (Home Tab)

This is the primary screen — the app opens to this.

```
┌──────────────────────────────────┐
│ ■ 12:34                    ■ 87% │  ← iOS status bar
├──────────────────────────────────┤
│                                  │
│                                  │
│       LIVE CAMERA PREVIEW        │
│       (full bleed, edge-to       │
│        edge behind overlay)      │
│                                  │
│                                  │
│  ┌─────────────────────────────┐ │
│  │ ● REC  00:14:32   720p 24f │ │  ← Status bar overlay (top)
│  │ 🌡 WARM   💾 2.3/5.0 GB     │ │  ← Thermal + storage
│  └─────────────────────────────┘ │
│                                  │
│                                  │
│                                  │
│                                  │
│  ┌───┐                   ┌───┐  │
│  │ 🔇│                   │ 📷│  │  ← Mute toggle / Camera flip
│  └───┘                   └───┘  │
│                                  │
│           ┌─────────┐            │
│           │         │            │
│           │  ● REC  │            │  ← Giant record button (80pt)
│           │         │            │     Red = recording, White = idle
│           └─────────┘            │
│                                  │
├──────────────────────────────────┤
│   ◉ Record    📁 Library   ⚙ Set │  ← Tab bar
└──────────────────────────────────┘
```

**States:**

Idle state: Camera preview is live, record button is white/outlined, status bar shows "READY" with storage available, no recording indicator.

Recording state: Record button turns solid red with pulse animation, status bar shows red "● REC" + running timer + resolution + frame rate, thermal indicator appears (green/yellow/orange/red dot), storage usage updates every segment rotation.

Incident detected: Screen flashes brief yellow border, status bar shows "⚠ INCIDENT SAVED" for 3 seconds, haptic feedback (heavy impact), sound plays if audio enabled.

Background state: UI is not visible, but Live Activity shows in Dynamic Island as a compact red dot and expanded view shows timer + "Recording…", lock screen widget shows recording status.

### 3.2 Library Screen

```
┌──────────────────────────────────┐
│          Recordings              │
│  ┌─────┐ ┌─────┐ ┌─────┐       │
│  │ All │ │Saved│ │Stars│       │  ← Filter chips
│  └─────┘ └─────┘ └─────┘       │
├──────────────────────────────────┤
│                                  │
│  TODAY                           │
│  ┌──────────┐  ┌──────────┐    │
│  │ ▶ thumb  │  │ ▶ thumb  │    │
│  │ 14:30    │  │ 14:33    │    │  ← Thumbnail grid
│  │ 3:00     │  │ 3:00     │    │     Shows timestamp + duration
│  │     🛡️   │  │          │    │     Shield = protected
│  └──────────┘  └──────────┘    │
│  ┌──────────┐  ┌──────────┐    │
│  │ ▶ thumb  │  │ ▶ thumb  │    │
│  │ 14:36    │  │ 14:39    │    │
│  │ 3:00     │  │ 2:14     │    │
│  └──────────┘  └──────────┘    │
│                                  │
│  YESTERDAY                       │
│  ┌──────────┐  ┌──────────┐    │
│  │ ...      │  │ ...      │    │
│  └──────────┘  └──────────┘    │
│                                  │
│  Storage: 3.2 / 5.0 GB used    │  ← Bottom storage bar
├──────────────────────────────────┤
│   ◉ Record    📁 Library   ⚙ Set │
└──────────────────────────────────┘
```

**Interactions:**
- Tap thumbnail → opens Clip Detail View (full-screen playback)
- Long press → context menu (Share, Protect, Star, Delete)
- Swipe left on clip → Delete (with confirmation for protected clips)
- Multi-select mode via "Select" button in nav bar

### 3.3 Clip Detail View

```
┌──────────────────────────────────┐
│ ← Back              Share  ···  │
├──────────────────────────────────┤
│                                  │
│                                  │
│         VIDEO PLAYBACK           │
│         (full width)             │
│                                  │
│                                  │
│  ▶ ────────●───────────── 02:14 │  ← Scrub bar
├──────────────────────────────────┤
│                                  │
│  📅 April 12, 2026 at 2:30 PM   │
│  ⏱ Duration: 3:00               │
│  💾 Size: 56.2 MB               │
│  📍 Highway 101, San Francisco  │
│  🚗 Avg Speed: 45 mph           │
│                                  │
│  ┌──────┐  ┌──────┐  ┌───────┐ │
│  │ 🛡 Pro│  │ ⭐ Star│  │🗑 Del │ │  ← Action buttons
│  │ tect │  │      │  │ ete  │ │
│  └──────┘  └──────┘  └───────┘ │
│                                  │
└──────────────────────────────────┘
```

### 3.4 Settings Screen

```
┌──────────────────────────────────┐
│          Settings                │
├──────────────────────────────────┤
│                                  │
│  RECORDING                       │
│  ┌──────────────────────────────┐│
│  │ Resolution          1080p  > ││
│  │ Frame Rate          30fps  > ││
│  │ Audio               ● ON    ││
│  │ Camera             Back    > ││
│  └──────────────────────────────┘│
│                                  │
│  SEGMENTS                        │
│  ┌──────────────────────────────┐│
│  │ Clip Duration       3 min  > ││
│  │ Storage Limit       5 GB   > ││
│  └──────────────────────────────┘│
│                                  │
│  INCIDENT DETECTION              │
│  ┌──────────────────────────────┐│
│  │ Enabled             ● ON    ││
│  │ Sensitivity        Medium  > ││
│  └──────────────────────────────┘│
│                                  │
│  POWER MANAGEMENT                │
│  ┌──────────────────────────────┐│
│  │ Auto-dim Display    ● ON    ││
│  │ Thermal Throttling  ● ON    ││
│  └──────────────────────────────┘│
│                                  │
│  BEHAVIOR                        │
│  ┌──────────────────────────────┐│
│  │ Auto-record on Launch  OFF  ││
│  └──────────────────────────────┘│
│                                  │
│  About · Privacy · Restore       │
│  Purchases                       │
│                                  │
│  v1.0.0 (1)                     │
├──────────────────────────────────┤
│   ◉ Record    📁 Library   ⚙ Set │
└──────────────────────────────────┘
```

### 3.5 Onboarding Flow (First Launch)

Screen 1 — Welcome: App icon + "DashCam Pro" + "Your phone is your dashcam." + "Get Started" button.

Screen 2 — Camera Permission: Illustration of phone mounted on dashboard + "Camera access is required to record." + System permission prompt trigger.

Screen 3 — Microphone Permission: "Record audio with your footage (optional)" + "Audio may be subject to consent laws in your area." + System permission prompt trigger.

Screen 4 — Location Permission: "Track speed and location for your clips" + "Used only on-device, never shared." + System permission prompt trigger → request "Always" for background.

Screen 5 — Legal Disclaimer: "By using DashCam Pro, you acknowledge that recording laws vary by jurisdiction. You are responsible for compliance with local laws." + "I Understand" button.

Screen 6 — Setup Complete: "You're ready to roll." + "Start Recording" button → goes to Recording screen and auto-starts.

---

## 4. Color Palette

```
Background:        #0A0A0A (near-black)
Surface:           #1A1A1A (cards, panels)
Surface Elevated:  #2A2A2A (buttons, inputs)
Primary:           #FF3B30 (recording red — matches Apple's system red)
Secondary:         #30D158 (system green — "ready" state)
Warning:           #FF9F0A (system orange — thermal warning)
Critical:          #FF453A (system red — critical thermal)
Text Primary:      #FFFFFF
Text Secondary:    #8E8E93 (system gray)
Accent:            #0A84FF (system blue — interactive elements)
```

---

## 5. Typography

Use SF Pro (system font) throughout — no custom fonts needed.

- Screen titles: `.largeTitle` (34pt, bold)
- Section headers: `.headline` (17pt, semibold)  
- Body text: `.body` (17pt, regular)
- Status bar overlay: `.system(size: 14, weight: .bold, design: .monospaced)`
- Timer display: `.system(size: 48, weight: .bold, design: .monospaced)`

---

## 6. Animations & Feedback

Record button pulse: When recording, the red button has a subtle scale animation (1.0 → 1.05 → 1.0) on a 2-second loop. Segment rotation: Brief flash of the recording indicator to show a new segment started. Incident alert: Screen border flashes yellow twice over 1 second, then fades. Thermal state change: Status bar color transitions smoothly (0.3s ease). Haptics: UIImpactFeedbackGenerator(.heavy) for incident detection, UIImpactFeedbackGenerator(.medium) for record start/stop, UISelectionFeedbackGenerator for settings changes.
