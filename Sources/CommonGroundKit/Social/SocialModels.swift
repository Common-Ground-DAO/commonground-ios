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

    /// Mentions keyed by the visible alias used by the structured body. Keeping
    /// this information when a message enters the editor prevents an otherwise
    /// lossless text edit from silently downgrading mentions to plain text.
    public var mentions: [String: String] {
        content.reduce(into: [:]) { result, node in
            guard let object = node.objectValue,
                  object["type"]?.stringValue == "mention",
                  let alias = object["alias"]?.stringValue,
                  let userID = object["userId"]?.stringValue else { return }
            result[alias] = userID
        }
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

    public var roleAccess: [ChannelRoleAccess] {
        rolePermissions.compactMap(ChannelRoleAccess.init)
    }
}

public struct ChannelRoleAccess: Identifiable, Equatable, Sendable {
    public let roleId: String
    public let roleTitle: String
    public var permissions: [String]
    public var id: String { roleId }

    public init(roleId: String, roleTitle: String, permissions: [String]) {
        self.roleId = roleId
        self.roleTitle = roleTitle
        self.permissions = permissions
    }

    init?(_ value: JSONValue) {
        guard let object = value.objectValue,
              let roleId = object["roleId"]?.stringValue,
              let roleTitle = object["roleTitle"]?.stringValue else { return nil }
        self.roleId = roleId
        self.roleTitle = roleTitle
        if case .array(let values) = object["permissions"] {
            permissions = values.compactMap(\.stringValue)
        } else {
            permissions = []
        }
    }

    public var jsonValue: JSONValue {
        .object([
            "roleId": .string(roleId),
            "roleTitle": .string(roleTitle),
            "permissions": .array(permissions.map(JSONValue.string)),
        ])
    }
}

public struct CommunityLink: Codable, Equatable, Sendable {
    public let url: String
    public let text: String

    public init(url: String, text: String) {
        self.url = url
        self.text = text
    }
}

