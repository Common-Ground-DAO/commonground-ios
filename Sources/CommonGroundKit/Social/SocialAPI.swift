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
        id: UUID = UUID()
    ) async throws -> Message {
        try await transport.call(
            "Message/createMessage",
            body: CreateMessageRequest(
                id: id.uuidString.lowercased(),
                access: access,
                body: .text(text),
                parentMessageId: nil,
                attachments: []
            )
        )
    }
}

private struct IDRequest: Encodable, Sendable { let id: String }
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
