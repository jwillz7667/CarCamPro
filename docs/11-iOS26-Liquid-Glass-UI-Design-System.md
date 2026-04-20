# iOS 26 Liquid Glass UI Design System
## DashCam Pro — Cutting-Edge Interface Specification

**Version:** 2.0 (replaces Document 05)
**Date:** April 12, 2026
**Minimum Target:** iOS 26.0 (to fully leverage Liquid Glass APIs)

---

## 1. Design Philosophy

DashCam Pro's UI is built entirely on Apple's **Liquid Glass** design language introduced in iOS 26. Every control, every navigation element, every button floats above content with translucent, refractive glass materials. The camera feed IS the background — all UI elements are glass layers hovering over the live video.

**Core Principles:**
- **Content-first:** The camera feed is always the hero. UI is transparent glass floating above it.
- **One-glance readability:** A driver glances for < 1 second. Status must be instantly parseable through the glass.
- **Touch-friendly glass:** All interactive glass elements use `.interactive()` for satisfying press feedback with scaling, bounce, and shimmer.
- **Dark-optimized glass:** Liquid Glass looks stunning over dark/night content. Our camera feed provides the perfect backdrop.
- **Zero opaque panels:** Nothing blocks the camera view. Everything is glass or invisible.

---

## 2. Navigation — Floating Liquid Glass Tab Bar

### 2.1 Tab Structure

Use the new iOS 26 `Tab` API (not the deprecated `tabItem`):

```swift
TabView {
    Tab("Record", systemImage: "video.circle.fill") {
        RecordingView()
    }

    Tab("Library", systemImage: "film.stack.fill") {
        LibraryView()
    }

    Tab("Settings", systemImage: "gearshape.fill") {
        SettingsView()
    }
}
.tabBarMinimizeBehavior(.onScrollDown)  // Collapses when scrolling in Library
```

The tab bar automatically renders as a **floating Liquid Glass capsule** at the bottom of the screen. It's translucent, refracts the camera feed beneath it, and morphs smoothly between states.

### 2.2 Tab Bar Behavior

- **Recording screen:** Tab bar is visible but semi-transparent over the camera feed. Minimizes after 5 seconds of no interaction to maximize camera view.
- **Library screen:** Tab bar collapses on scroll down (`.tabBarMinimizeBehavior(.onScrollDown)`), expands on scroll up.
- **Settings screen:** Tab bar stays visible (standard behavior).

### 2.3 Bottom Accessory

Use `.tabViewBottomAccessory` for a persistent mini recording status bar that sits above the tab bar on non-recording screens:

```swift
TabView { ... }
.tabViewBottomAccessory {
    if recordingEngine.isRecording {
        HStack {
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)
                .pulseAnimation()
            Text("Recording · \(formattedDuration)")
                .font(.caption)
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
```

---

## 3. Recording Screen — Full Liquid Glass HUD

This is the crown jewel. Full-bleed camera preview with floating glass elements.

### 3.1 Layout Architecture

```
┌──────────────────────────────────────┐
│          FULL CAMERA PREVIEW         │
│          (edge to edge, behind       │
│           all glass elements)        │
│                                      │
│  ┌────────────────────────────────┐  │
│  │ ● REC  00:14:32        1080p  │  │  ← Floating glass status bar
│  │ 🌡 Fair   💾 3.2/10 GB        │  │     .glassEffect(.regular)
│  └────────────────────────────────┘  │
│                                      │
│                                      │
│                                      │
│                                      │
│                                      │
│  GlassEffectContainer {             │
│    ┌───┐                     ┌───┐  │  ← Floating glass tool buttons
│    │ 🔇│                     │ 📷│  │     .glassEffect(.regular.interactive())
│    └───┘                     └───┘  │
│  }                                   │
│                                      │
│           ┌───────────┐              │
│           │           │              │  ← Floating glass record button
│           │  ● START  │              │     .glassEffect(.regular.tint(.red)
│           │           │              │                   .interactive())
│           └───────────┘              │
│                                      │
│  ┌───┐  ┌───┐  ┌───┐               │  ← Floating glass tab bar
│  │Rec│  │Lib│  │Set│               │     (automatic from TabView)
│  └───┘  └───┘  └───┘               │
└──────────────────────────────────────┘
```

### 3.2 Status Bar Overlay (Top)