public struct Community: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let url: String
    public let title: String
    public let logoSmallId: String?
    public let logoLargeId: String?
    public let headerImageId: String?
    public let shortDescription: String?
    public let description: String
    public let links: [CommunityLink]
    public let tags: [String]
    public let creatorId: String?
    public let createdAt: String
    public let updatedAt: String
    public let memberCount: Int
    public let myRoleIds: [String]
    public var channels: [Channel]
    public let areas: [JSONValue]
    public let roles: [JSONValue]
    public let calls: [JSONValue]
    public let official: Bool
    public let premium: JSONValue?
    public let tokens: [JSONValue]
    public let pointBalance: Double
    public let onboardingOptions: JSONValue?
    public let membersPendingApproval: Int
    public let enablePersonalNewsletter: Bool
    public let allowUserBots: Bool
    public let plugins: [JSONValue]
    public let notificationState: CommunityNotificationState

    private enum CodingKeys: String, CodingKey {
        case id, url, title, logoSmallId, logoLargeId, headerImageId, shortDescription
        case description, links, tags, creatorId
        case createdAt, updatedAt, memberCount, myRoleIds
        case channels, areas, roles, calls, official, premium, tokens, pointBalance
        case onboardingOptions, membersPendingApproval, enablePersonalNewsletter, allowUserBots, plugins
        case notificationState
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        url = try container.decode(String.self, forKey: .url)
        title = try container.decode(String.self, forKey: .title)
        logoSmallId = try container.decodeIfPresent(String.self, forKey: .logoSmallId)
        logoLargeId = try container.decodeIfPresent(String.self, forKey: .logoLargeId)
        headerImageId = try container.decodeIfPresent(String.self, forKey: .headerImageId)
        shortDescription = try container.decodeIfPresent(String.self, forKey: .shortDescription)
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        links = try container.decodeIfPresent([CommunityLink].self, forKey: .links) ?? []
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        creatorId = try container.decodeIfPresent(String.self, forKey: .creatorId)
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
        official = try container.decodeIfPresent(Bool.self, forKey: .official) ?? false
        premium = try container.decodeIfPresent(JSONValue.self, forKey: .premium)
        tokens = try container.decodeIfPresent([JSONValue].self, forKey: .tokens) ?? []
        pointBalance = try container.decodeIfPresent(Double.self, forKey: .pointBalance) ?? 0
        onboardingOptions = try container.decodeIfPresent(JSONValue.self, forKey: .onboardingOptions)
        membersPendingApproval = try container.decodeIfPresent(Int.self, forKey: .membersPendingApproval) ?? 0
        enablePersonalNewsletter = try container.decodeIfPresent(Bool.self, forKey: .enablePersonalNewsletter) ?? false
        allowUserBots = try container.decodeIfPresent(Bool.self, forKey: .allowUserBots) ?? false
        plugins = try container.decodeIfPresent([JSONValue].self, forKey: .plugins) ?? []
        notificationState = try container.decodeIfPresent(
            CommunityNotificationState.self,
            forKey: .notificationState
        ) ?? CommunityNotificationState()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(url, forKey: .url)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(logoSmallId, forKey: .logoSmallId)
        try container.encodeIfPresent(logoLargeId, forKey: .logoLargeId)
        try container.encodeIfPresent(headerImageId, forKey: .headerImageId)
        try container.encodeIfPresent(shortDescription, forKey: .shortDescription)
        try container.encode(description, forKey: .description)
        try container.encode(links, forKey: .links)
        try container.encode(tags, forKey: .tags)
        try container.encodeIfPresent(creatorId, forKey: .creatorId)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(memberCount, forKey: .memberCount)
        try container.encode(myRoleIds, forKey: .myRoleIds)
        try container.encode(channels, forKey: .channels)
        try container.encode(areas, forKey: .areas)
        try container.encode(roles, forKey: .roles)
        try container.encode(calls, forKey: .calls)
        try container.encode(official, forKey: .official)
        try container.encodeIfPresent(premium, forKey: .premium)
        try container.encode(tokens, forKey: .tokens)
        try container.encode(pointBalance, forKey: .pointBalance)
        try container.encodeIfPresent(onboardingOptions, forKey: .onboardingOptions)
        try container.encode(membersPendingApproval, forKey: .membersPendingApproval)
        try container.encode(enablePersonalNewsletter, forKey: .enablePersonalNewsletter)
        try container.encode(allowUserBots, forKey: .allowUserBots)
        try container.encode(plugins, forKey: .plugins)
        try container.encode(notificationState, forKey: .notificationState)
    }

    public var managementPermissions: Set<String> {
        let ownRoles = Set(myRoleIds)
        return Set(roles.flatMap { role -> [String] in
            guard let object = role.objectValue,
                  let id = object["id"]?.stringValue,
                  ownRoles.contains(id),
                  let permissions = object["permissions"],
                  case .array(let values) = permissions else { return [] }
            return values.compactMap(\.stringValue)
        })
    }

    public var canManageInfo: Bool {
        managementPermissions.contains("COMMUNITY_MANAGE_INFO")
    }

    public var canManageArticles: Bool {
        managementPermissions.contains("COMMUNITY_MANAGE_ARTICLES")
    }

    public var canManageChannels: Bool {
        managementPermissions.contains("COMMUNITY_MANAGE_CHANNELS")
    }

    public var canManageRoles: Bool {
        managementPermissions.contains("COMMUNITY_MANAGE_ROLES")
    }

    public var canModerate: Bool {
        managementPermissions.contains("COMMUNITY_MODERATE")
    }

    public var canManageApplications: Bool {
        managementPermissions.contains("COMMUNITY_MANAGE_USER_APPLICATIONS")
    }

    public var canManageEvents: Bool {
        managementPermissions.contains("COMMUNITY_MANAGE_EVENTS")
    }

    public var isAdmin: Bool {
        let ownRoles = Set(myRoleIds)
        return roles.contains { role in
            guard let object = role.objectValue,
                  let id = object["id"]?.stringValue,
                  let title = object["title"]?.stringValue else { return false }
            return title == "Admin" && ownRoles.contains(id)
        }
    }

    public var roleInfos: [CommunityRoleInfo] {
        roles.compactMap(CommunityRoleInfo.init)
    }

    public var areaInfos: [CommunityAreaInfo] {
        areas.compactMap(CommunityAreaInfo.init).sorted { $0.order < $1.order }
    }

    public var premiumInfo: CommunityPremiumInfo? {
        premium.flatMap(CommunityPremiumInfo.init)
    }

    public var tokenInfos: [CommunityTokenInfo] {
        tokens.compactMap(CommunityTokenInfo.init).sorted { $0.order < $1.order }
    }

    public var pluginInfos: [CommunityPluginInfo] {
        plugins.compactMap(CommunityPluginInfo.init)
    }

    public var defaultArticleRolePermissions: [ArticleRolePermission] {
        let visible = ["ARTICLE_PREVIEW", "ARTICLE_READ"]
        let audience = roles.compactMap { role -> ArticleRolePermission? in
            guard let object = role.objectValue,
                  let id = object["id"]?.stringValue,
                  let title = object["title"]?.stringValue,
                  title == "Public" else { return nil }
            return ArticleRolePermission(roleId: id, roleTitle: title, permissions: visible)
        }
        if !audience.isEmpty { return audience }
        return roles.compactMap { role -> ArticleRolePermission? in
            guard let object = role.objectValue,
                  let id = object["id"]?.stringValue,
                  let title = object["title"]?.stringValue,
                  title == "Member" else { return nil }
            return ArticleRolePermission(roleId: id, roleTitle: title, permissions: visible)
        }
    }

    public var defaultEventRolePermissions: [CommunityEventRolePermission] {
        roles.compactMap { role -> CommunityEventRolePermission? in
            guard let object = role.objectValue,
                  let id = object["id"]?.stringValue,
                  let title = object["title"]?.stringValue else { return nil }
            switch title {
            case "Public":
                return CommunityEventRolePermission(
                    roleId: id,
                    roleTitle: title,
                    permissions: ["EVENT_PREVIEW"]
                )
            case "Member":
                return CommunityEventRolePermission(
                    roleId: id,
                    roleTitle: title,
                    permissions: ["EVENT_PREVIEW", "EVENT_ATTEND"]
                )
            default:
                return nil
            }
        }
    }
}

