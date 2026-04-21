import Foundation

/// Render state of a PDF incident report. The backend creates the row in
/// `QUEUED` and the worker flips it to `READY` once the PDF has been
/// rendered + uploaded to S3.
public enum APIIncidentReportStatus: String, Codable, Sendable, Hashable {
    case queued = "QUEUED"
    case ready  = "READY"
}

/// Response from `POST /v1/incidents/:clipId/report` (enqueue).
public struct APIIncidentReportEnqueueResponse: Codable, Sendable, Equatable {
    public let reportId: String
    public let status: APIIncidentReportStatus
}

/// Response from `GET /v1/incidents/:clipId/report` (status + download).
public struct APIIncidentReportStatusResponse: Codable, Sendable, Equatable {
    public let reportId: String
    public let status: APIIncidentReportStatus
    public let downloadUrl: URL?
    public let expiresInSeconds: Int?
}
