import Foundation

/// The normalized in-memory mirror used by UI code. Persistence can replace
/// this implementation without changing transport or domain APIs.
@MainActor
public final class SyncStore: ObservableObject {
    @Published public private(set) var ownUser: OwnUser?
    @Published public private(set) var communities: [String: Community] = [:]
    @Published public private(set) var messages: [String: [String: Message]] = [:]
    @Published public private(set) var unreadNotificationCount = 0

    private var listenerID: UUID?

    public init() {}

    public func hydrate(from response: LoginResponse) {
        ownUser = response.ownData
        communities = Dictionary(uniqueKeysWithValues: response.communities.map { ($0.id, $0) })
        unreadNotificationCount = response.unreadNotificationCount
    }

    public func seed(_ batch: [Message], channelId: String) {
        var channelMessages = messages[channelId] ?? [:]
        for message in batch { channelMessages[message.id] = message }
        messages[channelId] = channelMessages
    }

    public func orderedMessages(channelId: String) -> [Message] {
        (messages[channelId] ?? [:]).values.sorted { $0.createdAt < $1.createdAt }
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
            if payload["action"]?.stringValue == "new" { unreadNotificationCount += 1 }
            if payload["action"]?.stringValue == "allread" { unreadNotificationCount = 0 }
        default:
            break
        }
    }
}