public struct CommunityNotificationState: Codable, Equatable, Sendable {
    public let notifyMentions: Bool
    public let notifyReplies: Bool
    public let notifyPosts: Bool
    public let notifyEvents: Bool
    public let notifyCalls: Bool

    public init(
        notifyMentions: Bool = true,
        notifyReplies: Bool = true,
        notifyPosts: Bool = true,
        notifyEvents: Bool = true,
        notifyCalls: Bool = true
    ) {
        self.notifyMentions = notifyMentions
        self.notifyReplies = notifyReplies
        self.notifyPosts = notifyPosts
        self.notifyEvents = notifyEvents
        self.notifyCalls = notifyCalls
    }

    private enum CodingKeys: String, CodingKey {
        case notifyMentions, notifyReplies, notifyPosts, notifyEvents, notifyCalls
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        notifyMentions = try container.decodeIfPresent(Bool.self, forKey: .notifyMentions) ?? true
        notifyReplies = try container.decodeIfPresent(Bool.self, forKey: .notifyReplies) ?? true
        notifyPosts = try container.decodeIfPresent(Bool.self, forKey: .notifyPosts) ?? true
        notifyEvents = try container.decodeIfPresent(Bool.self, forKey: .notifyEvents) ?? true
        notifyCalls = try container.decodeIfPresent(Bool.self, forKey: .notifyCalls) ?? true
    }
}

public struct CommunityRoleInfo: Identifiable, Equatable, Sendable {
    public let id: String
    public let communityId: String
    public let title: String
    public let type: String
    public let permissions: [String]
    public let description: String?
    public let imageId: String?
    public let assignmentRules: JSONValue?

    init?(_ value: JSONValue) {
        guard let object = value.objectValue,
              let id = object["id"]?.stringValue,
              let communityId = object["communityId"]?.stringValue,
              let title = object["title"]?.stringValue else { return nil }
        self.id = id
        self.communityId = communityId
        self.title = title
        type = object["type"]?.stringValue ?? "PREDEFINED"
        if case .array(let values) = object["permissions"] {
            permissions = values.compactMap(\.stringValue)
        } else {
            permissions = []
        }
        description = object["description"]?.stringValue
        imageId = object["imageId"]?.stringValue
        assignmentRules = object["assignmentRules"]
    }
}

public struct CommunityAreaInfo: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let order: Int

    init?(_ value: JSONValue) {
        guard let object = value.objectValue,
              let id = object["id"]?.stringValue,
              let title = object["title"]?.stringValue else { return nil }
        self.id = id
        self.title = title
        order = Int(object["order"]?.numberValue ?? 0)
    }
}

public struct CommunityPremiumInfo: Equatable, Sendable {
    public let featureName: String
    public let activeUntil: String
    public let autoRenew: String?

    init?(_ value: JSONValue) {
        guard let object = value.objectValue,
              let featureName = object["featureName"]?.stringValue,
              let activeUntil = object["activeUntil"]?.stringValue else { return nil }
        self.featureName = featureName
        self.activeUntil = activeUntil
        autoRenew = object["autoRenew"]?.stringValue
    }
}

