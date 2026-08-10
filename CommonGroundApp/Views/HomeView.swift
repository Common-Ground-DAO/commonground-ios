import CommonGroundKit
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct HomeView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HomeContent(store: model.store)
    }
}

private enum SidebarItem: Hashable {
    case overview
    case events
    case directMessages
    case notifications
    case search
    case feed
    case discoverCommunities
    case appStore
    case publicCommunity(String)
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

private struct EventRoute: Identifiable {
    let event: CommunityEvent
    let community: Community
    var id: String { event.id }
}

private struct HomeContent: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var store: SyncStore
    @State private var sidebarSelection: SidebarItem? = .overview
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar
    @State private var showAccount = false
    @State private var showCreateCommunity = false
    @State private var publicCommunity: Community?
    @State private var publicChannelID: String?
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
                model.selectChannel(nil)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .commonGroundPluginNavigate)) { notification in
            guard let path = notification.object as? String else { return }
            openPluginDestination(path)
        }
    }

    private var sidebar: some View {
        List(selection: $sidebarSelection) {
            Section {
                sidebarRow("Overview", systemImage: "square.grid.2x2", item: .overview)
                sidebarRow("Events", systemImage: "calendar", item: .events)
                sidebarRow("Messages", systemImage: "bubble.left.and.bubble.right", item: .directMessages)
                sidebarRow(
                    "Notifications",
                    systemImage: "bell",
                    item: .notifications,
                    badge: store.unreadNotificationCount
                )
                sidebarRow("Search", systemImage: "magnifyingglass", item: .search)
                sidebarRow("Feed", systemImage: "rectangle.stack", item: .feed)
                sidebarRow("Discover Communities", systemImage: "safari", item: .discoverCommunities)
                sidebarRow("App Store", systemImage: "storefront", item: .appStore)
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
                browseCommunities: { sidebarSelection = .discoverCommunities },
                createCommunity: { showCreateCommunity = true }
            )
        case .events:
            EventsView(store: store)
        case .directMessages:
            ChatListView(
                chats: chats,
                store: store,
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
        case .feed:
            FeedView(store: store)
        case .discoverCommunities:
            CommunityDiscoveryView(store: store) { communityID in
                await openDiscoveredCommunity(communityID)
            }
        case .appStore:
            RootAppStoreView(store: store)
        case .publicCommunity(let id):
            if let community = publicCommunity, community.id == id {
                PublicCommunityChannelListView(
                    community: community,
                    selectedChannelID: publicChannelID,
                    openHome: {
                        publicChannelID = nil
                        preferredCompactColumn = .detail
                    },
                    select: {
                        publicChannelID = $0
                        preferredCompactColumn = .detail
                    },
                    didJoin: { finishJoiningPublicCommunity(community.id) }
                )
            } else {
                ProgressView("Opening community…")
            }
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
        case .publicCommunity(let communityID):
            if let community = publicCommunity, community.id == communityID,
               let channel = community.channels.first(where: { $0.channelId == publicChannelID }) {
                ConversationView(
                    context: .channel(channel),
                    store: store,
                    readOnly: !channel.publicCanWrite
                )
            } else if let community = publicCommunity, community.id == communityID {
                CommunityHomeView(community: community, store: store)
            } else {
                ConversationPlaceholder(
                    title: "Opening community",
                    message: "Loading the public community experience.",
                    systemImage: "safari"
                )
            }
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
        case .events:
            ConversationPlaceholder(
                title: "Events",
                message: "Discover upcoming events or review the ones you are attending.",
                systemImage: "calendar"
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
        case .feed:
            ConversationPlaceholder(
                title: "Your Feed",
                message: "Read the latest posts from communities across this instance.",
                systemImage: "rectangle.stack"
            )
        case .discoverCommunities:
            ConversationPlaceholder(
                title: "Discover Communities",
                message: "Search and filter public communities in the middle column.",
                systemImage: "safari"
            )
        case .appStore:
            ConversationPlaceholder(
                title: "Common Ground apps",
                message: "Browse apps in the middle column and install them in communities you administer.",
                systemImage: "storefront"
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

    @MainActor
    private func openDiscoveredCommunity(_ id: String) async {
        if store.communities[id] != nil {
            openCommunity(id)
            return
        }
        guard let community = await model.feedCommunityDetail(id: id) else { return }
        publicCommunity = community
        publicChannelID = nil
        sidebarSelection = .publicCommunity(id)
        preferredCompactColumn = .content
    }

    private func finishJoiningPublicCommunity(_ id: String) {
        guard store.communities[id] != nil else { return }
        let channelID = publicChannelID
        publicCommunity = nil
        publicChannelID = nil
        model.selectCommunity(id)
        model.selectChannel(channelID)
        sidebarSelection = .community(id)
        preferredCompactColumn = channelID == nil ? .content : .detail
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

    private func openPluginDestination(_ path: String) {
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count >= 2, parts[0] == "c",
              let community = store.communities.values.first(where: { $0.url == parts[1] }) else {
            return
        }
        if parts.count >= 4, parts[2] == "channel",
           let channel = community.channels.first(where: { $0.url == parts[3] }) {
            openChannel(channel.channelId, communityID: community.id)
        } else {
            openCommunity(community.id)
            preferredCompactColumn = .detail
        }
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

private enum EventsContentMode: String, CaseIterable, Identifiable {
    case discover
    case attending

    var id: String { rawValue }
    var title: String {
        switch self {
        case .discover: "Upcoming"
        case .attending: "Attending"
        }
    }
}

private struct EventsQuery: Hashable {
    let mode: EventsContentMode
    let scope: CommunityFeedScope
    let topics: [String]
}

private struct EventsView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var store: SyncStore
    @State private var route: EventRoute?
    @State private var mode: EventsContentMode = .discover
    @State private var scope: CommunityFeedScope = .explore
    @State private var topics: Set<String> = []
    @State private var showTopicPicker = false
    @State private var loadingEventID: String?

    private var query: EventsQuery {
        EventsQuery(
            mode: mode,
            scope: scope,
            topics: topics.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        )
    }

    private var upcoming: [CommunityEvent] {
        model.myEvents.filter {
            guard let date = parseEventDate($0.scheduleDate) else { return true }
            return date.addingTimeInterval(TimeInterval($0.duration * 60)) >= Date()
        }
    }

    private var past: [CommunityEvent] {
        Array(model.myEvents.filter {
            guard let date = parseEventDate($0.scheduleDate) else { return false }
            return date.addingTimeInterval(TimeInterval($0.duration * 60)) < Date()
        }.reversed())
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                Text("Discover what is happening across this Common Ground instance.")
                    .foregroundStyle(.secondary)

                Picker("Events", selection: $mode) {
                    ForEach(EventsContentMode.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)

                if mode == .discover {
                    SelectedTopicChips(topics: $topics)
                    discoverContent
                } else {
                    attendingContent
                }
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(20)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Events")
        .toolbar {
            if mode == .discover {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker("Scope", selection: $scope) {
                            ForEach(CommunityFeedScope.allCases, id: \.self) { option in
                                Text(option.feedTitle).tag(option)
                            }
                        }
                        Button("Choose topics", systemImage: "number") {
                            showTopicPicker = true
                        }
                    } label: {
                        Label(
                            "Filters",
                            systemImage: topics.isEmpty && scope == .explore
                                ? "line.3.horizontal.decrease.circle"
                                : "line.3.horizontal.decrease.circle.fill"
                        )
                    }
                }
            }
        }
        .refreshable { await refresh() }
        .task(id: query) { await refresh() }
        .sheet(item: $route) { route in
            CommunityEventDetailView(community: route.community, event: route.event)
        }
        .sheet(isPresented: $showTopicPicker) {
            FeedTopicPicker(
                availableTopics: model.feedTopicOptions,
                initialSelection: topics
            ) { topics = $0 }
        }
    }

    @ViewBuilder
    private var discoverContent: some View {
        if model.feedEvents.isEmpty, model.isLoadingFeedEvents {
            ProgressView("Loading events…")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
        } else if model.feedEvents.isEmpty {
            ContentUnavailableView(
                "No upcoming events",
                systemImage: "calendar",
                description: Text("Try another scope or topic filter.")
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 60)
        } else {
            ForEach(model.feedEvents) { event in eventRow(event) }
            feedEventFooter
        }
    }

    @ViewBuilder
    private var attendingContent: some View {
        if model.myEvents.isEmpty, model.isLoadingMyEvents {
            ProgressView("Loading events…")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
        } else if model.myEvents.isEmpty {
            ContentUnavailableView(
                "No events yet",
                systemImage: "calendar.badge.plus",
                description: Text("Attend an event from a community home and it will appear here.")
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 60)
        } else {
            eventSection("Upcoming", events: upcoming)
            eventSection("Past", events: past)
            if model.canLoadMoreMyEvents {
                FeedLoadMoreFooter(
                    isLoading: model.isLoadingMyEvents,
                    title: "Load more events",
                    load: model.loadMoreMyEvents
                )
                .id(model.myEvents.count)
            }
        }
    }

    @ViewBuilder
    private func eventSection(_ title: String, events: [CommunityEvent]) -> some View {
        if !events.isEmpty {
            Text(title)
                .font(.title3.bold())
                .padding(.top, 12)
            ForEach(events) { event in
                eventRow(event)
            }
        }
    }

    private func eventRow(_ event: CommunityEvent) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                FeedCommunityLabel(
                    community: model.feedCommunitySummaries[event.communityId],
                    date: nil,
                    fallbackName: store.communities[event.communityId]?.title,
                    fallbackLogoSmallID: store.communities[event.communityId]?.logoSmallId
                )
                Spacer()
                if loadingEventID == event.id { ProgressView().controlSize(.small) }
            }
            CommunityEventCard(
                event: event,
                imageURL: event.imageId.flatMap { model.attachmentURLs[$0] }
            ) { openEvent(event) }
            .disabled(loadingEventID != nil)
            .accessibilityIdentifier("events.event.\(event.id)")
        }
    }

    @ViewBuilder
    private var feedEventFooter: some View {
        if model.canLoadMoreFeedEvents {
            FeedLoadMoreFooter(
                isLoading: model.isLoadingFeedEvents,
                title: "Load more events",
                load: model.loadMoreFeedEvents
            )
            .id(model.feedEvents.count)
        }
    }

    private func refresh() async {
        switch mode {
        case .discover:
            await model.loadEventFeed(scope: scope, topics: topics)
        case .attending:
            await model.loadMyEvents()
        }
    }

    private func openEvent(_ event: CommunityEvent) {
        guard loadingEventID == nil else { return }
        if let community = store.communities[event.communityId] {
            route = EventRoute(event: event, community: community)
            return
        }
        loadingEventID = event.id
        Task {
            if let community = await model.feedCommunityDetail(id: event.communityId) {
                route = EventRoute(event: event, community: community)
            }
            loadingEventID = nil
        }
    }
}

private struct FeedQuery: Hashable {
    let scope: PostFeedScope
    let actorTypes: [FeedPostKind]
    let topics: [String]
    let verification: FeedVerification
}

private extension CommunityFeedScope {
    var feedTitle: String {
        switch self {
        case .explore: "Explore"
        case .myCommunities: "My communities"
        }
    }
}

private extension PostFeedScope {
    var feedTitle: String {
        switch self {
        case .explore: "Explore"
        case .following: "Following"
        }
    }
}

private extension FeedVerification {
    var title: String {
        switch self {
        case .both: "All communities"
        case .verified: "Verified communities"
        case .unverified: "Unverified communities"
        }
    }
}

private struct FeedView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var store: SyncStore
    @State private var scope: PostFeedScope = .explore
    @State private var actorTypes = Set(FeedPostKind.allCases)
    @State private var topics: Set<String> = []
    @State private var verification: FeedVerification = .both
    @State private var showTopicPicker = false
    @State private var showPostComposer = false
    @State private var selectedPost: FeedPost?
    @State private var selectedProfile: NotificationProfileRoute?
    @State private var selectedCommunity: Community?
    @State private var isLoadingCommunity = false

    private var query: FeedQuery {
        FeedQuery(
            scope: scope,
            actorTypes: actorTypes.sorted { $0.rawValue < $1.rawValue },
            topics: topics.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending },
            verification: verification
        )
    }

    private var isInitiallyLoading: Bool {
        model.feedPosts.isEmpty && model.isLoadingFeedPosts
    }

    private var publishingCommunities: [Community] {
        store.communities.values
            .filter(\.canManageArticles)
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                if let ownUser = store.ownUser {
                    FeedPostComposerPrompt(
                        name: ownUser.displayName,
                        imageURL: ownUserImageID.flatMap { model.attachmentURLs[$0] }
                    ) {
                        showPostComposer = true
                    }
                }
                if isInitiallyLoading {
                    ProgressView("Loading Feed…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 70)
                } else if model.feedPosts.isEmpty {
                    ContentUnavailableView(
                        "Nothing in this Feed yet",
                        systemImage: "rectangle.stack",
                        description: Text(emptyDescription)
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 50)
                } else {
                    postContent
                }
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Feed")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Scope", selection: $scope) {
                        ForEach(PostFeedScope.allCases, id: \.self) { option in
                            Text(option.feedTitle).tag(option)
                        }
                    }

                    Menu("Post authors") {
                        Toggle(
                            "People",
                            isOn: actorTypeBinding(.user)
                        )
                        Toggle(
                            "Communities",
                            isOn: actorTypeBinding(.community)
                        )
                    }

                    Picker("Community verification", selection: $verification) {
                        ForEach(FeedVerification.allCases, id: \.self) { option in
                            Text(option.title).tag(option)
                        }
                    }

                    Button {
                        showTopicPicker = true
                    } label: {
                        Label(
                            topics.isEmpty ? "Choose topics" : "Topics (\(topics.count))",
                            systemImage: "number"
                        )
                    }
                } label: {
                    Label(
                        "Filters",
                        systemImage: filtersAreDefault
                            ? "line.3.horizontal.decrease.circle"
                            : "line.3.horizontal.decrease.circle.fill"
                    )
                }
            }
        }
        .refreshable { await load() }
        .task(id: query) { await load() }
        .sheet(isPresented: $showTopicPicker) {
            FeedTopicPicker(
                availableTopics: model.feedTopicOptions,
                initialSelection: topics,
                footer: "Selecting several topics matches posts tagged with any of them."
            ) { topics = $0 }
        }
        .sheet(isPresented: $showPostComposer) {
            FeedPostComposer(
                store: store,
                communities: publishingCommunities
            ) {
                showPostComposer = false
                Task { await load() }
            }
        }
        .navigationDestination(isPresented: postDestinationIsPresented) {
            if let post = selectedPost {
                ArticleReaderView(
                    articleID: post.id,
                    source: post.kind == .community ? .community(post.actor.id) : .user(post.actor.id),
                    store: store,
                    focusedCommentID: nil,
                    presentation: .pushedPost,
                    feedPost: post
                )
            }
        }
        .sheet(item: $selectedProfile) { route in
            UserProfileView(userID: route.id, store: store) { _ in }
        }
        .sheet(item: $selectedCommunity) { community in
            NavigationStack {
                CommunityHomeView(community: community, store: store)
            }
        }
        .overlay {
            if isLoadingCommunity {
                ProgressView()
                    .padding(18)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private var emptyDescription: String {
        if !topics.isEmpty {
            return "Try removing a topic or changing the Feed filters."
        }
        return scope == .following
            ? "Follow people, join communities, or switch to Explore to find more posts."
            : "Published posts from people and communities will appear here."
    }

    private var postDestinationIsPresented: Binding<Bool> {
        Binding(
            get: { selectedPost != nil },
            set: { if !$0 { selectedPost = nil } }
        )
    }

    private var ownUserImageID: String? {
        guard let ownUser = store.ownUser else { return nil }
        return ownUser.accounts.first(where: { $0.type == ownUser.displayAccount })?.imageId
            ?? ownUser.accounts.first?.imageId
    }

    @ViewBuilder
    private var postContent: some View {
        if model.feedPosts.isEmpty {
            ContentUnavailableView(
                "No matching posts",
                systemImage: "rectangle.stack",
                description: Text("Try another scope or topic filter.")
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 50)
        } else {
            ForEach(model.feedPosts) { post in
                FeedPostCard(
                    post: post,
                    actorImageURL: model.feedActorImageURL(for: post),
                    mediaURL: mediaURL,
                    openPost: { selectedPost = post },
                    openActor: { openActor(post) }
                )
            }
            feedPostFooter
        }
    }

    private var filtersAreDefault: Bool {
        topics.isEmpty
            && actorTypes == Set(FeedPostKind.allCases)
            && verification == .both
    }

    @ViewBuilder
    private var feedPostFooter: some View {
        if model.canLoadMoreFeedPosts {
            FeedLoadMoreFooter(
                isLoading: model.isLoadingFeedPosts,
                title: "Load more posts"
            ) {
                await model.loadMoreFeedPosts()
            }
            .id(model.feedPosts.count)
        }
    }

    private func actorTypeBinding(_ kind: FeedPostKind) -> Binding<Bool> {
        Binding(
            get: { actorTypes.contains(kind) },
            set: { selected in
                if selected {
                    actorTypes.insert(kind)
                } else if actorTypes.count > 1 {
                    actorTypes.remove(kind)
                }
            }
        )
    }

    private func load() async {
        await model.loadPostFeed(
            scope: scope,
            actorTypes: actorTypes,
            topics: topics,
            verification: verification
        )
    }

    private func mediaURL(_ media: FeedPostMedia) -> URL? {
        if let large = media.largeObjectId, let url = model.attachmentURLs[large] { return url }
        if media.type == .video,
           let poster = media.posterImageId,
           let url = model.attachmentURLs[poster] { return url }
        return model.attachmentURLs[media.objectId]
    }

    private func openActor(_ post: FeedPost) {
        switch post.kind {
        case .user:
            selectedProfile = NotificationProfileRoute(id: post.actor.id)
        case .community:
            guard !isLoadingCommunity else { return }
            isLoadingCommunity = true
            Task {
                selectedCommunity = await model.feedCommunityDetail(id: post.actor.id)
                isLoadingCommunity = false
            }
        }
    }
}

private enum FeedPostingIdentity: Hashable {
    case user
    case community(String)
}

private struct FeedPostComposerPrompt: View {
    let name: String
    let imageURL: URL?
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                Avatar(name: name, url: imageURL)
                    .frame(width: 44, height: 44)
                Text("Start a post")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        Color(uiColor: .secondarySystemBackground),
                        in: Capsule()
                    )
            }
            .padding(14)
            .background(Color(uiColor: .systemBackground))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("feed.composer.prompt")
    }
}

