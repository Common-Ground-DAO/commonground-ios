import Foundation

public struct CommunityAPI: Sendable {
    private let transport: HTTPTransport
    public init(transport: HTTPTransport) { self.transport = transport }

    public func detail(id: String) async throws -> Community {
        try await transport.call("Community/getCommunityDetailView", body: IDRequest(id: id))
    }

    public func join(id: String) async throws -> Community? {
        try await transport.call("Community/joinCommunity", body: IDRequest(id: id))
    }

    public func leave(id: String) async throws -> Community {
        try await transport.call("Community/leaveCommunity", body: IDRequest(id: id))
    }

    public func list(
        search: String? = nil,
        sort: CommunitySort = .popular,
        offset: Int = 0,
        limit: Int = 50
    ) async throws -> [CommunitySummary] {
        try await transport.call(
            "Community/getCommunityList",
            body: CommunityListRequest(
                offset: offset,
                sort: sort,
                tags: [],
                limit: limit,
                search: search
            )
        )
    }

    public func create(
        title: String,
        shortDescription: String = "",
        description: String = "",
        tags: [String] = [],
        links: [CommunityLink] = [],
        logoSmallID: String,
        logoLargeID: String,
        headerImageID: String? = nil
    ) async throws -> Community {
        try await transport.call(
            "Community/createCommunity",
            body: CreateCommunityRequest(
                title: title,
                shortDescription: shortDescription,
                description: description,
                tags: tags,
                links: links,
                logoSmallId: logoSmallID,
                logoLargeId: logoLargeID,
                headerImageId: headerImageID
            )
        )
    }

    public func update(
        id: String,
        title: String,
        shortDescription: String,
        description: String,
        tags: [String],
        links: [CommunityLink]
    ) async throws {
        let _: EmptyResponse = try await transport.call(
            "Community/updateCommunity",
            body: UpdateCommunityRequest(
                id: id,
                title: title,
                shortDescription: shortDescription,
                description: description,
                links: links,
                tags: tags
            )
        )
    }

    public func channelMembers(
        communityID: String,
        channelID: String,
        offset: Int = 0,
        limit: Int = 100,
        search: String? = nil
    ) async throws -> ChannelMemberList {
        try await transport.call(
            "Community/getChannelMemberList",
            body: ChannelMemberListRequest(
                communityId: communityID,
                channelId: channelID,
                offset: offset,
                limit: limit,
                search: search
            )
        )
    }

    public func members(
        communityID: String,
        offset: Int = 0,
        limit: Int = 100,
        search: String? = nil,
        roleID: String? = nil
    ) async throws -> CommunityMemberList {
        try await transport.call(
            "Community/getMemberList",
            body: CommunityMemberListRequest(
                communityId: communityID,
                offset: offset,
                limit: limit,
                search: search,
                roleId: roleID
            )
        )
    }

    public func bannedUsers(communityID: String, limit: Int = 100) async throws -> [CommunityBan] {
        try await transport.call(
            "Community/getBannedUsers",
            body: BannedUsersRequest(communityId: communityID, limit: limit, before: nil)
        )
    }

    public func setBlockState(
        communityID: String,
        userID: String,
        state: String?,
        until: String? = nil
    ) async throws {
        let _: EmptyResponse = try await transport.call(
            "Community/setUserBlockState",
            body: SetCommunityBlockStateRequest(
                userId: userID,
                communityId: communityID,
                until: until,
                blockState: state
            )
        )
    }

    public func setOnboardingOptions(
        communityID: String,
        options: JSONValue,
        password: String? = nil
    ) async throws {
        let _: EmptyResponse = try await transport.call(
            "Community/setOnboardingOptions",
            body: SetOnboardingOptionsRequest(
                communityId: communityID,
                onboardingOptions: options,
                password: password
            )
        )
    }

    public func communityPassword(communityID: String) async throws -> String? {
        let response: CommunityPasswordResponse = try await transport.call(
            "Community/getCommunityPassword",
            body: CommunityIDRequest(communityId: communityID)
        )
        return response.password
    }

    public func pendingApprovals(communityID: String) async throws -> [CommunityPendingApproval] {
        try await transport.call(
            "Community/getPendingJoinApprovals",
            body: CommunityIDRequest(communityId: communityID)
        )
    }

