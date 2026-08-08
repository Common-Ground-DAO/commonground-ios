import CommonGroundKit
import PhotosUI
import SwiftUI
import UIKit

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
    case discover
    case community(String)
}

private struct ReportTarget: Identifiable {
    let type: ReportType
    let id: String
    let subject: String
}

private struct NotificationArticleRoute: Identifiable {
    let source: ArticleOwner
    let articleID: String
    let commentID: String?
    var id: String { "\(articleID):\(commentID ?? "")" }
}

private struct NotificationProfileRoute: Identifiable {
    let id: String
}

private struct HomeContent: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var store: SyncStore
    @State private var sidebarSelection: SidebarItem? = .overview
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar
    @State private var showAccount = false
    @State private var showCreateCommunity = false
    @State private var notificationArticle: NotificationArticleRoute?
    @State private var notificationProfile: NotificationProfileRoute?

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
        .sheet(isPresented: $showCreateCommunity) {
            CreateCommunityView { communityID in
                showCreateCommunity = false
                openCommunity(communityID)
            }
        }
        .sheet(item: $notificationArticle) { route in
            ArticleReaderView(
                articleID: route.articleID,
                source: route.source,
                store: store,
                focusedCommentID: route.commentID
            )
        }
        .sheet(item: $notificationProfile) { route in
            UserProfileView(userID: route.id, store: store) { chatID in
                notificationProfile = nil
                openChat(chatID)
            }
        }
        .overlay(alignment: .top) {
            VStack(spacing: 8) {
                if let notification = model.inAppNotification {
                    Button {
                        openNotification(notification)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "bell.fill")
                                .foregroundStyle(AppTheme.accent)
                            Text(notification.text)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                        .padding(14)
                        .frame(maxWidth: 520)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                        .shadow(color: .black.opacity(0.15), radius: 14, y: 6)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .accessibilityHint("Opens the related activity")
                }
                if let notice = model.realtimeNotice {
                    Label(notice, systemImage: "bolt.slash")
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .accessibilityLabel("Connection notice: \(notice)")
                }
            }
            .padding(.top, 8)
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
                sidebarRow("Discover", systemImage: "safari", item: .discover)
            }

            Section("Communities") {
                Button {
                    showCreateCommunity = true
                } label: {
                    Label("Create community", systemImage: "plus.circle.fill")
                        .foregroundStyle(AppTheme.accent)
                        .fontWeight(.semibold)
                }
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
                            CommunityMark(
                                name: community.title,
                                url: community.logoSmallId.flatMap { model.attachmentURLs[$0] }
                            )
                        }
                        .tag(SidebarItem.community(community.id))
                    }
                }
            }

            Section {
                Button { showAccount = true } label: {
                    HStack(spacing: 12) {
                        Avatar(
                            name: store.users[store.ownUser?.id ?? ""]?.displayName
                                ?? store.ownUser?.displayName
                                ?? "CG",
                            url: store.users[store.ownUser?.id ?? ""]
                                .flatMap { $0.imageID }
                                .flatMap { model.attachmentURLs[$0] }
                        )
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
        .refreshable { await model.refreshHome() }
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
                openMessages: { sidebarSelection = .directMessages },
                discover: { sidebarSelection = .discover },
                createCommunity: { showCreateCommunity = true }
            )
        case .directMessages:
            ChatListView(
                chats: chats,
                ownUserID: store.ownUser?.id,
                selectedChatID: model.selectedChatID,
                select: openChat
            )
        case .notifications:
            NotificationsView(store: store, open: openNotification)
        case .search:
            SearchView(
                communities: communities,
                store: store,
                openChannel: openChannel,
                openChat: openChat
            )
        case .discover:
            CommunityDiscoveryView(store: store, openCommunity: openCommunity)
        case .community(let id):
            if let community = store.communities[id] {
                ChannelListView(
                    community: community,
                    selectedChannelID: model.selectedChannelID,
                    openHome: {
                        model.selectChannel(nil)
                        preferredCompactColumn = .detail
                    },
                    select: { openChannel($0, communityID: community.id) },
                    leave: {
                        Task {
                            if await model.leaveCommunity(id: community.id) {
                                sidebarSelection = .overview
                                preferredCompactColumn = .sidebar
                            }
                        }
                    }
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
            } else if let community = store.communities[communityID] {
                CommunityHomeView(community: community, store: store)
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
        case .discover:
            ConversationPlaceholder(
                title: "Find your people",
                message: "Browse public communities or create a new space.",
                systemImage: "safari"
            )
        }
    }

    private func restoreNavigation() {
        guard let id = model.selectedCommunityID, store.communities[id] != nil else { return }
        sidebarSelection = .community(id)
        if let channelID = model.selectedChannelID,
           store.communities[id]?.channels.contains(where: { $0.channelId == channelID }) == true {
            preferredCompactColumn = .detail
        }
    }

    private func openCommunity(_ id: String) {
        model.selectCommunity(id)
        model.selectChannel(nil)
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

    private func openNotification(_ notification: AppNotification) {
        model.dismissInAppNotification()
        Task {
            await model.markNotificationRead(notification.id)
            guard let destination = notification.destination else {
                model.errorMessage = "This notification does not contain a destination."
                return
            }
            switch destination {
            case .channel(let communityID, let channelID, let messageID):
                if store.communities[communityID]?.channels.contains(where: {
                    $0.channelId == channelID
                }) != true {
                    await model.refreshHome()
                }
                guard store.communities[communityID]?.channels.contains(where: {
                    $0.channelId == channelID
                }) == true else {
                    model.errorMessage = "That channel is no longer available."
                    return
                }
                openChannel(channelID, communityID: communityID)
                model.focusMessage(messageID)
            case .chat(let chatID, _, let messageID):
                if store.chats[chatID] == nil { await model.refreshHome() }
                guard store.chats[chatID] != nil else {
                    model.errorMessage = "That conversation is no longer available."
                    return
                }
                openChat(chatID)
                model.focusMessage(messageID)
            case .article(let owner, let articleID, let messageID):
                let source: ArticleOwner
                switch owner {
                case .community(let id): source = .community(id)
                case .user(let id): source = .user(id)
                }
                notificationArticle = NotificationArticleRoute(
                    source: source,
                    articleID: articleID,
                    commentID: messageID
                )
            case .profile(let userID):
                notificationProfile = NotificationProfileRoute(id: userID)
            case .community(let communityID):
                if store.communities[communityID] == nil { await model.refreshHome() }
                guard store.communities[communityID] != nil else {
                    model.errorMessage = "That community is no longer available."
                    return
                }
                openCommunity(communityID)
            case .path:
                model.errorMessage = "This notification links to a feature that is not available in the app yet."
            case .unknownArticle:
                model.errorMessage = "This article notification is missing its owner information."
            }
        }
    }
}

private struct OverviewView: View {
    @EnvironmentObject private var model: AppModel
    let communities: [Community]
    let chatCount: Int
    let unreadCount: Int
    let openCommunity: (String) -> Void
    let openMessages: () -> Void
    let discover: () -> Void
    let createCommunity: () -> Void

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
                                    CommunityMark(
                                        name: community.title,
                                        url: community.logoSmallId.flatMap { model.attachmentURLs[$0] }
                                    )
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

                Button(action: discover) {
                    Label("Discover communities", systemImage: "safari")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button(action: createCommunity) {
                    Label("Create a community", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(20)
        }
        .navigationTitle("Overview")
        .refreshable { await model.refreshHome() }
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

private struct CommunityDiscoveryView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var store: SyncStore
    let openCommunity: (String) -> Void
    @State private var query = ""
    @State private var joiningIDs: Set<String> = []
    @State private var showCreate = false
    @State private var approvalCommunity: CommunitySummary?
    @State private var reportCommunity: CommunitySummary?

    var body: some View {
        Group {
            if model.isLoadingCommunities && model.communityResults.isEmpty {
                ProgressView("Finding communities…")
            } else if model.communityResults.isEmpty {
                ContentUnavailableView(
                    query.isEmpty ? "No public communities" : "No communities found",
                    systemImage: "person.3.sequence",
                    description: Text(
                        query.isEmpty
                            ? "Create the first community on this instance."
                            : "Try a different name or tag."
                    )
                )
            } else {
                List(model.communityResults) { community in
                    CommunityDiscoveryRow(
                        community: community,
                        isJoined: store.communities[community.id] != nil,
                        isJoining: joiningIDs.contains(community.id),
                        open: { openCommunity(community.id) },
                        join: { join(community) }
                    )
                    .contextMenu {
                        Button("Report community", systemImage: "exclamationmark.bubble", role: .destructive) {
                            reportCommunity = community
                        }
                    }
                }
                .refreshable { await model.discoverCommunities(query: query) }
            }
        }
        .navigationTitle("Discover")
        .searchable(text: $query, prompt: "Community name or tag")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Create community", systemImage: "plus") { showCreate = true }
            }
        }
        .task(id: query) {
            do {
                try await Task.sleep(for: .milliseconds(query.isEmpty ? 0 : 350))
                await model.discoverCommunities(query: query)
            } catch {
                // A newer search superseded this request.
            }
        }
        .sheet(isPresented: $showCreate) {
            CreateCommunityView { communityID in
                showCreate = false
                openCommunity(communityID)
            }
        }
        .sheet(item: $reportCommunity) { community in
            ReportSheet(
                target: ReportTarget(type: .community, id: community.id, subject: community.title)
            )
        }
        .alert("Join request submitted", isPresented: pendingAlert) {
            Button("OK") { approvalCommunity = nil }
        } message: {
            Text("A community moderator needs to approve your request before its channels become available.")
        }
    }

    private var pendingAlert: Binding<Bool> {
        Binding(
            get: { approvalCommunity != nil },
            set: { if !$0 { approvalCommunity = nil } }
        )
    }

    private func join(_ community: CommunitySummary) {
        joiningIDs.insert(community.id)
        Task {
            let outcome = await model.joinCommunity(id: community.id)
            joiningIDs.remove(community.id)
            switch outcome {
            case .joined: openCommunity(community.id)
            case .pending: approvalCommunity = community
            case .failed: break
            }
        }
    }
}

private struct CommunityDiscoveryRow: View {
    @EnvironmentObject private var model: AppModel
    let community: CommunitySummary
    let isJoined: Bool
    let isJoining: Bool
    let open: () -> Void
    let join: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            CommunityMark(
                name: community.title,
                url: community.logoSmallId.flatMap { model.attachmentURLs[$0] }
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(community.title).fontWeight(.semibold)
                if let description = community.shortDescription, !description.isEmpty {
                    Text(description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                HStack(spacing: 8) {
                    Label("\(community.memberCount)", systemImage: "person.2")
                    if !community.tags.isEmpty {
                        Text(community.tags.prefix(3).map { "#\($0)" }.joined(separator: " "))
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if isJoining {
                ProgressView().controlSize(.small)
            } else if isJoined {
                Button("Open", action: open).buttonStyle(.bordered)
            } else {
                Button("Join", action: join).buttonStyle(.borderedProminent)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct CreateCommunityView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let created: (String) -> Void
    @State private var title = ""
    @State private var shortDescription = ""
    @State private var description = ""
    @State private var tags = ""
    @State private var iconSelection: PhotosPickerItem?
    @State private var sidebarSelection: PhotosPickerItem?
    @State private var iconData: Data?
    @State private var sidebarImageData: Data?
    @State private var isCreating = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Community") {
                    TextField("Name", text: $title)
                    TextField("Short description", text: $shortDescription)
                    TextField("Full description", text: $description, axis: .vertical)
                        .lineLimit(3...8)
                }
                Section("Required images") {
                    CommunityImagePicker(
                        title: "Community icon",
                        guidance: "Square image · 75 × 75 recommended",
                        selection: $iconSelection,
                        data: iconData
                    )
                    CommunityImagePicker(
                        title: "Sidebar image",
                        guidance: "Community navigation cover · 282 × 220 recommended",
                        selection: $sidebarSelection,
                        data: sidebarImageData
                    )
                    Text("Both images are required so the community has a complete identity everywhere it appears.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Tags") {
                    TextField("swift, design, berlin", text: $tags)
                    Text("Separate tags with commas. You can add a hero image and links in Community Settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("New community")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }
                        .disabled(trimmedTitle.isEmpty || iconData == nil || sidebarImageData == nil || isCreating)
                }
            }
            .overlay { if isCreating { ProgressView() } }
            .onChange(of: iconSelection) { _, item in loadImage(item, into: $iconData) }
            .onChange(of: sidebarSelection) { _, item in loadImage(item, into: $sidebarImageData) }
        }
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func create() {
        guard let iconData, let sidebarImageData else { return }
        isCreating = true
        Task {
            let normalizedTags = tags
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "#")) }
                .filter { !$0.isEmpty }
            if let community = await model.createCommunity(
                title: trimmedTitle,
                shortDescription: String(shortDescription.prefix(50)),
                description: String(description.prefix(1_000)),
                tags: Array(normalizedTags.prefix(10)),
                iconData: iconData,
                sidebarImageData: sidebarImageData
            ) {
                created(community.id)
            }
            isCreating = false
        }
    }

    private func loadImage(_ item: PhotosPickerItem?, into data: Binding<Data?>) {
        guard let item else { return }
        Task {
            if let loaded = try? await item.loadTransferable(type: Data.self) {
                data.wrappedValue = loaded
            } else {
                model.errorMessage = "That image could not be loaded from the photo library."
            }
        }
    }
}

private struct EditableCommunityLink: Identifiable {
    let id = UUID()
    var text: String
    var url: String
}

private struct CommunitySettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let community: Community

    private var current: Community {
        model.store.communities[community.id] ?? community
    }

    var body: some View {
        NavigationStack {
            List {
                if current.canManageInfo || current.creatorId == model.store.ownUser?.id {
                    Section {
                        NavigationLink {
                            CommunityGeneralSettingsView(community: current)
                        } label: {
                            SettingsRow(icon: "gearshape", color: .gray, title: "General")
                        }
                        NavigationLink {
                            CommunitySettingsStatusView(
                                title: "Premium",
                                icon: "sparkles",
                                rows: [
                                    ("Plan", current.premium == nil ? "Free" : "Premium"),
                                    ("Community points", current.pointBalance.formatted()),
                                ]
                            )
                        } label: {
                            SettingsRow(icon: "sparkles", color: .purple, title: "Premium")
                        }
                        NavigationLink {
                            CommunityNewsletterSettingsView(community: current)
                        } label: {
                            SettingsRow(icon: "envelope", color: .orange, title: "Newsletters")
                        }
                    }
                }
                if current.canManageRoles || current.canManageApplications {
                    NavigationLink {
                        CommunityOnboardingSettingsView(community: current)
                    } label: {
                        SettingsRow(icon: "person.badge.plus", color: .blue, title: "Onboarding", badge: current.membersPendingApproval)
                    }
                }

                Section("People & access") {
                    if current.canManageRoles || current.canModerate {
                        NavigationLink {
                            CommunityMembersSettingsView(community: current)
                        } label: {
                            SettingsRow(icon: "person.2", color: .blue, title: "Members", badge: current.memberCount)
                        }
                    }
                    if current.canModerate {
                        NavigationLink {
                            CommunityBansSettingsView(community: current)
                        } label: {
                            SettingsRow(icon: "hand.raised", color: .red, title: "Manage Bans")
                        }
                    }
                    if current.canManageChannels {
                        NavigationLink {
                            CommunityChannelsSettingsView(community: current)
                        } label: {
                            SettingsRow(icon: "number", color: .indigo, title: "Channels", badge: current.channels.count)
                        }
                    }
                    if current.canManageRoles {
                        NavigationLink {
                            CommunityRolesSettingsView(community: current)
                        } label: {
                            SettingsRow(icon: "person.badge.key", color: .teal, title: "Roles & Permissions", badge: current.roles.count)
                        }
                    }
                }

                if current.canManageInfo || current.creatorId == model.store.ownUser?.id {
                    Section("Extensions") {
                    NavigationLink {
                        CommunitySettingsStatusView(
                            title: "Token",
                            icon: "hexagon",
                            rows: [("Configured tokens", "\(current.tokens.count)")]
                        )
                    } label: {
                        SettingsRow(icon: "hexagon", color: .mint, title: "Token", badge: current.tokens.count)
                    }
                    NavigationLink {
                        CommunitySettingsStatusView(
                            title: "Bots",
                            icon: "cpu",
                            rows: [("Member-installed bots", current.allowUserBots ? "Allowed" : "Disabled")]
                        )
                    } label: {
                        SettingsRow(icon: "cpu", color: .yellow, title: "Bots")
                    }
                    NavigationLink {
                        CommunitySettingsStatusView(
                            title: "Plugins",
                            icon: "puzzlepiece.extension",
                            rows: [("Installed", "\(current.plugins.count)")]
                        )
                    } label: {
                        SettingsRow(icon: "puzzlepiece.extension", color: .pink, title: "Plugins", badge: current.plugins.count)
                    }
                    }
                }
            }
            .navigationTitle("Community Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct SettingsRow: View {
    let icon: String
    let color: Color
    let title: String
    var badge: Int? = nil

    var body: some View {
        Label {
            HStack {
                Text(title)
                Spacer()
                if let badge, badge > 0 {
                    Text("\(badge)").foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(color.gradient, in: RoundedRectangle(cornerRadius: 7))
        }
    }
}

private struct CommunitySettingsStatusView: View {
    let title: String
    let icon: String
    let rows: [(String, String)]

    var body: some View {
        List {
            Section {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    LabeledContent(row.0, value: row.1)
                }
            } footer: {
                Text("This section is connected to the community's live configuration. Editing controls will appear here as each workflow is made native on iPhone and iPad.")
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct CommunityNewsletterSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let community: Community
    @State private var enabled: Bool
    @State private var isSaving = false

    init(community: Community) {
        self.community = community
        _enabled = State(initialValue: community.enablePersonalNewsletter)
    }

    var body: some View {
        Form {
            Section {
                Toggle("Personal newsletters", isOn: $enabled)
            } footer: {
                Text("Allow members to opt in to personalized email updates from this community.")
            }
        }
        .navigationTitle("Newsletters")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    isSaving = true
                    Task {
                        if await model.setCommunityPersonalNewsletter(
                            communityID: community.id,
                            enabled: enabled
                        ) { dismiss() }
                        isSaving = false
                    }
                }
                .disabled(isSaving || enabled == community.enablePersonalNewsletter)
            }
        }
        .overlay { if isSaving { ProgressView() } }
    }
}

private struct CommunityOnboardingSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let community: Community
    @State private var manualApproval: Bool
    @State private var approvalEmail: String
    @State private var customWelcome: Bool
    @State private var welcomeText: String
    @State private var requirements: Bool
    @State private var minAccountAge: Bool
    @State private var minAccountDays: Int
    @State private var universalProfile: Bool
    @State private var xProfile: Bool
    @State private var isSaving = false

    init(community: Community) {
        self.community = community
        let options = community.onboardingOptions?.objectValue ?? [:]
        let approval = options["manuallyApprove"]?.objectValue ?? [:]
        let welcome = options["customWelcome"]?.objectValue ?? [:]
        let required = options["requirements"]?.objectValue ?? [:]
        _manualApproval = State(initialValue: approval["enabled"]?.boolValue ?? false)
        _approvalEmail = State(initialValue: approval["email"]?.stringValue ?? "")
        _customWelcome = State(initialValue: welcome["enabled"]?.boolValue ?? false)
        _welcomeText = State(initialValue: welcome["welcomeString"]?.stringValue ?? "")
        _requirements = State(initialValue: required["enabled"]?.boolValue ?? false)
        _minAccountAge = State(initialValue: required["minAccountTimeEnabled"]?.boolValue ?? false)
        _minAccountDays = State(initialValue: Int(required["minAccountTimeDays"]?.numberValue ?? 0))
        _universalProfile = State(initialValue: required["universalProfileEnabled"]?.boolValue ?? false)
        _xProfile = State(initialValue: required["xProfileEnabled"]?.boolValue ?? false)
    }

    var body: some View {
        Form {
            if community.canManageApplications {
                Section {
                    NavigationLink {
                        CommunityPendingApprovalsView(community: community)
                    } label: {
                        LabeledContent("Pending applications", value: "\(community.membersPendingApproval)")
                    }
                }
            }

            if community.canManageRoles {
                Section("Approval") {
                    Toggle("Approve new members manually", isOn: $manualApproval)
                    if manualApproval {
                        TextField("Notification email (optional)", text: $approvalEmail)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                    }
                }

                Section("Welcome") {
                    Toggle("Custom welcome message", isOn: $customWelcome)
                    if customWelcome {
                        TextField("Welcome message", text: $welcomeText, axis: .vertical)
                            .lineLimit(3...8)
                    }
                }

                Section("Requirements") {
                    Toggle("Enforce joining requirements", isOn: $requirements)
                    if requirements {
                        Toggle("Minimum account age", isOn: $minAccountAge)
                        if minAccountAge {
                            Stepper("At least \(minAccountDays) days", value: $minAccountDays, in: 0...3_650)
                        }
                        Toggle("Require Universal Profile", isOn: $universalProfile)
                        Toggle("Require X profile", isOn: $xProfile)
                    }
                }
            }
        }
        .navigationTitle("Onboarding")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if community.canManageRoles {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(isSaving)
                }
            }
        }
        .overlay { if isSaving { ProgressView() } }
    }

    private func save() {
        var options = community.onboardingOptions?.objectValue ?? [:]
        var approval = options["manuallyApprove"]?.objectValue ?? [:]
        approval["enabled"] = .bool(manualApproval)
        let normalizedEmail = approvalEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedEmail.isEmpty { approval.removeValue(forKey: "email") }
        else { approval["email"] = .string(normalizedEmail) }
        options["manuallyApprove"] = .object(approval)

        var welcome = options["customWelcome"]?.objectValue ?? [:]
        welcome["enabled"] = .bool(customWelcome)
        let normalizedWelcome = welcomeText.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedWelcome.isEmpty { welcome.removeValue(forKey: "welcomeString") }
        else { welcome["welcomeString"] = .string(welcomeText) }
        options["customWelcome"] = .object(welcome)

        var required = options["requirements"]?.objectValue ?? [:]
        required["enabled"] = .bool(requirements)
        required["minAccountTimeEnabled"] = .bool(minAccountAge)
        required["minAccountTimeDays"] = .number(Double(minAccountDays))
        required["universalProfileEnabled"] = .bool(universalProfile)
        required["xProfileEnabled"] = .bool(xProfile)
        options["requirements"] = .object(required)

        isSaving = true
        Task {
            if await model.saveCommunityOnboarding(
                communityID: community.id,
                options: .object(options)
            ) { dismiss() }
            isSaving = false
        }
    }
}

private struct CommunityPendingApprovalsView: View {
    @EnvironmentObject private var model: AppModel
    let community: Community
    @State private var decidingUserID: String?

    private var approvals: [CommunityPendingApproval] {
        model.communityPendingApprovals[community.id] ?? []
    }

    var body: some View {
        List {
            if approvals.isEmpty {
                ContentUnavailableView(
                    "No pending applications",
                    systemImage: "person.badge.checkmark",
                    description: Text("New applications will appear here.")
                )
            } else {
                ForEach(approvals) { approval in
                    VStack(alignment: .leading, spacing: 10) {
                        let user = model.store.users[approval.userId]
                        HStack(spacing: 12) {
                            Avatar(name: user?.displayName ?? "Member", isBot: user?.isBot ?? false, small: true)
                            Text(user?.displayName ?? "Loading member…").fontWeight(.semibold)
                        }
                        if let answers = approval.questionnaireAnswers, !answers.isEmpty {
                            Text("\(answers.count) questionnaire answers")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Button("Deny", role: .destructive) { decide(approval, state: "DENIED") }
                                .buttonStyle(.bordered)
                            Spacer()
                            Button("Approve") { decide(approval, state: "APPROVED") }
                                .buttonStyle(.borderedProminent)
                        }
                        .disabled(decidingUserID != nil)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Applications")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.loadPendingApprovals(communityID: community.id) }
        .refreshable { await model.loadPendingApprovals(communityID: community.id) }
    }

    private func decide(_ approval: CommunityPendingApproval, state: String) {
        decidingUserID = approval.userId
        Task {
            _ = await model.decidePendingApproval(
                communityID: community.id,
                userID: approval.userId,
                state: state
            )
            decidingUserID = nil
        }
    }
}

private struct CommunityGeneralSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let community: Community
    @State private var title: String
    @State private var shortDescription: String
    @State private var description: String
    @State private var tags: String
    @State private var links: [EditableCommunityLink]
    @State private var iconSelection: PhotosPickerItem?
    @State private var sidebarSelection: PhotosPickerItem?
    @State private var heroSelection: PhotosPickerItem?
    @State private var iconData: Data?
    @State private var sidebarData: Data?
    @State private var heroData: Data?
    @State private var isSaving = false

    init(community: Community) {
        self.community = community
        _title = State(initialValue: community.title)
        _shortDescription = State(initialValue: community.shortDescription ?? "")
        _description = State(initialValue: community.description)
        _tags = State(initialValue: community.tags.joined(separator: ", "))
        _links = State(initialValue: community.links.map {
            EditableCommunityLink(text: $0.text, url: $0.url)
        })
    }

    var body: some View {
        Form {
                Section("Community information") {
                    TextField("Community name", text: $title)
                    TextField("Tagline", text: $shortDescription)
                        .onChange(of: shortDescription) { _, value in
                            if value.count > 50 { shortDescription = String(value.prefix(50)) }
                        }
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(4...10)
                        .onChange(of: description) { _, value in
                            if value.count > 1_000 { description = String(value.prefix(1_000)) }
                        }
                    TextField("Tags separated by commas", text: $tags)
                }

                Section("Community images") {
                    CommunityImagePicker(
                        title: "Community icon",
                        guidance: "Square image · 75 × 75 recommended",
                        selection: $iconSelection,
                        data: iconData,
                        existingURL: community.logoSmallId.flatMap { model.attachmentURLs[$0] }
                    )
                    CommunityImagePicker(
                        title: "Sidebar image",
                        guidance: "282 × 220 recommended",
                        selection: $sidebarSelection,
                        data: sidebarData,
                        existingURL: community.logoLargeId.flatMap { model.attachmentURLs[$0] }
                    )
                    CommunityImagePicker(
                        title: "Hero image",
                        guidance: "Community home banner · 800 × 252 recommended",
                        selection: $heroSelection,
                        data: heroData,
                        existingURL: community.headerImageId.flatMap { model.attachmentURLs[$0] }
                    )
                }

                Section("Links") {
                    ForEach($links) { $link in
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Label", text: $link.text)
                            TextField("https://example.com", text: $link.url)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.URL)
                            Button("Remove link", systemImage: "trash", role: .destructive) {
                                links.removeAll { $0.id == link.id }
                            }
                            .font(.caption)
                        }
                    }
                    Button("Add link", systemImage: "plus") {
                        links.append(EditableCommunityLink(text: "", url: ""))
                    }
                }
            }
            .navigationTitle("General")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(trimmedTitle.isEmpty || isSaving)
                }
            }
            .overlay { if isSaving { ProgressView() } }
            .onChange(of: iconSelection) { _, item in loadImage(item, into: $iconData) }
            .onChange(of: sidebarSelection) { _, item in loadImage(item, into: $sidebarData) }
            .onChange(of: heroSelection) { _, item in loadImage(item, into: $heroData) }
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        isSaving = true
        Task {
            let normalizedTags = tags
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "#")) }
                .filter { !$0.isEmpty }
            let normalizedLinks = links.compactMap { link -> CommunityLink? in
                let text = link.text.trimmingCharacters(in: .whitespacesAndNewlines)
                let url = link.url.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty, !url.isEmpty else { return nil }
                return CommunityLink(url: url, text: text)
            }
            let saved = await model.updateCommunity(
                community,
                title: trimmedTitle,
                shortDescription: String(shortDescription.prefix(50)),
                description: String(description.prefix(1_000)),
                tags: Array(normalizedTags.prefix(10)),
                links: normalizedLinks,
                iconData: iconData,
                sidebarImageData: sidebarData,
                heroImageData: heroData
            )
            isSaving = false
            if saved { dismiss() }
        }
    }

    private func loadImage(_ item: PhotosPickerItem?, into data: Binding<Data?>) {
        guard let item else { return }
        Task {
            if let loaded = try? await item.loadTransferable(type: Data.self) {
                data.wrappedValue = loaded
            } else {
                model.errorMessage = "That image could not be loaded from the photo library."
            }
        }
    }
}