public struct CommunityTokenInfo: Identifiable, Equatable, Sendable {
    public let contractId: String
    public let order: Int
    public var id: String { contractId }

    init?(_ value: JSONValue) {
        guard let object = value.objectValue,
              let contractId = object["contractId"]?.stringValue else { return nil }
        self.contractId = contractId
        order = Int(object["order"]?.numberValue ?? 0)
    }
}

public struct CommunityNewsletterEntry: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let creatorId: String
    public let markAsNewsletter: Bool
    public let sentAsNewsletter: String?
    public let url: String?
}

public enum CommunityEventType: String, Codable, CaseIterable, Sendable {
    case external
    case reminder
    case call
    case broadcast

    public var title: String {
        switch self {
        case .external: "External event"
        case .reminder: "Reminder"
        case .call: "Group call"
        case .broadcast: "Broadcast"
        }
    }
}

public struct CommunityEventRolePermission: Codable, Equatable, Sendable {
    public let roleId: String
    public let roleTitle: String
    public let permissions: [String]

    public init(roleId: String, roleTitle: String, permissions: [String]) {
        self.roleId = roleId
        self.roleTitle = roleTitle
        self.permissions = permissions
    }
}

public enum CommunityFeedScope: String, Codable, CaseIterable, Hashable, Sendable {
    case explore = "verified"
    case myCommunities = "following"
}

public struct CommunityEvent: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let type: CommunityEventType
    public let communityId: String
    public let eventCreator: String
    public let url: String?
    public let title: String
    public let description: JSONValue
    public let externalUrl: String?
    public let location: String?
    public let scheduleDate: String
    public let duration: Int
    public let createdAt: String
    public let deletedAt: String?
    public let updatedAt: String
    public let callId: String?
    public let imageId: String?
    public let rolePermissions: [CommunityEventRolePermission]
    public let participantIds: [String]
    public let participantCount: Int
    public let isSelfAttending: Bool

    public var descriptionText: String {
        guard let root = description.objectValue else { return description.stringValue ?? "" }
        if root["version"]?.stringValue == "1" { return root["text"]?.stringValue ?? "" }
        guard case .array(let nodes) = root["content"] else { return "" }
        return nodes.compactMap { node -> String? in
            guard let object = node.objectValue else { return nil }
            switch object["type"]?.stringValue {
            case "newline": return "\n"
            case "text", "link", "richTextLink": return object["value"]?.stringValue
            default: return nil
            }
        }.joined()
    }

    public var canAttend: Bool {
        rolePermissions.contains { $0.permissions.contains("EVENT_ATTEND") }
    }

    private enum CodingKeys: String, CodingKey {
        case id, type, communityId, eventCreator, url, title, description
        case externalUrl, location, scheduleDate, duration, createdAt, deletedAt, updatedAt
        case callId, imageId, rolePermissions, participantIds, participantCount, isSelfAttending
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decode(CommunityEventType.self, forKey: .type)
        communityId = try container.decode(String.self, forKey: .communityId)
        eventCreator = try container.decode(String.self, forKey: .eventCreator)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decode(JSONValue.self, forKey: .description)
        externalUrl = try container.decodeIfPresent(String.self, forKey: .externalUrl)
        location = try container.decodeIfPresent(String.self, forKey: .location)
        scheduleDate = try container.decode(String.self, forKey: .scheduleDate)
        duration = try container.decode(Int.self, forKey: .duration)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        deletedAt = try container.decodeIfPresent(String.self, forKey: .deletedAt)
        updatedAt = try container.decode(String.self, forKey: .updatedAt)
        callId = try container.decodeIfPresent(String.self, forKey: .callId)
        imageId = try container.decodeIfPresent(String.self, forKey: .imageId)
        rolePermissions = try container.decodeIfPresent(
            [CommunityEventRolePermission].self,
            forKey: .rolePermissions
        ) ?? []
        participantIds = try container.decodeIfPresent([String].self, forKey: .participantIds) ?? []
        if let count = try? container.decode(Int.self, forKey: .participantCount) {
            participantCount = count
        } else {
            participantCount = Int(try container.decodeIfPresent(String.self, forKey: .participantCount) ?? "0") ?? 0
        }
        isSelfAttending = try container.decodeIfPresent(Bool.self, forKey: .isSelfAttending) ?? false
    }
}

public struct PluginPermissionSet: Codable, Equatable, Sendable {
    public let mandatory: [String]
    public let optional: [String]
}

