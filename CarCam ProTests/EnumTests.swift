import Testing
@testable import CarCam_Pro

@Suite("Enum Definitions")
struct EnumTests {

    // MARK: - VideoResolution

    @Test("VideoResolution 720p dimensions")
    func resolution720p() {
        let res = VideoResolution.hd720
        #expect(res.dimensions.width == 1280)
        #expect(res.dimensions.height == 720)
        #expect(res.bitrate == 2_000_000)
        #expect(res.rawValue == "720p")
    }

    @Test("VideoResolution 1080p dimensions")
    func resolution1080p() {
        let res = VideoResolution.hd1080
        #expect(res.dimensions.width == 1920)
        #expect(res.dimensions.height == 1080)
        #expect(res.bitrate == 5_000_000)
        #expect(res.rawValue == "1080p")
    }

    @Test("VideoResolution 4K dimensions")
    func resolution4K() {
        let res = VideoResolution.uhd4k
        #expect(res.dimensions.width == 3840)
        #expect(res.dimensions.height == 2160)
        #expect(res.bitrate == 15_000_000)
        #expect(res.rawValue == "4K")
    }

    @Test("VideoResolution raw value round-trip")
    func resolutionRoundTrip() {
        for res in VideoResolution.allCases {
            let decoded = VideoResolution(rawValue: res.rawValue)
            #expect(decoded == res)
        }
    }

    // MARK: - VideoCodec

    @Test("VideoCodec raw values")
    func codecRawValues() {
        #expect(VideoCodec.h264.rawValue == "H.264")
        #expect(VideoCodec.hevc.rawValue == "HEVC")
    }

    @Test("VideoCodec round-trip")
    func codecRoundTrip() {
        #expect(VideoCodec(rawValue: "H.264") == .h264)
        #expect(VideoCodec(rawValue: "HEVC") == .hevc)
        #expect(VideoCodec(rawValue: "invalid") == nil)
    }

    // MARK: - IncidentSensitivity

    @Test("IncidentSensitivity thresholds")
    func sensitivityThresholds() {
        #expect(IncidentSensitivity.low.threshold == 6.0)
        #expect(IncidentSensitivity.medium.threshold == 3.0)
        #expect(IncidentSensitivity.high.threshold == 1.5)
    }

    @Test("IncidentSensitivity round-trip")
    func sensitivityRoundTrip() {
        for sensitivity in IncidentSensitivity.allCases {
            let decoded = IncidentSensitivity(rawValue: sensitivity.rawValue)
            #expect(decoded == sensitivity)
        }
    }

    // MARK: - IncidentSeverity

    @Test("IncidentSeverity raw values")
    func severityRawValues() {
        #expect(IncidentSeverity.minor.rawValue == "minor")
        #expect(IncidentSeverity.moderate.rawValue == "moderate")
        #expect(IncidentSeverity.severe.rawValue == "severe")
    }

    // MARK: - ProtectionReason

    @Test("ProtectionReason raw values")
    func protectionReasonRawValues() {
        #expect(ProtectionReason.incidentDetected.rawValue == "incidentDetected")
        #expect(ProtectionReason.userStarred.rawValue == "userStarred")
        #expect(ProtectionReason.manualProtect.rawValue == "manualProtect")
    }

    // MARK: - CameraPosition

    @Test("CameraPosition all cases exist")
    func cameraPositionCases() {
        #expect(CameraPosition.allCases.count == 3)
        #expect(CameraPosition.backWide.rawValue == "Back (Wide)")
        #expect(CameraPosition.backUltraWide.rawValue == "Back (Ultra Wide)")
        #expect(CameraPosition.front.rawValue == "Front (Cabin)")
    }
}
