import Foundation

/// The normalized in-memory mirror used by UI code. Persistence can replace
/// this implementation without changing transport or domain APIs.
@MainActor
public final class SyncStore: ObservableObject {
    @Published public private(set) var ownUser: OwnUser?
    @Published public private(set) var communities: [String: Community] = [:]
    @Published public private(set) var chats: [String: Chat] = [:]
    @Published public private(set) var messages: [String: [String: Message]] = [:]
    @Published public private(set) var notifications: [String: AppNotification] = [:]
    @Published public private(set) var users: [String: UserProfile] = [:]
    @Published public private(set) var unreadNotificationCount = 0

    private var listenerID: UUID?

    public init() {}

    public func hydrate(from response: LoginResponse) {
        ownUser = response.ownData
        communities = Dictionary(uniqueKeysWithValues: response.communities.map { ($0.id, $0) })
        chats = Dictionary(uniqueKeysWithValues: response.chats.map { ($0.id, $0) })
        unreadNotificationCount = response.unreadNotificationCount
    }

    public func reset() {
        ownUser = nil
        communities = [:]
        chats = [:]
        messages = [:]
        notifications = [:]
        users = [:]
        unreadNotificationCount = 0
        listenerID = nil
    }

    public func seed(_ batch: [Message], channelId: String) {
        var channelMessages = messages[channelId] ?? [:]
        for message in batch { channelMessages[message.id] = message }
        messages[channelId] = channelMessages
    }

    public func orderedMessages(channelId: String) -> [Message] {
        (messages[channelId] ?? [:]).values.sorted { $0.createdAt < $1.createdAt }
    }

    public func seed(chat: Chat) {
        chats[chat.id] = chat
    }

    public func replaceNotifications(_ batch: [AppNotification], unreadCount: Int) {
        notifications = Dictionary(uniqueKeysWithValues: batch.map { ($0.id, $0) })
        unreadNotificationCount = unreadCount
    }

    public func seed(users batch: [UserProfile]) {
        for user in batch { users[user.id] = user }
    }

    public func setFollowing(userID: String, isFollowed: Bool) {
        guard let user = users[userID] else { return }
        users[userID] = user.replacingFollowed(isFollowed)
    }

    public func markNotificationRead(_ id: String) {
        guard let item = notifications[id], !item.read else { return }
        notifications[id] = AppNotification(
            type: item.type,
            id: item.id,
            text: item.text,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt,
            read: true,
            subjectItemId: item.subjectItemId,
            subjectCommunityId: item.subjectCommunityId,
            subjectUserId: item.subjectUserId,
            subjectArticleId: item.subjectArticleId,
            extraData: item.extraData
        )
        unreadNotificationCount = max(0, unreadNotificationCount - 1)
    }

    public func markAllNotificationsRead() {
        for id in Array(notifications.keys) { markNotificationRead(id) }
        unreadNotificationCount = 0
    }

    public func attach(to realtime: RealtimeClient) {
        if let listenerID { realtime.removeListener(listenerID) }
        listenerID = realtime.onEvent { [weak self] event in self?.apply(event) }
    }

    public func applyOwnWrite(_ message: Message) {
        // The server intentionally sends no same-device socket echo.
        seed([message], channelId: message.channelId)
    }

    private func apply(_ event: RealtimeEvent) {
        guard case .object(let payload) = event.payload else { return }
        switch event.type {
        case .message:
            guard let action = payload["action"]?.stringValue,
                  let data = payload["data"],
                  let encoded = try? JSONEncoder().encode(data) else { return }
            if action == "new", let message = try? JSONDecoder().decode(Message.self, from: encoded) {
                seed([message], channelId: message.channelId)
            } else if action == "delete", case .object(let deletion) = data,
                      let channelId = deletion["channelId"]?.stringValue,
                      case .array(let ids) = deletion["deletedIds"] {
                var current = messages[channelId] ?? [:]
                for id in ids.compactMap(\.stringValue) { current.removeValue(forKey: id) }
                messages[channelId] = current
            }
        case .notification:
            let action = payload["action"]?.stringValue
            if action == "new", let data = payload["data"],
               let encoded = try? JSONEncoder().encode(data),
               let notification = try? JSONDecoder().decode(AppNotification.self, from: encoded) {
                notifications[notification.id] = notification
                unreadNotificationCount += notification.read ? 0 : 1
            } else if action == "update", case .object(let data) = payload["data"],
                      let id = data["id"]?.stringValue {
                markNotificationRead(id)
            } else if action == "allread" {
                markAllNotificationsRead()
            }
        default:
            break
        }
    }
}