```swift
// Floating glass status bar
VStack(spacing: 4) {
    HStack {
        // Recording indicator
        HStack(spacing: 6) {
            Circle()
                .fill(.red)
                .frame(width: 10, height: 10)
                .opacity(isPulsing ? 1.0 : 0.3)
                .animation(.easeInOut(duration: 1).repeatForever(), value: isPulsing)
            Text("REC")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(.red)
        }
        
        // Timer
        Text(formattedDuration)
            .font(.system(size: 13, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white)
            .contentTransition(.numericText())
        
        Spacer()
        
        // Resolution badge
        Text(settings.resolution.rawValue)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.8))
    }
    
    HStack {
        // Thermal indicator
        HStack(spacing: 4) {
            Circle()
                .fill(thermalColor)
                .frame(width: 6, height: 6)
            Text(thermalLabel)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
        }
        
        Spacer()
        
        // Storage
        HStack(spacing: 4) {
            Image(systemName: "internaldrive.fill")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.7))
            Text("\(formattedUsage) / \(formattedCap)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
        }
    }
}
.padding(.horizontal, 16)
.padding(.vertical, 10)
.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
.padding(.horizontal, 16)
.padding(.top, 8)
```

### 3.3 Record Button — Glass with Red Tint

```swift
GlassEffectContainer {
    Button(action: { toggleRecording() }) {
        ZStack {
            if recordingEngine.isRecording {
                // Stop: rounded square inside glass circle
                RoundedRectangle(cornerRadius: 6)
                    .fill(.white)
                    .frame(width: 28, height: 28)
            } else {
                // Start: large red circle
                Circle()
                    .fill(.red)
                    .frame(width: 56, height: 56)
            }
        }
        .frame(width: 72, height: 72)
        .contentShape(Circle())
    }
    .glassEffect(
        recordingEngine.isRecording
            ? .regular.tint(.red.opacity(0.4)).interactive()
            : .regular.interactive(),
        in: .circle
    )
    .sensoryFeedback(
        recordingEngine.isRecording ? .stop : .start,
        trigger: recordingEngine.isRecording
    )
}
```

### 3.4 Tool Buttons — Glass Effect Container

```swift
// Left and right floating tool buttons
GlassEffectContainer(spacing: 0) {
    HStack {
        // Mute toggle
        Button(action: { toggleMute() }) {
            Image(systemName: settings.audioEnabled ? "mic.fill" : "mic.slash.fill")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
        }
        .glassEffect(.regular.interactive(), in: .circle)
        
        Spacer()
        
        // Camera flip
        Button(action: { flipCamera() }) {
            Image(systemName: "camera.rotate.fill")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
        }
        .glassEffect(.regular.interactive(), in: .circle)
    }
    .padding(.horizontal, 24)
}
```

### 3.5 Incident Alert Animation

When an incident is detected, the entire recording view gets a brief glass-tinted flash:

```swift
// Incident overlay (shown briefly)
if showingIncidentAlert {
    RoundedRectangle(cornerRadius: 0)
        .stroke(Color.yellow, lineWidth: 4)
        .glassEffect(.regular.tint(.yellow.opacity(0.3)))
        .ignoresSafeArea()
        .transition(.opacity)
        .onAppear {
            // Haptic
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            // Auto-dismiss
            withAnimation(.easeOut(duration: 2)) {
                showingIncidentAlert = false
            }
        }
    
    // Floating incident badge
    Text("⚠ INCIDENT SAVED")
        .font(.system(size: 15, weight: .bold, design: .rounded))
        .foregroundStyle(.black)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.yellow)
        .clipShape(Capsule())
        .transition(.move(edge: .top).combined(with: .opacity))
}
```

---

## 4. Library Screen — Glass Cards Over Dark Grid

### 4.1 Layout

```swift
NavigationStack {
    ScrollView {
        // Filter chips — glass capsules
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(LibraryFilter.allCases) { filter in
                    Button(filter.label) {
                        selectedFilter = filter
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(selectedFilter == filter ? .white : .white.opacity(0.6))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .glassEffect(
                        selectedFilter == filter
                            ? .regular.tint(.blue.opacity(0.4)).interactive()
                            : .regular.interactive(),
                        in: .capsule
                    )
                }
            }
            .padding(.horizontal, 16)
        }
        
        // Clips grid
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8)
        ], spacing: 8) {
            ForEach(filteredClips) { clip in
                ClipThumbnailView(clip: clip)
            }
        }
        .padding(.horizontal, 16)
    }
    .background(Color(hex: "0A0A0A"))
    .navigationTitle("Recordings")
}
```

