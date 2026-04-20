import OSLog

enum AppLogger {
    nonisolated static let camera = Logger(subsystem: "Res.CarCam-Pro", category: "camera")
    nonisolated static let recording = Logger(subsystem: "Res.CarCam-Pro", category: "recording")
    nonisolated static let storage = Logger(subsystem: "Res.CarCam-Pro", category: "storage")
    nonisolated static let thermal = Logger(subsystem: "Res.CarCam-Pro", category: "thermal")
    nonisolated static let incident = Logger(subsystem: "Res.CarCam-Pro", category: "incident")
    nonisolated static let ui = Logger(subsystem: "Res.CarCam-Pro", category: "ui")
    nonisolated static let location = Logger(subsystem: "Res.CarCam-Pro", category: "location")
}
