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
    @Published public private(set) var pendingMessages: [String: PendingMessage] = [:]
    @Published public private(set) var savedMessageIDs: Set<String> = []
    @Published public private(set) var typingUsersByAccess: [MessageAccess: Set<String>] = [:]
    @Published public private(set) var unreadNotificationCount = 0

    private struct TypingPresenceKey: Hashable {
        let access: MessageAccess
        let userID: String
    }

    private var listenerID: UUID?
    private var database: OfflineDatabase?
    private let typingExpiry: Duration
    private var typingExpiryTasks: [TypingPresenceKey: Task<Void, Never>] = [:]

    public init(typingExpiry: Duration = .seconds(7)) {
        self.typingExpiry = typingExpiry
    }

    public func configurePersistence(_ database: OfflineDatabase) async {
        self.database = database
        guard let snapshot = try? await database.loadSnapshot() else { return }
        if let ownUser = snapshot.ownUser { self.ownUser = ownUser }
        communities.merge(
            Dictionary(uniqueKeysWithValues: snapshot.communities.map { ($0.id, $0) })
        ) { _, cached in cached }
        chats.merge(Dictionary(uniqueKeysWithValues: snapshot.chats.map { ($0.id, $0) })) { _, cached in cached }
        for message in snapshot.messages {
            messages[message.channelId, default: [:]][message.id] = message
        }
        notifications.merge(
            Dictionary(uniqueKeysWithValues: snapshot.notifications.map { ($0.id, $0) })
        ) { _, cached in cached }
        users.merge(Dictionary(uniqueKeysWithValues: snapshot.users.map { ($0.id, $0) })) { _, cached in cached }
        for pending in snapshot.pendingMessages {
            pendingMessages[pending.id] = pending
            messages[pending.access.channelId, default: [:]][pending.id] = pending.placeholder
        }
        savedMessageIDs.formUnion(snapshot.savedMessageIDs)
        unreadNotificationCount = max(unreadNotificationCount, snapshot.unreadNotificationCount)
    }

    public func clearPersistentData() async {
        try? await database?.clear()
    }

    public func detachPersistence() { database = nil }

    public func hydrate(from response: LoginResponse) {
        ownUser = response.ownData
        communities = Dictionary(uniqueKeysWithValues: response.communities.map { ($0.id, $0) })
        chats = Dictionary(uniqueKeysWithValues: response.chats.map { ($0.id, $0) })
        unreadNotificationCount = response.unreadNotificationCount
        if let database { Task { try? await database.replaceAccountState(response) } }
    }

    public func reset() {
        ownUser = nil
        communities = [:]
        chats = [:]
        messages = [:]
        notifications = [:]
        users = [:]
        pendingMessages = [:]
        savedMessageIDs = []
        clearTypingPresence()
        unreadNotificationCount = 0
        listenerID = nil
    }

    public func typingUserIDs(for access: MessageAccess) -> [String] {
        Array(typingUsersByAccess[access] ?? []).sorted()
    }

    /// Clears ephemeral receiver state when the socket is interrupted. A
    /// newly authenticated connection will repopulate it from fresh events.
    public func clearTypingPresence() {
        for task in typingExpiryTasks.values { task.cancel() }
        typingExpiryTasks = [:]
        typingUsersByAccess = [:]
    }

    public func seed(_ batch: [Message], channelId: String) {
        var channelMessages = messages[channelId] ?? [:]
        for message in batch { channelMessages[message.id] = message }
        messages[channelId] = channelMessages
        if let database { Task { try? await database.save(messages: batch) } }
    }

    public func orderedMessages(channelId: String) -> [Message] {
        (messages[channelId] ?? [:]).values.sorted { lhs, rhs in
            let lhsDate = Self.parseTimestamp(lhs.createdAt)
            let rhsDate = Self.parseTimestamp(rhs.createdAt)
            switch (lhsDate, rhsDate) {
            case let (lhsDate?, rhsDate?):
                if lhsDate == rhsDate { return lhs.id < rhs.id }
                return lhsDate < rhsDate
            default:
                if lhs.createdAt == rhs.createdAt { return lhs.id < rhs.id }
                return lhs.createdAt < rhs.createdAt
            }
        }
    }

    public func seed(chat: Chat) {
        chats[chat.id] = chat
        if let database { Task { try? await database.save(chat: chat) } }
    }

    public func seed(community: Community) {
        communities[community.id] = community
        if let database { Task { try? await database.save(community: community) } }
    }

    public func removeCommunity(id: String) {
        communities.removeValue(forKey: id)
        if let database { Task { try? await database.removeCommunity(id: id) } }
    }

    public func applyCommunityFields(id: String, fields: [String: JSONValue]) {
        guard let community = communities[id] else { return }
        var patch = fields
        patch["id"] = .string(id)
        guard let updated: Community = applying(patch, to: community) else { return }
        communities[id] = updated
        if let database { Task { try? await database.save(community: updated) } }
    }

    public func replaceNotifications(_ batch: [AppNotification], unreadCount: Int) {
        notifications = Dictionary(uniqueKeysWithValues: batch.map { ($0.id, $0) })
        unreadNotificationCount = unreadCount
        if let database {
            Task { try? await database.replaceNotifications(batch, unreadCount: unreadCount) }
        }
    }

    public func seed(users batch: [UserProfile]) {
        for user in batch { users[user.id] = user }
        if let database { Task { try? await database.save(users: batch) } }
    }

    public func setFollowing(userID: String, isFollowed: Bool) {
        guard let user = users[userID] else { return }
        users[userID] = user.replacingFollowed(isFollowed)
        if let updated = users[userID], let database {
            Task { try? await database.save(users: [updated]) }
        }
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
        if let updated = notifications[id], let database {
            let count = unreadNotificationCount
            Task { try? await database.save(notification: updated, unreadCount: count) }
        }
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

    public func enqueue(_ pending: PendingMessage) {
        pendingMessages[pending.id] = pending
        seed([pending.placeholder], channelId: pending.access.channelId)
        if let database { Task { try? await database.save(pendingMessage: pending) } }
    }

    public func updatePending(
        id: String,
        state: PendingMessageState,
        error: String? = nil
    ) {
        guard var pending = pendingMessages[id] else { return }
        pending.state = state
        pending.lastError = error
        pendingMessages[id] = pending
        if let database { Task { try? await database.save(pendingMessage: pending) } }
    }

    public func completePending(id: String, with message: Message) {
        pendingMessages.removeValue(forKey: id)
        messages[message.channelId]?[id] = message
        if let database {
            Task {
                try? await database.removePendingMessage(id: id)
                try? await database.save(messages: [message])
            }
        }
    }

    public func discardPending(id: String) {
        guard let pending = pendingMessages.removeValue(forKey: id) else { return }
        messages[pending.access.channelId]?.removeValue(forKey: id)
        if let database {
            Task {
                try? await database.removePendingMessage(id: id)
                try? await database.removeMessage(id: id)
            }
        }
    }

    public func setMessageSaved(id: String, saved: Bool) {
        if saved { savedMessageIDs.insert(id) }
        else { savedMessageIDs.remove(id) }
        if let database { Task { try? await database.setMessageSaved(id: id, saved: saved) } }
    }

    public func applyMessageUpdates(_ updates: MessageUpdates, channelID: String) {
        seed(updates.updated, channelId: channelID)
        for id in updates.deleted {
            messages[channelID]?.removeValue(forKey: id)
            if let database { Task { try? await database.removeMessage(id: id) } }
        }
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

    public func applyModeratorDeleteAll(creatorID: String, channelID: String) {
        let ids = messages[channelID]?.values.filter { $0.creatorId == creatorID }.map(\.id) ?? []
        for id in ids {
            messages[channelID]?.removeValue(forKey: id)
            if let database { Task { try? await database.removeMessage(id: id) } }
        }
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
                if let database {
                    for id in ids.compactMap(\.stringValue) {
                        Task { try? await database.removeMessage(id: id) }
                    }
                }
            }
        case .notification:
            let action = payload["action"]?.stringValue
            if action == "new", let data = payload["data"],
               let encoded = try? JSONEncoder().encode(data),
               let notification = try? JSONDecoder().decode(AppNotification.self, from: encoded) {
                let wasKnownUnread = notifications[notification.id]?.read == false
                notifications[notification.id] = notification
                if !notification.read && !wasKnownUnread { unreadNotificationCount += 1 }
                if let database {
                    let count = unreadNotificationCount
                    Task { try? await database.save(notification: notification, unreadCount: count) }
                }
            } else if action == "update", case .object(let data) = payload["data"],
                      let id = data["id"]?.stringValue {
                markNotificationRead(id)
            } else if action == "allread" {
                markAllNotificationsRead()
            }
        case .community:
            let action = payload["action"]?.stringValue
            guard let data = payload["data"] else { return }
            if action == "new-or-full-update", let community: Community = decode(data) {
                seed(community: community)
            } else if action == "update", case .object(let patch) = data,
                      let id = patch["id"]?.stringValue,
                      let community = communities[id],
                      let updated: Community = applying(patch, to: community) {
                seed(community: updated)
            } else if action == "delete", case .object(let deletion) = data,
                      let id = deletion["id"]?.stringValue {
                removeCommunity(id: id)
            }
        case .chat:
            applyChatEvent(payload)
        case .channelLastRead:
            guard let channelID = payload["channelId"]?.stringValue,
                  let lastRead = payload["lastRead"]?.stringValue else { return }
            updateChannel(channelID: channelID) { channel in
                channel.lastRead = lastRead
            }
        case .userOwnData:
            guard case .object(let patch) = payload["data"],
                  let ownUser,
                  let updated: OwnUser = applying(patch, to: ownUser) else { return }
            self.ownUser = updated
            if let database { Task { try? await database.save(ownUser: updated) } }
        case .userData:
            guard case .object(let patch) = payload["data"],
                  let id = patch["id"]?.stringValue,
                  let user = users[id],
                  let updated: UserProfile = applying(patch, to: user) else { return }
            seed(users: [updated])
        case .typing:
            guard let accessValue = payload["access"],
                  let access: MessageAccess = decode(accessValue),
                  let userID = payload["userId"]?.stringValue,
                  !userID.isEmpty,
                  let isTyping = payload["isTyping"]?.boolValue else { return }
            applyTypingPresence(access: access, userID: userID, isTyping: isTyping)
        default:
            break
        }
    }

    private func applyTypingPresence(access: MessageAccess, userID: String, isTyping: Bool) {
        let key = TypingPresenceKey(access: access, userID: userID)
        typingExpiryTasks[key]?.cancel()
        typingExpiryTasks[key] = nil

        guard isTyping else {
            removeTypingPresence(key)
            return
        }

        typingUsersByAccess[access, default: []].insert(userID)
        let expiry = typingExpiry
        typingExpiryTasks[key] = Task { [weak self] in
            do {
                try await Task.sleep(for: expiry)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.removeTypingPresence(key)
        }
    }

    private func removeTypingPresence(_ key: TypingPresenceKey) {
        typingExpiryTasks[key]?.cancel()
        typingExpiryTasks[key] = nil
        typingUsersByAccess[key.access]?.remove(key.userID)
        if typingUsersByAccess[key.access]?.isEmpty == true {
            typingUsersByAccess[key.access] = nil
        }
    }

    private func applyChatEvent(_ payload: [String: JSONValue]) {
        let action = payload["action"]?.stringValue
        guard let data = payload["data"] else { return }
        if action == "new", let chat: Chat = decode(data) {
            seed(chat: chat)
        } else if action == "update", case .object(let patch) = data,
                  let id = patch["id"]?.stringValue,
                  let chat = chats[id],
                  let updated: Chat = applying(patch, to: chat) {
            seed(chat: updated)
        } else if action == "delete", case .object(let deletion) = data,
                  let id = deletion["id"]?.stringValue {
            chats.removeValue(forKey: id)
            if let database { Task { try? await database.removeChat(id: id) } }
        }
    }

    private func updateChannel(channelID: String, mutate: (inout Channel) -> Void) {
        guard let communityID = communities.first(where: { _, community in
            community.channels.contains(where: { $0.channelId == channelID })
        })?.key, var community = communities[communityID],
              let index = community.channels.firstIndex(where: { $0.channelId == channelID }) else { return }
        mutate(&community.channels[index])
        communities[communityID] = community
        if let database { Task { try? await database.save(community: community) } }
    }

    private func decode<Value: Decodable>(_ value: JSONValue) -> Value? {
        guard let encoded = try? JSONEncoder().encode(value) else { return nil }
        return try? JSONDecoder().decode(Value.self, from: encoded)
    }

    private static func parseTimestamp(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
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
        let updated = Message(
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
        messages[message.channelId]?[message.id] = updated
        if let database { Task { try? await database.save(messages: [updated]) } }
    }
}