private struct CommunityMembersSettingsView: View {
    @EnvironmentObject private var model: AppModel
    let community: Community
    @State private var search = ""
    @State private var selectedRoleID: String?
    @State private var roleMember: ChannelMemberEntry?

    private var result: CommunityMemberList? { model.communityMemberLists[community.id] }
    private var members: [ChannelMemberEntry] { (result?.online ?? []) + (result?.offline ?? []) }

    var body: some View {
        List {
            if community.roleInfos.count > 1 {
                Section {
                    Picker("Role", selection: $selectedRoleID) {
                        Text("All roles").tag(String?.none)
                        ForEach(community.roleInfos) { role in
                            Text(role.title).tag(String?.some(role.id))
                        }
                    }
                }
            }
            Section {
                if members.isEmpty {
                    ContentUnavailableView.search(text: search)
                } else {
                    ForEach(members) { member in
                        if let user = model.store.users[member.userId] {
                            HStack(spacing: 12) {
                                NavigationLink {
                                    UserProfileView(userID: user.id, store: model.store) { _ in }
                                } label: {
                                    HStack(spacing: 12) {
                                        Avatar(name: user.displayName, isBot: user.isBot, small: true)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(user.displayName)
                                            Text(roleNames(member.roleIds))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Circle()
                                            .fill(model.effectiveOnlineStatus(for: user) == "online" ? .green : .secondary)
                                            .frame(width: 9, height: 9)
                                    }
                                }
                                if community.canManageRoles {
                                    Button("Manage roles", systemImage: "person.badge.key") {
                                        roleMember = member
                                    }
                                    .labelStyle(.iconOnly)
                                    .buttonStyle(.borderless)
                                }
                            }
                        } else {
                            ProgressView().frame(maxWidth: .infinity)
                        }
                    }
                }
            } header: {
                Text(result.map { "\($0.resultCount) of \($0.totalCount) members" } ?? "Members")
            }
        }
        .navigationTitle("Members")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Find a member")
        .task(id: "\(search)|\(selectedRoleID ?? "all")") {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await model.loadCommunityMembers(
                communityID: community.id,
                search: search,
                roleID: selectedRoleID
            )
        }
        .refreshable {
            await model.loadCommunityMembers(
                communityID: community.id,
                search: search,
                roleID: selectedRoleID
            )
        }
        .sheet(item: $roleMember) { member in
            NavigationStack {
                CommunityMemberRoleEditor(community: community, member: member)
            }
        }
    }