    public func setPendingApproval(
        communityID: String,
        userID: String,
        state: String,
        message: String? = nil
    ) async throws {
        let _: EmptyResponse = try await transport.call(
            "Community/setPendingJoinApproval",
            body: SetPendingApprovalRequest(
                communityId: communityID,
                userId: userID,
                approvalState: state,
                message: message
            )
        )
    }

    public func setPersonalNewsletter(communityID: String, enabled: Bool) async throws {
        let _: EmptyResponse = try await transport.call(
            "Community/updateCommunity",
            body: PersonalNewsletterRequest(id: communityID, enablePersonalNewsletter: enabled)
        )
    }

    public func newsletterHistory(
        communityID: String,
        timeframe: String
    ) async throws -> [CommunityNewsletterEntry] {
        let response: NewsletterHistoryResponse = try await transport.call(
            "Community/getNewsletterHistory",
            body: NewsletterHistoryRequest(communityId: communityID, timeframe: timeframe)
        )
        return response.entries
    }

    public func sendArticleAsNewsletter(communityID: String, articleID: String) async throws {
        let _: EmptyResponse = try await transport.call(
            "Community/sendArticleAsEmail",
            body: CommunityArticleIDRequest(communityId: communityID, articleId: articleID)
        )
    }

    public func events(communityID: String) async throws -> [CommunityEvent] {
        try await transport.call(
            "Community/getEventList",
            body: CommunityIDRequest(communityId: communityID)
        )
    }

    public func myEvents(
        scheduledBefore: String? = nil,
        beforeID: String? = nil
    ) async throws -> [CommunityEvent] {
        try await transport.call(
            "Community/getMyEvents",
            body: MyEventsRequest(scheduledBefore: scheduledBefore, beforeId: beforeID)
        )
    }

    public func event(id: String) async throws -> CommunityEvent {
        try await transport.call("Community/getEvent", body: IDRequest(id: id))
    }

    public func createEvent(
        communityID: String,
        type: CommunityEventType,
        title: String,
        description: String,
        duration: Int,
        imageID: String?,
        scheduledAt: String,
        rolePermissions: [CommunityEventRolePermission],
        externalURL: String?,
        location: String?
    ) async throws -> CommunityEvent {
        try await transport.call(
            "Community/createCommunityEvent",
            body: CreateCommunityEventRequest(
                type: type,
                communityId: communityID,
                title: title,
                description: description,
                duration: duration,
                url: nil,
                imageId: imageID,
                scheduleDate: scheduledAt,
                rolePermissions: rolePermissions.filter { $0.roleTitle != "Admin" },
                externalUrl: type == .external ? externalURL : nil,
                location: type == .external ? location : nil
            )
        )
    }

    public func updateEvent(
        id: String,
        type: CommunityEventType,
        title: String,
        description: String,
        duration: Int,
        imageID: String?,
        scheduledAt: String,
        rolePermissions: [CommunityEventRolePermission],
        externalURL: String?,
        location: String?
    ) async throws -> CommunityEvent {
        try await transport.call(
            "Community/updateCommunityEvent",
            body: UpdateCommunityEventRequest(
                id: id,
                type: type,
                title: title,
                description: description,
                duration: duration,
                imageId: imageID,
                scheduleDate: scheduledAt,
                rolePermissions: rolePermissions.filter { $0.roleTitle != "Admin" },
                externalUrl: type == .external ? externalURL : nil,
                location: type == .external ? location : nil
            )
        )
    }

    public func deleteEvent(communityID: String, eventID: String) async throws {
        let _: EmptyResponse = try await transport.call(
            "Community/deleteCommunityEvent",
            body: DeleteCommunityEventRequest(eventId: eventID, communityId: communityID)
        )
    }

    public func attendEvent(id: String) async throws {
        let _: EmptyResponse = try await transport.call(
            "Community/addEventParticipant",
            body: EventIDRequest(eventId: id)
        )
    }

    public func leaveEvent(id: String) async throws {
        let _: EmptyResponse = try await transport.call(
            "Community/removeEventParticipant",
            body: EventIDRequest(eventId: id)
        )
    }

    public func giveSpark(communityID: String, amount: Int) async throws {
        let _: EmptyResponse = try await transport.call(
            "Community/givePointsToCommunity",
            body: GiveSparkRequest(communityId: communityID, amount: amount)
        )
    }

