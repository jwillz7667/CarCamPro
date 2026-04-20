# System Design & Data Models
## DashCam Pro

**Version:** 1.0
**Date:** April 12, 2026

---

## 1. State Machine — Recording Engine

The RecordingEngine is the heart of the app. It manages all recording states and transitions.

```
                    ┌──────────┐
                    │   IDLE   │
                    └────┬─────┘
                         │ startRecording()
                         ▼
                    ┌──────────┐
              ┌─────│ STARTING │
              │     └────┬─────┘
              │          │ camera + writer ready
    error     │          ▼
              │     ┌──────────┐
              │     │RECORDING │◄──────────────────┐
              │     └──┬───┬───┘                   │
              │        │   │                       │
              │        │   │ segment duration hit   │
              │        │   ▼                       │
              │        │ ┌──────────────┐          │
              │        │ │  ROTATING    │──────────┘
              │        │ │  SEGMENT     │  new writer ready
              │        │ └──────────────┘
              │        │
              │        │ stopRecording()
              │        ▼
              │     ┌──────────┐
              │     │ STOPPING │
              │     └────┬─────┘
              │          │ writer finalized
              │          ▼
              │     ┌──────────┐
              └────►│  ERROR   │
                    └────┬─────┘
                         │ reset()
                         ▼
                    ┌──────────┐
                    │   IDLE   │
                    └──────────┘
```

### State Definitions

```swift
enum RecordingState: Equatable {
    case idle
    case starting
    case recording(segment: Int, duration: TimeInterval)
    case rotatingSegment(fromSegment: Int, toSegment: Int)
    case stopping
    case error(RecordingError)
}
```

---

## 2. Data Models

### 2.1 SwiftData Models

```swift
@Model
class RecordingSession {
    @Attribute(.unique) var id: UUID
    var startDate: Date
    var endDate: Date?
    var totalDuration: TimeInterval
    var totalSegments: Int
    var wasInterrupted: Bool
    
    @Relationship(deleteRule: .cascade)
    var clips: [VideoClip]
    
    var formattedDate: String { /* computed */ }
}

@Model
class VideoClip {
    @Attribute(.unique) var id: UUID
    var fileName: String          // "clip_2026-04-12_14-30-00_001.mp4"
    var filePath: String          // Relative path from Documents/
    var thumbnailPath: String?
    var startDate: Date
    var endDate: Date?
    var duration: TimeInterval
    var fileSize: Int64           // bytes
    var resolution: VideoResolution
    var frameRate: Int
    var codec: VideoCodec
    
    // Protection
    var isProtected: Bool         // true = excluded from FIFO deletion
    var isStarred: Bool           // user-favorited
    var protectionReason: ProtectionReason?
    
    // Metadata
    var startLatitude: Double?
    var startLongitude: Double?
    var endLatitude: Double?
    var endLongitude: Double?
    var averageSpeed: Double?     // km/h
    var maxSpeed: Double?
    
    // Incident
    var hasIncident: Bool
    var incidentTimestamp: Date?
    var incidentSeverity: IncidentSeverity?
    var peakGForce: Double?
    
    // Relationship
    var session: RecordingSession?
    
    // Computed
    var fileURL: URL { /* Documents directory + filePath */ }
    var formattedDuration: String { /* computed */ }
    var formattedFileSize: String { /* computed */ }
}
```

### 2.2 Supporting Enums

```swift
enum VideoResolution: String, Codable, CaseIterable {
    case hd720 = "720p"
    case hd1080 = "1080p"
    case uhd4k = "4K"
    
    var dimensions: CMVideoDimensions {
        switch self {
        case .hd720:  return CMVideoDimensions(width: 1280, height: 720)
        case .hd1080: return CMVideoDimensions(width: 1920, height: 1080)
        case .uhd4k:  return CMVideoDimensions(width: 3840, height: 2160)
        }
    }
    
    var bitrate: Int {
        switch self {
        case .hd720:  return 2_000_000   // 2 Mbps
        case .hd1080: return 5_000_000   // 5 Mbps
        case .uhd4k:  return 15_000_000  // 15 Mbps
        }
    }
}

enum VideoCodec: String, Codable {
    case h264 = "H.264"
    case hevc = "HEVC"   // preferred — better quality at lower bitrate
}

enum IncidentSeverity: String, Codable {
    case minor      // 1.5-3g sudden deceleration
    case moderate   // 3-6g
    case severe     // 6g+
}

enum ProtectionReason: String, Codable {
    case incidentDetected
    case userStarred
    case manualProtect
}
```

### 2.3 Settings Model

```swift
struct AppSettings {
    // Recording
    var resolution: VideoResolution = .hd1080
    var frameRate: Int = 30
    var codec: VideoCodec = .hevc
    var audioEnabled: Bool = true
    var selectedCamera: CameraPosition = .backWide
    
    // Segments
    var segmentDuration: TimeInterval = 180  // 3 minutes
    var storageCap: Int64 = 5_368_709_120    // 5 GB in bytes
    
    // Incident Detection
    var incidentDetectionEnabled: Bool = true
    var incidentSensitivity: IncidentSensitivity = .medium
    
    // Behavior
    var autoStartOnLaunch: Bool = false
    var dimDisplayWhileRecording: Bool = true
    var showSpeedOverlay: Bool = false
    
    // Thermal
    var allowThermalThrottling: Bool = true  // auto-reduce quality
}

enum CameraPosition: String, Codable, CaseIterable {
    case backWide = "Back (Wide)"
    case backUltraWide = "Back (Ultra Wide)"
    case front = "Front (Cabin)"
}

enum IncidentSensitivity: String, Codable, CaseIterable {
    case low       // 6g+ only (hard crash)
    case medium    // 3g+ (hard braking + crash)
    case high      // 1.5g+ (any sudden movement)
    
    var threshold: Double {
        switch self {
        case .low:    return 6.0
        case .medium: return 3.0
        case .high:   return 1.5
        }
    }
}
```

