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
        tags: [String] = []
    ) async throws -> Community {
        try await transport.call(
            "Community/createCommunity",
            body: CreateCommunityRequest(
                title: title,
                shortDescription: shortDescription,
                description: description,
                tags: tags
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
        createdBefore: String = ISO8601DateFormatter().string(from: Date())
    ) async throws -> [Message] {
        try await transport.call(
            "Message/loadMessages",
            body: LoadMessagesRequest(access: access, createdBefore: createdBefore)
        )
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
        text: String
    ) async throws -> MessageEditResult {
        try await transport.call(
            "Message/editMessage",
            body: EditMessageRequest(access: access, id: messageID, body: .text(text))
        )
    }

    public func delete(access: MessageAccess, messageID: String, creatorID: String) async throws {
        let _: EmptyResponse = try await transport.call(
            "Message/deleteMessage",
            body: DeleteMessageRequest(access: access, messageId: messageID, creatorId: creatorID)
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

    private enum CodingKeys: String, CodingKey {
        case title, logoSmallId, logoLargeId, headerImageId
        case shortDescription, description, links, tags
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encodeNil(forKey: .logoSmallId)
        try container.encodeNil(forKey: .logoLargeId)
        try container.encodeNil(forKey: .headerImageId)
        try container.encode(shortDescription, forKey: .shortDescription)
        try container.encode(description, forKey: .description)
        try container.encode([String](), forKey: .links)
        try container.encode(tags, forKey: .tags)
    }
}
private struct OtherUserRequest: Encodable, Sendable { let otherUserId: String }
private struct ChatIDRequest: Encodable, Sendable { let chatId: String }
private struct LoadMessagesRequest: Encodable, Sendable {
    let access: MessageAccess
    let createdBefore: String
}
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