    public func setAllowUserBots(communityID: String, allowed: Bool) async throws {
        let _: EmptyResponse = try await transport.call(
            "Community/updateCommunity",
            body: AllowUserBotsRequest(id: communityID, allowUserBots: allowed)
        )
    }

    public func updateNotificationState(
        communityID: String,
        state: CommunityNotificationState
    ) async throws {
        let _: EmptyResponse = try await transport.call(
            "Community/updateNotificationState",
            body: UpdateCommunityNotificationStateRequest(
                data: [CommunityNotificationStateEntry(communityId: communityID, state: state)]
            )
        )
    }

    public func createRole(communityID: String, title: String) async throws -> String {
        let response: RoleIDResponse = try await transport.call(
            "Community/createRole",
            body: CreateRoleRequest(
                title: title,
                type: "CUSTOM_MANUAL_ASSIGN",
                imageId: nil,
                assignmentRules: nil,
                communityId: communityID,
                description: nil,
                permissions: []
            )
        )
        return response.id
    }

    public func updateRole(
        communityID: String,
        roleID: String,
        title: String?,
        description: String?,
        permissions: [String]?,
        type: String? = nil,
        assignmentRules: JSONValue? = nil
    ) async throws {
        let _: EmptyResponse = try await transport.call(
            "Community/updateRole",
            body: UpdateRoleRequest(
                id: roleID,
                communityId: communityID,
                title: title,
                description: description,
                permissions: permissions,
                type: type,
                assignmentRules: assignmentRules
            )
        )
    }

    public func deleteRole(communityID: String, roleID: String) async throws {
        let _: EmptyResponse = try await transport.call(
            "Community/deleteRole",
            body: DeleteRoleRequest(id: roleID, communityId: communityID)
        )
    }

    public func addUserToRoles(communityID: String, userID: String, roleIDs: [String]) async throws {
        guard !roleIDs.isEmpty else { return }
        let _: EmptyResponse = try await transport.call(
            "Community/addUserToRoles",
            body: UserRolesRequest(userId: userID, communityId: communityID, roleIds: roleIDs)
        )
    }

    public func removeUserFromRoles(communityID: String, userID: String, roleIDs: [String]) async throws {
        guard !roleIDs.isEmpty else { return }
        let _: EmptyResponse = try await transport.call(
            "Community/removeUserFromRoles",
            body: UserRolesRequest(userId: userID, communityId: communityID, roleIds: roleIDs)
        )
    }

    public func createArea(communityID: String, title: String, order: Int) async throws {
        let _: EmptyResponse = try await transport.call(
            "Community/createArea",
            body: CreateAreaRequest(communityId: communityID, title: title, order: order)
        )
    }

    public func updateArea(
        communityID: String,
        areaID: String,
        title: String? = nil,
        order: Int? = nil
    ) async throws {
        let _: EmptyResponse = try await transport.call(
            "Community/updateArea",
            body: UpdateAreaRequest(id: areaID, communityId: communityID, title: title, order: order)
        )
    }

    public func deleteArea(communityID: String, areaID: String) async throws {
        let _: EmptyResponse = try await transport.call(
            "Community/deleteArea",
            body: DeleteAreaRequest(id: areaID, communityId: communityID)
        )
    }

    public func createChannel(
        communityID: String,
        areaID: String,
        title: String,
        url: String?,
        order: Int,
        description: String?,
        emoji: String?,
        roleAccess: [ChannelRoleAccess]
    ) async throws {
        let _: EmptyResponse = try await transport.call(
            "Community/createChannel",
            body: CreateChannelRequest(
                communityId: communityID,
                areaId: areaID,
                title: title,
                url: url,
                order: order,
                description: description,
                emoji: emoji,
                rolePermissions: roleAccess
                    .filter { $0.roleTitle != "Admin" }
                    .map(\.jsonValue)
            )
        )
    }

    public func updateChannel(
        communityID: String,
        channelID: String,
        areaID: String?,
        title: String,
        url: String?,
        order: Int,
        description: String?,
        emoji: String?,
        roleAccess: [ChannelRoleAccess]
    ) async throws {
        let _: EmptyResponse = try await transport.call(
            "Community/updateChannel",
            body: UpdateChannelRequest(
                channelId: channelID,
                communityId: communityID,
                areaId: areaID,
                title: title,
                url: url,
                order: order,
                description: description,
                emoji: emoji,
                rolePermissions: roleAccess
                    .filter { $0.roleTitle != "Admin" }
                    .map(\.jsonValue)
            )
        )
    }