    private func roleNames(_ ids: [String]) -> String {
        let names = community.roleInfos.filter { ids.contains($0.id) }.map(\.title)
        return names.isEmpty ? "Member" : names.joined(separator: ", ")
    }
}

private struct CommunityMemberRoleEditor: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let community: Community
    let member: ChannelMemberEntry
    @State private var selected: Set<String>
    @State private var isSaving = false

    init(community: Community, member: ChannelMemberEntry) {
        self.community = community
        self.member = member
        _selected = State(initialValue: Set(member.roleIds))
    }

    var body: some View {
        Form {
            if let user = model.store.users[member.userId] {
                Section {
                    HStack(spacing: 12) {
                        Avatar(name: user.displayName, isBot: user.isBot, small: true)
                        Text(user.displayName).fontWeight(.semibold)
                    }
                }
            }
            Section {
                ForEach(community.roleInfos) { role in
                    Toggle(role.title, isOn: Binding(
                        get: { selected.contains(role.id) },
                        set: { enabled in
                            if enabled { selected.insert(role.id) }
                            else { selected.remove(role.id) }
                        }
                    ))
                    .disabled(role.title == "Public")
                }
            } header: {
                Text("Assigned roles")
            } footer: {
                Text("Role changes affect community, channel, article, and moderation permissions immediately.")
            }
        }
        .navigationTitle("Member Roles")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    isSaving = true
                    Task {
                        if await model.setCommunityMemberRoles(
                            communityID: community.id,
                            userID: member.userId,
                            previous: Set(member.roleIds),
                            selected: selected
                        ) { dismiss() }
                        isSaving = false
                    }
                }
                .disabled(isSaving || selected == Set(member.roleIds))
            }
        }
        .overlay { if isSaving { ProgressView() } }
    }
}

private struct CommunityBansSettingsView: View {
    @EnvironmentObject private var model: AppModel
    let community: Community
    @State private var unbanning: String?

    private var bans: [CommunityBan] { model.communityBans[community.id] ?? [] }