public struct PluginConfiguration: Codable, Equatable, Sendable {
    public let canGiveRole: Bool?
    public let giveableRoleIds: [String]?
}

public struct CommunityPluginInfo: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let communityId: String
    public let pluginId: String
    public let ownerCommunityId: String
    public let name: String
    public let description: String?
    public let imageId: String?
    public let config: PluginConfiguration?
    public let url: String
    public let tags: [String]?
    public let permissions: PluginPermissionSet?
    public let acceptedPermissions: [String]?
    public let clonable: Bool
    public let appstoreEnabled: Bool
    public let warnAbusive: Bool
    public let requiresIsolationMode: Bool
    public let reportFlagged: Bool

    init?(_ value: JSONValue) {
        guard let data = try? JSONEncoder().encode(value),
              let decoded = try? JSONDecoder().decode(Self.self, from: data) else { return nil }
        self = decoded
    }
}

public struct PluginBridgeResponse: Codable, Equatable, Sendable {
    public let response: String
    public let signature: String
}

public struct AppStorePlugin: Codable, Equatable, Identifiable, Sendable {
    public let pluginId: String
    public let ownerCommunityId: String
    public let url: String
    public let description: String
    public let permissions: PluginPermissionSet
    public let imageId: String?
    public let name: String
    public let communityCount: Int
    public let appstoreEnabled: Bool
    public let tags: [String]?
    public var id: String { pluginId }

    private enum CodingKeys: String, CodingKey {
        case pluginId, ownerCommunityId, url, description, permissions, imageId
        case name, communityCount, appstoreEnabled, tags
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pluginId = try container.decode(String.self, forKey: .pluginId)
        ownerCommunityId = try container.decode(String.self, forKey: .ownerCommunityId)
        url = try container.decode(String.self, forKey: .url)
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        permissions = try container.decode(PluginPermissionSet.self, forKey: .permissions)
        imageId = try container.decodeIfPresent(String.self, forKey: .imageId)
        name = try container.decode(String.self, forKey: .name)
        if let value = try? container.decode(Int.self, forKey: .communityCount) {
            communityCount = value
        } else {
            communityCount = Int(try container.decode(String.self, forKey: .communityCount)) ?? 0
        }
        appstoreEnabled = try container.decodeIfPresent(Bool.self, forKey: .appstoreEnabled) ?? true
        tags = try container.decodeIfPresent([String].self, forKey: .tags)
    }
}

public struct CommunitySummary: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let url: String
    public let title: String
    public let logoSmallId: String?
    public let logoLargeId: String?
    public let headerImageId: String?
    public let shortDescription: String?
    public let memberCount: Int
    public let tags: [String]
    public let createdAt: String
    public let updatedAt: String

    private enum CodingKeys: String, CodingKey {
        case id, url, title, logoSmallId, logoLargeId, headerImageId
        case shortDescription, memberCount, tags, createdAt, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        url = try container.decode(String.self, forKey: .url)
        title = try container.decode(String.self, forKey: .title)
        logoSmallId = try container.decodeIfPresent(String.self, forKey: .logoSmallId)
        logoLargeId = try container.decodeIfPresent(String.self, forKey: .logoLargeId)
        headerImageId = try container.decodeIfPresent(String.self, forKey: .headerImageId)
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

public struct ChannelMemberEntry: Decodable, Equatable, Identifiable, Sendable {
    public let userId: String
    public let roleIds: [String]
    public var id: String { userId }

    public init(userId: String, roleIds: [String]) {
        self.userId = userId
        self.roleIds = roleIds
    }

    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        userId = try container.decode(String.self)
        roleIds = try container.decode([String].self)
    }
}

public struct CommunityMemberList: Decodable, Equatable, Sendable {
    public let totalCount: Int
    public let resultCount: Int
    public let roles: [CommunityRoleCount]
    public let online: [ChannelMemberEntry]
    public let offline: [ChannelMemberEntry]
}

public struct CommunityRoleCount: Decodable, Equatable, Identifiable, Sendable {
    public let roleId: String
    public let count: Int
    public var id: String { roleId }

    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        roleId = try container.decode(String.self)
        count = try container.decode(Int.self)
    }
}

public struct CommunityBan: Decodable, Equatable, Identifiable, Sendable {
    public let userId: String
    public let blockState: String
    public let blockStateUntil: String?
    public let blockStateUpdatedAt: String?
    public var id: String { userId }
}