### 4.2 Clip Thumbnail Card

Each clip thumbnail is a glass card:

```swift
struct ClipThumbnailView: View {
    let clip: VideoClip
    
    var body: some View {
        Button(action: { /* navigate to detail */ }) {
            ZStack(alignment: .bottomLeading) {
                // Thumbnail image
                AsyncImage(url: clip.thumbnailURL) { image in
                    image
                        .resizable()
                        .aspectRatio(16/9, contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color(hex: "1A1A1A"))
                        .aspectRatio(16/9, contentMode: .fill)
                        .overlay {
                            ProgressView()
                                .tint(.white.opacity(0.5))
                        }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                
                // Info overlay — glass strip at bottom
                VStack(alignment: .leading, spacing: 2) {
                    Text(clip.formattedTime)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    Text(clip.formattedDuration)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular, in: UnevenRoundedRectangle(
                    bottomLeadingRadius: 12,
                    bottomTrailingRadius: 12
                ))
                
                // Protection badge — top left glass pill
                if clip.isProtected {
                    HStack(spacing: 4) {
                        Image(systemName: "shield.checkered")
                            .font(.system(size: 10, weight: .bold))
                        Text("SAVED")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(.yellow)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .glassEffect(.regular.tint(.yellow.opacity(0.3)), in: .capsule)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(8)
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Share", systemImage: "square.and.arrow.up") { }
            Button("Protect", systemImage: "shield.fill") { }
            Button("Star", systemImage: "star.fill") { }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) { }
        }
    }
}
```

### 4.3 Storage Bar — Glass Footer

```swift
// Sticky glass footer
HStack {
    Image(systemName: "internaldrive.fill")
        .foregroundStyle(.white.opacity(0.7))
    
    // Glass progress bar
    GeometryReader { geometry in
        ZStack(alignment: .leading) {
            Capsule()
                .fill(.white.opacity(0.1))
                .frame(height: 6)
            Capsule()
                .fill(storageColor)
                .frame(width: geometry.size.width * storagePercentage, height: 6)
        }
    }
    .frame(height: 6)
    
    Text("\(formattedUsed) / \(formattedCap)")
        .font(.system(size: 12, weight: .medium, design: .monospaced))
        .foregroundStyle(.white.opacity(0.7))
}
.padding(.horizontal, 16)
.padding(.vertical, 12)
.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
.padding(.horizontal, 16)
.padding(.bottom, 8)
```

---

## 5. Clip Detail Screen — Glass Player Controls

```swift
struct ClipDetailView: View {
    let clip: VideoClip
    @State private var player: AVPlayer?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Video player — full width
                VideoPlayerView(player: player)
                    .aspectRatio(16/9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(alignment: .bottom) {
                        // Glass scrub bar overlay
                        VideoScrubBar(player: player)
                            .padding(.horizontal, 12)
                            .padding(.bottom, 8)
                            .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 12))
                            .padding(8)
                    }
                
                // Metadata cards — glass panels
                VStack(spacing: 12) {
                    // Info card
                    VStack(alignment: .leading, spacing: 8) {
                        MetadataRow(icon: "calendar", label: "Date", value: clip.formattedDate)
                        MetadataRow(icon: "timer", label: "Duration", value: clip.formattedDuration)
                        MetadataRow(icon: "doc.fill", label: "Size", value: clip.formattedFileSize)
                        if let speed = clip.averageSpeed {
                            MetadataRow(icon: "speedometer", label: "Avg Speed", value: "\(Int(speed)) mph")
                        }
                        if clip.hasIncident {
                            MetadataRow(icon: "exclamationmark.triangle.fill", label: "Incident",
                                       value: "\(clip.incidentSeverity?.rawValue ?? "Detected") · \(String(format: "%.1f", clip.peakGForce ?? 0))g")
                                .foregroundStyle(.yellow)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
                    
                    // Action buttons — glass container
                    GlassEffectContainer(spacing: 12) {
                        HStack(spacing: 12) {
                            ActionButton(icon: "shield.fill",
                                        label: clip.isProtected ? "Unprotect" : "Protect",
                                        tint: .yellow)
                            ActionButton(icon: "star.fill",
                                        label: clip.isStarred ? "Unstar" : "Star",
                                        tint: .orange)
                            ActionButton(icon: "square.and.arrow.up",
                                        label: "Share",
                                        tint: .blue)
                            ActionButton(icon: "trash.fill",
                                        label: "Delete",
                                        tint: .red)
                        }
                    }
                }
                .padding(16)
            }
        }
        .background(Color(hex: "0A0A0A"))
        .navigationTitle("Clip Detail")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ActionButton: View {
    let icon: String
    let label: String
    let tint: Color
    
    var body: some View {
        Button(action: { /* action */ }) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                Text(label)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .glassEffect(.regular.tint(tint.opacity(0.3)).interactive(),
                     in: RoundedRectangle(cornerRadius: 14))
    }
}
```

