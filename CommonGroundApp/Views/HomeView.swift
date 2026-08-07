import CommonGroundKit
import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HomeContent(store: model.store)
    }
}

private enum SidebarItem: Hashable {
    case overview
    case directMessages
    case notifications
    case search
    case community(String)
}

private struct HomeContent: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var store: SyncStore
    @State private var sidebarSelection: SidebarItem? = .overview
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar
    @State private var showAccount = false

    private var communities: [Community] {
        let order = store.ownUser?.communityOrder ?? []
        return store.communities.values.sorted { lhs, rhs in
            let left = order.firstIndex(of: lhs.id)
            let right = order.firstIndex(of: rhs.id)
            switch (left, right) {
            case let (.some(left), .some(right)): return left < right
            case (.some, .none): return true
            case (.none, .some): return false
            case (.none, .none):
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        }
    }

    private var chats: [Chat] {
        store.chats.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        NavigationSplitView(
            columnVisibility: $columnVisibility,
            preferredCompactColumn: $preferredCompactColumn
        ) {
            sidebar
        } content: {
            contentColumn
        } detail: {
            detailColumn
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: $showAccount) {
            AccountView(store: store)
                .presentationDetents([.medium, .large])
        }
        .overlay(alignment: .top) {
            if let notice = model.realtimeNotice {
                Label(notice, systemImage: "bolt.slash")
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 8)
                    .accessibilityLabel("Connection notice: \(notice)")
            }
        }
        .onAppear(perform: restoreNavigation)
        .onChange(of: sidebarSelection) { _, selection in
            if case .community(let id) = selection {
                model.selectCommunity(id)
            }
        }
    }

    private var sidebar: some View {
        List(selection: $sidebarSelection) {
            Section {
                sidebarRow("Overview", systemImage: "square.grid.2x2", item: .overview)
                sidebarRow("Messages", systemImage: "bubble.left.and.bubble.right", item: .directMessages)
                sidebarRow(
                    "Notifications",
                    systemImage: "bell",
                    item: .notifications,
                    badge: store.unreadNotificationCount
                )
                sidebarRow("Search", systemImage: "magnifyingglass", item: .search)
            }

            Section("Communities") {
                if communities.isEmpty {
                    Text("No communities yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(communities) { community in
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(community.title)
                                Text("\(community.memberCount) members")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            CommunityMark(name: community.title)
                        }
                        .tag(SidebarItem.community(community.id))
                    }
                }
            }

            Section {
                Button { showAccount = true } label: {
                    HStack(spacing: 12) {
                        Avatar(name: store.ownUser?.displayName ?? "CG")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(store.ownUser?.displayName ?? "Member")
                                .fontWeight(.semibold)
                            Text(model.instanceHost)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle(AppConfiguration.productName)
    }

    private func sidebarRow(
        _ title: String,
        systemImage: String,
        item: SidebarItem,
        badge: Int = 0
    ) -> some View {
        Label {
            HStack {
                Text(title)
                Spacer()
                if badge > 0 {
                    Text(badge, format: .number)
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(AppTheme.accent, in: Capsule())
                        .accessibilityLabel("\(badge) unread")
                }
            }
        } icon: {
            Image(systemName: systemImage)
        }
        .tag(item)
    }

    @ViewBuilder
    private var contentColumn: some View {
        switch sidebarSelection ?? .overview {
        case .overview:
            OverviewView(
                communities: communities,
                chatCount: chats.count,
                unreadCount: store.unreadNotificationCount,
                openCommunity: openCommunity,
                openMessages: { sidebarSelection = .directMessages }
            )
        case .directMessages:
            ChatListView(
                chats: chats,
                ownUserID: store.ownUser?.id,
                selectedChatID: model.selectedChatID,
                select: openChat
            )
        case .notifications:
            NotificationsView(store: store)
        case .search:
            SearchView(
                communities: communities,
                store: store,
                openChannel: openChannel,
                openChat: openChat
            )
        case .community(let id):
            if let community = store.communities[id] {
                ChannelListView(
                    community: community,
                    selectedChannelID: model.selectedChannelID,
                    select: { openChannel($0, communityID: community.id) }
                )
            } else {
                ContentUnavailableView("Community unavailable", systemImage: "person.3")
            }
        }
    }

    @ViewBuilder
    private var detailColumn: some View {
        switch sidebarSelection ?? .overview {
        case .community(let communityID):
            if let channel = store.communities[communityID]?.channels.first(where: {
                $0.channelId == model.selectedChannelID
            }) {
                ConversationView(context: .channel(channel), store: store)
            } else {
                ConversationPlaceholder(
                    title: "Choose a channel",
                    message: "Channels in this community appear in the middle column.",
                    systemImage: "number"
                )
            }
        case .directMessages:
            if let chatID = model.selectedChatID, let chat = store.chats[chatID] {
                ConversationView(context: .chat(chat), store: store)
            } else {
                ConversationPlaceholder(
                    title: "Choose a message",
                    message: "Your direct conversations appear in the middle column.",
                    systemImage: "bubble.left.and.bubble.right"
                )
            }
        case .overview:
            ConversationPlaceholder(
                title: "Welcome back",
                message: "Choose a community or conversation to get started.",
                systemImage: "sparkles"
            )
        case .notifications:
            ConversationPlaceholder(
                title: "Notification details",
                message: "Select a notification to see its context here.",
                systemImage: "bell"
            )
        case .search:
            ConversationPlaceholder(
                title: "Search Common Ground",
                message: "Find a channel in the middle column to open it here.",
                systemImage: "magnifyingglass"
            )
        }
    }

    private func restoreNavigation() {
        guard let id = model.selectedCommunityID, store.communities[id] != nil else { return }
        sidebarSelection = .community(id)
    }

    private func openCommunity(_ id: String) {
        model.selectCommunity(id)
        sidebarSelection = .community(id)
        preferredCompactColumn = .content
    }

    private func openChannel(_ channelID: String, communityID: String) {
        model.selectCommunity(communityID)
        model.selectChannel(channelID)
        sidebarSelection = .community(communityID)
        preferredCompactColumn = .detail
    }

    private func openChat(_ id: String) {
        model.selectChat(id)
        sidebarSelection = .directMessages
        preferredCompactColumn = .detail
    }
}

private struct OverviewView: View {
    @EnvironmentObject private var model: AppModel
    let communities: [Community]
    let chatCount: Int
    let unreadCount: Int
    let openCommunity: (String) -> Void
    let openMessages: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your Common Ground")
                        .font(.title2.bold())
                    Text("Pick up where you left off without being dropped into an arbitrary room.")
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    MetricCard(value: communities.count, label: "Communities", systemImage: "person.3")
                    MetricCard(value: chatCount, label: "Messages", systemImage: "bubble.left.and.bubble.right")
                    MetricCard(value: unreadCount, label: "Unread", systemImage: "bell")
                }

                if communities.isEmpty {
                    ContentUnavailableView(
                        "No communities yet",
                        systemImage: "person.3",
                        description: Text("Communities you join on this instance will appear here.")
                    )
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("COMMUNITIES")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        ForEach(communities) { community in
                            Button { openCommunity(community.id) } label: {
                                HStack(spacing: 12) {
                                    CommunityMark(name: community.title)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(community.title).fontWeight(.semibold)
                                        Text("\(community.channels.count) channels · \(community.memberCount) members")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(12)
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Button(action: openMessages) {
                    Label("Open direct messages", systemImage: "bubble.left.and.bubble.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(20)
        }
        .navigationTitle("Overview")
        .task { await model.loadNotifications() }
    }
}

private struct MetricCard: View {
    let value: Int
    let label: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(AppTheme.accent)
            Text(value, format: .number)
                .font(.title3.bold())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct ChannelListView: View {
    let community: Community
    let selectedChannelID: String?
    let select: (String) -> Void

    var body: some View {
        List {
            if let description = community.channels.first?.description, !description.isEmpty {
                Section {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Channels") {
                ForEach(community.channels.sorted(by: { $0.order < $1.order })) { channel in
                    Button { select(channel.channelId) } label: {
                        HStack {
                            Label(channel.title, systemImage: "number")
                            Spacer()
                            if selectedChannelID == channel.channelId {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(AppTheme.accent)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle(community.title)
    }
}

private struct ChatListView: View {
    let chats: [Chat]
    let ownUserID: String?
    let selectedChatID: String?
    let select: (String) -> Void

    var body: some View {
        Group {
            if chats.isEmpty {
                ContentUnavailableView(
                    "No direct messages",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Your conversations on this instance will appear here.")
                )
            } else {
                List(chats) { chat in
                    Button { select(chat.id) } label: {
                        HStack(spacing: 12) {
                            Avatar(name: chat.displayTitle(excluding: ownUserID), small: true)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(chat.displayTitle(excluding: ownUserID))
                                    .fontWeight(.semibold)
                                Text(chat.lastMessage?.body.plainText ?? "No messages yet")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if let unread = chat.unread, unread > 0 {
                                Text(unread, format: .number)
                                    .font(.caption2.bold())
                                    .padding(6)
                                    .background(AppTheme.accent, in: Circle())
                                    .foregroundStyle(.white)
                            } else if selectedChatID == chat.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(AppTheme.accent)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Messages")
    }
}

private struct NotificationsView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var store: SyncStore

    private var notifications: [AppNotification] {
        store.notifications.values.sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        Group {
            if model.isLoadingNotifications && notifications.isEmpty {
                ProgressView("Loading notifications…")
            } else if notifications.isEmpty {
                ContentUnavailableView(
                    "You’re all caught up",
                    systemImage: "bell",
                    description: Text("New activity on this instance will appear here.")
                )
            } else {
                List(notifications) { notification in
                    Button {
                        Task { await model.markNotificationRead(notification.id) }
                    } label: {
                        NotificationRow(notification: notification)
                    }
                    .buttonStyle(.plain)
                }
                .refreshable { await model.loadNotifications() }
            }
        }
        .navigationTitle("Notifications")
        .toolbar {
            if store.unreadNotificationCount > 0 {
                ToolbarItem(placement: .primaryAction) {
                    Button("Read all") {
                        Task { await model.markAllNotificationsRead() }
                    }
                }
            }
        }
        .task { await model.loadNotifications() }
    }
}

private struct NotificationRow: View {
    let notification: AppNotification

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .frame(width: 32, height: 32)
                .foregroundStyle(notification.read ? .secondary : AppTheme.accent)
                .background(.thinMaterial, in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                Text(notification.text)
                    .fontWeight(notification.read ? .regular : .semibold)
                    .foregroundStyle(.primary)
                Text(timestamp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !notification.read {
                Circle()
                    .fill(AppTheme.accent)
                    .frame(width: 8, height: 8)
                    .accessibilityLabel("Unread")
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var icon: String {
        switch notification.type {
        case "Follower": "person.badge.plus"
        case "Mention": "at"
        case "Reply": "arrowshape.turn.up.left"
        case "DM": "bubble.left"
        case "ChannelMessage": "number"
        case "Call": "phone"
        case "Approval": "checkmark.seal"
        case "BanState": "hand.raised"
        default: "bell"
        }
    }

    private var timestamp: String {
        guard let date = ISO8601DateFormatter().date(from: notification.createdAt) else { return "" }
        return date.formatted(.relative(presentation: .named))
    }
}

private struct SearchView: View {
    @EnvironmentObject private var model: AppModel
    let communities: [Community]
    @ObservedObject var store: SyncStore
    let openChannel: (String, String) -> Void
    let openChat: (String) -> Void
    @State private var query = ""
    @State private var selectedUser: UserProfile?

    private var channelResults: [(Community, Channel)] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return communities.flatMap { community in
            community.channels
                .filter {
                    $0.title.localizedCaseInsensitiveContains(query)
                        || community.title.localizedCaseInsensitiveContains(query)
                }
                .map { (community, $0) }
        }
    }

    private var userResults: [UserProfile] {
        model.userSearchResultIDs.compactMap { store.users[$0] }
    }

    var body: some View {
        Group {
            if query.isEmpty {
                ContentUnavailableView(
                    "Search this instance",
                    systemImage: "magnifyingglass",
                    description: Text("Start with a community or channel name.")
                )
            } else if channelResults.isEmpty && userResults.isEmpty && !model.isSearchingUsers {
                ContentUnavailableView.search(text: query)
            } else {
                List {
                    if !userResults.isEmpty {
                        Section("People") {
                            ForEach(userResults) { user in
                                Button { selectedUser = user } label: {
                                    HStack(spacing: 12) {
                                        Avatar(name: user.displayName, small: true)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(user.displayName).fontWeight(.semibold)
                                            Text(user.onlineStatus.capitalized)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    if !channelResults.isEmpty {
                        Section("Channels") {
                            ForEach(channelResults, id: \.1.channelId) { community, channel in
                                Button { openChannel(channel.channelId, community.id) } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Label(channel.title, systemImage: "number")
                                        Text(community.title)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .overlay { if model.isSearchingUsers { ProgressView() } }
            }
        }
        .navigationTitle("Search")
        .searchable(text: $query, prompt: "People, communities, and channels")
        .task(id: query) {
            do {
                try await Task.sleep(for: .milliseconds(300))
                await model.searchUsers(query: query)
            } catch {
                // A newer keystroke cancelled this search.
            }
        }
        .sheet(item: $selectedUser) { user in
            UserProfileView(userID: user.id, store: store) { chatID in
                selectedUser = nil
                openChat(chatID)
            }
        }
    }
}

private struct UserProfileView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let userID: String
    @ObservedObject var store: SyncStore
    let openChat: (String) -> Void

    private var user: UserProfile? { store.users[userID] }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let user {
                    VStack(spacing: 18) {
                        Avatar(name: user.displayName)
                            .scaleEffect(1.8)
                            .padding(28)
                        VStack(spacing: 5) {
                            Text(user.displayName).font(.title2.bold())
                            Label(user.onlineStatus.capitalized, systemImage: "circle.fill")
                                .font(.caption)
                                .foregroundStyle(user.onlineStatus == "online" ? .green : .secondary)
                        }

                        HStack(spacing: 36) {
                            profileMetric(user.followerCount, "Followers")
                            profileMetric(user.followingCount, "Following")
                        }

                        if user.id != store.ownUser?.id {
                            Button {
                                Task {
                                    await model.setFollowing(userID: user.id, following: !user.isFollowed)
                                }
                            } label: {
                                Label(
                                    user.isFollowed ? "Following" : "Follow",
                                    systemImage: user.isFollowed ? "person.badge.checkmark" : "person.badge.plus"
                                )
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)

                            if user.isFollowed && user.isFollower {
                                Button {
                                    Task {
                                        if let chat = await model.startChat(with: user.id) {
                                            dismiss()
                                            openChat(chat.id)
                                        }
                                    }
                                } label: {
                                    Label("Message", systemImage: "bubble.left.and.bubble.right")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                            } else {
                                Label("Direct messages unlock after you follow each other.", systemImage: "person.2")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if let tags = user.tags, !tags.isEmpty {
                            Text(tags.map { "#\($0)" }.joined(separator: "  "))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: 480)
                    .padding(24)
                    .frame(maxWidth: .infinity)
                } else {
                    ContentUnavailableView("Profile unavailable", systemImage: "person.crop.circle.badge.questionmark")
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func profileMetric(_ value: Int, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value, format: .number).font(.headline)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

private enum ConversationContext {
    case channel(Channel)
    case chat(Chat)

    var channelID: String {
        switch self {
        case .channel(let channel): channel.channelId
        case .chat(let chat): chat.channelId
        }
    }

    var title: String {
        switch self {
        case .channel(let channel): channel.title
        case .chat: "Direct message"
        }
    }

    var composerPrompt: String {
        switch self {
        case .channel(let channel): "Message #\(channel.title)"
        case .chat: "Write a message"
        }
    }
}

private struct ConversationView: View {
    @EnvironmentObject private var model: AppModel
    let context: ConversationContext
    @ObservedObject var store: SyncStore

    private var messages: [Message] {
        store.orderedMessages(channelId: context.channelID)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        if messages.isEmpty {
                            ContentUnavailableView(
                                "Start the conversation",
                                systemImage: "sparkles",
                                description: Text("Messages sent here are delivered to the selected conversation.")
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 60)
                        }
                        ForEach(messages) { message in
                            MessageRow(
                                message: message,
                                isOwn: message.creatorId == store.ownUser?.id
                            )
                            .id(message.id)
                        }
                    }
                    .frame(maxWidth: 760)
                    .padding(20)
                    .frame(maxWidth: .infinity)
                }
                .refreshable { await load() }
                .onChange(of: messages.count) { _, _ in
                    if let id = messages.last?.id {
                        withAnimation { proxy.scrollTo(id, anchor: .bottom) }
                    }
                }
            }

            Divider()
            HStack(alignment: .bottom, spacing: 10) {
                TextField(context.composerPrompt, text: $model.draftMessage, axis: .vertical)
                    .lineLimit(1...5)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
                    .submitLabel(.send)
                    .onSubmit { Task { await send() } }
                Button { Task { await send() } } label: {
                    Image(systemName: "arrow.up")
                        .fontWeight(.bold)
                        .frame(width: 42, height: 42)
                        .foregroundStyle(.white)
                        .background(AppTheme.accent, in: Circle())
                }
                .disabled(model.draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Send message")
            }
            .frame(maxWidth: 760)
            .padding(12)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(context.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: context.channelID) { await load() }
    }

    private func load() async {
        switch context {
        case .channel(let channel): await model.loadMessages(channel: channel)
        case .chat(let chat): await model.loadMessages(chat: chat)
        }
    }

    private func send() async {
        switch context {
        case .channel(let channel): await model.sendMessage(channel: channel)
        case .chat(let chat): await model.sendMessage(chat: chat)
        }
    }
}

private struct MessageRow: View {
    let message: Message
    let isOwn: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Avatar(name: isOwn ? "You" : String(message.creatorId.prefix(4)), small: true)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(isOwn ? "You" : "Member")
                        .font(.subheadline.weight(.semibold))
                    Text(relativeDate(message.createdAt))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Text(message.body.plainText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func relativeDate(_ value: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: value) else { return "" }
        return date.formatted(date: .omitted, time: .shortened)
    }
}

private struct ConversationPlaceholder: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        ContentUnavailableView(
            title,
            systemImage: systemImage,
            description: Text(message)
        )
    }
}

private struct AccountView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: SyncStore

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        Avatar(name: store.ownUser?.displayName ?? "CG")
                            .scaleEffect(1.25)
                            .padding(8)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(store.ownUser?.displayName ?? "Member")
                                .font(.title3.bold())
                            Text(store.ownUser?.email ?? model.instanceHost)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Instance") {
                    LabeledContent("Connected to", value: model.instanceHost)
                    Button("Choose another instance", systemImage: "network") {
                        dismiss()
                        model.chooseAnotherInstance()
                    }
                }

                Section("About") {
                    Link("Privacy policy", destination: AppConfiguration.privacyURL)
                    Link("Contact support", destination: URL(string: "mailto:\(AppConfiguration.supportEmail)")!)
                }

                Section {
                    Button(role: .destructive) {
                        dismiss()
                        Task { await model.logout() }
                    } label: {
                        Label("Log out and remove this device", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle("Account")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct Avatar: View {
    let name: String
    var small = false

    var body: some View {
        Text(String(name.prefix(2)).uppercased())
            .font(small ? .caption.bold() : .subheadline.bold())
            .frame(width: small ? 34 : 42, height: small ? 34 : 42)
            .foregroundStyle(.black)
            .background(
                LinearGradient(
                    colors: [AppTheme.accent, AppTheme.secondaryAccent],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: Circle()
            )
            .accessibilityHidden(true)
    }
}

private struct CommunityMark: View {
    let name: String

    var body: some View {
        Text(String(name.prefix(1)).uppercased())
            .font(.caption.bold())
            .frame(width: 30, height: 30)
            .foregroundStyle(.white)
            .background(AppTheme.accent.gradient, in: RoundedRectangle(cornerRadius: 8))
            .accessibilityHidden(true)
    }
}

private extension Chat {
    func displayTitle(excluding ownUserID: String?) -> String {
        let others = userIds.filter { $0 != ownUserID }
        guard !others.isEmpty else { return "Direct message" }
        return others.map { "Member \($0.prefix(4))" }.joined(separator: ", ")
    }
}
