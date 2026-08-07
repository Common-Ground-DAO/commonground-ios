import Foundation

public struct AppNotification: Decodable, Equatable, Identifiable, Sendable {
    public let type: String
    public let id: String
    public let text: String
    public let createdAt: String
    public let updatedAt: String
    public let read: Bool
    public let subjectItemId: String?
    public let subjectCommunityId: String?
    public let subjectUserId: String?
    public let subjectArticleId: String?
    public let extraData: [String: JSONValue]?
}

public enum NotificationOrder: String, Encodable, Sendable {
    case ascending = "ASC"
    case descending = "DESC"
}

public struct NotificationUpdates: Decodable, Equatable, Sendable {
    public let updated: [AppNotification]
    public let deleted: [String]
}