    /// Updates only the fields needed when moving a channel. Keeping this request
    /// partial avoids rewriting channel metadata and role permissions during a drag.
    public func updateChannelOrder(
        communityID: String,
        channelID: String,
        areaID: String,
        order: Int
    ) async throws {
        let _: EmptyResponse = try await transport.call(
            "Community/updateChannel",
            body: UpdateChannelOrderRequest(
                channelId: channelID,
                communityId: communityID,
                areaId: areaID,
                order: order
            )
        )
    }

    public func deleteChannel(communityID: String, channelID: String) async throws {
        let _: EmptyResponse = try await transport.call(
            "Community/deleteChannel",
            body: DeleteChannelRequest(channelId: channelID, communityId: communityID)
        )
    }

    public func setPinnedMessages(
        communityID: String,
        channelID: String,
        messageIDs: [String]
    ) async throws {
        let _: EmptyResponse = try await transport.call(
            "Community/updateChannel",
            body: PinnedMessagesRequest(
                communityId: communityID,
                channelId: channelID,
                pinnedMessageIds: Array(messageIDs.prefix(2))
            )
        )
    }

    public func addToken(communityID: String, contractID: String, order: Int) async throws {
        let _: EmptyResponse = try await transport.call(
            "Community/addCommunityToken",
            body: CommunityTokenRequest(
                communityId: communityID,
                contractId: contractID,
                order: order
            )
        )
    }

    public func removeToken(communityID: String, contractID: String) async throws {
        let _: EmptyResponse = try await transport.call(
            "Community/removeCommunityToken",
            body: RemoveCommunityTokenRequest(communityId: communityID, contractId: contractID)
        )
    }

    public func buyPremium(
        communityID: String,
        feature: String,
        duration: String
    ) async throws {
        let _: EmptyResponse = try await transport.call(
            "Community/buyCommunityPremiumFeature",
            body: BuyCommunityPremiumRequest(
                communityId: communityID,
                featureName: feature,
                duration: duration
            )
        )
    }

    public func setPremiumAutoRenew(
        communityID: String,
        feature: String,
        autoRenew: String?
    ) async throws {
        let _: EmptyResponse = try await transport.call(
            "Community/setPremiumFeatureAutoRenew",
            body: PremiumAutoRenewRequest(
                communityId: communityID,
                featureName: feature,
                autoRenew: autoRenew
            )
        )
    }
}

public enum CommunitySort: String, Encodable, Sendable {
    case new
    case popular
}

public struct MessageAPI: Sendable {
    private let transport: HTTPTransport
    public init(transport: HTTPTransport) { self.transport = transport }

    public func load(
        access: MessageAccess,
        order: MessageOrder = .descending,
        createdBefore: String? = ISO8601DateFormatter().string(from: Date()),
        createdAfter: String? = nil
    ) async throws -> [Message] {
        try await transport.call(
            "Message/loadMessages",
            body: LoadMessagesRequest(
                access: access,
                order: order,
                createdBefore: createdBefore,
                createdAfter: createdAfter
            )
        )
    }

    public func byIDs(access: MessageAccess, messageIDs: [String]) async throws -> [Message] {
        try await transport.call(
            "Message/messagesById",
            body: MessagesByIDRequest(access: access, messageIds: messageIDs)
        )
    }

    public func updates(
        access: MessageAccess,
        createdStart: String,
        createdEnd: String,
        updatedAfter: String
    ) async throws -> MessageUpdates {
        try await transport.call(
            "Message/loadUpdates",
            body: MessageUpdatesRequest(
                access: access,
                createdStart: createdStart,
                createdEnd: createdEnd,
                updatedAfter: updatedAfter
            )
        )
    }

    public func urlPreview(_ url: String) async throws -> URLPreview {
        try await transport.call("Message/getUrlPreview", body: URLPreviewRequest(url: url))
    }

    public func send(
        access: MessageAccess,
        text: String,
        mentions: [String: String] = [:],
        parentMessageID: String? = nil,
        imageAttachments: [MessageImageAttachment] = [],
        id: UUID = UUID()
    ) async throws -> Message {
        try await transport.call(
            "Message/createMessage",
            body: CreateMessageRequest(
                id: id.uuidString.lowercased(),
                access: access,
                body: .composed(text, mentions: mentions),
                parentMessageId: parentMessageID,
                attachments: imageAttachments.map(\.jsonValue)
            )
        )
    }

