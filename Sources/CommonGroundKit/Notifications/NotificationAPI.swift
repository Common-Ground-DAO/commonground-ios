import Foundation

public struct NotificationAPI: Sendable {
    private let transport: HTTPTransport

    public init(transport: HTTPTransport) {
        self.transport = transport
    }

    public func load(
        order: NotificationOrder = .descending,
        createdBefore: String? = nil,
        createdAfter: String? = nil,
        unreadOnly: Bool? = nil
    ) async throws -> [AppNotification] {
        try await transport.call(
            "Notification/loadNotifications",
            body: LoadNotificationsRequest(
                order: order,
                createdBefore: createdBefore,
                createdAfter: createdAfter,
                unreadOnly: unreadOnly
            )
        )
    }

    public func loadUpdates(
        createdStart: String,
        createdEnd: String,
        updatedAfter: String
    ) async throws -> NotificationUpdates {
        try await transport.call(
            "Notification/loadUpdates",
            body: LoadUpdatesRequest(
                createdStart: createdStart,
                createdEnd: createdEnd,
                updatedAfter: updatedAfter
            )
        )
    }

    public func unreadCount() async throws -> Int {
        let result: FlexibleInteger = try await transport.call("Notification/getUnreadCount")
        return result.value
    }

    public func markAsRead(_ notificationID: String) async throws {
        let _: EmptyResponse = try await transport.call(
            "Notification/markAsRead",
            body: NotificationIDRequest(notificationId: notificationID)
        )
    }

    public func markAllAsRead() async throws {
        let _: EmptyResponse = try await transport.call("Notification/markAllAsRead")
    }
}

private struct LoadNotificationsRequest: Encodable, Sendable {
    let order: NotificationOrder
    let createdBefore: String?
    let createdAfter: String?
    let unreadOnly: Bool?
}

private struct LoadUpdatesRequest: Encodable, Sendable {
    let createdStart: String
    let createdEnd: String
    let updatedAfter: String
}

private struct NotificationIDRequest: Encodable, Sendable {
    let notificationId: String
}

private struct FlexibleInteger: Decodable, Sendable {
    let value: Int

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Int.self) {
            self.value = value
        } else {
            let string = try container.decode(String.self)
            guard let value = Int(string) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Expected an integer or integer string"
                )
            }
            self.value = value
        }
    }
}