private struct FeedPostComposer: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: SyncStore
    let communities: [Community]
    let published: () -> Void
    @State private var identity: FeedPostingIdentity = .user
    @State private var bodyText = ""
    @State private var isPublishing = false
    @FocusState private var bodyFocused: Bool

    private var trimmedBody: String {
        bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var selectedCommunity: Community? {
        guard case .community(let id) = identity else { return nil }
        return communities.first { $0.id == id }
    }

    private var ownUserImageID: String? {
        guard let ownUser = store.ownUser else { return nil }
        return ownUser.accounts.first(where: { $0.type == ownUser.displayAccount })?.imageId
            ?? ownUser.accounts.first?.imageId
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Menu {
                    Picker("Post as", selection: $identity) {
                        Text(store.ownUser?.displayName ?? "My profile")
                            .tag(FeedPostingIdentity.user)
                        ForEach(communities) { community in
                            Text(community.title)
                                .tag(FeedPostingIdentity.community(community.id))
                        }
                    }
                } label: {
                    HStack(spacing: 11) {
                        postingMark
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Post as")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(postingName)
                                .font(.headline)
                                .foregroundStyle(.primary)
                        }
                        Spacer()
                        Image(systemName: communities.isEmpty ? "person" : "chevron.up.chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(communities.isEmpty)

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $bodyText)
                        .focused($bodyFocused)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                    if bodyText.isEmpty {
                        Text("What do you want to share?")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }
                .frame(minHeight: 220)

                Label("Markdown formatting is supported.", systemImage: "textformat")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(20)
            .navigationTitle("Create Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isPublishing)
                        .accessibilityIdentifier("feed.composer.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Post") { publish() }
                        .fontWeight(.semibold)
                        .disabled(trimmedBody.isEmpty || isPublishing)
                        .accessibilityIdentifier("feed.composer.publish")
                }
            }
            .overlay {
                if isPublishing {
                    ProgressView()
                        .padding(18)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .interactiveDismissDisabled(isPublishing)
            .task { bodyFocused = true }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private var postingMark: some View {
        if let community = selectedCommunity {
            CommunityMark(
                name: community.title,
                url: community.logoSmallId.flatMap { model.attachmentURLs[$0] },
                size: 44
            )
        } else {
            Avatar(
                name: store.ownUser?.displayName ?? "My profile",
                url: ownUserImageID.flatMap { model.attachmentURLs[$0] }
            )
            .frame(width: 44, height: 44)
        }
    }

    private var postingName: String {
        selectedCommunity?.title ?? store.ownUser?.displayName ?? "My profile"
    }

    private func publish() {
        guard !trimmedBody.isEmpty else { return }
        isPublishing = true
        Task {
            let succeeded: Bool
            switch identity {
            case .user:
                succeeded = await model.createUserArticle(
                    title: "",
                    preview: "",
                    text: trimmedBody,
                    tags: [],
                    publish: true
                ) != nil
            case .community(let communityID):
                guard let community = communities.first(where: { $0.id == communityID }) else {
                    isPublishing = false
                    return
                }
                succeeded = await model.createCommunityArticle(
                    community: community,
                    title: "",
                    preview: "",
                    text: trimmedBody,
                    tags: [],
                    publish: true
                ) != nil
            }
            isPublishing = false
            if succeeded {
                published()
                dismiss()
            }
        }
    }
}

private struct FeedPostCard: View {
    let post: FeedPost
    let actorImageURL: URL?
    let mediaURL: (FeedPostMedia) -> URL?
    let openPost: () -> Void
    let openActor: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                FeedPostHeader(
                    post: post,
                    actorImageURL: actorImageURL,
                    openPost: openPost,
                    openActor: openActor
                )
                if !post.markdownSource.isEmpty {
                    MarkdownArticleText(source: post.markdownSource, headingStyle: .social)
                }
                if post.isTruncated {
                    Button("… more", action: openPost)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            if !post.media.isEmpty {
                FeedPostMediaGrid(media: post.media, url: mediaURL, open: openPost)
            }

            Divider().padding(.horizontal, 16)
            HStack(spacing: 24) {
                Button(action: openPost) {
                    Label("\(post.commentCount)", systemImage: "bubble.left")
                }
                .accessibilityLabel("\(post.commentCount) comments")
                .accessibilityIdentifier("feed.comments.\(post.id)")
                Label("0", systemImage: "arrow.2.squarepath")
                    .accessibilityLabel("0 reposts")
                Label("0", systemImage: "heart")
                    .accessibilityLabel("0 likes")
                Label("0", systemImage: "chart.bar")
                    .accessibilityLabel("0 views")
                Spacer()
                if let value = post.permalink, let url = URL(string: value) {
                    ShareLink(item: url) {
                        Label("Share", systemImage: "paperplane")
                    }
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .systemBackground))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("feed.post.\(post.id)")
    }
}

private struct FeedPostHeader: View {
    let post: FeedPost
    let actorImageURL: URL?
    var openPost: (() -> Void)? = nil
    let openActor: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Button(action: openActor) {
                actorImage
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                Button(action: openActor) {
                    Text(post.actor.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                if let creator = post.creator {
                    Text("Posted by \(creator.displayName)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 5) {
                    if let date = parseEventDate(post.publishedAt) {
                        Text(date.formatted(.relative(presentation: .named)))
                    }
                    if post.editedAt != nil { Text("· Edited") }
                    Text("·")
                    Image(systemName: "globe")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if openPost != nil || post.permalink != nil {
                Menu("Post options", systemImage: "ellipsis") {
                    if let openPost {
                        Button("Open post", systemImage: "arrow.up.right.square", action: openPost)
                    }
                    if let value = post.permalink, let url = URL(string: value) {
                        ShareLink(item: url) { Label("Share post", systemImage: "square.and.arrow.up") }
                    }
                }
                .labelStyle(.iconOnly)
            }
        }
        .accessibilityIdentifier("feed.actor.\(post.kind.rawValue).\(post.actor.id)")
    }

    @ViewBuilder
    private var actorImage: some View {
        if post.kind == .community {
            CommunityMark(name: post.actor.name, url: actorImageURL, size: 48)
        } else {
            Avatar(name: post.actor.name, url: actorImageURL)
                .frame(width: 48, height: 48)
        }
    }
}

private struct FeedPostMediaGrid: View {
    let media: [FeedPostMedia]
    let url: (FeedPostMedia) -> URL?
    let open: () -> Void

    private var visibleMedia: [FeedPostMedia] { Array(media.prefix(4)) }

    var body: some View {
        Button(action: open) {
            Group {
                if visibleMedia.count == 1, let first = visibleMedia.first {
                    mediaCell(first)
                        .aspectRatio(preferredAspectRatio(first), contentMode: .fit)
                } else {
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2)],
                        spacing: 2
                    ) {
                        ForEach(Array(visibleMedia.enumerated()), id: \.element.id) { index, item in
                            mediaCell(item)
                                .aspectRatio(1, contentMode: .fill)
                                .overlay {
                                    if index == 3, media.count > 4 {
                                        Color.black.opacity(0.46)
                                        Text("+\(media.count - 3)")
                                            .font(.title.bold())
                                            .foregroundStyle(.white)
                                    }
                                }
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func mediaCell(_ item: FeedPostMedia) -> some View {
        if let imageURL = url(item) {
            FeedPostImage(url: imageURL)
                .overlay(alignment: .bottomLeading) {
                    if item.type == .video {
                        Label("Video", systemImage: "play.fill")
                            .font(.caption.bold())
                            .padding(8)
                            .foregroundStyle(.white)
                            .background(.black.opacity(0.65), in: Capsule())
                            .padding(10)
                    }
                }
        } else {
            Color.secondary.opacity(0.08)
                .overlay { ProgressView() }
        }
    }

    private func preferredAspectRatio(_ item: FeedPostMedia) -> CGFloat {
        guard let width = item.width, let height = item.height, height > 0 else { return 4 / 3 }
        return min(max(CGFloat(width) / CGFloat(height), 0.65), 1.9)
    }
}

private struct SelectedTopicChips: View {
    @Binding var topics: Set<String>

    var body: some View {
        if !topics.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(topics.sorted(), id: \.self) { topic in
                        Button {
                            topics.remove(topic)
                        } label: {
                            Label(topic, systemImage: "xmark")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                    }
                    Button("Clear") { topics.removeAll() }
                        .font(.caption.weight(.semibold))
                }
            }
        }
    }
}

private struct FeedCommunityLabel: View {
    @EnvironmentObject private var model: AppModel
    let community: CommunitySummary?
    let date: Date?
    var fallbackName: String? = nil
    var fallbackLogoSmallID: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            CommunityMark(
                name: community?.title ?? fallbackName ?? "Community",
                url: (community?.logoSmallId ?? fallbackLogoSmallID).flatMap { model.attachmentURLs[$0] }
            )
            .frame(width: 26, height: 26)
            Text(community?.title ?? fallbackName ?? "Community")
                .font(.caption.weight(.semibold))
            if let date {
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct FeedLoadMoreFooter: View {
    let isLoading: Bool
    let title: String
    let load: () async -> Void

    var body: some View {
        Group {
            if isLoading {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Loading more…").foregroundStyle(.secondary)
                }
            } else {
                Button(title, systemImage: "arrow.down.circle") {
                    Task { await load() }
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .task { await load() }
    }
}

private struct FeedTopicPicker: View {
    @Environment(\.dismiss) private var dismiss
    let availableTopics: [String]
    let apply: (Set<String>) -> Void
    let footer: String
    @State private var selectedTopics: Set<String>
    @State private var search = ""

    init(
        availableTopics: [String],
        initialSelection: Set<String>,
        footer: String = "Selecting several topics matches communities with any of them.",
        apply: @escaping (Set<String>) -> Void
    ) {
        self.availableTopics = availableTopics
        self.apply = apply
        self.footer = footer
        _selectedTopics = State(initialValue: initialSelection)
    }

    private var topics: [String] {
        let all = Array(Set(availableTopics).union(selectedTopics))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        let query = normalizedSearch
        guard !query.isEmpty else { return all }
        return all.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    private var normalizedSearch: String {
        search
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    }

    private var canAddSearchAsTopic: Bool {
        let query = normalizedSearch
        return !query.isEmpty
            && query.count <= 30
            && selectedTopics.count < 50
            && query.range(of: "^[A-Za-z0-9_\\- /]+$", options: .regularExpression) != nil
            && !selectedTopics.contains { $0.caseInsensitiveCompare(query) == .orderedSame }
            && !availableTopics.contains { $0.caseInsensitiveCompare(query) == .orderedSame }
    }

    var body: some View {
        NavigationStack {
            List {
                if canAddSearchAsTopic {
                    Section {
                        Button {
                            selectedTopics.insert(normalizedSearch)
                            search = ""
                        } label: {
                            Label("Add #\(normalizedSearch)", systemImage: "plus.circle")
                        }
                    }
                }
                Section {
                    ForEach(topics, id: \.self) { topic in
                        Button {
                            if selectedTopics.contains(topic) {
                                selectedTopics.remove(topic)
                            } else {
                                selectedTopics.insert(topic)
                            }
                        } label: {
                            HStack {
                                Text(topic).foregroundStyle(.primary)
                                Spacer()
                                if selectedTopics.contains(topic) {
                                    Image(systemName: "checkmark")
                                        .fontWeight(.semibold)
                                        .foregroundStyle(AppTheme.accent)
                                }
                            }
                        }
                    }
                } footer: {
                    Text(footer)
                }
            }
            .navigationTitle("Topics")
            .searchable(text: $search, prompt: "Find a topic")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        apply(selectedTopics)
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !selectedTopics.isEmpty {
                    Button("Clear all topics") { selectedTopics.removeAll() }
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(.regularMaterial)
                }
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
    let browseCommunities: () -> Void
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

                Button(action: browseCommunities) {
                    Label("Browse communities", systemImage: "person.3")
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

private struct CommunityDiscoveryQuery: Hashable {
    let search: String
    let tags: [String]
}

private struct CommunityDiscoveryView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var store: SyncStore
    let openCommunity: (String) async -> Void
    @State private var query = ""
    @State private var selectedTags: Set<String> = []
    @State private var openingIDs: Set<String> = []
    @State private var showCreate = false
    @State private var showTagPicker = false
    @State private var reportCommunity: CommunitySummary?

    private var discoveryQuery: CommunityDiscoveryQuery {
        CommunityDiscoveryQuery(
            search: query,
            tags: selectedTags.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            SelectedTopicChips(topics: $selectedTags)
                .padding(.horizontal, 16)
                .padding(.top, selectedTags.isEmpty ? 0 : 8)

            Group {
                if model.isLoadingCommunities && model.communityResults.isEmpty {
                    ProgressView("Finding communities…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if model.communityResults.isEmpty {
                    ContentUnavailableView(
                        query.isEmpty && selectedTags.isEmpty ? "No public communities" : "No communities found",
                        systemImage: "safari",
                        description: Text(
                            query.isEmpty && selectedTags.isEmpty
                                ? "Create the first community on this instance."
                                : "Try a different name or tag."
                        )
                    )
                } else {
                    List(model.communityResults) { community in
                        CommunityDiscoveryRow(
                            community: community,
                            isJoined: store.communities[community.id] != nil,
                            isOpening: openingIDs.contains(community.id),
                            open: { open(community.id) }
                        )
                        .contextMenu {
                            Button("Report community", systemImage: "exclamationmark.bubble", role: .destructive) {
                                reportCommunity = community
                            }
                        }
                    }
                    .refreshable {
                        await model.discoverCommunities(query: query, tags: selectedTags)
                    }
                }
            }
        }
        .navigationTitle("Discover Communities")
        .searchable(text: $query, prompt: "Community name or tag")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showTagPicker = true
                } label: {
                    Label(
                        selectedTags.isEmpty ? "Tags" : "Tags (\(selectedTags.count))",
                        systemImage: selectedTags.isEmpty
                            ? "line.3.horizontal.decrease.circle"
                            : "line.3.horizontal.decrease.circle.fill"
                    )
                }
                Button("Create community", systemImage: "plus") { showCreate = true }
            }
        }
        .task(id: discoveryQuery) {
            do {
                try await Task.sleep(for: .milliseconds(query.isEmpty ? 0 : 350))
                await model.discoverCommunities(query: query, tags: selectedTags)
            } catch {
                // A newer search superseded this request.
            }
        }
        .sheet(isPresented: $showCreate) {
            CreateCommunityView { communityID in
                showCreate = false
                Task { await openCommunity(communityID) }
            }
        }
        .sheet(isPresented: $showTagPicker) {
            FeedTopicPicker(
                availableTopics: model.feedTopicOptions,
                initialSelection: selectedTags,
                footer: "Communities must include every selected tag."
            ) { selectedTags = $0 }
        }
        .sheet(item: $reportCommunity) { community in
            ReportSheet(
                target: ReportTarget(type: .community, id: community.id, subject: community.title)
            )
        }
    }

    private func open(_ communityID: String) {
        guard !openingIDs.contains(communityID) else { return }
        openingIDs.insert(communityID)
        Task {
            await openCommunity(communityID)
            openingIDs.remove(communityID)
        }
    }
}

private struct CommunityDiscoveryRow: View {
    @EnvironmentObject private var model: AppModel
    let community: CommunitySummary
    let isJoined: Bool
    let isOpening: Bool
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                CommunityMark(
                    name: community.title,
                    url: community.logoSmallId.flatMap { model.attachmentURLs[$0] }
                )
                VStack(alignment: .leading, spacing: 4) {
                    Text(community.title).fontWeight(.semibold).foregroundStyle(.primary)
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
                if isOpening {
                    ProgressView().controlSize(.small)
                } else {
                    if isJoined {
                        Text("Joined")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isOpening)
        .padding(.vertical, 4)
        .accessibilityIdentifier(
            "community.discovery.\(isJoined ? "joined" : "public").\(community.id)"
        )
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
            Group {
                if !current.isAdmin {
                    ContentUnavailableView(
                        "Administrator access required",
                        systemImage: "lock.shield",
                        description: Text("Community settings are available only to administrators.")
                    )
                } else {
                    List {
                        if current.canManageInfo || current.creatorId == model.store.ownUser?.id {
                            Section {
                                NavigationLink {
                                    CommunityGeneralSettingsView(community: current)
                                } label: {
                                    SettingsRow(icon: "gearshape", color: .gray, title: "General")
                                }
                                NavigationLink {
                                    CommunityNewsletterSettingsView(community: current)
                                } label: {
                                    SettingsRow(icon: "envelope", color: .orange, title: "Newsletters")
                                }
                            }
                        }
                        if current.canManageRoles {
                            Section("Plan") {
                                NavigationLink {
                                    CommunityPremiumSettingsView(community: current)
                                } label: {
                                    SettingsRow(icon: "sparkles", color: .purple, title: "Premium")
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

                        if current.canManageRoles || current.canManageInfo
                            || current.creatorId == model.store.ownUser?.id || current.isAdmin {
                            Section("Extensions") {
                                if current.canManageRoles {
                                    NavigationLink {
                                        CommunityTokenSettingsView(community: current)
                                    } label: {
                                        SettingsRow(icon: "hexagon", color: .mint, title: "Token", badge: current.tokens.count)
                                    }
                                }
                                if current.canManageInfo || current.creatorId == model.store.ownUser?.id {
                                    NavigationLink {
                                        CommunityBotsSettingsView(community: current)
                                    } label: {
                                        SettingsRow(icon: "cpu", color: .yellow, title: "Bots")
                                    }
                                }
                                if current.isAdmin {
                                    NavigationLink {
                                        CommunityPluginsSettingsView(community: current)
                                    } label: {
                                        SettingsRow(icon: "puzzlepiece.extension", color: .pink, title: "Plugins", badge: current.plugins.count)
                                    }
                                }
                            }
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

private struct CommunityPremiumSettingsView: View {
    @EnvironmentObject private var model: AppModel
    let community: Community
    @State private var feature = "BASIC"
    @State private var duration = "month"
    @State private var autoRenew: String?
    @State private var confirmingPurchase = false
    @State private var isSaving = false

    init(community: Community) {
        self.community = community
        _feature = State(initialValue: community.premiumInfo?.featureName ?? "BASIC")
        _autoRenew = State(initialValue: community.premiumInfo?.autoRenew)
    }

    private var current: Community { model.store.communities[community.id] ?? community }

    var body: some View {
        Form {
            Section("Current plan") {
                LabeledContent("Plan", value: current.premiumInfo?.featureName.capitalized ?? "Free")
                if let expiry = current.premiumInfo?.activeUntil {
                    LabeledContent("Active until", value: expiry)
                }
                LabeledContent("Community Spark", value: current.pointBalance.formatted())
            }
            if let premium = current.premiumInfo {
                Section("Renewal") {
                    Picker("Automatic renewal", selection: $autoRenew) {
                        Text("Off").tag(String?.none)
                        Text("Monthly").tag(String?.some("MONTH"))
                        Text("Yearly").tag(String?.some("YEAR"))
                    }
                    Button("Save renewal") {
                        isSaving = true
                        Task {
                            _ = await model.setCommunityPremiumAutoRenew(
                                communityID: current.id,
                                feature: premium.featureName,
                                autoRenew: autoRenew
                            )
                            isSaving = false
                        }
                    }
                    .disabled(isSaving || autoRenew == premium.autoRenew)
                }
            }
            Section {
                Picker("Plan", selection: $feature) {
                    Text("Basic").tag("BASIC")
                    Text("Pro").tag("PRO")
                    Text("Enterprise").tag("ENTERPRISE")
                }
                Picker("Duration", selection: $duration) {
                    Text("Month").tag("month")
                    Text("Year").tag("year")
                    if current.premiumInfo != nil { Text("Upgrade current term").tag("upgrade") }
                }
                Button("Review purchase", systemImage: "sparkles") { confirmingPurchase = true }
            } header: {
                Text("Purchase or upgrade")
            } footer: {
                Text("The instance determines the Spark price and rejects purchases when the community balance is insufficient.")
            }
        }
        .navigationTitle("Premium")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Buy \(feature.capitalized) for \(duration)?",
            isPresented: $confirmingPurchase,
            titleVisibility: .visible
        ) {
            Button("Confirm Spark purchase") {
                isSaving = true
                Task {
                    _ = await model.buyCommunityPremium(
                        communityID: current.id,
                        feature: feature,
                        duration: duration
                    )
                    isSaving = false
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This spends Spark from the community balance according to the instance's configured price.")
        }
        .overlay { if isSaving { ProgressView() } }
    }
}

private struct CommunityTokenSettingsView: View {
    @EnvironmentObject private var model: AppModel
    let community: Community
    @State private var contractID = ""
    @State private var isSaving = false

    private var current: Community { model.store.communities[community.id] ?? community }

    var body: some View {
        List {
            Section("Configured tokens") {
                if current.tokenInfos.isEmpty {
                    ContentUnavailableView("No tokens", systemImage: "hexagon")
                }
                ForEach(current.tokenInfos) { token in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(token.contractId).textSelection(.enabled)
                        Text("Order \(token.order + 1)").font(.caption).foregroundStyle(.secondary)
                    }
                    .swipeActions {
                        Button("Remove", role: .destructive) {
                            Task {
                                _ = await model.removeCommunityToken(
                                    communityID: current.id,
                                    contractID: token.contractId
                                )
                            }
                        }
                    }
                }
            }
            Section {
                TextField("Contract ID", text: $contractID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Add token", systemImage: "plus") {
                    let value = contractID.trimmingCharacters(in: .whitespacesAndNewlines)
                    isSaving = true
                    Task {
                        if await model.addCommunityToken(communityID: current.id, contractID: value) {
                            contractID = ""
                        }
                        isSaving = false
                    }
                }
                .disabled(isSaving || contractID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } header: {
                Text("Add token contract")
            } footer: {
                Text("Token-gated roles can reference the configured contracts in Roles & Permissions.")
            }
        }
        .navigationTitle("Token")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct CommunityPluginsSettingsView: View {
    @EnvironmentObject private var model: AppModel
    let community: Community
    private var current: Community { model.store.communities[community.id] ?? community }

    var body: some View {
        List {
            Section("Installed") {
                if current.pluginInfos.isEmpty {
                    ContentUnavailableView("No plugins installed", systemImage: "puzzlepiece.extension")
                }
                ForEach(current.pluginInfos) { plugin in
                    NavigationLink {
                        CommunityPluginEditor(plugin: plugin)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(plugin.name)
                            Text(plugin.description ?? plugin.url)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            }
            Section {
                NavigationLink {
                    CommunityPluginCatalog(community: current)
                } label: {
                    Label("Browse Common Ground apps", systemImage: "storefront")
                }
            }
        }
        .navigationTitle("Plugins")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct RootAppStoreView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var store: SyncStore
    @State private var search = ""
    @State private var selectedPlugin: AppStorePlugin?

    var body: some View {
        Group {
            if model.isLoadingAppStore && model.appStorePlugins.isEmpty {
                ProgressView("Loading apps…")
            } else if model.appStorePlugins.isEmpty {
                ContentUnavailableView(
                    search.isEmpty ? "No apps available" : "No apps found",
                    systemImage: "storefront",
                    description: Text(
                        search.isEmpty
                            ? "Apps published by this instance will appear here."
                            : "Try a different search."
                    )
                )
            } else {
                List(model.appStorePlugins) { plugin in
                    Button { selectedPlugin = plugin } label: {
                        HStack(alignment: .top, spacing: 12) {
                            AppStoreMark(
                                name: plugin.name,
                                url: plugin.imageId.flatMap { model.attachmentURLs[$0] }
                            )
                            VStack(alignment: .leading, spacing: 5) {
                                Text(plugin.name).font(.headline)
                                Text(plugin.description)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                                HStack(spacing: 10) {
                                    Label("\(plugin.communityCount)", systemImage: "person.3")
                                    if let firstTag = plugin.tags?.first {
                                        Text("#\(firstTag)")
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .refreshable { await model.loadAppStorePlugins(query: search) }
            }
        }
        .navigationTitle("App Store")
        .searchable(text: $search, prompt: "Search apps")
        .task(id: search) {
            try? await Task.sleep(for: .milliseconds(search.isEmpty ? 0 : 250))
            guard !Task.isCancelled else { return }
            await model.loadAppStorePlugins(query: search)
        }
        .sheet(item: $selectedPlugin) { plugin in
            NavigationStack {
                RootAppStoreDetail(plugin: plugin, store: store)
            }
        }
    }
}

private struct AppStoreMark: View {
    let name: String
    let url: URL?

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    ProgressView()
                }
            } else {
                Image(systemName: "puzzlepiece.extension.fill")
                    .font(.title2)
                    .foregroundStyle(AppTheme.accent)
                    .accessibilityLabel(name)
            }
        }
        .frame(width: 52, height: 52)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct RootAppStoreDetail: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let plugin: AppStorePlugin
    @ObservedObject var store: SyncStore
    @State private var installingCommunityID: String?

    private var adminCommunities: [Community] {
        store.communities.values.filter(\.isAdmin).sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    var body: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 14) {
                    AppStoreMark(
                        name: plugin.name,
                        url: plugin.imageId.flatMap { model.attachmentURLs[$0] }
                    )
                    VStack(alignment: .leading, spacing: 5) {
                        Text(plugin.name).font(.title3.bold())
                        Text(plugin.description).foregroundStyle(.secondary)
                    }
                }
            }
            if let tags = plugin.tags, !tags.isEmpty {
                Section("Tags") {
                    Text(tags.map { "#\($0)" }.joined(separator: "  "))
                }
            }
            if !plugin.permissions.mandatory.isEmpty {
                Section("Required permissions") {
                    ForEach(plugin.permissions.mandatory, id: \.self) {
                        Label($0.permissionTitle, systemImage: "checkmark.shield")
                    }
                }
            }
            Section("Install in a community") {
                if adminCommunities.isEmpty {
                    Text("Only community administrators can install apps.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(adminCommunities) { community in
                        let installed = community.pluginInfos.contains { $0.pluginId == plugin.pluginId }
                        Button {
                            installingCommunityID = community.id
                            Task {
                                _ = await model.installPlugin(plugin, communityID: community.id)
                                installingCommunityID = nil
                            }
                        } label: {
                            HStack {
                                Text(community.title)
                                Spacer()
                                if installingCommunityID == community.id {
                                    ProgressView().controlSize(.small)
                                } else if installed {
                                    Label("Installed", systemImage: "checkmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("Install")
                                }
                            }
                        }
                        .disabled(installed || installingCommunityID != nil)
                    }
                }
            }
        }
        .navigationTitle(plugin.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}

private struct CommunityPluginEditor: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let plugin: CommunityPluginInfo
    @State private var accepted: Set<String>
    @State private var confirmingRemoval = false
    @State private var isSaving = false

    init(plugin: CommunityPluginInfo) {
        self.plugin = plugin
        _accepted = State(initialValue: Set(plugin.acceptedPermissions ?? plugin.permissions?.mandatory ?? []))
    }

    var body: some View {
        Form {
            Section("App") {
                LabeledContent("Name", value: plugin.name)
                LabeledContent("Origin", value: plugin.url)
                if plugin.requiresIsolationMode {
                    Label("Requires isolated web content", systemImage: "lock.shield")
                }
                if plugin.reportFlagged || plugin.warnAbusive {
                    Label("This app has a safety warning", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
            if let permissions = plugin.permissions {
                Section("Required permissions") {
                    ForEach(permissions.mandatory, id: \.self) { Text($0.permissionTitle) }
                }
                Section("Optional permissions") {
                    ForEach(permissions.optional, id: \.self) { permission in
                        Toggle(permission.permissionTitle, isOn: Binding(
                            get: { accepted.contains(permission) },
                            set: { enabled in
                                if enabled { accepted.insert(permission) }
                                else { accepted.remove(permission) }
                            }
                        ))
                    }
                    Button("Save permissions") {
                        isSaving = true
                        Task {
                            let required = Set(permissions.mandatory)
                            _ = await model.updatePluginPermissions(
                                plugin,
                                permissions: Array(required.union(accepted)).sorted()
                            )
                            isSaving = false
                        }
                    }
                    .disabled(isSaving)
                }
            }
            Section {
                Button("Remove Plugin", role: .destructive) { confirmingRemoval = true }
            }
        }
        .navigationTitle(plugin.name)
        .confirmationDialog("Remove \(plugin.name)?", isPresented: $confirmingRemoval) {
            Button("Remove Plugin", role: .destructive) {
                Task { if await model.removePlugin(plugin, communityID: plugin.communityId) { dismiss() } }
            }
        }
    }
}

private struct CommunityPluginCatalog: View {
    @EnvironmentObject private var model: AppModel
    let community: Community
    @State private var search = ""
    @State private var installingID: String?

    var body: some View {
        List(model.appStorePlugins) { plugin in
            VStack(alignment: .leading, spacing: 7) {
                Text(plugin.name).font(.headline)
                Text(plugin.description).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                if !plugin.permissions.mandatory.isEmpty {
                    Text("Requires: \(plugin.permissions.mandatory.map(\.permissionTitle).joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Install", systemImage: "square.and.arrow.down") {
                    installingID = plugin.id
                    Task {
                        _ = await model.installPlugin(plugin, communityID: community.id)
                        installingID = nil
                    }
                }
                .disabled(installingID != nil || community.pluginInfos.contains { $0.pluginId == plugin.pluginId })
            }
            .padding(.vertical, 4)
        }
        .overlay { if model.appStorePlugins.isEmpty { ProgressView() } }
        .navigationTitle("App Store")
        .searchable(text: $search, prompt: "Search apps")
        .task(id: search) {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await model.loadAppStorePlugins(query: search)
        }
    }
}

private extension String {
    var permissionTitle: String {
        replacingOccurrences(of: "_", with: " ").lowercased().capitalized
    }
}

private struct CommunityNewsletterSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let community: Community
    @State private var enabled: Bool
    @State private var isSaving = false
    @State private var timeframe = "90days"

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
            Section("Newsletter history") {
                Picker("Timeframe", selection: $timeframe) {
                    Text("30 days").tag("30days")
                    Text("90 days").tag("90days")
                    Text("1 year").tag("1year")
                }
                ForEach(model.communityNewsletterHistory[community.id] ?? []) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.title)
                        Text(entry.sentAsNewsletter.map { "Sent \($0)" } ?? "Queued")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if model.communityNewsletterHistory[community.id]?.isEmpty == true {
                    Text("No deliveries in this timeframe, or newsletters are not enabled for this instance.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
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
        .task(id: timeframe) {
            await model.loadCommunityNewsletterHistory(communityID: community.id, timeframe: timeframe)
        }
    }
}

private struct CommunityBotsSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let community: Community
    @State private var allowUserBots: Bool
    @State private var isSaving = false

    init(community: Community) {
        self.community = community
        _allowUserBots = State(initialValue: community.allowUserBots)
    }

    var body: some View {
        Form {
            Section {
                Toggle("Allow member-installed bots", isOn: $allowUserBots)
            } footer: {
                Text("When enabled, members may add bots they control to this community. Community-managed bots are unaffected.")
            }
        }
        .navigationTitle("Bots")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    isSaving = true
                    Task {
                        if await model.setCommunityUserBots(
                            communityID: community.id,
                            allowed: allowUserBots
                        ) { dismiss() }
                        isSaving = false
                    }
                }
                .disabled(isSaving || allowUserBots == community.allowUserBots)
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
    @State private var moderationMember: ChannelMemberEntry?

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
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if community.canModerate && member.userId != model.store.ownUser?.id {
                                    Button("Moderate") { moderationMember = member }
                                        .tint(.orange)
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
        .sheet(item: $moderationMember) { member in
            NavigationStack {
                CommunityMemberModerationView(community: community, member: member)
            }
        }
    }

    private func roleNames(_ ids: [String]) -> String {
        let names = community.roleInfos.filter { ids.contains($0.id) }.map(\.title)
        return names.isEmpty ? "Member" : names.joined(separator: ", ")
    }
}

private struct CommunityMemberModerationView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let community: Community
    let member: ChannelMemberEntry
    @State private var isSaving = false

    private var userName: String {
        model.store.users[member.userId]?.displayName ?? "Member"
    }

    var body: some View {
        Form {
            Section {
                Text("Choose a moderation action for \(userName). The change applies immediately across the community.")
            }
            Section("Mute chat") {
                Button("Mute for 24 hours") { apply(state: "CHAT_MUTED", days: 1) }
                Button("Mute for 7 days") { apply(state: "CHAT_MUTED", days: 7) }
            }
            Section("Ban") {
                Button("Ban for 24 hours", role: .destructive) { apply(state: "BANNED", days: 1) }
                Button("Ban for 7 days", role: .destructive) { apply(state: "BANNED", days: 7) }
                Button("Ban indefinitely", role: .destructive) { apply(state: "BANNED", days: nil) }
            }
        }
        .navigationTitle("Moderate Member")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        .disabled(isSaving)
        .overlay { if isSaving { ProgressView() } }
    }

    private func apply(state: String, days: Int?) {
        isSaving = true
        let until = days.map {
            ISO8601DateFormatter().string(from: Date().addingTimeInterval(Double($0) * 86_400))
        }
        Task {
            if await model.setCommunityMemberBlock(
                communityID: community.id,
                userID: member.userId,
                state: state,
                until: until
            ) { dismiss() }
            isSaving = false
        }
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
    @State private var showingNewArea = false
    @State private var areaName = ""
    @State private var orderedAreas: [CommunityAreaInfo] = []
    @State private var draggedAreaID: String?
    @State private var isSavingOrder = false

    private var current: Community { model.store.communities[community.id] ?? community }

    var body: some View {
        List {
            Section("Areas") {
                if orderedAreas.isEmpty {
                    ContentUnavailableView(
                        "No areas",
                        systemImage: "folder",
                        description: Text("Create an area before adding channels.")
                    )
                }
                ForEach(orderedAreas) { area in
                    NavigationLink {
                        CommunityAreaChannelsView(community: current, area: area)
                    } label: {
                        HStack {
                            Label(area.title, systemImage: "folder")
                            Spacer()
                            Text(current.channels.filter { $0.areaId == area.id }.count, format: .number)
                                .foregroundStyle(.secondary)
                            Image(systemName: "line.3.horizontal")
                                .foregroundStyle(.secondary)
                                .padding(.leading, 4)
                                .onDrag {
                                    draggedAreaID = area.id
                                    return NSItemProvider(object: area.id as NSString)
                                }
                                .accessibilityLabel("Reorder \(area.title)")
                        }
                    }
                    .onDrop(
                        of: [UTType.plainText],
                        delegate: ReorderDropDelegate(
                            targetID: area.id,
                            items: $orderedAreas,
                            draggedID: $draggedAreaID,
                            didFinish: persistAreaOrder
                        )
                    )
                }
            }
        }
        .navigationTitle("Channels")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if current.canManageChannels {
                ToolbarItem(placement: .primaryAction) {
                    Button("New area", systemImage: "plus") { showingNewArea = true }
                }
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
            Text("You can add and reorder channels after opening the area.")
        }
        .onAppear { synchronizeAreas() }
        .onChange(of: current.areaInfos) { _, _ in synchronizeAreas() }
    }

    private func synchronizeAreas() {
        guard draggedAreaID == nil, !isSavingOrder else { return }
        orderedAreas = current.areaInfos
    }

    private func persistAreaOrder(_ orderedIDs: [String]) {
        guard !isSavingOrder else { return }
        isSavingOrder = true
        Task {
            let saved = await model.reorderCommunityAreas(
                communityID: current.id,
                orderedIDs: orderedIDs
            )
            isSavingOrder = false
            if !saved { orderedAreas = current.areaInfos }
        }
    }
}

private struct CommunityAreaChannelsView: View {
    @EnvironmentObject private var model: AppModel
    let community: Community
    let area: CommunityAreaInfo
    @State private var showingNewChannel = false
    @State private var showingAreaSettings = false
    @State private var orderedChannels: [Channel] = []
    @State private var draggedChannelID: String?
    @State private var isSavingOrder = false

    private var current: Community { model.store.communities[community.id] ?? community }
    private var currentArea: CommunityAreaInfo {
        current.areaInfos.first(where: { $0.id == area.id }) ?? area
    }
    private var currentChannels: [Channel] {
        current.channels.filter { $0.areaId == area.id }.sorted { $0.order < $1.order }
    }

    var body: some View {
        List {
            Section {
                if orderedChannels.isEmpty {
                    ContentUnavailableView(
                        "No channels",
                        systemImage: "number",
                        description: Text("Add the first channel to this area.")
                    )
                }
                ForEach(orderedChannels) { channel in
                    NavigationLink {
                        CommunityChannelEditor(community: current, channel: channel)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Label(channel.title, systemImage: "number")
                                if let description = channel.description, !description.isEmpty {
                                    Text(description).font(.caption).foregroundStyle(.secondary)
                                }
                                Text("\(channel.rolePermissions.count) role access rules")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Image(systemName: "line.3.horizontal")
                                .foregroundStyle(.secondary)
                                .padding(.leading, 4)
                                .onDrag {
                                    draggedChannelID = channel.id
                                    return NSItemProvider(object: channel.id as NSString)
                                }
                                .accessibilityLabel("Reorder \(channel.title)")
                        }
                    }
                    .onDrop(
                        of: [UTType.plainText],
                        delegate: ReorderDropDelegate(
                            targetID: channel.id,
                            items: $orderedChannels,
                            draggedID: $draggedChannelID,
                            didFinish: persistChannelOrder
                        )
                    )
                }
            }
        }
        .navigationTitle(currentArea.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if current.canManageChannels {
                ToolbarItem(placement: .primaryAction) {
                    Button("New channel", systemImage: "plus") { showingNewChannel = true }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button("Area settings", systemImage: "ellipsis.circle") {
                        showingAreaSettings = true
                    }
                }
            }
        }
        .sheet(isPresented: $showingNewChannel) {
            NavigationStack {
                CommunityChannelEditor(
                    community: current,
                    channel: nil,
                    initialAreaID: area.id
                )
            }
        }
        .sheet(isPresented: $showingAreaSettings) {
            NavigationStack {
                CommunityAreaEditor(community: current, area: currentArea)
            }
        }
        .onAppear { synchronizeChannels() }
        .onChange(of: currentChannels) { _, _ in synchronizeChannels() }
    }

    private func synchronizeChannels() {
        guard draggedChannelID == nil, !isSavingOrder else { return }
        orderedChannels = currentChannels
    }

    private func persistChannelOrder(_ orderedIDs: [String]) {
        guard !isSavingOrder else { return }
        isSavingOrder = true
        Task {
            let saved = await model.reorderCommunityChannels(
                communityID: current.id,
                areaID: area.id,
                orderedIDs: orderedIDs
            )
            isSavingOrder = false
            if !saved { orderedChannels = currentChannels }
        }
    }
}

private struct ReorderDropDelegate<Item: Identifiable & Equatable>: DropDelegate where Item.ID == String {
    let targetID: String
    @Binding var items: [Item]
    @Binding var draggedID: String?
    let didFinish: ([String]) -> Void

    func dropEntered(info: DropInfo) {
        guard let draggedID,
              draggedID != targetID,
              let sourceIndex = items.firstIndex(where: { $0.id == draggedID }),
              let targetIndex = items.firstIndex(where: { $0.id == targetID }) else { return }
        withAnimation(.snappy) {
            items.move(
                fromOffsets: IndexSet(integer: sourceIndex),
                toOffset: targetIndex > sourceIndex ? targetIndex + 1 : targetIndex
            )
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        let orderedIDs = items.map(\.id)
        draggedID = nil
        didFinish(orderedIDs)
        return true
    }
}

private struct CommunityAreaEditor: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let community: Community
    let area: CommunityAreaInfo
    @State private var title: String
    @State private var confirmingDelete = false
    @State private var isSaving = false

    init(community: Community, area: CommunityAreaInfo) {
        self.community = community
        self.area = area
        _title = State(initialValue: area.title)
    }

    var body: some View {
        Form {
            Section("Area") {
                TextField("Name", text: $title)
            }
            Section {
                Button("Delete Area", role: .destructive) { confirmingDelete = true }
                    .disabled(community.channels.contains { $0.areaId == area.id })
            } footer: {
                if community.channels.contains(where: { $0.areaId == area.id }) {
                    Text("Move or delete every channel in this area before deleting it.")
                }
            }
        }
        .navigationTitle(area.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    isSaving = true
                    Task {
                        if await model.saveCommunityArea(
                            communityID: community.id,
                            areaID: area.id,
                            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                            order: area.order
                        ) { dismiss() }
                        isSaving = false
                    }
                }
                .disabled(isSaving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .confirmationDialog("Delete \(area.title)?", isPresented: $confirmingDelete) {
            Button("Delete Area", role: .destructive) {
                Task {
                    if await model.deleteCommunityArea(communityID: community.id, areaID: area.id) {
                        dismiss()
                    }
                }
            }
        }
        .overlay { if isSaving { ProgressView() } }
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

    init(community: Community, channel: Channel?, initialAreaID: String? = nil) {
        self.community = community
        self.channel = channel
        let initialAreaID = channel?.areaId ?? initialAreaID ?? community.areaInfos.first?.id
        _title = State(initialValue: channel?.title ?? "")
        _description = State(initialValue: channel?.description ?? "")
        _emoji = State(initialValue: channel?.emoji ?? "💬")
        _url = State(initialValue: channel?.url ?? "")
        _areaID = State(initialValue: initialAreaID)
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
            let order: Int
            if let channel, channel.areaId == areaID {
                order = channel.order
            } else {
                order = (community.channels.filter { $0.areaId == areaID }.map(\.order).max() ?? -1) + 1
            }
            let saved = await model.saveCommunityChannel(
                communityID: community.id,
                channelID: channel?.id,
                areaID: areaID,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                url: url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : url,
                order: order,
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
    @State private var assignmentMode: String
    @State private var tokenContractID: String
    @State private var tokenType: String
    @State private var tokenAmount: String
    @State private var tokenID: String
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
        let assignment = role.assignmentRules?.objectValue ?? [:]
        let rules = assignment["rules"]?.objectValue ?? [:]
        let rule = rules["rule1"]?.objectValue ?? [:]
        let mode = assignment["type"]?.stringValue ?? "manual"
        _assignmentMode = State(initialValue: mode)
        _tokenContractID = State(initialValue: rule["contractId"]?.stringValue ?? community.tokenInfos.first?.contractId ?? "")
        _tokenType = State(initialValue: rule["type"]?.stringValue ?? "ERC20")
        _tokenAmount = State(initialValue: rule["amount"]?.stringValue ?? "1")
        _tokenID = State(initialValue: rule["tokenId"]?.stringValue ?? "0")
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
                    Picker("Assignment", selection: $assignmentMode) {
                        Text("Assigned by moderators").tag("manual")
                        Text("Claimable by anyone").tag("free")
                        Text("Token gated").tag("token")
                    }
                    if assignmentMode == "token" {
                        if community.tokenInfos.isEmpty {
                            Label("Add a token contract in Token settings first.", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        } else {
                            Picker("Contract", selection: $tokenContractID) {
                                ForEach(community.tokenInfos) { token in
                                    Text(token.contractId).tag(token.contractId)
                                }
                            }
                            Picker("Token standard", selection: $tokenType) {
                                Text("ERC-20").tag("ERC20")
                                Text("ERC-721").tag("ERC721")
                                Text("ERC-1155").tag("ERC1155")
                                Text("LSP-7").tag("LSP7")
                                Text("LSP-8").tag("LSP8")
                            }
                            TextField("Minimum amount", text: $tokenAmount)
                                .keyboardType(.decimalPad)
                            if tokenType == "ERC1155" {
                                TextField("Token ID", text: $tokenID)
                                    .keyboardType(.numberPad)
                            }
                        }
                    }
                } header: {
                    Text("Assignment")
                } footer: {
                    Text("Automatic roles are claimed by members when they meet the configured rule; moderators can still manage manual roles directly.")
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
                Button("Save") { save() }.disabled(
                    isSaving
                        || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || (assignmentMode == "token" && tokenContractID.isEmpty)
                )
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
            let assignmentRules: JSONValue?
            switch assignmentMode {
            case "free":
                assignmentRules = .object(["type": .string("free")])
            case "token":
                var rule: [String: JSONValue] = [
                    "type": .string(tokenType),
                    "contractId": .string(tokenContractID),
                    "amount": .string(tokenAmount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "1" : tokenAmount),
                ]
                if tokenType == "ERC1155" {
                    rule["tokenId"] = .string(tokenID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "0" : tokenID)
                }
                assignmentRules = .object([
                    "type": .string("token"),
                    "rules": .object(["rule1": .object(rule)]),
                ])
            default:
                assignmentRules = nil
            }
            let saved = await model.updateCommunityRole(
                communityID: community.id,
                roleID: role.id,
                title: isCustom ? title.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
                description: description,
                permissions: isAdmin ? nil : Array(permissions).sorted(),
                type: isCustom ? (assignmentMode == "manual" ? "CUSTOM_MANUAL_ASSIGN" : "CUSTOM_AUTO_ASSIGN") : nil,
                assignmentRules: isCustom ? assignmentRules : nil
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
    @State private var selectedEvent: CommunityEvent?
    @State private var showComposer = false
    @State private var showEventComposer = false
    @State private var showSpark = false

    private var articles: [CommunityArticlePreview] {
        model.communityArticles[community.id] ?? []
    }

    private var drafts: [CommunityArticlePreview] {
        model.communityArticleDrafts[community.id] ?? []
    }

    private var events: [CommunityEvent] {
        (model.communityEvents[community.id] ?? []).filter {
            (parseEventDate($0.scheduleDate) ?? .distantPast).addingTimeInterval(Double($0.duration) * 60) > Date()
        }
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
                    Text("\(community.memberCount) members · \(community.channels.count) channels")
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 14) {
                    Image(systemName: "sparkles")
                        .font(.title2)
                        .foregroundStyle(.orange)
                        .frame(width: 44, height: 44)
                        .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(community.pointBalance.formatted(.number.precision(.fractionLength(0))))
                            .font(.title3.bold())
                        Text("Spark in Community Safe")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Give Spark") { showSpark = true }
                        .buttonStyle(.bordered)
                }
                .padding(14)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))

                Divider()
                HStack {
                    Text("Upcoming events").font(.title2.bold())
                    Spacer()
                    if community.canManageEvents {
                        Button("Schedule", systemImage: "calendar.badge.plus") {
                            showEventComposer = true
                        }
                    } else {
                        Image(systemName: "calendar").foregroundStyle(AppTheme.accent)
                    }
                }

                if events.isEmpty {
                    ContentUnavailableView(
                        "No upcoming events",
                        systemImage: "calendar",
                        description: Text("Scheduled community events will appear here.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(events) { event in
                            CommunityEventCard(
                                event: event,
                                imageURL: event.imageId.flatMap { model.attachmentURLs[$0] }
                            ) { selectedEvent = event }
                        }
                    }
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
        .refreshable {
            async let home: Void = model.refreshCommunityHome(communityID: community.id)
            async let events: Void = model.loadCommunityEvents(communityID: community.id)
            _ = await (home, events)
        }
        .task(id: community.id) {
            async let articles: Void = model.loadCommunityArticles(communityID: community.id)
            async let events: Void = model.loadCommunityEvents(communityID: community.id)
            _ = await (articles, events)
        }
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
        .sheet(item: $selectedEvent) { event in
            CommunityEventDetailView(community: community, event: event)
        }
        .sheet(isPresented: $showEventComposer) {
            CommunityEventComposer(community: community) {
                showEventComposer = false
            }
        }
        .sheet(isPresented: $showSpark) {
            SparkDonationView(community: community)
        }
    }
}

private struct CommunityEventCard: View {
    let event: CommunityEvent
    let imageURL: URL?
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 14) {
                if let imageURL {
                    CommunityFeatureImage(url: imageURL, height: 84)
                    .frame(width: 92, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 11))
                } else {
                    Image(systemName: event.type == .external ? "globe" : "calendar")
                        .font(.title2)
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 58, height: 58)
                        .background(AppTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(event.title).font(.headline).foregroundStyle(.primary)
                    if let date = parseEventDate(event.scheduleDate) {
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.accent)
                    }
                    if !event.descriptionText.isEmpty {
                        Text(event.descriptionText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Label("\(event.participantCount) attending", systemImage: "person.2")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 15))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(event.title), \(event.participantCount) attending")
    }
}

private struct CommunityEventDetailView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let community: Community
    let event: CommunityEvent
    @State private var showEditor = false
    @State private var confirmDelete = false
    @State private var changingAttendance = false

    private var current: CommunityEvent {
        model.communityEvents[community.id]?.first { $0.id == event.id } ?? event
    }

    private var mayAttend: Bool {
        if current.isSelfAttending || community.isAdmin { return true }
        let ownRoles = Set(community.myRoleIds)
        return current.rolePermissions.contains {
            ownRoles.contains($0.roleId) && $0.permissions.contains("EVENT_ATTEND")
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let imageID = current.imageId,
                       let url = model.attachmentURLs[imageID] {
                        CommunityFeatureImage(url: url, height: 250)
                    }
                    Text(current.type.title.uppercased())
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.accent)
                    Text(current.title).font(.largeTitle.bold())
                    if let date = parseEventDate(current.scheduleDate) {
                        Label {
                            VStack(alignment: .leading) {
                                Text(date.formatted(date: .complete, time: .shortened))
                                Text("\(current.duration) minutes")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "calendar")
                        }
                    }
                    if let location = current.location, !location.isEmpty {
                        Label(location, systemImage: "mappin.and.ellipse")
                    }
                    if !current.descriptionText.isEmpty {
                        Text(current.descriptionText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    Label("\(current.participantCount) attending", systemImage: "person.2")
                        .foregroundStyle(.secondary)

                    if mayAttend {
                        Button {
                            changingAttendance = true
                            Task {
                                _ = await model.setEventAttendance(
                                    current,
                                    attending: !current.isSelfAttending
                                )
                                changingAttendance = false
                            }
                        } label: {
                            Label(
                                current.isSelfAttending ? "Leave event" : "Attend event",
                                systemImage: current.isSelfAttending ? "checkmark.circle.fill" : "plus.circle.fill"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.accent)
                        .disabled(changingAttendance)
                    }

                    if let external = current.externalUrl.flatMap(URL.init(string:)) {
                        Button("Open event link", systemImage: "arrow.up.right.square") {
                            openURL(external)
                        }
                        .buttonStyle(.bordered)
                    }
                    if current.type == .call || current.type == .broadcast {
                        Label(
                            "Joining native calls will arrive with the calls workstream.",
                            systemImage: "info.circle"
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: 720, alignment: .leading)
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if community.canManageEvents {
                    ToolbarItem(placement: .primaryAction) {
                        Menu("Manage event", systemImage: "ellipsis.circle") {
                            if current.type == .external || current.type == .reminder {
                                Button("Edit event", systemImage: "pencil") { showEditor = true }
                            }
                            Button("Delete event", systemImage: "trash", role: .destructive) {
                                confirmDelete = true
                            }
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showEditor) {
                CommunityEventComposer(community: community, event: current) {
                    showEditor = false
                }
            }
            .confirmationDialog("Delete this event?", isPresented: $confirmDelete) {
                Button("Delete event", role: .destructive) {
                    Task {
                        if await model.deleteCommunityEvent(current) { dismiss() }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The event and its public listing will be removed.")
            }
        }
    }
}

private enum EventAudienceAccess: String, CaseIterable, Identifiable {
    case hidden
    case preview
    case attend
    case moderate

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var permissions: [String] {
        switch self {
        case .hidden: []
        case .preview: ["EVENT_PREVIEW"]
        case .attend: ["EVENT_PREVIEW", "EVENT_ATTEND"]
        case .moderate: ["EVENT_PREVIEW", "EVENT_ATTEND", "EVENT_MODERATE"]
        }
    }

    init(permissions: [String]) {
        if permissions.contains("EVENT_MODERATE") { self = .moderate }
        else if permissions.contains("EVENT_ATTEND") { self = .attend }
        else if permissions.contains("EVENT_PREVIEW") { self = .preview }
        else { self = .hidden }
    }
}

private struct CommunityEventComposer: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let community: Community
    let event: CommunityEvent?
    let saved: () -> Void
    @State private var title: String
    @State private var details: String
    @State private var type: CommunityEventType
    @State private var start: Date
    @State private var end: Date
    @State private var externalURL: String
    @State private var location: String
    @State private var audience: [String: EventAudienceAccess]
    @State private var imageSelection: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var isSaving = false

    init(community: Community, event: CommunityEvent? = nil, saved: @escaping () -> Void) {
        self.community = community
        self.event = event
        self.saved = saved
        let eventStart = event.flatMap { parseEventDate($0.scheduleDate) } ?? Date().addingTimeInterval(3_600)
        _title = State(initialValue: event?.title ?? "")
        _details = State(initialValue: event?.descriptionText ?? "")
        _type = State(initialValue: event?.type ?? .external)
        _start = State(initialValue: eventStart)
        _end = State(initialValue: eventStart.addingTimeInterval(Double(event?.duration ?? 60) * 60))
        _externalURL = State(initialValue: event?.externalUrl ?? "")
        _location = State(initialValue: event?.location ?? "")
        let permissions = event?.rolePermissions ?? community.defaultEventRolePermissions
        _audience = State(initialValue: Dictionary(uniqueKeysWithValues: permissions.map {
            ($0.roleId, EventAudienceAccess(permissions: $0.permissions))
        }))
    }

    private var roles: [CommunityRoleInfo] {
        community.roleInfos.filter { $0.title != "Admin" }
    }

    private var rolePermissions: [CommunityEventRolePermission] {
        roles.compactMap { role in
            let access = audience[role.id] ?? .hidden
            guard access != .hidden else { return nil }
            return CommunityEventRolePermission(
                roleId: role.id,
                roleTitle: role.title,
                permissions: access.permissions
            )
        }
    }

    private var validExternalURL: Bool {
        guard type == .external else { return true }
        guard let url = URL(string: externalURL), let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "https" || scheme == "http"
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && title.count <= 100
            && details.count <= 2_000
            && start > Date().addingTimeInterval(30)
            && end > start
            && end.timeIntervalSince(start) <= 8 * 60 * 60
            && validExternalURL
            && externalURL.count <= 200
            && location.count <= 200
            && !rolePermissions.isEmpty
            && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Event") {
                    TextField("Title", text: $title)
                        .onChange(of: title) { _, value in title = String(value.prefix(100)) }
                    TextField("Description", text: $details, axis: .vertical)
                        .lineLimit(3...10)
                        .onChange(of: details) { _, value in details = String(value.prefix(2_000)) }
                    Picker("Type", selection: $type) {
                        Text("External event").tag(CommunityEventType.external)
                        Text("Reminder").tag(CommunityEventType.reminder)
                    }
                }
                Section("Schedule") {
                    DatePicker("Starts", selection: $start, in: Date()...)
                    DatePicker("Ends", selection: $end, in: start...)
                    Text("Events must start at least one minute from now.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if type == .external {
                    Section("Place") {
                        TextField("https://…", text: $externalURL)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            .onChange(of: externalURL) { _, value in
                                externalURL = String(value.prefix(200))
                            }
                        TextField("Location (optional)", text: $location)
                            .onChange(of: location) { _, value in location = String(value.prefix(200)) }
                    }
                }
                Section("Banner") {
                    if imageData == nil, let imageID = event?.imageId,
                       let url = model.attachmentURLs[imageID] {
                        CommunityFeatureImage(url: url, height: 150)
                    }
                    CommunityImagePicker(
                        title: event?.imageId == nil ? "Choose event image" : "Replace event image",
                        guidance: "Optional landscape image",
                        selection: $imageSelection,
                        data: imageData
                    )
                }
                Section {
                    ForEach(roles) { role in
                        Picker(role.title, selection: Binding(
                            get: { audience[role.id] ?? .hidden },
                            set: { audience[role.id] = $0 }
                        )) {
                            ForEach(EventAudienceAccess.allCases) { access in
                                Text(access.title).tag(access)
                            }
                        }
                    }
                } header: {
                    Text("Audience & permissions")
                } footer: {
                    Text("Preview can see the listing. Attend can RSVP. Moderate can also manage the event.")
                }
            }
            .navigationTitle(event == nil ? "Schedule Event" : "Edit Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!canSave)
                }
            }
            .overlay { if isSaving { ProgressView() } }
            .onChange(of: start) { old, new in
                if end <= new { end = new.addingTimeInterval(max(3_600, end.timeIntervalSince(old))) }
            }
            .onChange(of: imageSelection) { _, item in
                guard let item else { return }
                Task {
                    if let loaded = try? await item.loadTransferable(type: Data.self) {
                        imageData = loaded
                    } else {
                        model.errorMessage = "That image could not be loaded from the photo library."
                    }
                }
            }
        }
    }

    private func save() {
        isSaving = true
        Task {
            let didSave = await model.saveCommunityEvent(
                community: community,
                editing: event,
                type: type,
                title: title,
                description: details,
                start: start,
                end: end,
                externalURL: type == .external ? externalURL : nil,
                location: type == .external && !location.isEmpty ? location : nil,
                rolePermissions: rolePermissions,
                imageData: imageData
            )
            isSaving = false
            if didSave { saved() }
        }
    }
}

private func parseEventDate(_ value: String) -> Date? {
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
}

private struct SparkDonationView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let community: Community
    @State private var selectedAmount = 5_000
    @State private var customAmount = ""
    @State private var isGiving = false
    @State private var confirming = false

    private var balance: Double { model.store.ownUser?.pointBalance ?? 0 }
    private var amount: Int {
        if !customAmount.isEmpty { return Int(customAmount) ?? 0 }
        return selectedAmount
    }
    private var canGive: Bool {
        amount >= 1_000 && Double(amount) <= balance && !isGiving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Community Safe") {
                        Label(
                            community.pointBalance.formatted(.number.precision(.fractionLength(0))),
                            systemImage: "sparkles"
                        )
                    }
                    LabeledContent("Your balance") {
                        Text(balance.formatted(.number.precision(.fractionLength(0))))
                    }
                }

                Section("Select amount") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach([5_000, 10_000, 20_000, 50_000], id: \.self) { value in
                            Button {
                                selectedAmount = value
                                customAmount = ""
                            } label: {
                                Label(value.formatted(), systemImage: "sparkles")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(selectedAmount == value && customAmount.isEmpty ? AppTheme.accent : .secondary)
                        }
                    }
                    TextField("Custom amount (minimum 1,000)", text: $customAmount)
                        .keyboardType(.numberPad)
                        .onChange(of: customAmount) { _, value in
                            customAmount = String(value.filter(\.isNumber).prefix(12))
                        }
                }

                Section {
                    Button("Give \(amount.formatted()) Spark", systemImage: "sparkles") {
                        confirming = true
                    }
                    .disabled(!canGive)
                } footer: {
                    Text("Contributions move Spark into the community’s Safe immediately and are non-refundable.")
                }

                if balance < 1_000 {
                    Section {
                        Label("You need at least 1,000 Spark to contribute.", systemImage: "info.circle")
                            .foregroundStyle(.secondary)
                    } footer: {
                        Text("Buying Spark will be added with the native wallet flow in a later milestone.")
                    }
                }
            }
            .navigationTitle("Give Spark")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .overlay { if isGiving { ProgressView() } }
            .confirmationDialog(
                "Give \(amount.formatted()) Spark to \(community.title)?",
                isPresented: $confirming,
                titleVisibility: .visible
            ) {
                Button("Give Spark") { give() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This contribution cannot be reversed.")
            }
        }
    }

    private func give() {
        guard canGive else { return }
        isGiving = true
        Task {
            if await model.giveSpark(to: community.id, amount: amount) { dismiss() }
            isGiving = false
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

private enum ArticleReaderPresentation {
    case sheet
    case pushedPost
}

private struct ArticleReaderView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let articleID: String
    let source: ArticleOwner
    @ObservedObject var store: SyncStore
    let focusedCommentID: String?
    var presentation: ArticleReaderPresentation = .sheet
    var feedPost: FeedPost? = nil
    @State private var commentText = ""
    @State private var isSendingComment = false
    @State private var showEditor = false
    @State private var confirmDelete = false
    @State private var confirmNewsletter = false
    @State private var selectedFeedProfile: NotificationProfileRoute?
    @State private var selectedFeedCommunity: Community?
    @State private var isLoadingFeedActor = false
    @FocusState private var commentComposerFocused: Bool

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
    private var commentAccess: MessageAccess? {
        article.map { model.articleAccess(owner: source, article: $0) }
    }
    private var typingUserIDs: [String] {
        commentAccess.map { store.typingUserIDs(for: $0) } ?? []
    }

    var body: some View {
        Group {
            if presentation == .sheet {
                NavigationStack { articleContent }
            } else {
                articleContent
            }
        }
    }

    private var articleContent: some View {
        ScrollViewReader { proxy in
                ScrollView {
                    if let article {
                    VStack(alignment: .leading, spacing: 18) {
                        if presentation == .pushedPost, let feedPost {
                            FeedPostHeader(
                                post: feedPost,
                                actorImageURL: model.feedActorImageURL(for: feedPost),
                                openActor: openFeedActor
                            )
                        }
                        if let imageID = article.headerImageId,
                           let url = model.attachmentURLs[imageID] {
                            AsyncImage(url: url) { image in
                                image.resizable().scaledToFit()
                            } placeholder: {
                                ProgressView()
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                        if presentation == .sheet {
                            Text(article.title).font(.largeTitle.bold())
                        }
                        if presentation == .sheet, let creator = store.users[article.creatorId] {
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
                        if presentation == .sheet,
                           let preview = article.previewText,
                           !preview.isEmpty {
                            Text(preview)
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                        Divider()
                        MarkdownArticleText(
                            source: article.markdownSource,
                            headingStyle: presentation == .pushedPost ? .social : .article
                        )
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
                            if !typingUserIDs.isEmpty {
                                TypingIndicatorView(userIDs: typingUserIDs, users: store.users)
                            }
                            HStack(alignment: .bottom, spacing: 10) {
                                TextField("Add a comment…", text: $commentText, axis: .vertical)
                                    .lineLimit(1...5)
                                    .focused($commentComposerFocused)
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
            .navigationTitle(presentation == .pushedPost ? "Post" : "Article")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if canEdit {
                    ToolbarItem(placement: .primaryAction) {
                        Menu("Manage article", systemImage: "ellipsis.circle") {
                            Button("Edit article", systemImage: "pencil") { showEditor = true }
                            if case .community = source, !isDraft {
                                Button("Send as newsletter", systemImage: "envelope") {
                                    confirmNewsletter = true
                                }
                            }
                            Button("Delete article", systemImage: "trash", role: .destructive) {
                                confirmDelete = true
                            }
                        }
                    }
                }
                if presentation == .sheet {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
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
            .sheet(item: $selectedFeedProfile) { route in
                UserProfileView(userID: route.id, store: store) { _ in }
            }
            .sheet(item: $selectedFeedCommunity) { community in
                NavigationStack {
                    CommunityHomeView(community: community, store: store)
                }
            }
            .overlay {
                if isLoadingFeedActor {
                    ProgressView()
                        .padding(18)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
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
            .confirmationDialog("Send this article as a newsletter?", isPresented: $confirmNewsletter) {
                Button("Queue Newsletter") {
                    guard case .community(let communityID) = source else { return }
                    Task {
                        _ = await model.sendCommunityArticleAsNewsletter(
                            communityID: communityID,
                            articleID: articleID
                        )
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This queues email delivery to subscribed members. Delivery cannot be recalled from the app.")
            }
            .onChange(of: commentText) { _, text in
                guard commentComposerFocused, let commentAccess else { return }
                model.updateTyping(access: commentAccess, text: text)
            }
            .onChange(of: commentComposerFocused) { _, focused in
                guard let commentAccess else { return }
                if focused {
                    model.updateTyping(access: commentAccess, text: commentText)
                } else {
                    model.stopTyping(access: commentAccess)
                }
            }
            .onDisappear {
                guard let article else { return }
                model.stopTyping(access: model.articleAccess(owner: source, article: article))
                Task { await model.leaveArticleComments(owner: source, article: article) }
            }
    }

    private func openFeedActor() {
        guard let feedPost else { return }
        switch feedPost.kind {
        case .user:
            selectedFeedProfile = NotificationProfileRoute(id: feedPost.actor.id)
        case .community:
            guard !isLoadingFeedActor else { return }
            isLoadingFeedActor = true
            Task {
                selectedFeedCommunity = await model.feedCommunityDetail(id: feedPost.actor.id)
                isLoadingFeedActor = false
            }
        }
    }

    private func sendComment(_ article: ArticleDetail) {
        let text = commentText
        model.stopTyping(access: model.articleAccess(owner: source, article: article))
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

private struct PublicCommunityChannelListView: View {
    @EnvironmentObject private var model: AppModel
    let community: Community
    let selectedChannelID: String?
    let openHome: () -> Void
    let select: (String) -> Void
    let didJoin: () -> Void
    @State private var isJoining = false
    @State private var joinRequestPending = false
    @State private var reportTarget: ReportTarget?

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
                Button {
                    join()
                } label: {
                    HStack {
                        Label("Join community", systemImage: "person.badge.plus")
                        Spacer()
                        if isJoining { ProgressView().controlSize(.small) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .disabled(isJoining)
                .foregroundStyle(AppTheme.accent)
                .fontWeight(.semibold)
            } footer: {
                Text("You are viewing this community with its public permissions.")
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

            Section("Public channels") {
                ForEach(community.channels.sorted(by: { $0.order < $1.order })) { channel in
                    Button {
                        if channel.publicCanRead { select(channel.channelId) }
                    } label: {
                        HStack {
                            Label(channel.title, systemImage: "number")
                            Spacer()
                            if !channel.publicCanRead {
                                Image(systemName: "lock").foregroundStyle(.tertiary)
                            } else if selectedChannelID == channel.channelId {
                                Image(systemName: "checkmark").foregroundStyle(AppTheme.accent)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!channel.publicCanRead)
                }
            }
        }
        .navigationTitle(community.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if let shareURL = model.communityShareURL(community) {
                        ShareLink(
                            item: shareURL,
                            subject: Text(community.title),
                            message: Text("Explore \(community.title) on Common Ground")
                        ) {
                            Label("Share community", systemImage: "square.and.arrow.up")
                        }
                    }
                    Button("Report community", systemImage: "exclamationmark.bubble") {
                        reportTarget = ReportTarget(
                            type: .community,
                            id: community.id,
                            subject: community.title
                        )
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("Join request submitted", isPresented: $joinRequestPending) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("A community moderator needs to approve your request before member-only areas become available.")
        }
        .sheet(item: $reportTarget) { ReportSheet(target: $0) }
    }

    private func join() {
        guard !isJoining else { return }
        isJoining = true
        Task {
            let outcome = await model.joinCommunity(id: community.id)
            isJoining = false
            switch outcome {
            case .joined: didJoin()
            case .pending: joinRequestPending = true
            case .failed: break
            }
        }
    }
}

private struct ChannelListView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showLeaveConfirmation = false
    @State private var reportTarget: ReportTarget?
    @State private var showCommunitySettings = false
    @State private var showNotificationSettings = false
    @State private var selectedPlugin: CommunityPluginInfo?
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
            if !community.pluginInfos.isEmpty {
                Section("Community apps") {
                    ForEach(community.pluginInfos) { plugin in
                        Button {
                            selectedPlugin = plugin
                        } label: {
                            HStack {
                                Label(plugin.name, systemImage: "puzzlepiece.extension")
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
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
                    Button("Notification settings", systemImage: "bell.badge") {
                        showNotificationSettings = true
                    }
                    if community.isAdmin {
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
        .sheet(item: $selectedPlugin) { plugin in
            PluginRuntimeView(community: community, plugin: plugin)
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
        .sheet(isPresented: $showNotificationSettings) {
            CommunityNotificationSettingsView(community: community)
        }
    }
}

private struct CommunityNotificationSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let community: Community
    @State private var mentions: Bool
    @State private var replies: Bool
    @State private var posts: Bool
    @State private var events: Bool
    @State private var calls: Bool
    @State private var isSaving = false

    init(community: Community) {
        self.community = community
        let state = community.notificationState
        _mentions = State(initialValue: state.notifyMentions)
        _replies = State(initialValue: state.notifyReplies)
        _posts = State(initialValue: state.notifyPosts)
        _events = State(initialValue: state.notifyEvents)
        _calls = State(initialValue: state.notifyCalls)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Mentions", isOn: $mentions)
                    Toggle("Replies", isOn: $replies)
                    Toggle("New posts", isOn: $posts)
                    Toggle("Events", isOn: $events)
                    Toggle("Calls", isOn: $calls)
                } footer: {
                    Text("These preferences apply to notifications from \(community.title) on this Common Ground instance.")
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(isSaving || !hasChanges)
                }
            }
            .overlay { if isSaving { ProgressView() } }
        }
    }

    private var state: CommunityNotificationState {
        CommunityNotificationState(
            notifyMentions: mentions,
            notifyReplies: replies,
            notifyPosts: posts,
            notifyEvents: events,
            notifyCalls: calls
        )
    }

    private var hasChanges: Bool { state != community.notificationState }

    private func save() {
        isSaving = true
        Task {
            if await model.setCommunityNotifications(communityID: community.id, state: state) {
                dismiss()
            }
            isSaving = false
        }
    }
}

private struct ChatListView: View {
    @EnvironmentObject private var model: AppModel
    let chats: [Chat]
    @ObservedObject var store: SyncStore
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
                            Avatar(
                                name: chat.displayTitle(
                                    excluding: store.ownUser?.id,
                                    users: store.users
                                ),
                                url: chat.primaryParticipant(
                                    excluding: store.ownUser?.id,
                                    users: store.users
                                )?.imageID.flatMap { model.attachmentURLs[$0] },
                                small: true
                            )
                            VStack(alignment: .leading, spacing: 3) {
                                Text(chat.displayTitle(
                                    excluding: store.ownUser?.id,
                                    users: store.users
                                ))
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
        .task(id: chats.flatMap(\.userIds).sorted().joined(separator: ",")) {
            await model.loadChatMembers(chats: chats)
        }
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

private struct TypingIndicatorView: View {
    let userIDs: [String]
    let users: [String: UserProfile]

    private var summary: String {
        let names = userIDs.compactMap { users[$0]?.displayName }
        switch userIDs.count {
        case 0:
            return ""
        case 1:
            return "\(names.first ?? "Someone") is typing…"
        case 2 where names.count == 2:
            return "\(names[0]) and \(names[1]) are typing…"
        case 2:
            return "Two people are typing…"
        default:
            if let first = names.first {
                return "\(first) and \(userIDs.count - 1) others are typing…"
            }
            return "\(userIDs.count) people are typing…"
        }
    }

    var body: some View {
        Label(summary, systemImage: "ellipsis.message.fill")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentTransition(.numericText())
            .accessibilityLabel(summary)
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

    var channel: Channel? {
        if case .channel(let channel) = self { return channel }
        return nil
    }
}

private extension Channel {
    var publicCanRead: Bool {
        roleAccess.contains {
            $0.roleTitle == "Public" && $0.permissions.contains("CHANNEL_READ")
        }
    }

    var publicCanWrite: Bool {
        roleAccess.contains {
            $0.roleTitle == "Public" && $0.permissions.contains("CHANNEL_WRITE")
        }
    }
}

private struct ConversationView: View {
    @EnvironmentObject private var model: AppModel
    let context: ConversationContext
    @ObservedObject var store: SyncStore
    var readOnly = false
    @State private var reportTarget: ReportTarget?
    @State private var moderationMember: ChannelMemberEntry?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var deleteTarget: Message?
    @State private var showMentionPicker = false
    @State private var selectedUser: UserProfile?
    @State private var showParticipants = false
    @State private var showSearch = false
    @State private var showSaved = false
    @State private var showGallery = false
    @State private var showGIFPicker = false
    @State private var threadRoot: Message?
    @GestureState private var participantDrag: CGFloat = 0
    @FocusState private var composerFocused: Bool

    private var messages: [Message] {
        store.orderedMessages(channelId: context.channelID)
    }

    private var typingUserIDs: [String] {
        store.typingUserIDs(for: context.access)
    }

    private var canModerateChannel: Bool {
        guard let channel = context.channel,
              let community = store.communities[channel.communityId] else { return false }
        let ownRoles = Set(community.myRoleIds)
        return community.isAdmin || channel.roleAccess.contains {
            ownRoles.contains($0.roleId) && $0.permissions.contains("CHANNEL_MODERATE")
        }
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
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Search messages", systemImage: "magnifyingglass") { showSearch = true }
                Menu("Conversation options", systemImage: "ellipsis.circle") {
                    Button("Channel participants", systemImage: "person.2") {
                        showParticipants.toggle()
                    }
                    Button("Saved messages", systemImage: "bookmark") { showSaved = true }
                    Button("Media gallery", systemImage: "photo.on.rectangle") { showGallery = true }
                }
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
        .sheet(item: $moderationMember) { member in
            if let channel = context.channel,
               let community = store.communities[channel.communityId] {
                NavigationStack {
                    CommunityMemberModerationView(community: community, member: member)
                }
            }
        }
        .sheet(isPresented: $showMentionPicker) {
            MentionPicker(store: store) { user in
                model.insertMention(user)
                showMentionPicker = false
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showSearch) {
            MessageSearchView(title: context.title, messages: messages, store: store) { id in
                model.focusMessage(id)
                showSearch = false
            }
        }
        .sheet(isPresented: $showSaved) {
            MessageSearchView(
                title: "Saved Messages",
                messages: messages.filter { store.savedMessageIDs.contains($0.id) },
                store: store,
                searchEnabled: false
            ) { id in
                model.focusMessage(id)
                showSaved = false
            }
        }
        .sheet(isPresented: $showGallery) {
            MessageGalleryView(messages: messages)
        }
        .sheet(isPresented: $showGIFPicker) {
            GIFPickerView { gif in
                Task {
                    if await model.selectGIF(gif) {
                        showGIFPicker = false
                    }
                }
            }
        }
        .sheet(item: $threadRoot) { root in
            MessageThreadView(
                root: root,
                replies: messages.filter { $0.parentMessageId == root.id },
                store: store
            ) {
                threadRoot = nil
                model.beginReply(to: root)
            }
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
            if let message = deleteTarget,
               message.creatorId != store.ownUser?.id,
               canModerateChannel {
                Button("Delete all messages from this member", role: .destructive) {
                    deleteTarget = nil
                    Task {
                        await model.deleteAllMessages(
                            by: message.creatorId,
                            access: context.access
                        )
                    }
                }
            }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: {
            Text("This cannot be undone.")
        }
        .onChange(of: model.draftMessage) { _, text in
            guard composerFocused else { return }
            model.updateTyping(access: context.access, text: text)
        }
        .onChange(of: composerFocused) { _, focused in
            if focused {
                model.updateTyping(access: context.access, text: model.draftMessage)
            } else {
                model.stopTyping(access: context.access)
            }
        }
        .onDisappear { model.stopTyping(access: context.access) }
    }

    private var conversationBody: some View {
        let orderedMessages = messages
        let messageIndex = Dictionary(uniqueKeysWithValues: orderedMessages.map { ($0.id, $0) })
        let messageIDs = orderedMessages.map(\.id)
        let firstUnreadID = firstUnreadMessageID(in: orderedMessages)
        return VStack(spacing: 0) {
            if let channel = context.channel, let pins = channel.pinnedMessageIds, !pins.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(pins, id: \.self) { id in
                            if let message = messageIndex[id] {
                                Button {
                                    model.focusMessage(id)
                                } label: {
                                    Label(message.body.plainText, systemImage: "pin.fill")
                                        .lineLimit(1)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 7)
                                        .background(AppTheme.accent.opacity(0.12), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                }
                Divider()
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        if orderedMessages.isEmpty {
                            ContentUnavailableView(
                                "Start the conversation",
                                systemImage: "sparkles",
                                description: Text("Messages sent here are delivered to the selected conversation.")
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 60)
                        }
                        ForEach(orderedMessages) { message in
                            if message.id == firstUnreadID {
                                HStack {
                                    Rectangle().frame(height: 1)
                                    Text("New messages").font(.caption.bold())
                                    Rectangle().frame(height: 1)
                                }
                                .foregroundStyle(AppTheme.accent)
                            }
                            let previewURL = AppModel.firstURL(in: message.body.plainText)
                            let preview = previewURL.flatMap { model.linkPreviews[$0] }
                            MessageRow(
                                message: message,
                                pending: store.pendingMessages[message.id],
                                isOwn: message.creatorId == store.ownUser?.id,
                                author: store.users[message.creatorId],
                                avatarURL: store.users[message.creatorId]?
                                    .imageID
                                    .flatMap { model.attachmentURLs[$0] },
                                parent: message.parentMessageId.flatMap { messageIndex[$0] },
                                attachmentURL: message.imageAttachments.first.flatMap {
                                    model.attachmentURLs[$0.largeImageId] ?? model.attachmentURLs[$0.imageId]
                                },
                                linkPreview: preview,
                                linkPreviewImageURL: preview?.imageId.flatMap { model.attachmentURLs[$0] },
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
                                },
                                canModerate: canModerateChannel,
                                moderate: {
                                    let roles = model.channelMembers[context.channelID]?.all
                                        .first { $0.userId == message.creatorId }?.roleIds ?? []
                                    moderationMember = ChannelMemberEntry(
                                        userId: message.creatorId,
                                        roleIds: roles
                                    )
                                },
                                retry: { Task { await model.retryPendingMessage(message.id) } },
                                discard: { model.discardPendingMessage(message.id) },
                                focusParent: { parentID in model.focusMessage(parentID) },
                                isSaved: store.savedMessageIDs.contains(message.id),
                                toggleSaved: {
                                    model.setMessageSaved(
                                        message,
                                        saved: !store.savedMessageIDs.contains(message.id)
                                    )
                                },
                                isPinned: context.channel?.pinnedMessageIds?.contains(message.id) == true,
                                canPin: canModerateChannel,
                                togglePinned: {
                                    guard let channel = context.channel else { return }
                                    Task {
                                        await model.setMessagePinned(
                                            message,
                                            channel: channel,
                                            pinned: channel.pinnedMessageIds?.contains(message.id) != true
                                        )
                                    }
                                },
                                viewThread: { threadRoot = message }
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
                .onChange(of: messageIDs, initial: true) { _, ids in
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
                .onChange(of: model.focusedMessageID) { _, target in
                    guard let target, messageIDs.contains(target) else { return }
                    withAnimation { proxy.scrollTo(target, anchor: .center) }
                }
            }

            Divider()
            if readOnly {
                Label("This channel is read-only for public visitors.", systemImage: "eye")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(14)
            } else {
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

                if !typingUserIDs.isEmpty {
                    TypingIndicatorView(userIDs: typingUserIDs, users: store.users)
                }

                HStack(alignment: .bottom, spacing: 10) {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Image(systemName: "photo")
                            .frame(width: 34, height: 42)
                    }
                    .disabled(model.editingMessage != nil || model.isUploadingAttachment)
                    .accessibilityLabel("Attach image")

                    if model.instanceConfig?.giphyApiKey?.isEmpty == false {
                        Button("GIF") { showGIFPicker = true }
                            .font(.caption.bold())
                            .frame(width: 34, height: 42)
                            .disabled(model.editingMessage != nil || model.isUploadingAttachment)
                            .accessibilityLabel("Choose a GIF")
                    }

                    Button("Mention someone", systemImage: "at") {
                        showMentionPicker = true
                    }
                    .labelStyle(.iconOnly)
                    .frame(width: 30, height: 42)

                    TextField(context.composerPrompt, text: $model.draftMessage, axis: .vertical)
                        .lineLimit(1...5)
                        .focused($composerFocused)
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
    }

    private func firstUnreadMessageID(in messages: [Message]) -> String? {
        guard let lastRead = context.channel?.lastRead,
              let lastReadDate = Self.parseDate(lastRead) else { return nil }
        return messages.first { message in
            Self.parseDate(message.createdAt).map { $0 > lastReadDate } ?? false
        }?.id
    }

    private static func parseDate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
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
                        || (entry.userId == store.ownUser?.id && model.isRealtimeAuthenticated),
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
                        ? model.isRealtimeAuthenticated
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

private struct MessageSearchView: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let messages: [Message]
    @ObservedObject var store: SyncStore
    var searchEnabled = true
    let select: (String) -> Void
    @State private var query = ""

    private var results: [Message] {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard searchEnabled && !value.isEmpty else { return Array(messages.reversed()) }
        return Array(messages.filter {
            $0.body.plainText.localizedCaseInsensitiveContains(value)
                || (store.users[$0.creatorId]?.displayName.localizedCaseInsensitiveContains(value) ?? false)
        }.reversed())
    }

    var body: some View {
        NavigationStack {
            List(results) { message in
                Button {
                    select(message.id)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.users[message.creatorId]?.displayName ?? "Member")
                            .font(.caption.bold())
                            .foregroundStyle(AppTheme.accent)
                        Text(message.body.plainText).lineLimit(3).foregroundStyle(.primary)
                    }
                }
            }
            .overlay {
                if results.isEmpty {
                    ContentUnavailableView(
                        searchEnabled ? "No matching messages" : "No saved messages",
                        systemImage: searchEnabled ? "magnifyingglass" : "bookmark"
                    )
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .searchable(text: $query, prompt: "Search messages")
        }
    }
}

private struct MessageGalleryView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let messages: [Message]

    private var attachments: [MessageImageAttachment] {
        messages.flatMap(\.imageAttachments)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 3)], spacing: 3) {
                    ForEach(Array(attachments.enumerated()), id: \.offset) { _, attachment in
                        let url = model.attachmentURLs[attachment.largeImageId]
                            ?? model.attachmentURLs[attachment.imageId]
                        AsyncImage(url: url) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Color.secondary.opacity(0.1).overlay { ProgressView() }
                        }
                        .frame(minHeight: 140)
                        .aspectRatio(1, contentMode: .fill)
                        .clipped()
                    }
                }
            }
            .overlay {
                if attachments.isEmpty {
                    ContentUnavailableView("No shared images", systemImage: "photo.on.rectangle")
                }
            }
            .navigationTitle("Media")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

private struct GIFPickerView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    let select: (GIFSearchResult) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 116), spacing: 8)
    ]

    var body: some View {
        NavigationStack {
            Group {
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView(
                        "Find a GIF",
                        systemImage: "sparkles.rectangle.stack",
                        description: Text("Search GIPHY, then tap a result to attach it to your message.")
                    )
                } else if model.gifResults.isEmpty && !model.isSearchingGIFs {
                    ContentUnavailableView.search(text: query)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(model.gifResults) { gif in
                                Button { select(gif) } label: {
                                    AsyncImage(url: gif.previewURL) { phase in
                                        switch phase {
                                        case .success(let image):
                                            image.resizable().scaledToFill()
                                        case .failure:
                                            Color.secondary.opacity(0.12)
                                                .overlay { Image(systemName: "photo.badge.exclamationmark") }
                                        default:
                                            Color.secondary.opacity(0.08)
                                                .overlay { ProgressView() }
                                        }
                                    }
                                    .frame(height: 116)
                                    .frame(maxWidth: .infinity)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(gif.title.isEmpty ? "GIF result" : gif.title)
                            }
                        }
                        .padding()
                    }
                }
            }
            .overlay {
                if model.isSearchingGIFs { ProgressView().controlSize(.large) }
            }
            .safeAreaInset(edge: .bottom) {
                Text("Powered by GIPHY")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(.bar)
            }
            .navigationTitle("GIFs")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Search GIPHY")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task(id: query) {
                guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    await model.searchGIFs(query: "")
                    return
                }
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                await model.searchGIFs(query: query)
            }
        }
    }
}

private struct MessageThreadView: View {
    @Environment(\.dismiss) private var dismiss
    let root: Message
    let replies: [Message]
    @ObservedObject var store: SyncStore
    let reply: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Original message") {
                    threadRow(root)
                }
                Section("Replies · \(replies.count)") {
                    if replies.isEmpty {
                        Text("No replies yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(replies) { message in threadRow(message) }
                    }
                }
            }
            .navigationTitle("Thread")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Button {
                    dismiss()
                    reply()
                } label: {
                    Label("Reply in thread", systemImage: "arrowshape.turn.up.left")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
                .padding()
                .background(.bar)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func threadRow(_ message: Message) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(store.users[message.creatorId]?.displayName ?? "Member")
                    .font(.subheadline.bold())
                Spacer()
                Text(message.createdAt)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(message.body.plainText)
                .textSelection(.enabled)
        }
        .padding(.vertical, 4)
    }
}

private struct MessageRow: View {
    let message: Message
    let pending: PendingMessage?
    let isOwn: Bool
    let author: UserProfile?
    let avatarURL: URL?
    let parent: Message?
    let attachmentURL: URL?
    let linkPreview: URLPreview?
    let linkPreviewImageURL: URL?
    let openProfile: () -> Void
    let reply: () -> Void
    let edit: () -> Void
    let delete: () -> Void
    let react: (String?) -> Void
    let report: () -> Void
    let canModerate: Bool
    let moderate: () -> Void
    let retry: () -> Void
    let discard: () -> Void
    let focusParent: (String) -> Void
    let isSaved: Bool
    let toggleSaved: () -> Void
    let isPinned: Bool
    let canPin: Bool
    let togglePinned: () -> Void
    let viewThread: () -> Void

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
                    if let pending {
                        Label(
                            pending.state == .sending ? "Sending" : pending.state == .failed ? "Failed" : "Queued",
                            systemImage: pending.state == .sending
                                ? "arrow.up.circle"
                                : pending.state == .failed ? "exclamationmark.circle" : "clock"
                        )
                        .font(.caption2)
                        .foregroundStyle(pending.state == .failed ? .red : .secondary)
                    }
                }
                if let parent {
                    Button {
                        focusParent(parent.id)
                    } label: {
                        HStack(spacing: 6) {
                            Rectangle().fill(AppTheme.accent).frame(width: 2)
                            Text(parent.body.plainText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 2)
                } else if message.parentMessageId != nil {
                    Label("Earlier message", systemImage: "arrowshape.turn.up.left")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(message.body.plainText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let linkPreview, let destination = URL(string: linkPreview.url) {
                    Link(destination: destination) {
                        HStack(spacing: 12) {
                            if let linkPreviewImageURL {
                                AsyncImage(url: linkPreviewImageURL) { image in
                                    image.resizable().scaledToFill()
                                } placeholder: {
                                    Color.secondary.opacity(0.1)
                                }
                                .frame(width: 82, height: 72)
                                .clipped()
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(linkPreview.title).font(.subheadline.bold()).lineLimit(2)
                                Text(linkPreview.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                Text(destination.host ?? destination.absoluteString)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(10)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
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
            if pending != nil {
                Button("Try sending again", systemImage: "arrow.clockwise", action: retry)
                Button("Discard message", systemImage: "trash", role: .destructive, action: discard)
            } else {
                Button("Reply", systemImage: "arrowshape.turn.up.left", action: reply)
                Button("View replies", systemImage: "bubble.left.and.bubble.right", action: viewThread)
                Button(isSaved ? "Remove from Saved" : "Save Message", systemImage: isSaved ? "bookmark.slash" : "bookmark", action: toggleSaved)
                if canPin {
                    Button(isPinned ? "Unpin Message" : "Pin Message", systemImage: isPinned ? "pin.slash" : "pin", action: togglePinned)
                }
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
                    if canModerate {
                        Button("Moderate member", systemImage: "person.badge.shield.checkmark", action: moderate)
                        Button("Delete message", systemImage: "trash", role: .destructive, action: delete)
                    }
                    Button("Report message", systemImage: "exclamationmark.bubble", role: .destructive) {
                        report()
                    }
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

                Section {
                    LabeledContent {
                        Text(
                            (store.ownUser?.pointBalance ?? 0)
                                .formatted(.number.precision(.fractionLength(0)))
                        )
                        .fontWeight(.semibold)
                    } label: {
                        Label("Available balance", systemImage: "sparkles")
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("Spark")
                } footer: {
                    Text("Spark is Common Ground’s off-chain currency for supporting and upgrading communities.")
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
                    if let supportURL = URL(string: "mailto:\(AppConfiguration.supportEmail)") {
                        Link("Contact support", destination: supportURL)
                    }
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
    var size: CGFloat = 30
    @State private var retryID = 0
    private let maximumAutomaticRetries = 3

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .empty:
                        fallback
                    case .failure:
                        fallback
                            .task(id: retryID) {
                                guard retryID < maximumAutomaticRetries else { return }
                                try? await Task.sleep(
                                    for: .milliseconds(Int64(200 * (retryID + 1)))
                                )
                                guard !Task.isCancelled else { return }
                                retryID += 1
                            }
                    @unknown default:
                        fallback
                    }
                }
                .id("\(url.absoluteString):\(retryID)")
            } else {
                fallback
            }
        }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.26))
            .accessibilityHidden(true)
            .onChange(of: url) { retryID = 0 }
    }

    private var fallback: some View {
        Text(String(name.prefix(1)).uppercased())
            .font(.caption.bold())
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(.white)
            .background(AppTheme.accent.gradient)
    }
}

private struct FeedPostImage: View {
    let url: URL
    @State private var retryID = 0
    private let maximumAutomaticRetries = 3

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
            case .empty:
                placeholder
                    .overlay { ProgressView() }
            case .failure:
                placeholder
                    .overlay {
                        if retryID < maximumAutomaticRetries {
                            ProgressView()
                                .task(id: retryID) {
                                    try? await Task.sleep(
                                        for: .milliseconds(Int64(250 * (retryID + 1)))
                                    )
                                    guard !Task.isCancelled else { return }
                                    retryID += 1
                                }
                        } else {
                            VStack(spacing: 6) {
                                Image(systemName: "photo.badge.exclamationmark")
                                    .font(.title2)
                                Text("Image unavailable")
                                    .font(.caption)
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
            @unknown default:
                EmptyView()
            }
        }
        .id("\(url.absoluteString):\(retryID)")
        .frame(maxWidth: .infinity)
        .background(Color.secondary.opacity(0.08))
        .accessibilityLabel("Article image")
        .onChange(of: url) { retryID = 0 }
    }

    private var placeholder: some View {
        Color.secondary.opacity(0.08)
            .aspectRatio(4 / 3, contentMode: .fit)
            .frame(maxWidth: .infinity)
    }
}

private struct CommunityFeatureImage: View {
    let url: URL
    let height: CGFloat
    @State private var retryID = 0
    private let maximumAutomaticRetries = 3

    var body: some View {
        GeometryReader { proxy in
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: proxy.size.width, height: height)
                        .clipped()
                case .empty:
                    Color.secondary.opacity(0.08)
                case .failure:
                    Group {
                        if retryID < maximumAutomaticRetries {
                            ProgressView()
                                .task(id: retryID) {
                                    try? await Task.sleep(
                                        for: .milliseconds(Int64(250 * (retryID + 1)))
                                    )
                                    guard !Task.isCancelled else { return }
                                    retryID += 1
                                }
                        } else {
                            VStack(spacing: 6) {
                                Image(systemName: "photo.badge.exclamationmark")
                                    .font(.title2)
                                Text("Image unavailable")
                                    .font(.caption)
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: proxy.size.width, height: height)
                @unknown default:
                    Color.clear
                }
            }
            .id("\(url.absoluteString):\(retryID)")
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityLabel("Community image")
        .onChange(of: url) { retryID = 0 }
    }
}

private enum MarkdownHeadingStyle {
    case article
    case social
}

private struct MarkdownArticleText: View {
    let source: String
    var headingStyle: MarkdownHeadingStyle = .article

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(MarkdownArticleBlock.parse(source)) { block in
                switch block.kind {
                case .paragraph:
                    inlineText(block.text)
                case .heading(let level):
                    inlineText(block.text)
                        .font(headingStyle == .social ? .body.bold() : headerFont(level))
                        .padding(.top, headingStyle == .social ? 3 : (level <= 2 ? 8 : 3))
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
    func primaryParticipant(
        excluding ownUserID: String?,
        users: [String: UserProfile]
    ) -> UserProfile? {
        userIds.lazy
            .filter { $0 != ownUserID }
            .compactMap { users[$0] }
            .first
    }

    func displayTitle(
        excluding ownUserID: String?,
        users: [String: UserProfile]
    ) -> String {
        let others = userIds.filter { $0 != ownUserID }
        guard !others.isEmpty else { return "Direct message" }
        return others.map { users[$0]?.displayName ?? "Member \($0.prefix(4))" }
            .joined(separator: ", ")
    }
}