    var body: some View {
        List {
            if bans.isEmpty {
                ContentUnavailableView(
                    "No banned members",
                    systemImage: "hand.raised",
                    description: Text("Members banned from this community will appear here.")
                )
            } else {
                ForEach(bans) { ban in
                    HStack(spacing: 12) {
                        let user = model.store.users[ban.userId]
                        Avatar(name: user?.displayName ?? "Member", isBot: user?.isBot ?? false, small: true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(user?.displayName ?? "Loading member…")
                            Text(ban.blockStateUntil.map { "Until \($0)" } ?? "Banned indefinitely")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Unban") {
                            unbanning = ban.userId
                            Task {
                                _ = await model.unbanUser(communityID: community.id, userID: ban.userId)
                                unbanning = nil
                            }
                        }
                        .disabled(unbanning != nil)
                    }
                }
            }
        }
        .navigationTitle("Manage Bans")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.loadCommunityBans(communityID: community.id) }
        .refreshable { await model.loadCommunityBans(communityID: community.id) }
    }
}

private struct CommunityChannelsSettingsView: View {
    @EnvironmentObject private var model: AppModel
    let community: Community
    @State private var showingNewChannel = false
    @State private var showingNewArea = false
    @State private var areaName = ""

    private var current: Community { model.store.communities[community.id] ?? community }

    var body: some View {
        List {
            channelSection(title: "Uncategorized", areaID: nil)
            ForEach(current.areaInfos) { area in
                channelSection(title: area.title, areaID: area.id)
            }
        }
        .navigationTitle("Channels")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if current.canManageChannels {
                ToolbarItem(placement: .primaryAction) {
                    Menu("Add", systemImage: "plus") {
                        Button("New channel", systemImage: "number") { showingNewChannel = true }
                            .disabled(current.areaInfos.isEmpty)
                        Button("New area", systemImage: "folder") { showingNewArea = true }
                    }
                }
            }
        }
        .sheet(isPresented: $showingNewChannel) {
            NavigationStack {
                CommunityChannelEditor(community: current, channel: nil)
            }
        }
        .alert("New area", isPresented: $showingNewArea) {
            TextField("Area name", text: $areaName)
            Button("Cancel", role: .cancel) { areaName = "" }
            Button("Create") {
                let title = areaName.trimmingCharacters(in: .whitespacesAndNewlines)
                areaName = ""
                Task {
                    _ = await model.saveCommunityArea(
                        communityID: current.id,
                        areaID: nil,
                        title: title,
                        order: (current.areaInfos.map(\.order).max() ?? -1) + 1
                    )
                }
            }
            .disabled(areaName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            if current.areaInfos.isEmpty {
                Text("Channels belong to an area. Create this area, then add the channel.")
            }
        }
    }

    @ViewBuilder
    private func channelSection(title: String, areaID: String?) -> some View {
        let channels = current.channels.filter { $0.areaId == areaID }.sorted { $0.order < $1.order }
        if !channels.isEmpty {
            Section(title) {
                ForEach(channels) { channel in
                    NavigationLink {
                        CommunityChannelEditor(community: current, channel: channel)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Label(channel.title, systemImage: "number")
                            if let description = channel.description, !description.isEmpty {
                                Text(description).font(.caption).foregroundStyle(.secondary)
                            }
                            Text("\(channel.rolePermissions.count) role access rules")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }
}

private struct CommunityChannelEditor: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let community: Community
    let channel: Channel?
    @State private var title: String
    @State private var description: String
    @State private var emoji: String
    @State private var url: String
    @State private var areaID: String?
    @State private var access: [String: Set<String>]
    @State private var isSaving = false
    @State private var confirmingDelete = false

    private static let permissionOptions: [(String, String)] = [
        ("CHANNEL_EXISTS", "Can see channel"),
        ("CHANNEL_READ", "Can read"),
        ("CHANNEL_WRITE", "Can write"),
        ("CHANNEL_MODERATE", "Can moderate"),
    ]

    init(community: Community, channel: Channel?) {
        self.community = community
        self.channel = channel
        _title = State(initialValue: channel?.title ?? "")
        _description = State(initialValue: channel?.description ?? "")
        _emoji = State(initialValue: channel?.emoji ?? "💬")
        _url = State(initialValue: channel?.url ?? "")
        _areaID = State(initialValue: channel?.areaId ?? community.areaInfos.first?.id)
        var initial = Dictionary(uniqueKeysWithValues: (channel?.roleAccess ?? []).map {
            ($0.roleId, Set($0.permissions))
        })
        if channel == nil {
            for role in community.roleInfos {
                switch role.title {
                case "Admin": initial[role.id] = ["CHANNEL_EXISTS", "CHANNEL_READ", "CHANNEL_WRITE", "CHANNEL_MODERATE"]
                case "Member": initial[role.id] = ["CHANNEL_EXISTS", "CHANNEL_READ", "CHANNEL_WRITE"]
                case "Public": initial[role.id] = ["CHANNEL_EXISTS", "CHANNEL_READ"]
                default: initial[role.id] = []
                }
            }
        }
        _access = State(initialValue: initial)
    }

    var body: some View {
        Form {
            Section("Channel") {
                TextField("Name", text: $title)
                TextField("Description", text: $description, axis: .vertical).lineLimit(2...5)
                TextField("Emoji", text: $emoji)
                TextField("URL slug (optional)", text: $url)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Picker("Area", selection: $areaID) {
                    ForEach(community.areaInfos) { area in
                        Text(area.title).tag(String?.some(area.id))
                    }
                }
            }

            ForEach(community.roleInfos) { role in
                Section(role.title) {
                    ForEach(Self.permissionOptions, id: \.0) { permission, label in
                        Toggle(label, isOn: permissionBinding(roleID: role.id, permission: permission))
                            .disabled(role.title == "Admin")
                    }
                }
            }

            if channel != nil {
                Section {
                    Button("Delete Channel", role: .destructive) { confirmingDelete = true }
                }
            }
        }
        .navigationTitle(channel == nil ? "New Channel" : "Edit Channel")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if channel == nil {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(isSaving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .overlay { if isSaving { ProgressView() } }
        .confirmationDialog("Delete this channel?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Channel", role: .destructive) {
                guard let channel else { return }
                Task {
                    if await model.deleteCommunityChannel(
                        communityID: community.id,
                        channelID: channel.id
                    ) { dismiss() }
                }
            }
        } message: {
            Text("Messages in this channel will no longer be accessible.")
        }
    }

    private func permissionBinding(roleID: String, permission: String) -> Binding<Bool> {
        Binding(
            get: { access[roleID, default: []].contains(permission) },
            set: { enabled in
                if enabled { access[roleID, default: []].insert(permission) }
                else { access[roleID, default: []].remove(permission) }
            }
        )
    }

    private func save() {
        isSaving = true
        Task {
            let roleAccess = community.roleInfos.filter { $0.title != "Admin" }.map { role in
                ChannelRoleAccess(
                    roleId: role.id,
                    roleTitle: role.title,
                    permissions: Array(access[role.id, default: []]).sorted()
                )
            }
            let saved = await model.saveCommunityChannel(
                communityID: community.id,
                channelID: channel?.id,
                areaID: areaID,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                url: url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : url,
                order: channel?.order ?? ((community.channels.filter { $0.areaId == areaID }.map(\.order).max() ?? -1) + 1),
                description: description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : description,
                emoji: emoji.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "💬" : emoji,
                roleAccess: roleAccess
            )
            isSaving = false
            if saved { dismiss() }
        }
    }
}

private struct CommunityRolesSettingsView: View {
    @EnvironmentObject private var model: AppModel
    let community: Community
    @State private var newRoleName = ""
    @State private var showingNewRole = false

    private var current: Community { model.store.communities[community.id] ?? community }

    var body: some View {
        List {
            ForEach(current.roleInfos) { role in
                NavigationLink {
                    CommunityRoleEditor(community: current, role: role)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(role.title)
                        Text("\(role.permissions.count) community permissions · \(role.type == "PREDEFINED" ? "Built in" : "Custom")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Roles & Permissions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if current.canManageRoles {
                ToolbarItem(placement: .primaryAction) {
                    Button("New role", systemImage: "plus") { showingNewRole = true }
                }
            }
        }
        .alert("New role", isPresented: $showingNewRole) {
            TextField("Role name", text: $newRoleName)
            Button("Cancel", role: .cancel) { newRoleName = "" }
            Button("Create") {
                let title = newRoleName
                newRoleName = ""
                Task { _ = await model.createCommunityRole(communityID: community.id, title: title) }
            }
            .disabled(newRoleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("New roles start without community-wide permissions. Configure the role after creating it.")
        }
    }
}

private struct CommunityRoleEditor: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let community: Community
    let role: CommunityRoleInfo
    @State private var title: String
    @State private var description: String
    @State private var permissions: Set<String>
    @State private var isSaving = false
    @State private var confirmingDelete = false

    private static let permissionOptions: [(String, String)] = [
        ("COMMUNITY_MANAGE_INFO", "Manage community info"),
        ("COMMUNITY_MANAGE_CHANNELS", "Manage channels"),
        ("COMMUNITY_MANAGE_ROLES", "Manage roles"),
        ("COMMUNITY_MANAGE_ARTICLES", "Manage articles"),
        ("COMMUNITY_MANAGE_USER_APPLICATIONS", "Manage applications"),
        ("COMMUNITY_MODERATE", "Moderate members"),
        ("COMMUNITY_MANAGE_EVENTS", "Manage events"),
        ("WEBRTC_CREATE", "Create calls"),
        ("WEBRTC_CREATE_CUSTOM", "Create custom calls"),
        ("WEBRTC_MODERATE", "Moderate calls"),
    ]

    init(community: Community, role: CommunityRoleInfo) {
        self.community = community
        self.role = role
        _title = State(initialValue: role.title)
        _description = State(initialValue: role.description ?? "")
        _permissions = State(initialValue: Set(role.permissions))
    }

    private var isAdmin: Bool { role.title == "Admin" }
    private var isCustom: Bool { role.type != "PREDEFINED" }

    var body: some View {
        Form {
            Section("Role") {
                TextField("Name", text: $title).disabled(!isCustom)
                TextField("Description", text: $description, axis: .vertical).lineLimit(2...5)
            }
            Section("Community permissions") {
                ForEach(Self.permissionOptions, id: \.0) { permission, label in
                    Toggle(label, isOn: Binding(
                        get: { permissions.contains(permission) },
                        set: { enabled in
                            if enabled { permissions.insert(permission) }
                            else { permissions.remove(permission) }
                        }
                    ))
                    .disabled(isAdmin)
                }
            }
            if isCustom {
                Section {
                    Button("Delete Role", role: .destructive) { confirmingDelete = true }
                }
            }
        }
        .navigationTitle(role.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }.disabled(isSaving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .overlay { if isSaving { ProgressView() } }
        .confirmationDialog("Delete this role?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Role", role: .destructive) {
                Task {
                    if await model.deleteCommunityRole(communityID: community.id, roleID: role.id) { dismiss() }
                }
            }
        } message: {
            Text("Members assigned only to this role may lose access immediately.")
        }
    }

    private func save() {
        isSaving = true
        Task {
            let saved = await model.updateCommunityRole(
                communityID: community.id,
                roleID: role.id,
                title: isCustom ? title.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
                description: description,
                permissions: isAdmin ? nil : Array(permissions).sorted()
            )
            isSaving = false
            if saved { dismiss() }
        }
    }
}

private struct CommunityImagePicker: View {
    let title: String
    let guidance: String
    @Binding var selection: PhotosPickerItem?
    let data: Data?
    var existingURL: URL? = nil

    var body: some View {
        HStack(spacing: 14) {
            preview
                .frame(width: 76, height: 62)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).fontWeight(.semibold)
                Text(guidance).font(.caption).foregroundStyle(.secondary)
                PhotosPicker(selection: $selection, matching: .images) {
                    Text(data == nil && existingURL == nil ? "Choose image" : "Replace image")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var preview: some View {
        if let data, let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFill()
        } else if let existingURL {
            AsyncImage(url: existingURL) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            Color.secondary.opacity(0.12)
            Image(systemName: "photo").foregroundStyle(.secondary)
        }
    }
}

private struct ReportSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let target: ReportTarget
    @State private var reason: ReportReason = .spam
    @State private var details = ""
    @State private var isSending = false
    @State private var sent = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(target.subject).fontWeight(.semibold)
                    Text("Reports are reviewed by the instance moderation team.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Reason") {
                    Picker("Reason", selection: $reason) {
                        ForEach(ReportReason.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                }
                Section("Additional details (optional)") {
                    TextField("What should moderators know?", text: $details, axis: .vertical)
                        .lineLimit(3...8)
                        .onChange(of: details) { _, value in
                            if value.count > 2_000 { details = String(value.prefix(2_000)) }
                        }
                }
            }
            .navigationTitle("Report content")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") { send() }.disabled(isSending)
                }
            }
            .overlay { if isSending { ProgressView() } }
            .alert("Report sent", isPresented: $sent) {
                Button("Done") { dismiss() }
            } message: {
                Text("Thank you. The moderation team will review it.")
            }
        }
    }

    private func send() {
        isSending = true
        Task {
            sent = await model.report(
                type: target.type,
                targetID: target.id,
                reason: reason,
                message: details
            )
            isSending = false
        }
    }
}

private struct CommunityHomeView: View {
    @EnvironmentObject private var model: AppModel
    let community: Community
    @ObservedObject var store: SyncStore
    @State private var selectedArticle: ArticlePreview?
    @State private var showComposer = false

    private var articles: [CommunityArticlePreview] {
        model.communityArticles[community.id] ?? []
    }

    private var drafts: [CommunityArticlePreview] {
        model.communityArticleDrafts[community.id] ?? []
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let imageID = community.headerImageId,
                   let url = model.attachmentURLs[imageID] {
                    CommunityFeatureImage(url: url, height: 250)
                }
                VStack(alignment: .leading, spacing: 7) {
                    CommunityMark(
                        name: community.title,
                        url: community.logoSmallId.flatMap { model.attachmentURLs[$0] }
                    )
                        .scaleEffect(1.35, anchor: .leading)
                        .padding(.bottom, 8)
                    Text(community.title).font(.largeTitle.bold())
                    Text("\(community.memberCount) members · \(community.channels.count) channels")
                        .foregroundStyle(.secondary)
                }

                Divider()
                HStack {
                    Text("Latest articles").font(.title2.bold())
                    Spacer()
                    if community.canManageArticles {
                        Button("New article", systemImage: "square.and.pencil") {
                            showComposer = true
                        }
                    } else {
                        Image(systemName: "newspaper").foregroundStyle(AppTheme.accent)
                    }
                }

                if articles.isEmpty {
                    ContentUnavailableView(
                        "No published articles yet",
                        systemImage: "doc.text",
                        description: Text("Community articles and announcements will appear here.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(articles) { item in
                            ArticleCard(
                                article: item.article,
                                author: store.users[item.article.creatorId],
                                imageURL: item.article.thumbnailImageId.flatMap { model.attachmentURLs[$0] }
                            ) { selectedArticle = item.article }
                        }
                    }
                }

                if community.canManageArticles, !drafts.isEmpty {
                    Divider().padding(.top, 4)
                    Label("Drafts", systemImage: "doc.badge.clock")
                        .font(.title2.bold())
                    LazyVStack(spacing: 12) {
                        ForEach(drafts) { item in
                            ArticleCard(
                                article: item.article,
                                author: store.users[item.article.creatorId],
                                imageURL: item.article.thumbnailImageId.flatMap { model.attachmentURLs[$0] },
                                badge: "Draft"
                            ) { selectedArticle = item.article }
                        }
                    }
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(community.title)
        .refreshable { await model.loadCommunityArticles(communityID: community.id) }
        .task(id: community.id) { await model.loadCommunityArticles(communityID: community.id) }
        .sheet(item: $selectedArticle) { article in
            ArticleReaderView(
                articleID: article.id,
                source: .community(community.id),
                store: store,
                focusedCommentID: nil
            )
        }
        .sheet(isPresented: $showComposer) {
            ArticleComposer(owner: .community(community.id)) {
                showComposer = false
                Task { await model.loadCommunityArticles(communityID: community.id) }
            }
        }
    }
}

private struct ArticleCard: View {
    let article: ArticlePreview
    let author: UserProfile?
    let imageURL: URL?
    var badge: String? = nil
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 14) {
                if let imageURL {
                    AsyncImage(url: imageURL) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Color.secondary.opacity(0.12)
                    }
                    .frame(width: 92, height: 76)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(article.title).font(.headline).foregroundStyle(.primary)
                        if let badge {
                            Text(badge)
                                .font(.caption2.bold())
                                .foregroundStyle(AppTheme.accent)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(AppTheme.accent.opacity(0.12), in: Capsule())
                        }
                    }
                    if let preview = article.previewText, !preview.isEmpty {
                        Text(preview).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                    }
                    HStack {
                        Text(author?.displayName ?? "Common Ground member")
                        Spacer()
                        Label("\(article.commentCount)", systemImage: "bubble.left")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 15))
        }
        .buttonStyle(.plain)
    }
}