    public func edit(
        access: MessageAccess,
        messageID: String,
        text: String,
        mentions: [String: String] = [:]
    ) async throws -> MessageEditResult {
        try await transport.call(
            "Message/editMessage",
            body: EditMessageRequest(
                access: access,
                id: messageID,
                body: .composed(text, mentions: mentions)
            )
        )
    }

    public func delete(access: MessageAccess, messageID: String, creatorID: String) async throws {
        let _: EmptyResponse = try await transport.call(
            "Message/deleteMessage",
            body: DeleteMessageRequest(access: access, messageId: messageID, creatorId: creatorID)
        )
    }

    public func deleteAll(access: MessageAccess, creatorID: String) async throws {
        let _: EmptyResponse = try await transport.call(
            "Message/deleteAllUserMessages",
            body: DeleteAllUserMessagesRequest(access: access, creatorId: creatorID)
        )
    }

    public func setReaction(access: MessageAccess, messageID: String, reaction: String) async throws {
        let _: EmptyResponse = try await transport.call(
            "Message/setReaction",
            body: SetReactionRequest(access: access, messageId: messageID, reaction: reaction)
        )
    }

    public func unsetReaction(access: MessageAccess, messageID: String) async throws {
        let _: EmptyResponse = try await transport.call(
            "Message/unsetReaction",
            body: UnsetReactionRequest(access: access, messageId: messageID)
        )
    }

    public func setLastRead(access: MessageAccess, date: String) async throws {
        let _: EmptyResponse = try await transport.call(
            "Message/setChannelLastRead",
            body: SetLastReadRequest(access: access, lastRead: date)
        )
    }
}

public enum MessageOrder: String, Encodable, Sendable {
    case ascending = "ASC"
    case descending = "DESC"
}

public struct MessageEditResult: Codable, Equatable, Sendable {
    public let editedAt: String
    public let attachments: [JSONValue]?
}

public struct ChatAPI: Sendable {
    private let transport: HTTPTransport
    public init(transport: HTTPTransport) { self.transport = transport }

    public func list() async throws -> [Chat] {
        try await transport.call("Chat/getChats")
    }

    public func start(otherUserID: String) async throws -> Chat {
        try await transport.call(
            "Chat/startChat",
            body: OtherUserRequest(otherUserId: otherUserID)
        )
    }

    public func close(chatID: String) async throws {
        let _: EmptyResponse = try await transport.call(
            "Chat/closeChat",
            body: ChatIDRequest(chatId: chatID)
        )
    }
}

private struct IDRequest: Encodable, Sendable { let id: String }
private struct CommunityListRequest: Encodable, Sendable {
    let offset: Int
    let sort: CommunitySort
    let tags: [String]
    let limit: Int
    let search: String?
}
private struct CreateCommunityRequest: Encodable, Sendable {
    let title: String
    let shortDescription: String
    let description: String
    let tags: [String]
    let links: [CommunityLink]
    let logoSmallId: String
    let logoLargeId: String
    let headerImageId: String?

    private enum CodingKeys: String, CodingKey {
        case title, shortDescription, description, tags, links
        case logoSmallId, logoLargeId, headerImageId
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(shortDescription, forKey: .shortDescription)
        try container.encode(description, forKey: .description)
        try container.encode(tags, forKey: .tags)
        try container.encode(links, forKey: .links)
        try container.encode(logoSmallId, forKey: .logoSmallId)
        try container.encode(logoLargeId, forKey: .logoLargeId)
        if let headerImageId {
            try container.encode(headerImageId, forKey: .headerImageId)
        } else {
            try container.encodeNil(forKey: .headerImageId)
        }
    }
}
private struct UpdateCommunityRequest: Encodable, Sendable {
    let id: String
    let title: String
    let shortDescription: String
    let description: String
    let links: [CommunityLink]
    let tags: [String]
}
private struct ChannelMemberListRequest: Encodable, Sendable {
    let communityId: String
    let channelId: String
    let offset: Int
    let limit: Int
    let search: String?
}
private struct CommunityMemberListRequest: Encodable, Sendable {
    let communityId: String
    let offset: Int
    let limit: Int
    let search: String?
    let roleId: String?
}
private struct BannedUsersRequest: Encodable, Sendable {
    let communityId: String
    let limit: Int?
    let before: String?
}
private struct SetCommunityBlockStateRequest: Encodable, Sendable {
    let userId: String
    let communityId: String
    let until: String?
    let blockState: String?