---

## 6. Settings Screen — Native iOS 26 Glass Lists

Settings uses the native SwiftUI `Form` which automatically adopts Liquid Glass styling in iOS 26:

```swift
struct SettingsView: View {
    @AppStorage("resolution") private var resolution: VideoResolution = .hd1080
    // ... other @AppStorage properties
    
    var body: some View {
        NavigationStack {
            Form {
                // RECORDING section
                Section("Recording") {
                    Picker("Resolution", selection: $resolution) {
                        ForEach(VideoResolution.allCases, id: \.self) { res in
                            HStack {
                                Text(res.rawValue)
                                if res == .uhd4k && !isPremium {
                                    Text("PREMIUM")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.purple)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.purple.opacity(0.2))
                                        .clipShape(Capsule())
                                }
                                if res == .hd1080 && !isPro {
                                    Text("PRO")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.blue)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.blue.opacity(0.2))
                                        .clipShape(Capsule())
                                }
                            }
                            .tag(res)
                        }
                    }
                    
                    Picker("Frame Rate", selection: $frameRate) {
                        Text("24 fps").tag(24)
                        Text("30 fps").tag(30)
                    }
                    
                    Toggle("Audio Recording", isOn: $audioEnabled)
                    
                    Picker("Camera", selection: $cameraPosition) {
                        ForEach(CameraPosition.allCases, id: \.self) { pos in
                            Text(pos.rawValue).tag(pos)
                        }
                    }
                }
                
                Section("Segments") {
                    Picker("Clip Duration", selection: $segmentDuration) {
                        Text("1 minute").tag(60.0)
                        Text("3 minutes").tag(180.0)
                        Text("5 minutes").tag(300.0)
                        Text("10 minutes").tag(600.0)
                    }
                    
                    Picker("Storage Limit", selection: $storageCap) {
                        Text("2 GB").tag(Int64(2_147_483_648))
                        Text("5 GB").tag(Int64(5_368_709_120))
                        Text("10 GB").tag(Int64(10_737_418_240))
                        Text("25 GB").tag(Int64(26_843_545_600))
                        if isPremium {
                            Text("Unlimited").tag(Int64.max)
                        }
                    }
                }
                
                Section("Incident Detection") {
                    Toggle("Enabled", isOn: $incidentDetectionEnabled)
                    if incidentDetectionEnabled {
                        Picker("Sensitivity", selection: $incidentSensitivity) {
                            ForEach(IncidentSensitivity.allCases, id: \.self) { sens in
                                VStack(alignment: .leading) {
                                    Text(sens.rawValue.capitalized)
                                }
                                .tag(sens)
                            }
                        }
                    }
                }
                
                Section("Power Management") {
                    Toggle("Auto-dim Display", isOn: $dimDisplay)
                    Toggle("Adaptive Thermal Management", isOn: $thermalThrottling)
                }
                
                Section("Behavior") {
                    Toggle("Auto-record on Launch", isOn: $autoStart)
                }
                
                // Subscription section
                Section {
                    Button(action: { showPaywall = true }) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(currentTierLabel)
                                    .font(.headline)
                                Text("Tap to manage subscription")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Subscription")
                }
                
                Section("About") {
                    LabeledContent("Version", value: "1.0.0 (1)")
                        .onTapGesture(count: 3) { showDevStats = true }
                    Link("Privacy Policy", destination: URL(string: "https://dashcampro.app/privacy")!)
                    Link("Terms of Use", destination: URL(string: "https://dashcampro.app/terms")!)
                    Link("Contact Support", destination: URL(string: "mailto:support@dashcampro.app")!)
                    Button("Restore Purchases") { restorePurchases() }
                }
            }
            .navigationTitle("Settings")
        }
        .preferredColorScheme(.dark)
    }
}
```

