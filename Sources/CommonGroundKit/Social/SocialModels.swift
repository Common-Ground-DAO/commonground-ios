import Foundation

public struct MessageBody: Codable, Equatable, Sendable {
    public let version: String
    public let content: [JSONValue]

    public init(version: String = "1", content: [JSONValue]) {
        self.version = version
        self.content = content
    }

    public static func text(_ text: String) -> MessageBody {
        var nodes: [JSONValue] = []
        for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            if index > 0 { nodes.append(.object(["type": .string("newline")])) }
            if !line.isEmpty {
                nodes.append(.object(["type": .string("text"), "value": .string(String(line))]))
            }
        }
        return MessageBody(content: nodes)
    }

    public var plainText: String {
        content.compactMap { node -> String? in
            guard let object = node.objectValue else { return nil }
            switch object["type"]?.stringValue {
            case "newline": return "\n"
            case "text", "link": return object["value"]?.stringValue
            case "richTextLink": return object["value"]?.stringValue
            case "mention": return object["alias"]?.stringValue.map { "@\($0)" } ?? "@member"
            default: return nil
            }
        }.joined()
    }
}

public struct Message: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let creatorId: String
    public let channelId: String
    public let body: MessageBody
    public let attachments: [JSONValue]
    public let editedAt: String?
    public let createdAt: String
    public let updatedAt: String
    public let reactions: [String: Int]
    public let ownReaction: String?
    public let parentMessageId: String?
}

public struct Channel: Codable, Equatable, Identifiable, Sendable {
    public let communityId: String
    public let channelId: String
    public let areaId: String
    public let title: String
    public let url: String?
    public let order: Int
    public let description: String?
    public let emoji: String?
    public let updatedAt: String
    public var lastRead: String?
    public let lastMessageDate: String?
    public let pinnedMessageIds: [String]?
    public let rolePermissions: [JSONValue]

    public var id: String { channelId }
}

public struct Community: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let url: String
    public let title: String
    public let createdAt: String
    public let updatedAt: String
    public let memberCount: Int
    public let myRoleIds: [String]
    public var channels: [Channel]
    public let areas: [JSONValue]
    public let roles: [JSONValue]
    public let calls: [JSONValue]
}

public struct Chat: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let channelId: String
    public let userIds: [String]
    public let adminIds: [String]
    public let createdAt: String
    public let updatedAt: String
    public let unread: Bool?
    public let lastRead: String?
    public let lastMessage: Message?
}

public struct MessageAccess: Encodable, Equatable, Sendable {
    public let channelId: String
    public let communityId: String?
    public let chatId: String?
    public let callId: String?
    public let articleId: String?
    public let articleCommunityId: String?
    public let articleUserId: String?

    public static func community(_ communityId: String, channelId: String) -> MessageAccess {
        MessageAccess(channelId: channelId, communityId: communityId)
    }

    public static func chat(_ chatId: String, channelId: String) -> MessageAccess {
        MessageAccess(channelId: channelId, chatId: chatId)
    }

    private init(
        channelId: String,
        communityId: String? = nil,
        chatId: String? = nil,
        callId: String? = nil,
        articleId: String? = nil,
        articleCommunityId: String? = nil,
        articleUserId: String? = nil
    ) {
        self.channelId = channelId
        self.communityId = communityId
        self.chatId = chatId
        self.callId = callId
        self.articleId = articleId
        self.articleCommunityId = articleCommunityId
        self.articleUserId = articleUserId
    }
}