    enum CodingKeys: String, CodingKey { case userId, communityId, until, blockState }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userId, forKey: .userId)
        try container.encode(communityId, forKey: .communityId)
        if let until { try container.encode(until, forKey: .until) }
        else { try container.encodeNil(forKey: .until) }
        if let blockState { try container.encode(blockState, forKey: .blockState) }
        else { try container.encodeNil(forKey: .blockState) }
    }
}
private struct SetOnboardingOptionsRequest: Encodable, Sendable {
    let communityId: String
    let onboardingOptions: JSONValue
    let password: String?

    enum CodingKeys: String, CodingKey { case communityId, onboardingOptions, password }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(communityId, forKey: .communityId)
        try container.encode(onboardingOptions, forKey: .onboardingOptions)
        if let password { try container.encode(password, forKey: .password) }
        else { try container.encodeNil(forKey: .password) }
    }
}
private struct CommunityIDRequest: Encodable, Sendable { let communityId: String }
private struct CommunityPasswordResponse: Decodable, Sendable { let password: String? }
private struct SetPendingApprovalRequest: Encodable, Sendable {
    let communityId: String
    let userId: String
    let approvalState: String
    let message: String?
}
private struct PersonalNewsletterRequest: Encodable, Sendable {
    let id: String
    let enablePersonalNewsletter: Bool
}
private struct NewsletterHistoryRequest: Encodable, Sendable {
    let communityId: String
    let timeframe: String
}
private struct NewsletterHistoryResponse: Decodable, Sendable {
    let entries: [CommunityNewsletterEntry]
}
private struct CommunityArticleIDRequest: Encodable, Sendable {
    let communityId: String
    let articleId: String
}
private struct EventIDRequest: Encodable, Sendable { let eventId: String }
private struct MyEventsRequest: Encodable, Sendable {
    let scheduledBefore: String?
    let beforeId: String?

    enum CodingKeys: String, CodingKey { case scheduledBefore, beforeId }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let scheduledBefore { try container.encode(scheduledBefore, forKey: .scheduledBefore) }
        else { try container.encodeNil(forKey: .scheduledBefore) }
        if let beforeId { try container.encode(beforeId, forKey: .beforeId) }
        else { try container.encodeNil(forKey: .beforeId) }
    }
}
private struct DeleteCommunityEventRequest: Encodable, Sendable {
    let eventId: String
    let communityId: String
}
private struct CreateCommunityEventRequest: Encodable, Sendable {
    let type: CommunityEventType
    let communityId: String
    let title: String
    let description: String
    let duration: Int
    let url: String?
    let imageId: String?
    let scheduleDate: String
    let rolePermissions: [CommunityEventRolePermission]
    let externalUrl: String?
    let location: String?

    private enum CodingKeys: String, CodingKey {
        case type, communityId, title, description, duration, url, imageId
        case scheduleDate, rolePermissions, externalUrl, location
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(communityId, forKey: .communityId)
        try container.encode(title, forKey: .title)
        try container.encode(description, forKey: .description)
        try container.encode(duration, forKey: .duration)
        try container.encodeNil(forKey: .url)
        if let imageId { try container.encode(imageId, forKey: .imageId) }
        else { try container.encodeNil(forKey: .imageId) }
        try container.encode(scheduleDate, forKey: .scheduleDate)
        try container.encode(rolePermissions, forKey: .rolePermissions)
        if let externalUrl { try container.encode(externalUrl, forKey: .externalUrl) }
        else { try container.encodeNil(forKey: .externalUrl) }
        if let location { try container.encode(location, forKey: .location) }
        else { try container.encodeNil(forKey: .location) }
    }
}
private struct UpdateCommunityEventRequest: Encodable, Sendable {
    let id: String
    let type: CommunityEventType
    let title: String
    let description: String
    let duration: Int
    let imageId: String?
    let scheduleDate: String
    let rolePermissions: [CommunityEventRolePermission]
    let externalUrl: String?
    let location: String?

