import CommonGroundKit
import PhotosUI
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
    case discover
    case community(String)
}

private struct ReportTarget: Identifiable {
    let type: ReportType
    let id: String
    let subject: String
}

private struct HomeContent: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var store: SyncStore
    @State private var sidebarSelection: SidebarItem? = .overview
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar
    @State private var showAccount = false
    @State private var showCreateCommunity = false

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
                            CommunityMark(name: community.title)
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
            NotificationsView(store: store)
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
    let community: CommunitySummary
    let isJoined: Bool
    let isJoining: Bool
    let open: () -> Void
    let join: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            CommunityMark(name: community.title)
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
                Section("Tags") {
                    TextField("swift, design, berlin", text: $tags)
                    Text("Separate tags with commas. You can update imagery and richer settings later.")
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
                        .disabled(trimmedTitle.isEmpty || isCreating)
                }
            }
            .overlay { if isCreating { ProgressView() } }
        }
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func create() {
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
                tags: Array(normalizedTags.prefix(10))
            ) {
                created(community.id)
            }
            isCreating = false
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

    private var articles: [CommunityArticlePreview] {
        model.communityArticles[community.id] ?? []
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 7) {
                    CommunityMark(name: community.title)
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
                    Image(systemName: "newspaper").foregroundStyle(AppTheme.accent)
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
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(community.title)
        .refreshable { await model.loadCommunityArticles(communityID: community.id) }
        .task(id: community.id) { await model.loadCommunityArticles(communityID: community.id) }
        .sheet(item: $selectedArticle) { article in
            ArticleReaderView(articleID: article.id, source: .community(community.id), store: store)
        }
    }
}

private enum ArticleSource {
    case community(String)
    case user(String)
}

private struct ArticleCard: View {
    let article: ArticlePreview
    let author: UserProfile?
    let imageURL: URL?
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
                    Text(article.title).font(.headline).foregroundStyle(.primary)
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
    let source: ArticleSource
    @ObservedObject var store: SyncStore

    private var article: ArticleDetail? { model.articleDetails[articleID] }

    var body: some View {
        NavigationStack {
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
                                    small: true
                                )
                                Text(creator.displayName).fontWeight(.semibold)
                            }
                        }
                        if let preview = article.previewText, !preview.isEmpty {
                            Text(preview).font(.title3).foregroundStyle(.secondary)
                        }
                        Divider()
                        Text(article.plainText)
                            .font(.body)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if !article.tags.isEmpty {
                            Text(article.tags.map { "#\($0)" }.joined(separator: "  "))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: 720, alignment: .leading)
                    .padding(24)
                    .frame(maxWidth: .infinity)
                } else {
                    ProgressView("Loading article…").padding(50)
                }
            }
            .navigationTitle("Article")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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
            }
        }
    }
}

private struct ChannelListView: View {
    @State private var showLeaveConfirmation = false
    @State private var reportTarget: ReportTarget?
    let community: Community
    let selectedChannelID: String?
    let openHome: () -> Void
    let select: (String) -> Void
    let leave: () -> Void

    var body: some View {
        List {
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
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle(community.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
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
    @State private var reportTarget: ReportTarget?
    @State private var selectedArticle: ArticlePreview?
    @State private var showComposer = false

    private var user: UserProfile? { store.users[userID] }
    private var articles: [UserArticlePreview] { model.userArticles[userID] ?? [] }
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
                            url: user.imageID.flatMap { model.attachmentURLs[$0] }
                        )
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
            .task(id: userID) { await model.loadUserProfile(userID: userID) }
            .toolbar {
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
                ArticleReaderView(articleID: article.id, source: .user(userID), store: store)
            }
            .sheet(isPresented: $showComposer) {
                UserArticleComposer {
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
        .navigationTitle(context.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: context.channelID) { await load() }
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
                                Avatar(name: user.displayName, small: true)
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
                Avatar(name: author?.displayName ?? (isOwn ? "You" : "Member"), url: avatarURL, small: true)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Button(action: openProfile) {
                        Text(author?.displayName ?? (isOwn ? "You" : "Member"))
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.plain)
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

private struct UserArticleComposer: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let didPublish: () -> Void
    @State private var title = ""
    @State private var preview = ""
    @State private var bodyText = ""
    @State private var tags = ""
    @State private var isPublishing = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Article") {
                    TextField("Title", text: $title)
                    TextField("Short preview", text: $preview, axis: .vertical)
                    TextField("Write your article…", text: $bodyText, axis: .vertical)
                        .lineLimit(8...20)
                }
                Section("Tags") {
                    TextField("Comma-separated tags", text: $tags)
                        .textInputAutocapitalization(.never)
                }
                Section {
                    Label(
                        "This first native editor publishes plain text. Rich blocks and images can be added without changing the article API.",
                        systemImage: "info.circle"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("New Article")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Publish") {
                        isPublishing = true
                        Task {
                            let parsedTags = tags.split(separator: ",")
                                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                .filter { !$0.isEmpty }
                            if await model.publishUserArticle(
                                title: title,
                                preview: preview,
                                text: bodyText,
                                tags: parsedTags
                            ) {
                                didPublish()
                                dismiss()
                            }
                            isPublishing = false
                        }
                    }
                    .disabled(
                        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || isPublishing
                    )
                }
            }
            .overlay { if isPublishing { ProgressView() } }
        }
    }
}

private struct Avatar: View {
    let name: String
    var url: URL? = nil
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
        Text(String(name.prefix(2)).uppercased())
            .font(small ? .caption.bold() : .subheadline.bold())
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
