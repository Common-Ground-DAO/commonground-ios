import Foundation

public struct AppNotification: Codable, Equatable, Identifiable, Sendable {
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

    public var isPersisted: Bool {
        type != "DM" && type != "ChannelMessage" && type != "Call"
    }

    public var destination: NotificationDestination? {
        let dataType = extraData?["type"]?.stringValue
        let messageID = subjectItemId
        switch dataType {
        case "channelData", "channelDetailData":
            guard let communityID = subjectCommunityId
                    ?? extraData?["communityId"]?.stringValue,
                  let channelID = extraData?["channelId"]?.stringValue else { return nil }
            return .channel(communityID: communityID, channelID: channelID, messageID: messageID)
        case "chatData":
            guard let chatID = extraData?["chatId"]?.stringValue,
                  let channelID = extraData?["channelId"]?.stringValue else { return nil }
            return .chat(chatID: chatID, channelID: channelID, messageID: messageID)
        case "articleData":
            guard let articleID = subjectArticleId ?? extraData?["articleId"]?.stringValue,
                  let owner = extraData?["articleOwner"]?.objectValue,
                  let ownerType = owner["type"]?.stringValue else { return nil }
            if ownerType == "community", let communityID = owner["communityId"]?.stringValue {
                return .article(owner: .community(communityID), articleID: articleID, messageID: messageID)
            }
            if ownerType == "user", let userID = owner["userId"]?.stringValue {
                return .article(owner: .user(userID), articleID: articleID, messageID: messageID)
            }
            return nil
        case "callData":
            guard let communityID = subjectCommunityId else { return nil }
            return .community(communityID)
        case "approvalData":
            guard let communityID = subjectCommunityId else { return nil }
            return .community(communityID)
        case "generalData":
            guard let path = extraData?["navUrl"]?.stringValue else { return nil }
            return .path(path)
        default:
            if type == "Follower", let userID = subjectUserId { return .profile(userID) }
            if let articleID = subjectArticleId { return .unknownArticle(articleID) }
            if let communityID = subjectCommunityId { return .community(communityID) }
            if let userID = subjectUserId { return .profile(userID) }
            return nil
        }
    }
}

public enum NotificationArticleOwner: Equatable, Sendable {
    case community(String)
    case user(String)
}

public enum NotificationDestination: Equatable, Sendable {
    case channel(communityID: String, channelID: String, messageID: String?)
    case chat(chatID: String, channelID: String, messageID: String?)
    case article(owner: NotificationArticleOwner, articleID: String, messageID: String?)
    case profile(String)
    case community(String)
    case path(String)
    case unknownArticle(String)
}

public enum NotificationOrder: String, Encodable, Sendable {
    case ascending = "ASC"
    case descending = "DESC"
}

public struct NotificationUpdates: Decodable, Equatable, Sendable {
    public let updated: [AppNotification]
    public let deleted: [String]
}