    private enum CodingKeys: String, CodingKey {
        case id, type, title, description, duration, imageId
        case scheduleDate, rolePermissions, externalUrl, location
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encode(title, forKey: .title)
        try container.encode(description, forKey: .description)
        try container.encode(duration, forKey: .duration)
        if let imageId { try container.encode(imageId, forKey: .imageId) }
        else { try container.encodeNil(forKey: .imageId) }
        try container.encode(scheduleDate, forKey: .scheduleDate)
        try container.encode(rolePermissions, forKey: .rolePermissions)
        if let externalUrl { try container.encode(externalUrl, forKey: .externalUrl) }
        else { try container.encodeNil(forKey: .externalUrl) }
        if let location { try container.encode(location, forKey: .location) }
        else { try container.encodeNil(forKey: .location) }
    }
}
private struct GiveSparkRequest: Encodable, Sendable {
    let communityId: String
    let amount: Int
}
private struct AllowUserBotsRequest: Encodable, Sendable {
    let id: String
    let allowUserBots: Bool
}
private struct UpdateCommunityNotificationStateRequest: Encodable, Sendable {
    let data: [CommunityNotificationStateEntry]
}
private struct CommunityNotificationStateEntry: Encodable, Sendable {
    let communityId: String
    let notifyMentions: Bool
    let notifyReplies: Bool
    let notifyPosts: Bool
    let notifyEvents: Bool
    let notifyCalls: Bool

    init(communityId: String, state: CommunityNotificationState) {
        self.communityId = communityId
        notifyMentions = state.notifyMentions
        notifyReplies = state.notifyReplies
        notifyPosts = state.notifyPosts
        notifyEvents = state.notifyEvents
        notifyCalls = state.notifyCalls
    }
}
private struct RoleIDResponse: Decodable, Sendable { let id: String }
private struct CreateRoleRequest: Encodable, Sendable {
    let title: String
    let type: String
    let imageId: String?
    let assignmentRules: JSONValue?
    let communityId: String
    let description: String?
    let permissions: [String]

    enum CodingKeys: String, CodingKey {
        case title, type, imageId, assignmentRules, communityId, description, permissions
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(type, forKey: .type)
        try container.encodeNil(forKey: .imageId)
        try container.encodeNil(forKey: .assignmentRules)
        try container.encode(communityId, forKey: .communityId)
        try container.encodeNil(forKey: .description)
        try container.encode(permissions, forKey: .permissions)
    }
}
private struct UpdateRoleRequest: Encodable, Sendable {
    let id: String
    let communityId: String
    let title: String?
    let description: String?
    let permissions: [String]?
    let type: String?
    let assignmentRules: JSONValue?

    private enum CodingKeys: String, CodingKey {
        case id, communityId, title, description, permissions, type, assignmentRules
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(communityId, forKey: .communityId)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(permissions, forKey: .permissions)
        try container.encodeIfPresent(type, forKey: .type)
        if type != nil {
            if let assignmentRules { try container.encode(assignmentRules, forKey: .assignmentRules) }
            else { try container.encodeNil(forKey: .assignmentRules) }
        }
    }
}
private struct DeleteRoleRequest: Encodable, Sendable {
    let id: String
    let communityId: String
}
private struct UserRolesRequest: Encodable, Sendable {
    let userId: String
    let communityId: String
    let roleIds: [String]
}
private struct CreateAreaRequest: Encodable, Sendable {
    let communityId: String
    let title: String
    let order: Int
}
private struct UpdateAreaRequest: Encodable, Sendable {
    let id: String
    let communityId: String
    let title: String?
    let order: Int?
}
private struct DeleteAreaRequest: Encodable, Sendable {
    let id: String
    let communityId: String
}
private struct CreateChannelRequest: Encodable, Sendable {
    let communityId: String
    let areaId: String
    let title: String
    let url: String?
    let order: Int
    let description: String?
    let emoji: String?
    let rolePermissions: [JSONValue]