---

## 3. File System Layout

```
Documents/
├── Recordings/
│   ├── 2026-04-12/
│   │   ├── session_abc123/
│   │   │   ├── clip_001.mp4
│   │   │   ├── clip_002.mp4
│   │   │   └── clip_003.mp4
│   │   └── session_def456/
│   │       ├── clip_001.mp4
│   │       └── clip_002.mp4   ← protected (incident)
│   └── 2026-04-11/
│       └── ...
│
├── Thumbnails/
│   ├── thumb_clip_001.jpg
│   └── ...
│
└── Temp/
    └── recording_in_progress.mp4  ← current active segment
```

### File Naming Convention

```
clip_{session-short-id}_{sequence}_{timestamp}.mp4
Example: clip_abc123_001_20260412-143000.mp4
```

---

## 4. Service Interaction Diagram

```
User taps "Record"
        │
        ▼
RecordingViewModel
        │
        ▼
RecordingEngine.startRecording()
        │
        ├──► CameraService.configure(settings)
        │       └── AVCaptureSession.startRunning()
        │
        ├──► SegmentManager.beginNewSegment()
        │       └── AVAssetWriter setup + start writing
        │
        ├──► ThermalMonitor.startMonitoring()
        │       └── Observes ProcessInfo.thermalState
        │       └── Notifies AdaptiveQualityController
        │
        ├──► IncidentDetector.startDetecting()
        │       └── CMMotionManager.startAccelerometerUpdates()
        │
        ├──► LocationService.startTracking()
        │       └── CLLocationManager.startUpdatingLocation()
        │
        └──► BackgroundRecordingHandler.registerBackgroundTask()

        [All services now running concurrently]

        Timer fires (segment duration reached)
            │
            ▼
        SegmentManager.rotateSegment()
            ├── Finalize current AVAssetWriter
            ├── Save clip metadata to SwiftData
            ├── Start new AVAssetWriter
            └── StorageManager.enforceStorageCap()
                └── Delete oldest unprotected clips if over cap

        IncidentDetector fires (g-force threshold exceeded)
            │
            ▼
        ClipProtector.protectCurrentClip()
            ├── Mark current segment as protected
            ├── Also protect previous segment (30s buffer)
            ├── Haptic feedback
            └── Post local notification
```

---

## 5. Storage Cap Enforcement Algorithm

```
function enforceStorageCap():
    currentUsage = calculateTotalRecordingSize()
    
    if currentUsage <= settings.storageCap:
        return  // all good
    
    // Get all clips sorted by date (oldest first)
    candidates = allClips
        .filter { !$0.isProtected && !$0.isStarred }
        .sorted { $0.startDate < $1.startDate }
    
    bytesToFree = currentUsage - settings.storageCap
    freed = 0
    
    for clip in candidates:
        if freed >= bytesToFree:
            break
        delete clip.fileURL
        delete clip from SwiftData
        freed += clip.fileSize
    
    if freed < bytesToFree:
        // Protected clips are filling storage
        // Notify user: "Storage full — protected clips using X GB"
        postStorageWarningNotification()
```

---

## 6. Key Protocol Definitions

```swift
protocol CameraServiceProtocol {
    var isRunning: Bool { get }
    var currentConfiguration: CameraConfiguration { get }
    func configure(_ config: CameraConfiguration) async throws
    func startCapture() async throws
    func stopCapture() async
    func switchCamera(to position: CameraPosition) async throws
    func updateQuality(_ resolution: VideoResolution, bitrate: Int) async throws
}

protocol RecordingEngineProtocol {
    var state: RecordingState { get }
    var statePublisher: AnyPublisher<RecordingState, Never> { get }
    func startRecording() async throws
    func stopRecording() async throws
    func reset() async
}

protocol IncidentDetectorProtocol {
    var isDetecting: Bool { get }
    var incidentPublisher: AnyPublisher<IncidentEvent, Never> { get }
    func startDetecting(sensitivity: IncidentSensitivity) async
    func stopDetecting() async
}

protocol StorageManagerProtocol {
    var currentUsage: Int64 { get async }
    var availableSpace: Int64 { get async }
    func enforceStorageCap() async throws
    func deleteClip(_ clip: VideoClip) async throws
    func deleteAllUnprotected() async throws
}

protocol ThermalMonitorProtocol {
    var currentState: ProcessInfo.ThermalState { get }
    var thermalStatePublisher: AnyPublisher<ProcessInfo.ThermalState, Never> { get }
    func startMonitoring()
    func stopMonitoring()
}
```

These protocols enable dependency injection and make every service testable with mock implementations.