public struct CommunityPendingApproval: Decodable, Equatable, Identifiable, Sendable {
    public let communityId: String
    public let userId: String
    public let questionnaireAnswers: [JSONValue]?
    public let approvalState: String
    public var id: String { userId }
}

public struct ChannelMemberList: Decodable, Equatable, Sendable {
    public let count: Int
    public let adminCount: Int
    public let moderatorCount: Int
    public let writerCount: Int
    public let readerCount: Int
    public let offlineCount: Int
    public let admin: [ChannelMemberEntry]
    public let moderator: [ChannelMemberEntry]
    public let writer: [ChannelMemberEntry]
    public let reader: [ChannelMemberEntry]
    public let offline: [ChannelMemberEntry]

    public init(
        count: Int,
        adminCount: Int,
        moderatorCount: Int,
        writerCount: Int,
        readerCount: Int,
        offlineCount: Int,
        admin: [ChannelMemberEntry],
        moderator: [ChannelMemberEntry],
        writer: [ChannelMemberEntry],
        reader: [ChannelMemberEntry],
        offline: [ChannelMemberEntry]
    ) {
        self.count = count
        self.adminCount = adminCount
        self.moderatorCount = moderatorCount
        self.writerCount = writerCount
        self.readerCount = readerCount
        self.offlineCount = offlineCount
        self.admin = admin
        self.moderator = moderator
        self.writer = writer
        self.reader = reader
        self.offline = offline
    }

    public var online: [ChannelMemberEntry] {
        var seen = Set<String>()
        return (admin + moderator + writer + reader).filter { seen.insert($0.userId).inserted }
    }

    public var all: [ChannelMemberEntry] {
        var seen = Set<String>()
        return (online + offline).filter { seen.insert($0.userId).inserted }
    }

    public func appending(_ next: ChannelMemberList) -> ChannelMemberList {
        ChannelMemberList(
            count: next.count,
            adminCount: next.adminCount,
            moderatorCount: next.moderatorCount,
            writerCount: next.writerCount,
            readerCount: next.readerCount,
            offlineCount: next.offlineCount,
            admin: admin + next.admin,
            moderator: moderator + next.moderator,
            writer: writer + next.writer,
            reader: reader + next.reader,
            offline: offline + next.offline
        )
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

public struct MessageAccess: Codable, Hashable, Sendable {
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

    public static func communityArticle(
        _ communityId: String,
        articleId: String,
        channelId: String
    ) -> MessageAccess {
        MessageAccess(
            channelId: channelId,
            articleId: articleId,
            articleCommunityId: communityId
        )
    }

    public static func userArticle(
        _ userId: String,
        articleId: String,
        channelId: String
    ) -> MessageAccess {
        MessageAccess(
            channelId: channelId,
            articleId: articleId,
            articleUserId: userId
        )
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

public enum PendingMessageState: String, Codable, Equatable, Sendable {
    case queued
    case sending
    case failed
}

public struct PendingMessage: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let creatorID: String
    public let access: MessageAccess
    public let text: String
    public let mentions: [String: String]
    public let parentMessageID: String?
    public let imageAttachments: [MessageImageAttachment]
    public let createdAt: String
    public var state: PendingMessageState
    public var lastError: String?

    public init(
        id: String,
        creatorID: String,
        access: MessageAccess,
        text: String,
        mentions: [String: String],
        parentMessageID: String?,
        imageAttachments: [MessageImageAttachment],
        createdAt: String,
        state: PendingMessageState = .queued,
        lastError: String? = nil
    ) {
        self.id = id
        self.creatorID = creatorID
        self.access = access
        self.text = text
        self.mentions = mentions
        self.parentMessageID = parentMessageID
        self.imageAttachments = imageAttachments
        self.createdAt = createdAt
        self.state = state
        self.lastError = lastError
    }

    public var placeholder: Message {
        Message(
            id: id,
            creatorId: creatorID,
            channelId: access.channelId,
            body: .composed(text, mentions: mentions),
            attachments: imageAttachments.map(\.jsonValue),
            editedAt: nil,
            createdAt: createdAt,
            updatedAt: createdAt,
            reactions: [:],
            ownReaction: nil,
            parentMessageId: parentMessageID
        )
    }
}

public struct MessageUpdates: Decodable, Equatable, Sendable {
    public let updated: [Message]
    public let deleted: [String]
}

public struct URLPreview: Codable, Equatable, Sendable {
    public let title: String
    public let description: String
    public let imageId: String?
    public let url: String
}
