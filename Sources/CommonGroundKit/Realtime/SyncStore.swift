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

    public func seed(community: Community) {
        communities[community.id] = community
    }

    public func removeCommunity(id: String) {
        communities.removeValue(forKey: id)
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

    public func applyOwnEdit(messageID: String, channelID: String, body: MessageBody, editedAt: String) {
        guard let message = messages[channelID]?[messageID] else { return }
        replace(
            message,
            body: body,
            editedAt: editedAt,
            updatedAt: editedAt
        )
    }

    public func applyOwnDelete(messageID: String, channelID: String) {
        messages[channelID]?.removeValue(forKey: messageID)
    }

    public func applyOwnReaction(messageID: String, channelID: String, reaction: String?) {
        guard let message = messages[channelID]?[messageID] else { return }
        var counts = message.reactions
        if let previous = message.ownReaction {
            let next = max(0, (counts[previous] ?? 1) - 1)
            if next == 0 { counts.removeValue(forKey: previous) } else { counts[previous] = next }
        }
        if let reaction {
            counts[reaction, default: 0] += 1
        }
        replace(message, reactions: counts, ownReaction: .some(reaction))
    }

    func apply(_ event: RealtimeEvent) {
        guard case .object(let payload) = event.payload else { return }
        switch event.type {
        case .message:
            guard let action = payload["action"]?.stringValue,
                  let data = payload["data"],
                  let encoded = try? JSONEncoder().encode(data) else { return }
            if action == "new", let message = try? JSONDecoder().decode(Message.self, from: encoded) {
                seed([message], channelId: message.channelId)
            } else if action == "update", case .object(let patch) = data,
                      let channelID = patch["channelId"]?.stringValue,
                      let messageID = patch["id"]?.stringValue,
                      let message = messages[channelID]?[messageID] {
                applyMessagePatch(patch, to: message)
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
        case .community:
            guard payload["action"]?.stringValue == "update",
                  case .object(let patch) = payload["data"],
                  let id = patch["id"]?.stringValue,
                  let community = communities[id],
                  let updated: Community = applying(patch, to: community) else { return }
            communities[id] = updated
        case .userOwnData:
            guard case .object(let patch) = payload["data"],
                  let ownUser,
                  let updated: OwnUser = applying(patch, to: ownUser) else { return }
            self.ownUser = updated
        default:
            break
        }
    }

    func applying<Value: Codable>(
        _ patch: [String: JSONValue],
        to value: Value
    ) -> Value? {
        guard let encoded = try? JSONEncoder().encode(value),
              let root = try? JSONDecoder().decode(JSONValue.self, from: encoded),
              case .object(var object) = root else { return nil }
        for (key, value) in patch { object[key] = value }
        guard let merged = try? JSONEncoder().encode(JSONValue.object(object)) else { return nil }
        return try? JSONDecoder().decode(Value.self, from: merged)
    }

    private func applyMessagePatch(_ patch: [String: JSONValue], to message: Message) {
        func decode<T: Decodable>(_ value: JSONValue?, as type: T.Type) -> T? {
            guard let value,
                  let data = try? JSONEncoder().encode(value) else { return nil }
            return try? JSONDecoder().decode(type, from: data)
        }

        let body = decode(patch["body"], as: MessageBody.self) ?? message.body
        let attachments = decode(patch["attachments"], as: [JSONValue].self) ?? message.attachments
        let reactions = decode(patch["reactions"], as: [String: Int].self) ?? message.reactions
        let parentMessageID: String?
        if let parent = patch["parentMessageId"] {
            parentMessageID = parent.stringValue
        } else {
            parentMessageID = message.parentMessageId
        }
        let ownReaction: String?
        if let own = patch["ownReaction"] {
            ownReaction = own.stringValue
        } else {
            ownReaction = message.ownReaction
        }
        let contentChanged = patch["body"] != nil
            || patch["attachments"] != nil
            || patch["parentMessageId"] != nil
        replace(
            message,
            body: body,
            attachments: attachments,
            editedAt: contentChanged ? (patch["updatedAt"]?.stringValue ?? message.editedAt) : message.editedAt,
            updatedAt: patch["updatedAt"]?.stringValue ?? message.updatedAt,
            reactions: reactions,
            ownReaction: .some(ownReaction),
            parentMessageId: .some(parentMessageID)
        )
    }

    private func replace(
        _ message: Message,
        body: MessageBody? = nil,
        attachments: [JSONValue]? = nil,
        editedAt: String? = nil,
        updatedAt: String? = nil,
        reactions: [String: Int]? = nil,
        ownReaction: String?? = nil,
        parentMessageId: String?? = nil
    ) {
        messages[message.channelId]?[message.id] = Message(
            id: message.id,
            creatorId: message.creatorId,
            channelId: message.channelId,
            body: body ?? message.body,
            attachments: attachments ?? message.attachments,
            editedAt: editedAt ?? message.editedAt,
            createdAt: message.createdAt,
            updatedAt: updatedAt ?? message.updatedAt,
            reactions: reactions ?? message.reactions,
            ownReaction: ownReaction ?? message.ownReaction,
            parentMessageId: parentMessageId ?? message.parentMessageId
        )
    }
}