    enum CodingKeys: String, CodingKey {
        case communityId, areaId, title, url, order, description, emoji, rolePermissions
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(communityId, forKey: .communityId)
        try container.encode(areaId, forKey: .areaId)
        try container.encode(title, forKey: .title)
        if let url { try container.encode(url, forKey: .url) }
        else { try container.encodeNil(forKey: .url) }
        try container.encode(order, forKey: .order)
        if let description { try container.encode(description, forKey: .description) }
        else { try container.encodeNil(forKey: .description) }
        if let emoji { try container.encode(emoji, forKey: .emoji) }
        else { try container.encodeNil(forKey: .emoji) }
        try container.encode(rolePermissions, forKey: .rolePermissions)
    }
}
private struct UpdateChannelRequest: Encodable, Sendable {
    let channelId: String
    let communityId: String
    let areaId: String?
    let title: String
    let url: String?
    let order: Int
    let description: String?
    let emoji: String?
    let rolePermissions: [JSONValue]

    enum CodingKeys: String, CodingKey {
        case channelId, communityId, areaId, title, url, order, description, emoji, rolePermissions
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(channelId, forKey: .channelId)
        try container.encode(communityId, forKey: .communityId)
        if let areaId { try container.encode(areaId, forKey: .areaId) }
        try container.encode(title, forKey: .title)
        if let url { try container.encode(url, forKey: .url) }
        else { try container.encodeNil(forKey: .url) }
        try container.encode(order, forKey: .order)
        if let description { try container.encode(description, forKey: .description) }
        else { try container.encodeNil(forKey: .description) }
        if let emoji { try container.encode(emoji, forKey: .emoji) }
        else { try container.encodeNil(forKey: .emoji) }
        try container.encode(rolePermissions, forKey: .rolePermissions)
    }
}
private struct UpdateChannelOrderRequest: Encodable, Sendable {
    let channelId: String
    let communityId: String
    let areaId: String
    let order: Int
}
private struct DeleteChannelRequest: Encodable, Sendable {
    let channelId: String
    let communityId: String
}
private struct PinnedMessagesRequest: Encodable, Sendable {
    let communityId: String
    let channelId: String
    let pinnedMessageIds: [String]
}
private struct CommunityTokenRequest: Encodable, Sendable {
    let communityId: String
    let contractId: String
    let order: Int
}
private struct RemoveCommunityTokenRequest: Encodable, Sendable {
    let communityId: String
    let contractId: String
}
private struct BuyCommunityPremiumRequest: Encodable, Sendable {
    let communityId: String
    let featureName: String
    let duration: String
}
private struct PremiumAutoRenewRequest: Encodable, Sendable {
    let communityId: String
    let featureName: String
    let autoRenew: String?
}
private struct OtherUserRequest: Encodable, Sendable { let otherUserId: String }
private struct ChatIDRequest: Encodable, Sendable { let chatId: String }
private struct LoadMessagesRequest: Encodable, Sendable {
    let access: MessageAccess
    let order: MessageOrder
    let createdBefore: String?
    let createdAfter: String?
}
private struct MessagesByIDRequest: Encodable, Sendable {
    let access: MessageAccess
    let messageIds: [String]
}
private struct MessageUpdatesRequest: Encodable, Sendable {
    let access: MessageAccess
    let createdStart: String
    let createdEnd: String
    let updatedAfter: String
}
private struct URLPreviewRequest: Encodable, Sendable { let url: String }
private struct CreateMessageRequest: Encodable, Sendable {
    let id: String
    let access: MessageAccess
    let body: MessageBody
    let parentMessageId: String?
    let attachments: [JSONValue]

    enum CodingKeys: String, CodingKey { case id, access, body, parentMessageId, attachments }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(access, forKey: .access)
        try container.encode(body, forKey: .body)
        if let parentMessageId {
            try container.encode(parentMessageId, forKey: .parentMessageId)
        } else {
            try container.encodeNil(forKey: .parentMessageId)
        }
        try container.encode(attachments, forKey: .attachments)
    }
}
private struct EditMessageRequest: Encodable, Sendable {
    let access: MessageAccess
    let id: String
    let body: MessageBody
}
private struct DeleteMessageRequest: Encodable, Sendable {
    let access: MessageAccess
    let messageId: String
    let creatorId: String
}
private struct DeleteAllUserMessagesRequest: Encodable, Sendable {
    let access: MessageAccess
    let creatorId: String
}
private struct SetReactionRequest: Encodable, Sendable {
    let access: MessageAccess
    let messageId: String
    let reaction: String
}
private struct UnsetReactionRequest: Encodable, Sendable {
    let access: MessageAccess
    let messageId: String
}
private struct SetLastReadRequest: Encodable, Sendable {
    let access: MessageAccess
    let lastRead: String
}