private struct ArticleReaderView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let articleID: String
    let source: ArticleOwner
    @ObservedObject var store: SyncStore
    let focusedCommentID: String?
    @State private var commentText = ""
    @State private var isSendingComment = false
    @State private var showEditor = false
    @State private var confirmDelete = false

    private var article: ArticleDetail? { model.articleDetails[articleID] }
    private var comments: [Message] {
        guard let article else { return [] }
        return store.orderedMessages(channelId: article.channelId)
    }
    private var canEdit: Bool {
        switch source {
        case .user(let userID): userID == store.ownUser?.id
        case .community(let communityID): store.communities[communityID]?.canManageArticles == true
        }
    }
    private var isDraft: Bool { model.articleDraftIDs.contains(articleID) }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    if let article {
                    VStack(alignment: .leading, spacing: 18) {
                        if let imageID = article.headerImageId,
                           let url = model.attachmentURLs[imageID] {
                            AsyncImage(url: url) { image in
                                image.resizable().scaledToFit()
                            } placeholder: {
                                ProgressView()
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                        Text(article.title).font(.largeTitle.bold())
                        if let creator = store.users[article.creatorId] {
                            HStack {
                                Avatar(
                                    name: creator.displayName,
                                    url: creator.imageID.flatMap { model.attachmentURLs[$0] },
                                    isBot: creator.isBot,
                                    small: true
                                )
                                Text(creator.displayName).fontWeight(.semibold)
                            }
                        }
                        if let preview = article.previewText, !preview.isEmpty {
                            Text(preview).font(.title3).foregroundStyle(.secondary)
                        }
                        Divider()
                        MarkdownArticleText(source: article.markdownSource)
                        if !article.tags.isEmpty {
                            Text(article.tags.map { "#\($0)" }.joined(separator: "  "))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Divider().padding(.top, 8)
                        HStack {
                            Text("Comments").font(.title2.bold())
                            Spacer()
                            Text(comments.count, format: .number)
                                .foregroundStyle(.secondary)
                        }
                        if comments.isEmpty {
                            ContentUnavailableView(
                                "No comments yet",
                                systemImage: "bubble.left",
                                description: Text("Start the conversation about this article.")
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        } else {
                            LazyVStack(alignment: .leading, spacing: 16) {
                                ForEach(comments) { comment in
                                    ArticleCommentRow(
                                        message: comment,
                                        author: store.users[comment.creatorId],
                                        avatarURL: store.users[comment.creatorId]?
                                            .imageID
                                            .flatMap { model.attachmentURLs[$0] }
                                    )
                                    .padding(10)
                                    .background(
                                        comment.id == focusedCommentID
                                            ? AppTheme.accent.opacity(0.14)
                                            : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 14)
                                    )
                                    .id(comment.id)
                                }
                            }
                        }
                        if isDraft {
                            Label(
                                "Comments are read-only while this article is a draft.",
                                systemImage: "lock"
                            )
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                        } else {
                            HStack(alignment: .bottom, spacing: 10) {
                                TextField("Add a comment…", text: $commentText, axis: .vertical)
                                    .lineLimit(1...5)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 11)
                                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 17))
                                Button("Post", systemImage: "arrow.up.circle.fill") {
                                    sendComment(article)
                                }
                                .labelStyle(.iconOnly)
                                .font(.title2)
                                .foregroundStyle(AppTheme.accent)
                                .disabled(
                                    commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                        || isSendingComment
                                )
                            }
                        }
                    }
                    .frame(maxWidth: 720, alignment: .leading)
                    .padding(24)
                    .frame(maxWidth: .infinity)
                    } else {
                        ProgressView("Loading article…").padding(50)
                    }
                }
                .onChange(of: comments.map(\.id), initial: true) { _, ids in
                    guard let focusedCommentID, ids.contains(focusedCommentID) else { return }
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(120))
                        withAnimation { proxy.scrollTo(focusedCommentID, anchor: .center) }
                    }
                }
            }
            .navigationTitle("Article")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if canEdit {
                    ToolbarItem(placement: .primaryAction) {
                        Menu("Manage article", systemImage: "ellipsis.circle") {
                            Button("Edit article", systemImage: "pencil") { showEditor = true }
                            Button("Delete article", systemImage: "trash", role: .destructive) {
                                confirmDelete = true
                            }
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task(id: articleID) {
                switch source {
                case .community(let id):
                    await model.loadCommunityArticle(communityID: id, articleID: articleID)
                case .user(let id):
                    await model.loadUserArticle(userID: id, articleID: articleID)
                }
                if let article = model.articleDetails[articleID] {
                    await model.loadArticleComments(
                        owner: source,
                        article: article,
                        focusing: focusedCommentID
                    )
                }
            }
            .refreshable {
                guard let article else { return }
                await model.loadArticleComments(owner: source, article: article)
            }
            .sheet(isPresented: $showEditor) {
                if let article {
                    ArticleComposer(
                        owner: source,
                        article: article,
                        isDraft: model.articleDraftIDs.contains(articleID)
                    ) {
                        showEditor = false
                    }
                }
            }
            .confirmationDialog("Delete this article?", isPresented: $confirmDelete) {
                Button("Delete article", role: .destructive) {
                    Task {
                        if await model.deleteArticle(owner: source, articleID: articleID) { dismiss() }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the article and its public link.")
            }
            .onDisappear {
                guard let article else { return }
                Task { await model.leaveArticleComments(owner: source, article: article) }
            }
        }
    }

    private func sendComment(_ article: ArticleDetail) {
        let text = commentText
        isSendingComment = true
        Task {
            if await model.sendArticleComment(owner: source, article: article, text: text) {
                commentText = ""
            }
            isSendingComment = false
        }
    }
}

private struct ArticleCommentRow: View {
    let message: Message
    let author: UserProfile?
    let avatarURL: URL?

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Avatar(
                name: author?.displayName ?? "Member",
                url: avatarURL,
                isBot: author?.isBot == true,
                small: true
            )
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(author?.displayName ?? "Member").font(.subheadline.bold())
                    Text(commentDate)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Text(message.body.plainText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var commentDate: String {
        guard let date = ISO8601DateFormatter().date(from: message.createdAt) else { return "" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

private struct ChannelListView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showLeaveConfirmation = false
    @State private var reportTarget: ReportTarget?
    @State private var showCommunitySettings = false
    let community: Community
    let selectedChannelID: String?
    let openHome: () -> Void
    let select: (String) -> Void
    let leave: () -> Void

    var body: some View {
        List {
            if let imageID = community.logoLargeId,
               let url = model.attachmentURLs[imageID] {
                Section {
                    CommunityFeatureImage(url: url, height: 150)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }
            Section {
                Button(action: openHome) {
                    HStack {
                        Label("Community Home", systemImage: "newspaper")
                        Spacer()
                        if selectedChannelID == nil {
                            Image(systemName: "checkmark").foregroundStyle(AppTheme.accent)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
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
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle(community.title)
        .refreshable { await model.refreshHome() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if let shareURL = model.communityShareURL(community) {
                        ShareLink(
                            item: shareURL,
                            subject: Text(community.title),
                            message: Text("Join \(community.title) on Common Ground")
                        ) {
                            Label("Share community", systemImage: "square.and.arrow.up")
                        }
                    }
                    if !community.managementPermissions.isEmpty
                        || community.creatorId == model.store.ownUser?.id {
                        Button("Community settings", systemImage: "gearshape") {
                            showCommunitySettings = true
                        }
                    }
                    Divider()
                    Button("Report community", systemImage: "exclamationmark.bubble") {
                        reportTarget = ReportTarget(
                            type: .community,
                            id: community.id,
                            subject: community.title
                        )
                    }
                    Button(
                        "Leave community",
                        systemImage: "rectangle.portrait.and.arrow.right",
                        role: .destructive
                    ) {
                        showLeaveConfirmation = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog(
            "Leave \(community.title)?",
            isPresented: $showLeaveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Leave community", role: .destructive, action: leave)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You can join again later if the community remains public.")
        }
        .sheet(item: $reportTarget) { ReportSheet(target: $0) }
        .sheet(isPresented: $showCommunitySettings) {
            CommunitySettingsView(community: community)
        }
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
    let open: (AppNotification) -> Void

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
                        open(notification)
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
                                        Avatar(name: user.displayName, isBot: user.isBot, small: true)
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
    @State private var reportTarget: ReportTarget?
    @State private var selectedArticle: ArticlePreview?
    @State private var showComposer = false

    private var user: UserProfile? { store.users[userID] }
    private var onlineStatus: String {
        user.map { model.effectiveOnlineStatus(for: $0) } ?? "offline"
    }
    private var articles: [UserArticlePreview] { model.userArticles[userID] ?? [] }
    private var drafts: [UserArticlePreview] { model.userArticleDrafts[userID] ?? [] }
    private var cgDetails: [String: JSONValue] {
        model.profileDetails[userID]?
            .detailledProfiles
            .first(where: { $0.type == "cg" })?
            .extraData?
            .objectValue ?? [:]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let user {
                    VStack(spacing: 18) {
                        Avatar(
                            name: user.displayName,
                            url: user.imageID.flatMap { model.attachmentURLs[$0] },
                            isBot: user.isBot
                        )
                            .scaleEffect(1.8)
                            .padding(28)
                        VStack(spacing: 5) {
                            Text(user.displayName).font(.title2.bold())
                            Label(onlineStatus.capitalized, systemImage: "circle.fill")
                                .font(.caption)
                                .foregroundStyle(onlineStatus == "online" ? .green : .secondary)
                        }

                        HStack(spacing: 36) {
                            profileMetric(user.followerCount, "Followers")
                            profileMetric(user.followingCount, "Following")
                        }

                        if let description = cgDetails["description"]?.stringValue,
                           !description.isEmpty {
                            Text(description)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if let homepage = cgDetails["homepage"]?.stringValue,
                           let url = URL(string: homepage), !homepage.isEmpty {
                            Link(destination: url) {
                                Label(homepage, systemImage: "link")
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
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

                        Divider().padding(.top, 4)
                        HStack {
                            Text("Articles").font(.title2.bold())
                            Spacer()
                            if user.id == store.ownUser?.id {
                                Button("New article", systemImage: "square.and.pencil") {
                                    showComposer = true
                                }
                            }
                        }
                        if articles.isEmpty {
                            ContentUnavailableView(
                                user.id == store.ownUser?.id ? "You haven’t published yet" : "No articles yet",
                                systemImage: "doc.text"
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                        } else {
                            ForEach(articles) { item in
                                ArticleCard(
                                    article: item.article,
                                    author: user,
                                    imageURL: item.article.thumbnailImageId.flatMap {
                                        model.attachmentURLs[$0]
                                    }
                                ) {
                                    selectedArticle = item.article
                                }
                            }
                        }
                        if user.id == store.ownUser?.id, !drafts.isEmpty {
                            Divider().padding(.top, 8)
                            HStack {
                                Label("Drafts", systemImage: "doc.badge.clock")
                                    .font(.title2.bold())
                                Spacer()
                                Text(drafts.count, format: .number).foregroundStyle(.secondary)
                            }
                            ForEach(drafts) { item in
                                ArticleCard(
                                    article: item.article,
                                    author: user,
                                    imageURL: item.article.thumbnailImageId.flatMap {
                                        model.attachmentURLs[$0]
                                    },
                                    badge: "Draft"
                                ) {
                                    selectedArticle = item.article
                                }
                            }
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
            .refreshable { await model.loadUserProfile(userID: userID) }
            .task(id: userID) { await model.loadUserProfile(userID: userID) }
            .toolbar {
                ToolbarItem(placement: .secondaryAction) {
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        Task { await model.loadUserProfile(userID: userID) }
                    }
                }
                if let user, user.id != store.ownUser?.id {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Report user", systemImage: "exclamationmark.bubble") {
                            reportTarget = ReportTarget(type: .user, id: user.id, subject: user.displayName)
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $reportTarget) { ReportSheet(target: $0) }
            .sheet(item: $selectedArticle) { article in
                ArticleReaderView(
                    articleID: article.id,
                    source: .user(userID),
                    store: store,
                    focusedCommentID: nil
                )
            }
            .sheet(isPresented: $showComposer) {
                ArticleComposer(owner: .user(userID)) {
                    showComposer = false
                    Task { await model.loadUserProfile(userID: userID) }
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

    var access: MessageAccess {
        switch self {
        case .channel(let channel): .community(channel.communityId, channelId: channel.channelId)
        case .chat(let chat): .chat(chat.id, channelId: chat.channelId)
        }
    }
}

private struct ConversationView: View {
    @EnvironmentObject private var model: AppModel
    let context: ConversationContext
    @ObservedObject var store: SyncStore
    @State private var reportTarget: ReportTarget?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var deleteTarget: Message?
    @State private var showMentionPicker = false
    @State private var selectedUser: UserProfile?
    @State private var showParticipants = false
    @GestureState private var participantDrag: CGFloat = 0

    private var messages: [Message] {
        store.orderedMessages(channelId: context.channelID)
    }

    var body: some View {
        GeometryReader { proxy in
            let drawerWidth = min(max(proxy.size.width * 0.82, 280), 370)
            let baseOffset = showParticipants ? drawerWidth : 0
            let visibleOffset = min(drawerWidth, max(0, baseOffset - participantDrag))

            ZStack(alignment: .trailing) {
                conversationBody
                    .offset(x: -visibleOffset)
                    .overlay {
                        if visibleOffset > 1 {
                            Color.black
                                .opacity(0.18 * visibleOffset / drawerWidth)
                                .contentShape(Rectangle())
                                .onTapGesture { showParticipants = false }
                        }
                    }

                ConversationParticipantsView(
                    context: context,
                    store: store,
                    isVisible: showParticipants,
                    select: { selectedUser = $0 },
                    close: { showParticipants = false }
                )
                .frame(width: drawerWidth)
                .offset(x: drawerWidth - visibleOffset)
                .zIndex(1)
            }
            .clipped()
            .animation(.snappy(duration: 0.26), value: showParticipants)
            .simultaneousGesture(
                DragGesture(minimumDistance: 18)
                    .updating($participantDrag) { value, state, _ in
                        if abs(value.translation.width) > abs(value.translation.height) {
                            state = value.translation.width
                        }
                    }
                    .onEnded { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        if value.translation.width < -55 {
                            showParticipants = true
                        } else if value.translation.width > 55 {
                            showParticipants = false
                        }
                    }
            )
        }
        .navigationTitle(context.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Channel participants", systemImage: "person.2") {
                    showParticipants.toggle()
                }
                .accessibilityHint("Swipe left in the conversation to reveal this panel")
            }
        }
        .task(id: "\(context.channelID):\(model.focusedMessageID ?? "")") { await load() }
        .sheet(item: $reportTarget) { ReportSheet(target: $0) }
        .sheet(item: $selectedUser) { user in
            UserProfileView(userID: user.id, store: store) { chatID in
                selectedUser = nil
                model.selectChat(chatID)
            }
        }
        .sheet(isPresented: $showMentionPicker) {
            MentionPicker(store: store) { user in
                model.insertMention(user)
                showMentionPicker = false
            }
            .presentationDetents([.medium, .large])
        }
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    await model.uploadMessageImage(data)
                } else {
                    model.errorMessage = "That image could not be loaded from the photo library."
                }
                selectedPhoto = nil
            }
        }
        .confirmationDialog(
            "Delete this message?",
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete message", role: .destructive) {
                guard let message = deleteTarget else { return }
                deleteTarget = nil
                Task { await model.deleteMessage(message, access: context.access) }
            }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: {
            Text("This cannot be undone.")
        }
    }

    private var conversationBody: some View {
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
                                isOwn: message.creatorId == store.ownUser?.id,
                                author: store.users[message.creatorId],
                                avatarURL: store.users[message.creatorId]?
                                    .imageID
                                    .flatMap { model.attachmentURLs[$0] },
                                parent: message.parentMessageId.flatMap { parentID in
                                    messages.first { $0.id == parentID }
                                },
                                attachmentURL: message.imageAttachments.first.flatMap {
                                    model.attachmentURLs[$0.largeImageId] ?? model.attachmentURLs[$0.imageId]
                                },
                                openProfile: {
                                    selectedUser = store.users[message.creatorId]
                                },
                                reply: { model.beginReply(to: message) },
                                edit: { model.beginEditing(message) },
                                delete: { deleteTarget = message },
                                react: { reaction in
                                    Task {
                                        await model.setReaction(reaction, on: message, access: context.access)
                                    }
                                },
                                report: {
                                    reportTarget = ReportTarget(
                                        type: .message,
                                        id: message.id,
                                        subject: "Message from \(store.users[message.creatorId]?.displayName ?? "member")"
                                    )
                                }
                            )
                            .padding(8)
                            .background(
                                message.id == model.focusedMessageID
                                    ? AppTheme.accent.opacity(0.14)
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: 14)
                            )
                            .id(message.id)
                        }
                    }
                    .frame(maxWidth: 760)
                    .padding(20)
                    .frame(maxWidth: .infinity)
                }
                .refreshable { await load() }
                .onChange(of: messages.map(\.id), initial: true) { _, ids in
                    let target = model.focusedMessageID.flatMap { ids.contains($0) ? $0 : nil }
                        ?? ids.last
                    guard let target else { return }
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(100))
                        withAnimation {
                            proxy.scrollTo(
                                target,
                                anchor: target == model.focusedMessageID ? .center : .bottom
                            )
                        }
                    }
                }
            }

            Divider()
            VStack(spacing: 8) {
                if let editing = model.editingMessage {
                    ComposerContextBanner(
                        title: "Editing message",
                        preview: editing.body.plainText,
                        systemImage: "pencil",
                        close: model.cancelComposerContext
                    )
                } else if let reply = model.replyingTo {
                    ComposerContextBanner(
                        title: "Replying",
                        preview: reply.body.plainText,
                        systemImage: "arrowshape.turn.up.left",
                        close: model.cancelComposerContext
                    )
                }

                if model.pendingImageAttachment != nil {
                    HStack {
                        Label("Image attached", systemImage: "photo")
                            .font(.caption)
                        Spacer()
                        Button("Remove", systemImage: "xmark.circle", action: model.removePendingImage)
                            .labelStyle(.iconOnly)
                    }
                    .padding(.horizontal, 8)
                }

                HStack(alignment: .bottom, spacing: 10) {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Image(systemName: "photo")
                            .frame(width: 34, height: 42)
                    }
                    .disabled(model.editingMessage != nil || model.isUploadingAttachment)
                    .accessibilityLabel("Attach image")

                    Button("Mention someone", systemImage: "at") {
                        showMentionPicker = true
                    }
                    .labelStyle(.iconOnly)
                    .frame(width: 30, height: 42)

                    TextField(context.composerPrompt, text: $model.draftMessage, axis: .vertical)
                        .lineLimit(1...5)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
                        .submitLabel(.send)
                        .onSubmit { Task { await send() } }
                    Button { Task { await send() } } label: {
                        Image(systemName: model.editingMessage == nil ? "arrow.up" : "checkmark")
                            .fontWeight(.bold)
                            .frame(width: 42, height: 42)
                            .foregroundStyle(.white)
                            .background(AppTheme.accent, in: Circle())
                    }
                    .disabled(
                        model.isUploadingAttachment
                            || (model.draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                && model.pendingImageAttachment == nil)
                    )
                    .accessibilityLabel(model.editingMessage == nil ? "Send message" : "Save edit")
                }
            }
            .frame(maxWidth: 760)
            .padding(12)
            .frame(maxWidth: .infinity)
        }
    }

    private func load() async {
        switch context {
        case .channel(let channel):
            await model.loadMessages(channel: channel, focusing: model.focusedMessageID)
        case .chat(let chat):
            await model.loadMessages(chat: chat, focusing: model.focusedMessageID)
        }
    }

    private func send() async {
        switch context {
        case .channel(let channel): await model.sendMessage(channel: channel)
        case .chat(let chat): await model.sendMessage(chat: chat)
        }
    }
}

private struct ConversationParticipantsView: View {
    @EnvironmentObject private var model: AppModel
    let context: ConversationContext
    @ObservedObject var store: SyncStore
    let isVisible: Bool
    let select: (UserProfile) -> Void
    let close: () -> Void
    @State private var query = ""

    private struct Participant: Identifiable {
        let id: String
        let user: UserProfile?
        let isOnline: Bool
        let role: String
    }

    private var participants: [Participant] {
        switch context {
        case .channel(let channel):
            guard let members = model.channelMembers[channel.channelId] else { return [] }
            let onlineIDs = Set(members.online.map(\.userId))
            return members.all.map { entry in
                Participant(
                    id: entry.userId,
                    user: store.users[entry.userId],
                    isOnline: onlineIDs.contains(entry.userId)
                        || (entry.userId == store.ownUser?.id && model.realtimeNotice == nil),
                    role: role(for: entry.userId, in: members)
                )
            }
        case .chat(let chat):
            return chat.userIds.map { userID in
                let user = store.users[userID]
                let status = user?.onlineStatus ?? "offline"
                return Participant(
                    id: userID,
                    user: user,
                    isOnline: userID == store.ownUser?.id
                        ? model.realtimeNotice == nil
                        : status != "offline" && status != "invisible",
                    role: userID == store.ownUser?.id ? "You" : "Participant"
                )
            }
        }
    }

    private var filtered: [Participant] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return participants }
        return participants.filter {
            ($0.user?.displayName ?? "").localizedCaseInsensitiveContains(trimmed)
        }
    }

    private var online: [Participant] {
        filtered.filter(\.isOnline).sorted(by: participantSort)
    }

    private var other: [Participant] {
        filtered.filter { !$0.isOnline }.sorted(by: participantSort)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(contextParticipantTitle).font(.headline)
                        Text("\(participants.count) participants · \(participants.filter(\.isOnline).count) online")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Close participants", systemImage: "xmark") { close() }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.circle)
                }

                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Find a member", text: $query)
                        .textInputAutocapitalization(.never)
                    if !query.isEmpty {
                        Button("Clear search", systemImage: "xmark.circle.fill") { query = "" }
                            .labelStyle(.iconOnly)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 13))
            }
            .padding(16)
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .padding([.horizontal, .top], 10)
            .padding(.bottom, 4)

            List {
                if !online.isEmpty {
                    Section("Online now · \(online.count)") {
                        ForEach(online) { participantRow($0) }
                    }
                }
                Section(other.isEmpty ? "All members" : "Other members · \(other.count)") {
                    if filtered.isEmpty {
                        ContentUnavailableView.search(text: query)
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(other) { participantRow($0) }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .refreshable { await refresh() }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .overlay(alignment: .leading) { Divider() }
        .task(id: isVisible) {
            guard isVisible else { return }
            while !Task.isCancelled {
                await refresh()
                do {
                    try await Task.sleep(for: .seconds(20))
                } catch {
                    return
                }
            }
        }
    }

    @ViewBuilder
    private func participantRow(_ participant: Participant) -> some View {
        Button {
            if let user = participant.user { select(user) }
        } label: {
            HStack(spacing: 11) {
                Avatar(
                    name: participant.user?.displayName ?? "Member",
                    url: participant.user?.imageID.flatMap { model.attachmentURLs[$0] },
                    isBot: participant.user?.isBot == true,
                    small: true
                )
                .overlay(alignment: .bottomTrailing) {
                    Circle()
                        .fill(participant.isOnline ? Color.green : Color.secondary.opacity(0.45))
                        .frame(width: 11, height: 11)
                        .overlay(Circle().stroke(.background, lineWidth: 2))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(participant.user?.displayName ?? "Loading member…")
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    Text(participant.isOnline ? "Online · \(participant.role)" : participant.role)
                        .font(.caption)
                        .foregroundStyle(participant.isOnline ? Color.green : Color.secondary)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(participant.user == nil)
    }

    private var contextParticipantTitle: String {
        switch context {
        case .channel: "Channel members"
        case .chat: "Conversation"
        }
    }

    private func role(for userID: String, in members: ChannelMemberList) -> String {
        if members.admin.contains(where: { $0.userId == userID }) { return "Admin" }
        if members.moderator.contains(where: { $0.userId == userID }) { return "Moderator" }
        if members.writer.contains(where: { $0.userId == userID }) { return "Writer" }
        return "Member"
    }

    private func participantSort(_ lhs: Participant, _ rhs: Participant) -> Bool {
        (lhs.user?.displayName ?? lhs.id).localizedCaseInsensitiveCompare(
            rhs.user?.displayName ?? rhs.id
        ) == .orderedAscending
    }

    private func refresh() async {
        switch context {
        case .channel(let channel): await model.loadChannelMembers(channel: channel)
        case .chat(let chat): await model.loadChatMembers(chat: chat)
        }
    }
}

private struct MentionPicker: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: SyncStore
    let select: (UserProfile) -> Void
    @State private var query = ""

    private var users: [UserProfile] {
        model.userSearchResultIDs.compactMap { store.users[$0] }
    }

    var body: some View {
        NavigationStack {
            Group {
                if query.isEmpty {
                    ContentUnavailableView(
                        "Mention someone",
                        systemImage: "at",
                        description: Text("Search this instance by display name.")
                    )
                } else if users.isEmpty && !model.isSearchingUsers {
                    ContentUnavailableView.search(text: query)
                } else {
                    List(users) { user in
                        Button { select(user) } label: {
                            HStack(spacing: 12) {
                                Avatar(name: user.displayName, isBot: user.isBot, small: true)
                                Text(user.displayName).fontWeight(.semibold)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .overlay { if model.isSearchingUsers { ProgressView() } }
                }
            }
            .navigationTitle("Mention")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Display name")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task(id: query) {
                do {
                    try await Task.sleep(for: .milliseconds(300))
                    await model.searchUsers(query: query)
                } catch {
                    // A newer query superseded this one.
                }
            }
        }
    }
}

private struct ComposerContextBanner: View {
    let title: String
    let preview: String
    let systemImage: String
    let close: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage).foregroundStyle(AppTheme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption.bold())
                Text(preview).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button("Cancel", systemImage: "xmark.circle.fill", action: close)
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
    }
}

private struct MessageRow: View {
    let message: Message
    let isOwn: Bool
    let author: UserProfile?
    let avatarURL: URL?
    let parent: Message?
    let attachmentURL: URL?
    let openProfile: () -> Void
    let reply: () -> Void
    let edit: () -> Void
    let delete: () -> Void
    let react: (String?) -> Void
    let report: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Button(action: openProfile) {
                Avatar(
                    name: author?.displayName ?? (isOwn ? "You" : "Member"),
                    url: avatarURL,
                    isBot: author?.isBot == true,
                    small: true
                )
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Button(action: openProfile) {
                        Text(author?.displayName ?? (isOwn ? "You" : "Member"))
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    if author?.isBot == true {
                        Label("Bot", systemImage: "cpu")
                            .font(.caption2.bold())
                            .foregroundStyle(AppTheme.accent)
                    }
                    Text(relativeDate(message.createdAt))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    if message.editedAt != nil {
                        Text("edited").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                if let parent {
                    HStack(spacing: 6) {
                        Rectangle().fill(AppTheme.accent).frame(width: 2)
                        Text(parent.body.plainText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .padding(.vertical, 2)
                } else if message.parentMessageId != nil {
                    Label("Earlier message", systemImage: "arrowshape.turn.up.left")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(message.body.plainText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let attachmentURL {
                    AsyncImage(url: attachmentURL) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFit()
                        case .failure:
                            ContentUnavailableView("Image unavailable", systemImage: "photo.badge.exclamationmark")
                        default:
                            ProgressView()
                        }
                    }
                    .frame(maxWidth: 420, minHeight: 100, maxHeight: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                if !message.reactions.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(message.reactions.keys.sorted(), id: \.self) { reaction in
                            Button {
                                react(message.ownReaction == reaction ? nil : reaction)
                            } label: {
                                Text("\(reaction) \(message.reactions[reaction] ?? 0)")
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        message.ownReaction == reaction ? AppTheme.accent.opacity(0.2) : Color.secondary.opacity(0.1),
                                        in: Capsule()
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .contextMenu {
            Button("Reply", systemImage: "arrowshape.turn.up.left", action: reply)
            Menu("React", systemImage: "face.smiling") {
                ForEach(["👍", "❤️", "😂", "🎉", "👀"], id: \.self) { emoji in
                    Button(emoji) { react(message.ownReaction == emoji ? nil : emoji) }
                }
            }
            if isOwn {
                Button("Edit", systemImage: "pencil", action: edit)
                Button("Delete", systemImage: "trash", role: .destructive, action: delete)
            }
            if !isOwn {
                Button("Report message", systemImage: "exclamationmark.bubble", role: .destructive) {
                    report()
                }
            }
        }
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
    @State private var showProfile = false
    @State private var showEditor = false

    private var ownProfile: UserProfile? {
        guard let id = store.ownUser?.id else { return nil }
        return store.users[id]
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        Avatar(
                            name: ownProfile?.displayName ?? store.ownUser?.displayName ?? "CG",
                            url: ownProfile?.imageID.flatMap { model.attachmentURLs[$0] }
                        )
                            .scaleEffect(1.25)
                            .padding(8)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(ownProfile?.displayName ?? store.ownUser?.displayName ?? "Member")
                                .font(.title3.bold())
                            Text(store.ownUser?.email ?? model.instanceHost)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Profile") {
                    Button("View my public profile", systemImage: "person.crop.circle") {
                        showProfile = true
                    }
                    Button("Edit account and profile", systemImage: "pencil") {
                        showEditor = true
                    }
                }

                Section("Appearance") {
                    Picker("Color scheme", selection: $model.appearance) {
                        ForEach(AppearancePreference.allCases) { preference in
                            Text(preference.title).tag(preference)
                        }
                    }
                    .pickerStyle(.segmented)
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
            .sheet(isPresented: $showProfile) {
                if let id = store.ownUser?.id {
                    UserProfileView(userID: id, store: store) { _ in }
                }
            }
            .sheet(isPresented: $showEditor) {
                AccountEditorView(store: store)
            }
        }
    }
}

private struct AccountEditorView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: SyncStore
    @State private var displayName = ""
    @State private var bio = ""
    @State private var homepage = ""
    @State private var email = ""
    @State private var dmNotifications = true
    @State private var newPassword = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isUploadingAvatar = false
    @State private var isSaving = false

    private var ownID: String? { store.ownUser?.id }
    private var ownProfile: UserProfile? { ownID.flatMap { store.users[$0] } }
    private var cgDetails: [String: JSONValue] {
        guard let ownID else { return [:] }
        return model.profileDetails[ownID]?
            .detailledProfiles
            .first(where: { $0.type == "cg" })?
            .extraData?
            .objectValue ?? [:]
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Photo") {
                    HStack(spacing: 16) {
                        Avatar(
                            name: ownProfile?.displayName ?? displayName,
                            url: ownProfile?.imageID.flatMap { model.attachmentURLs[$0] }
                        )
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            Label("Choose profile photo", systemImage: "photo")
                        }
                        .disabled(isUploadingAvatar)
                        if isUploadingAvatar { ProgressView() }
                    }
                }
                Section("Public profile") {
                    TextField("Display name", text: $displayName)
                    TextField("Bio", text: $bio, axis: .vertical).lineLimit(3...8)
                    TextField("Homepage", text: $homepage)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                }
                Section("Account") {
                    TextField("Email", text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                    Toggle("Direct-message notifications", isOn: $dmNotifications)
                    SecureField("New password (optional)", text: $newPassword)
                        .textContentType(.newPassword)
                }
            }
            .navigationTitle("Edit Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        isSaving = true
                        Task {
                            if await model.updateAccount(
                                displayName: displayName,
                                description: bio,
                                homepage: homepage,
                                email: email,
                                dmNotifications: dmNotifications,
                                newPassword: newPassword
                            ) {
                                dismiss()
                            }
                            isSaving = false
                        }
                    }
                    .disabled(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
            .overlay { if isSaving { ProgressView() } }
            .onChange(of: selectedPhoto) { _, item in
                guard let item else { return }
                isUploadingAvatar = true
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        _ = await model.uploadProfileImage(data)
                    } else {
                        model.errorMessage = "That image could not be loaded from the photo library."
                    }
                    isUploadingAvatar = false
                    selectedPhoto = nil
                }
            }
            .task {
                guard let ownID else { return }
                await model.loadUserProfile(userID: ownID)
                displayName = ownProfile?.displayName ?? store.ownUser?.displayName ?? ""
                bio = cgDetails["description"]?.stringValue ?? ""
                homepage = cgDetails["homepage"]?.stringValue ?? ""
                email = store.ownUser?.email ?? ""
                dmNotifications = store.ownUser?.dmNotifications ?? true
            }
        }
    }
}

private struct ArticleComposer: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let owner: ArticleOwner
    let article: ArticleDetail?
    let didSave: () -> Void
    @State private var title: String
    @State private var preview: String
    @State private var bodyText: String
    @State private var tags: String
    @State private var publish: Bool
    @State private var isSaving = false

    init(
        owner: ArticleOwner,
        article: ArticleDetail? = nil,
        isDraft: Bool = false,
        didSave: @escaping () -> Void
    ) {
        self.owner = owner
        self.article = article
        self.didSave = didSave
        _title = State(initialValue: article?.title ?? "")
        _preview = State(initialValue: article?.previewText ?? "")
        _bodyText = State(initialValue: article?.markdownSource ?? "")
        _tags = State(initialValue: article?.tags.joined(separator: ", ") ?? "")
        _publish = State(initialValue: !isDraft)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Article") {
                    TextField("Title", text: $title)
                    TextField("Short preview", text: $preview, axis: .vertical)
                        .onChange(of: preview) { _, value in
                            if value.count > 150 { preview = String(value.prefix(150)) }
                        }
                    Text("\(preview.count)/150")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    TextField("Write Markdown…", text: $bodyText, axis: .vertical)
                        .lineLimit(8...20)
                }
                Section("Tags") {
                    TextField("Comma-separated tags", text: $tags)
                        .textInputAutocapitalization(.never)
                }
                Section("Publication") {
                    Picker("Status", selection: $publish) {
                        Text("Draft").tag(false)
                        Text("Published").tag(true)
                    }
                    .pickerStyle(.segmented)
                    Text(
                        publish
                            ? "The article will be visible to its audience immediately."
                            : "Only you and authorized community editors can see drafts."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                Section {
                    Label(
                        "Markdown is supported. Rich media blocks can be added later without changing the article API.",
                        systemImage: "info.circle"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(article == nil ? "New Article" : "Edit Article")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(article == nil ? (publish ? "Publish" : "Save Draft") : "Save") { save() }
                    .disabled(
                        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || isSaving
                    )
                }
            }
            .overlay { if isSaving { ProgressView() } }
        }
    }

    private func save() {
        isSaving = true
        Task {
            let parsedTags = tags.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let saved: Bool
            if let article {
                saved = await model.updateArticle(
                    owner: owner,
                    articleID: article.articleId,
                    title: title,
                    preview: preview,
                    text: bodyText,
                    tags: parsedTags,
                    publish: publish
                )
            } else {
                switch owner {
                case .user:
                    saved = await model.createUserArticle(
                        title: title,
                        preview: preview,
                        text: bodyText,
                        tags: parsedTags,
                        publish: publish
                    ) != nil
                case .community(let communityID):
                    guard let community = model.store.communities[communityID] else {
                        isSaving = false
                        return
                    }
                    saved = await model.createCommunityArticle(
                        community: community,
                        title: title,
                        preview: preview,
                        text: bodyText,
                        tags: parsedTags,
                        publish: publish
                    ) != nil
                }
            }
            isSaving = false
            if saved {
                didSave()
                dismiss()
            }
        }
    }
}

private struct Avatar: View {
    let name: String
    var url: URL? = nil
    var isBot = false
    var small = false

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    initials
                }
            } else {
                initials
            }
        }
            .frame(width: small ? 34 : 42, height: small ? 34 : 42)
            .clipShape(Circle())
            .accessibilityHidden(true)
    }

    private var initials: some View {
        Group {
            if isBot {
                Image(systemName: "cpu")
                    .font(small ? .caption.bold() : .subheadline.bold())
            } else {
                Text(String(name.prefix(2)).uppercased())
                    .font(small ? .caption.bold() : .subheadline.bold())
            }
        }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(.black)
            .background(
                LinearGradient(
                    colors: [AppTheme.accent, AppTheme.secondaryAccent],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }
}

private struct CommunityMark: View {
    let name: String
    var url: URL? = nil

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    fallback
                }
            } else {
                fallback
            }
        }
            .frame(width: 30, height: 30)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityHidden(true)
    }

    private var fallback: some View {
        Text(String(name.prefix(1)).uppercased())
            .font(.caption.bold())
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(.white)
            .background(AppTheme.accent.gradient)
    }
}

private struct CommunityFeatureImage: View {
    let url: URL
    let height: CGFloat

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            case .empty:
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.secondary.opacity(0.08))
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
            case .failure:
                EmptyView()
            @unknown default:
                EmptyView()
            }
        }
        .accessibilityLabel("Community image")
    }
}

