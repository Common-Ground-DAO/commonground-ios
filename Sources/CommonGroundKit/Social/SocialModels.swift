import Foundation

public struct MessageBody: Codable, Equatable, Sendable {
    public let version: String
    public let content: [JSONValue]

    public init(version: String = "1", content: [JSONValue]) {
        self.version = version
        self.content = content
    }

    public static func text(_ text: String) -> MessageBody {
        composed(text, mentions: [:])
    }

    public static func composed(_ text: String, mentions: [String: String]) -> MessageBody {
        var nodes: [JSONValue] = []
        for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            if index > 0 { nodes.append(.object(["type": .string("newline")])) }
            var remaining = String(line)
            while !remaining.isEmpty {
                let match = mentions.compactMap { alias, userID -> (Range<String.Index>, String, String)? in
                    guard let range = remaining.range(of: "@\(alias)") else { return nil }
                    return (range, alias, userID)
                }.min { lhs, rhs in
                    lhs.0.lowerBound < rhs.0.lowerBound
                }
                guard let match else {
                    nodes.append(.object(["type": .string("text"), "value": .string(remaining)]))
                    break
                }
                let prefix = String(remaining[..<match.0.lowerBound])
                if !prefix.isEmpty {
                    nodes.append(.object(["type": .string("text"), "value": .string(prefix)]))
                }
                nodes.append(.object([
                    "type": .string("mention"),
                    "userId": .string(match.2),
                    "alias": .string(match.1),
                ]))
                remaining = String(remaining[match.0.upperBound...])
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

public struct MessageImageAttachment: Codable, Equatable, Sendable {
    public let imageId: String
    public let largeImageId: String

    public init(imageId: String, largeImageId: String) {
        self.imageId = imageId
        self.largeImageId = largeImageId
    }

    public var jsonValue: JSONValue {
        .object([
            "type": .string("image"),
            "imageId": .string(imageId),
            "largeImageId": .string(largeImageId),
        ])
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

    enum CodingKeys: String, CodingKey {
        case id, creatorId, channelId, body, attachments, editedAt, createdAt, updatedAt
        case reactions, ownReaction, parentMessageId
    }

    public init(
        id: String,
        creatorId: String,
        channelId: String,
        body: MessageBody,
        attachments: [JSONValue],
        editedAt: String?,
        createdAt: String,
        updatedAt: String,
        reactions: [String: Int],
        ownReaction: String?,
        parentMessageId: String?
    ) {
        self.id = id
        self.creatorId = creatorId
        self.channelId = channelId
        self.body = body
        self.attachments = attachments
        self.editedAt = editedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.reactions = reactions
        self.ownReaction = ownReaction
        self.parentMessageId = parentMessageId
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        creatorId = try container.decode(String.self, forKey: .creatorId)
        channelId = try container.decode(String.self, forKey: .channelId)
        body = try container.decode(MessageBody.self, forKey: .body)
        attachments = try container.decode([JSONValue].self, forKey: .attachments)
        editedAt = try container.decodeIfPresent(String.self, forKey: .editedAt)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        updatedAt = try container.decode(String.self, forKey: .updatedAt)
        reactions = try container.decodeIfPresent([String: Int].self, forKey: .reactions) ?? [:]
        ownReaction = try container.decodeIfPresent(String.self, forKey: .ownReaction)
        parentMessageId = try container.decodeIfPresent(String.self, forKey: .parentMessageId)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(creatorId, forKey: .creatorId)
        try container.encode(channelId, forKey: .channelId)
        try container.encode(body, forKey: .body)
        try container.encode(attachments, forKey: .attachments)
        try container.encodeIfPresent(editedAt, forKey: .editedAt)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(reactions, forKey: .reactions)
        try container.encodeIfPresent(ownReaction, forKey: .ownReaction)
        try container.encodeIfPresent(parentMessageId, forKey: .parentMessageId)
    }

    public var imageAttachments: [MessageImageAttachment] {
        attachments.compactMap { value in
            guard let object = value.objectValue,
                  object["type"]?.stringValue == "image",
                  let imageId = object["imageId"]?.stringValue,
                  let largeImageId = object["largeImageId"]?.stringValue else { return nil }
            return MessageImageAttachment(imageId: imageId, largeImageId: largeImageId)
        }
    }
}

public struct Channel: Codable, Equatable, Identifiable, Sendable {
    public let communityId: String
    public let channelId: String
    public let areaId: String?
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

    private enum CodingKeys: String, CodingKey {
        case id, url, title, createdAt, updatedAt, memberCount, myRoleIds
        case channels, areas, roles, calls
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        url = try container.decode(String.self, forKey: .url)
        title = try container.decode(String.self, forKey: .title)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        updatedAt = try container.decode(String.self, forKey: .updatedAt)
        if let value = try? container.decode(Int.self, forKey: .memberCount) {
            memberCount = value
        } else if let value = try? container.decode(String.self, forKey: .memberCount),
                  let number = Int(value) {
            memberCount = number
        } else {
            memberCount = 0
        }
        myRoleIds = try container.decodeIfPresent([String].self, forKey: .myRoleIds) ?? []
        channels = try container.decodeIfPresent([Channel].self, forKey: .channels) ?? []
        areas = try container.decodeIfPresent([JSONValue].self, forKey: .areas) ?? []
        roles = try container.decodeIfPresent([JSONValue].self, forKey: .roles) ?? []
        calls = try container.decodeIfPresent([JSONValue].self, forKey: .calls) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(url, forKey: .url)
        try container.encode(title, forKey: .title)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(memberCount, forKey: .memberCount)
        try container.encode(myRoleIds, forKey: .myRoleIds)
        try container.encode(channels, forKey: .channels)
        try container.encode(areas, forKey: .areas)
        try container.encode(roles, forKey: .roles)
        try container.encode(calls, forKey: .calls)
    }
}

public struct CommunitySummary: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let url: String
    public let title: String
    public let shortDescription: String?
    public let memberCount: Int
    public let tags: [String]
    public let createdAt: String
    public let updatedAt: String

    private enum CodingKeys: String, CodingKey {
        case id, url, title, shortDescription, memberCount, tags, createdAt, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        url = try container.decode(String.self, forKey: .url)
        title = try container.decode(String.self, forKey: .title)
        shortDescription = try container.decodeIfPresent(String.self, forKey: .shortDescription)
        if let value = try? container.decode(Int.self, forKey: .memberCount) {
            memberCount = value
        } else if let value = try? container.decode(String.self, forKey: .memberCount),
                  let number = Int(value) {
            memberCount = number
        } else {
            memberCount = 0
        }
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        createdAt = try container.decode(String.self, forKey: .createdAt)
        updatedAt = try container.decode(String.self, forKey: .updatedAt)
    }
}

public struct Chat: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let channelId: String
    public let userIds: [String]
    public let adminIds: [String]
    public let createdAt: String
    public let updatedAt: String
    public let unread: Int?
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