In iOS 26, `Form` sections automatically get Liquid Glass group backgrounds. The toggles, pickers, and navigation links all use the system's glass-styled controls.

---

## 7. Paywall Screen — Premium Glass Design

```swift
struct PaywallView: View {
    @Namespace private var namespace
    @State private var selectedPlan: Plan = .proYearly
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "video.circle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.white)
                        .frame(width: 80, height: 80)
                        .glassEffect(.regular.tint(.red.opacity(0.3)), in: .circle)
                    
                    Text("Unlock DashCam Pro")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    
                    Text("Choose your plan")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                }
                .padding(.top, 20)
                
                // Plan cards — Glass
                GlassEffectContainer(spacing: 12) {
                    VStack(spacing: 12) {
                        PlanCard(plan: .proYearly, isSelected: selectedPlan == .proYearly,
                                badge: "MOST POPULAR", badgeColor: .blue)
                            .glassEffect(
                                selectedPlan == .proYearly
                                    ? .regular.tint(.blue.opacity(0.3)).interactive()
                                    : .regular.interactive(),
                                in: RoundedRectangle(cornerRadius: 20)
                            )
                            .glassEffectID("proYearly", in: namespace)
                            .onTapGesture { withAnimation(.bouncy) { selectedPlan = .proYearly } }
                        
                        PlanCard(plan: .premiumYearly, isSelected: selectedPlan == .premiumYearly,
                                badge: "BEST VALUE", badgeColor: .purple)
                            .glassEffect(
                                selectedPlan == .premiumYearly
                                    ? .regular.tint(.purple.opacity(0.3)).interactive()
                                    : .regular.interactive(),
                                in: RoundedRectangle(cornerRadius: 20)
                            )
                            .glassEffectID("premiumYearly", in: namespace)
                            .onTapGesture { withAnimation(.bouncy) { selectedPlan = .premiumYearly } }
                        
                        // Monthly options (collapsed, expandable)
                        DisclosureGroup("Monthly Plans") {
                            PlanCard(plan: .proMonthly, isSelected: selectedPlan == .proMonthly,
                                    badge: nil, badgeColor: .clear)
                                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 16))
                                .onTapGesture { withAnimation(.bouncy) { selectedPlan = .proMonthly } }
                            
                            PlanCard(plan: .premiumMonthly, isSelected: selectedPlan == .premiumMonthly,
                                    badge: nil, badgeColor: .clear)
                                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 16))
                                .onTapGesture { withAnimation(.bouncy) { selectedPlan = .premiumMonthly } }
                        }
                        .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .padding(.horizontal, 16)
                
                // Feature comparison
                FeatureComparisonGrid()
                    .padding(.horizontal, 16)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
                    .padding(.horizontal, 16)
                
                // CTA Button
                Button(action: { purchase(selectedPlan) }) {
                    Text(selectedPlan.ctaLabel)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .glassEffect(
                    .regular.tint(selectedPlan.isPremium ? .purple.opacity(0.5) : .blue.opacity(0.5)).interactive(),
                    in: .capsule
                )
                .padding(.horizontal, 16)
                
                // Legal links
                VStack(spacing: 8) {
                    Button("Restore Purchases") { restore() }
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                    
                    HStack(spacing: 16) {
                        Link("Terms", destination: URL(string: "https://dashcampro.app/terms")!)
                        Link("Privacy", destination: URL(string: "https://dashcampro.app/privacy")!)
                    }
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.3))
                    
                    Text("Subscriptions auto-renew unless cancelled at least 24 hours before the end of the current period.")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.25))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)
            }
        }
        .background(Color(hex: "0A0A0A"))
    }
}
```

---

## 8. Onboarding — Clean Glass Steps

Each onboarding screen uses a large SF Symbol with a glass backing:

```swift
struct OnboardingStepView: View {
    let icon: String
    let title: String
    let description: String
    let buttonLabel: String
    let action: () -> Void
    let tint: Color
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Icon with glass backing
            Image(systemName: icon)
                .font(.system(size: 48, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 100, height: 100)
                .glassEffect(.regular.tint(tint.opacity(0.3)), in: .circle)
            
            VStack(spacing: 12) {
                Text(title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                
                Text(description)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            Spacer()
            
            // CTA button — glass
            Button(action: action) {
                Text(buttonLabel)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .glassEffect(.regular.tint(tint.opacity(0.4)).interactive(), in: .capsule)
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .background(Color(hex: "0A0A0A"))
    }
}
```