private struct MarkdownArticleText: View {
    let source: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(MarkdownArticleBlock.parse(source)) { block in
                switch block.kind {
                case .paragraph:
                    inlineText(block.text)
                case .heading(let level):
                    inlineText(block.text)
                        .font(headerFont(level))
                        .padding(.top, level <= 2 ? 8 : 3)
                case .unordered:
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Text("•").fontWeight(.bold)
                        inlineText(block.text)
                    }
                    .padding(.leading, 8)
                case .ordered(let marker):
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Text("\(marker).").fontWeight(.semibold).monospacedDigit()
                        inlineText(block.text)
                    }
                    .padding(.leading, 8)
                case .quote:
                    HStack(alignment: .top, spacing: 10) {
                        Capsule().fill(AppTheme.accent.opacity(0.7)).frame(width: 3)
                        inlineText(block.text).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 3)
                case .code:
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(block.text)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(12)
                    }
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                case .divider:
                    Divider().padding(.vertical, 5)
                case .spacer:
                    Color.clear.frame(height: 5)
                }
            }
        }
        .font(.body)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inlineText(_ text: String) -> Text {
        if let rendered = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(rendered)
        }
        return Text(text)
    }

    private func headerFont(_ level: Int) -> Font {
        switch level {
        case 1: .largeTitle.bold()
        case 2: .title.bold()
        case 3: .title2.bold()
        default: .headline
        }
    }

}

private extension Chat {
    func displayTitle(excluding ownUserID: String?) -> String {
        let others = userIds.filter { $0 != ownUserID }
        guard !others.isEmpty else { return "Direct message" }
        return others.map { "Member \($0.prefix(4))" }.joined(separator: ", ")
    }
}
