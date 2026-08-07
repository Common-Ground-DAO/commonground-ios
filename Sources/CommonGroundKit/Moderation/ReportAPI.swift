import Foundation

public enum ReportType: String, Codable, CaseIterable, Sendable {
    case article = "ARTICLE"
    case plugin = "PLUGIN"
    case community = "COMMUNITY"
    case user = "USER"
    case message = "MESSAGE"
}

public enum ReportReason: String, CaseIterable, Identifiable, Hashable, Sendable {
    case doesNotLoad = "does-not-load"
    case spam
    case abusiveContent = "abusive-content"
    case misinformation
    case other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .doesNotLoad: "Content does not load"
        case .spam: "Spam"
        case .abusiveContent: "Abusive content"
        case .misinformation: "Misinformation"
        case .other: "Other"
        }
    }
}

public struct ReportAPI: Sendable {
    private let transport: HTTPTransport
    public init(transport: HTTPTransport) { self.transport = transport }

    public func create(
        type: ReportType,
        targetID: String,
        reason: ReportReason,
        message: String? = nil
    ) async throws {
        let _: EmptyResponse = try await transport.call(
            "Report/createReport",
            body: CreateReportRequest(
                type: type,
                targetId: targetID,
                reason: reason.rawValue,
                message: message
            )
        )
    }
}

private struct CreateReportRequest: Encodable, Sendable {
    let type: ReportType
    let targetId: String
    let reason: String
    let message: String?
}