---

## 9. Color System

```swift
extension Color {
    // Backgrounds (behind glass)
    static let appBackground = Color(hex: "0A0A0A")      // Near-black
    static let surfaceBackground = Color(hex: "111111")    // Slightly lighter
    
    // Glass tints (used with .glassEffect(.regular.tint()))
    static let glassTintRed = Color.red.opacity(0.4)       // Recording
    static let glassTintBlue = Color.blue.opacity(0.3)     // Pro features
    static let glassTintPurple = Color.purple.opacity(0.3)  // Premium features
    static let glassTintYellow = Color.yellow.opacity(0.3)  // Incidents/protection
    static let glassTintGreen = Color.green.opacity(0.3)    // Success/ready
    static let glassTintOrange = Color.orange.opacity(0.3)  // Warning
    
    // Semantic
    static let thermalNominal = Color.green
    static let thermalFair = Color.yellow
    static let thermalSerious = Color.orange
    static let thermalCritical = Color.red
    
    // Text
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.7)
    static let textTertiary = Color.white.opacity(0.4)
}
```

---

## 10. Typography System

```swift
extension Font {
    // Use system fonts throughout — they integrate perfectly with Liquid Glass
    static let displayTimer = Font.system(size: 48, weight: .bold, design: .monospaced)
    static let statusLabel = Font.system(size: 13, weight: .bold, design: .monospaced)
    static let statusValue = Font.system(size: 11, weight: .medium, design: .monospaced)
    static let sectionHeader = Font.system(size: 13, weight: .semibold, design: .rounded)
    static let cardTitle = Font.system(size: 15, weight: .semibold, design: .default)
    static let cardBody = Font.system(size: 13, weight: .regular, design: .default)
    static let buttonLabel = Font.system(size: 17, weight: .semibold, design: .rounded)
    static let badge = Font.system(size: 9, weight: .bold, design: .rounded)
}
```

---

## 11. Animation & Interaction Specifications

**Glass button press:** `.interactive()` handles this automatically — provides scale-down on press, bounce-back on release, shimmer effect, and touch-point illumination.

**Glass morphing transitions:** Use `glassEffectID` + `GlassEffectContainer` for elements that appear/disappear. The glass shapes morph fluidly into each other.

**Record button pulse:** When recording, overlay a subtle scale animation:
```swift
.scaleEffect(isRecording ? 1.0 : 0.95)
.animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: isRecording)
```

**Segment rotation indicator:** Brief shimmer on the status bar glass when a segment rotates.

**Tab bar minimize:** Use `.tabBarMinimizeBehavior(.onScrollDown)` — the glass tab bar smoothly collapses into a compact dot indicator.

**Content transitions:** Use `.contentTransition(.numericText())` on the timer and all changing numbers for smooth digit-rolling animations.

**Haptics:**
- Record start: `.sensoryFeedback(.start, trigger:)`
- Record stop: `.sensoryFeedback(.stop, trigger:)`
- Incident: `UIImpactFeedbackGenerator(style: .heavy)`
- Button press: Automatic via `.interactive()`
- Settings toggle: `.sensoryFeedback(.selection, trigger:)`

---

## 12. SF Symbols Used

| Context | Symbol | Weight |
|---|---|---|
| Record tab | `video.circle.fill` | medium |
| Library tab | `film.stack.fill` | medium |
| Settings tab | `gearshape.fill` | medium |
| Record button (start) | Inner red circle (custom) | — |
| Record button (stop) | Inner white square (custom) | — |
| Mute on | `mic.fill` | medium |
| Mute off | `mic.slash.fill` | medium |
| Camera flip | `camera.rotate.fill` | medium |
| Protected clip | `shield.checkered` | bold |
| Starred clip | `star.fill` | medium |
| Share | `square.and.arrow.up` | medium |
| Delete | `trash.fill` | medium |
| Storage | `internaldrive.fill` | medium |
| Thermal | `thermometer.medium` | medium |
| Incident | `exclamationmark.triangle.fill` | bold |
| Speed | `speedometer` | medium |
| Calendar | `calendar` | medium |
| Timer | `timer` | medium |
| Location | `location.fill` | medium |
| Pro badge | `crown.fill` | bold |
| Premium badge | `sparkles` | bold |
