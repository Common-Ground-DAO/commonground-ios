import CommonGroundKit
import Foundation
import SwiftUI

enum CommunityJoinOutcome {
    case joined
    case pending
    case failed
}

enum ArticleOwner: Equatable {
    case community(String)
    case user(String)
}

enum AppearancePreference: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    enum Phase { case instance, authentication, home }

    @Published var phase: Phase = .instance
    @Published var instanceInput = UserDefaults.standard.string(forKey: Keys.instance) ?? AppConfiguration.defaultInstanceURL
    @Published var instanceConfig: InstanceConfig?
    @Published var isWorking = false
    @Published var activity = ""
    @Published var errorMessage: String?
    @Published var realtimeNotice: String?
    @Published var selectedCommunityID: String?
    @Published var selectedChannelID: String?
    @Published var selectedChatID: String?
    @Published var focusedMessageID: String?
    @Published var inAppNotification: AppNotification?
    @Published var draftMessage = "" {
        didSet { scheduleDraftPersistence() }
    }
    @Published private(set) var draftMentions: [String: String] = [:]
    @Published var replyingTo: Message?
    @Published var editingMessage: Message?
    @Published var pendingImageAttachment: MessageImageAttachment?
    @Published var isUploadingAttachment = false
    @Published private(set) var attachmentURLs: [String: URL] = [:]
    private var attachmentURLExpirations: [String: Date] = [:]
    @Published var isLoadingNotifications = false
    @Published var isSearchingUsers = false
    @Published private(set) var userSearchResultIDs: [String] = []
    @Published var isLoadingCommunities = false
    @Published private(set) var isRefreshingHome = false
    @Published private(set) var communityResults: [CommunitySummary] = []
    @Published private(set) var communityArticles: [String: [CommunityArticlePreview]] = [:]
    @Published private(set) var communityArticleDrafts: [String: [CommunityArticlePreview]] = [:]
    @Published private(set) var userArticles: [String: [UserArticlePreview]] = [:]
    @Published private(set) var userArticleDrafts: [String: [UserArticlePreview]] = [:]
    @Published private(set) var articleDetails: [String: ArticleDetail] = [:]
    @Published private(set) var articleDraftIDs: Set<String> = []
    @Published private(set) var articlePublishedAt: [String: String] = [:]
    @Published private(set) var articleRolePermissions: [String: [ArticleRolePermission]] = [:]
    @Published private(set) var profileDetails: [String: UserProfileDetails] = [:]
    @Published private(set) var channelMembers: [String: ChannelMemberList] = [:]
    @Published private(set) var communityMemberLists: [String: CommunityMemberList] = [:]
    @Published private(set) var communityBans: [String: [CommunityBan]] = [:]
    @Published private(set) var communityPendingApprovals: [String: [CommunityPendingApproval]] = [:]
    @Published var appearance = AppearancePreference(
        rawValue: UserDefaults.standard.string(forKey: "appearancePreference") ?? ""
    ) ?? .system {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: "appearancePreference") }
    }

    let store = SyncStore()
    private(set) var client: CommonGroundClient?
    private var signingKey: (any DeviceSigningKey)?
    private var realtime: RealtimeClient?
    private var notificationListenerID: UUID?
    private var realtimeStatusListenerID: UUID?
    private var realtimeRefreshTask: Task<Void, Never>?
    private var offlineDatabase: OfflineDatabase?
    private var draftPersistenceTask: Task<Void, Never>?
    private var isRestoringDraft = false
    private var isFlushingOutbox = false
    private var notificationDismissTask: Task<Void, Never>?
    private var presentedNotificationIDs: Set<String> = []
    private var didAttemptLaunchRestore = false

    var savedDeviceID: String? {
        guard let instance = try? InstanceURL(instanceInput) else { return nil }
        return savedDeviceID(for: instance)
    }

    var instanceHost: String {
        client?.instance.url.host ?? "Common Ground"
    }

    func communityShareURL(_ community: Community) -> URL? {
        guard let baseURL = client?.instance.url else { return nil }
        return baseURL.appending(path: "c").appending(path: community.url)
    }

    func effectiveOnlineStatus(for user: UserProfile) -> String {
        if user.id == store.ownUser?.id, realtimeNotice == nil { return "online" }
        return user.onlineStatus
    }

    func refreshHome() async {
        guard !isRefreshingHome,
              let client,
              let signingKey,
              let deviceID = savedDeviceID else { return }
        isRefreshingHome = true
        defer { isRefreshingHome = false }
        do {
            let session = try await client.auth.loginWithDevice(
                deviceId: deviceID,
                deviceKey: signingKey
            )
            store.hydrate(from: session.response)
            saveCachedResponse(session.response, for: client.instance)
            await hydrateUsers(ids: [session.response.ownData.id])
            await refreshCommunityPresentation(
                communityIDs: session.response.communities.map(\.id)
            )
            let communityIDs = Set(session.response.communities.map(\.id))
            if let selectedCommunityID, !communityIDs.contains(selectedCommunityID) {
                selectCommunity(nil)
                selectChannel(nil)
            }
            if realtime?.connected != true {
                removeRealtimeListeners()
                realtime?.close()
                realtime = nil
                await startRealtime(session)
            }
            await flushPendingMessages()
            realtimeNotice = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = userMessage(for: error)
        }
    }

    func restoreOnLaunch() async {
        guard !didAttemptLaunchRestore else { return }
        didAttemptLaunchRestore = true
        guard UserDefaults.standard.string(forKey: Keys.instance) != nil else { return }
        await connect()
    }

    func connect() async {
        await perform(activity: "Checking this Common Ground…") {
            let instance = try InstanceURL(instanceInput)
            let client = CommonGroundClient(instance: instance)
            self.client = client
            self.instanceInput = instance.description
            UserDefaults.standard.set(instance.description, forKey: Keys.instance)
            let signingKey = try DeviceKeyStore.loadOrCreate(for: instance)
            self.signingKey = signingKey
            do {
                self.instanceConfig = try await client.instanceAPI.config()
            } catch {
                if let deviceID = self.savedDeviceID(for: instance),
                   let response = self.cachedResponse(for: instance) {
                    self.realtimeNotice = "Offline — showing saved content."
                    await self.didAuthenticate(
                        AuthSession(response: response, deviceId: deviceID, deviceKey: signingKey),
                        offline: true
                    )
                    return
                }
                throw error
            }
            if !(await self.restoreSession(client: client, signingKey: signingKey)) {
                self.phase = .authentication
            }
        }
    }

    func signIn(alias: String, password: String) async {
        await perform(activity: "Signing in…", authentication: true) {
            guard let client, let signingKey else { throw AppError.noInstance }
            let preparation = try await self.preparePasswordLogin(
                client: client,
                signingKey: signingKey
            )
            let session = try await client.auth.loginWithPassword(
                aliasOrEmail: alias,
                password: password,
                deviceKey: preparation.deviceKey
            )
            if let retirementClient = preparation.retirementClient {
                try? await retirementClient.auth.logout()
                await retirementClient.transport.clearCookies()
            }
            await self.didAuthenticate(session)
        }
    }

    func register(email: String, password: String, displayName: String) async {
        await perform(activity: "Solving the privacy-friendly challenge…", authentication: true) {
            guard let client, let signingKey else { throw AppError.noInstance }
            let session = try await client.auth.register(
                email: email,
                password: password,
                displayName: displayName,
                deviceKey: signingKey
            )
            await self.didAuthenticate(session)
        }
    }

    func continueWithDevice() async {
        await perform(activity: "Signing with this device…", authentication: true) {
            guard let client, let signingKey, let deviceID = savedDeviceID else {
                throw AppError.noSavedDevice
            }
            do {
                let session = try await client.auth.loginWithDevice(
                    deviceId: deviceID,
                    deviceKey: signingKey
                )
                await self.didAuthenticate(session)
            } catch let error as APIError where Self.isStaleDeviceError(error) {
                _ = try self.resetLocalDeviceIdentity(for: client.instance)
                throw AppError.savedDeviceExpired
            }
        }
    }

    func loadMessages(channel: Channel, focusing messageID: String? = nil) async {
        await loadMessages(
            access: .community(channel.communityId, channelId: channel.channelId),
            channelID: channel.channelId,
            focusing: messageID
        )
    }

    func loadMessages(chat: Chat, focusing messageID: String? = nil) async {
        await loadMessages(
            access: .chat(chat.id, channelId: chat.channelId),
            channelID: chat.channelId,
            focusing: messageID
        )
    }

    func sendMessage(channel: Channel) async {
        await sendMessage(
            access: .community(channel.communityId, channelId: channel.channelId)
        )
    }

    func sendMessage(chat: Chat) async {
        await sendMessage(access: .chat(chat.id, channelId: chat.channelId))
    }

    func selectCommunity(_ id: String?) {
        if selectedCommunityID != id {
            persistCurrentDraftImmediately()
            resetComposerContext()
            focusedMessageID = nil
            selectedChannelID = nil
            selectedChatID = nil
            restoreDraft(for: nil)
        }
        selectedCommunityID = id
        guard let client else { return }
        UserDefaults.standard.set(id, forKey: Keys.communityID(client.instance))
        UserDefaults.standard.removeObject(forKey: Keys.channelID(client.instance))
    }

    func selectChannel(_ id: String?) {
        persistCurrentDraftImmediately()
        resetComposerContext()
        focusedMessageID = nil
        selectedChannelID = id
        selectedChatID = nil
        restoreDraft(for: id.map { "channel:\($0)" })
        guard let client else { return }
        UserDefaults.standard.set(id, forKey: Keys.channelID(client.instance))
    }

    func selectChat(_ id: String?) {
        persistCurrentDraftImmediately()
        resetComposerContext()
        focusedMessageID = nil
        selectedChatID = id
        selectedChannelID = nil
        restoreDraft(for: id.map { "chat:\($0)" })
        guard let client else { return }
        UserDefaults.standard.set(id, forKey: Keys.chatID(client.instance))
    }

    func loadNotifications() async {
        guard let client, !isLoadingNotifications else { return }
        isLoadingNotifications = true
        defer { isLoadingNotifications = false }
        do {
            let notifications = try await client.notifications.load()
            let unreadCount = try await client.notifications.unreadCount()
            store.replaceNotifications(notifications, unreadCount: unreadCount)
            var userIDs = Set(notifications.compactMap(\.subjectUserId))
            if let ownUserID = store.ownUser?.id { userIDs.insert(ownUserID) }
            if !userIDs.isEmpty {
                store.seed(users: try await client.profiles.users(ids: Array(userIDs)))
            }
        } catch is CancellationError {
            return
        } catch {
            errorMessage = userMessage(for: error)
        }
    }

    func markNotificationRead(_ id: String) async {
        guard let notification = store.notifications[id], !notification.read else { return }
        guard notification.isPersisted else {
            store.markNotificationRead(id)
            return
        }
        guard let client else { return }
        do {
            try await client.notifications.markAsRead(id)
            store.markNotificationRead(id)
        } catch {
            errorMessage = userMessage(for: error)
        }
    }

    func focusMessage(_ id: String?) {
        focusedMessageID = id
    }

    func dismissInAppNotification() {
        notificationDismissTask?.cancel()
        notificationDismissTask = nil
        inAppNotification = nil
    }

    func markAllNotificationsRead() async {
        guard let client, store.unreadNotificationCount > 0 else { return }
        do {
            try await client.notifications.markAllAsRead()
            store.markAllNotificationsRead()
        } catch {
            errorMessage = userMessage(for: error)
        }
    }

    func searchUsers(query: String) async {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, let client else {
            userSearchResultIDs = []
            return
        }
        isSearchingUsers = true
        defer { isSearchingUsers = false }
        do {
            let hits = try await client.profiles.searchUsers(query: value)
            let ids = hits.map(\.id)
            if !ids.isEmpty { store.seed(users: try await client.profiles.users(ids: ids)) }
            userSearchResultIDs = ids
        } catch is CancellationError {
            return
        } catch {
            userSearchResultIDs = []
            errorMessage = userMessage(for: error)
        }
    }

    func setFollowing(userID: String, following: Bool) async {
        guard let client else { return }
        do {
            if following {
                try await client.profiles.follow(userID: userID)
            } else {
                try await client.profiles.unfollow(userID: userID)
            }
            store.setFollowing(userID: userID, isFollowed: following)
        } catch {
            errorMessage = userMessage(for: error)
        }
    }

    func loadUserProfile(userID: String) async {
        guard let client else { return }
        do {
            await hydrateUsers(ids: [userID])
            async let details = client.profiles.details(userID: userID)
            async let articles = client.articles.userArticles(userID: userID)
            profileDetails[userID] = try await details
            userArticles[userID] = try await articles
            for item in userArticles[userID] ?? [] {
                if let published = item.userArticle.published {
                    articlePublishedAt[item.id] = published
                }
            }
            if userID == store.ownUser?.id,
               let drafts = try? await client.articles.userArticles(userID: userID, drafts: true) {
                articleDraftIDs.subtract((userArticleDrafts[userID] ?? []).map(\.id))
                userArticleDrafts[userID] = drafts
                articleDraftIDs.formUnion(drafts.map(\.id))
                for item in drafts { articlePublishedAt.removeValue(forKey: item.id) }
            }
            await loadAttachmentURLs(
                objectIDs: (userArticles[userID] ?? []).compactMap(\.article.thumbnailImageId)
                    + (userArticleDrafts[userID] ?? []).compactMap(\.article.thumbnailImageId)
            )
        } catch is CancellationError {
            return
        } catch {
            errorMessage = userMessage(for: error)
        }
    }

    func loadCommunityArticles(communityID: String) async {
        guard let client else { return }
        do {
            let results = try await client.articles.communityArticles(communityID: communityID)
            communityArticles[communityID] = results
            for item in results {
                if let published = item.communityArticle.published {
                    articlePublishedAt[item.id] = published
                }
            }
            var allResults = results
            if store.communities[communityID]?.canManageArticles == true,
               let drafts = try? await client.articles.communityArticles(
                   communityID: communityID,
                   drafts: true
               ) {
                articleDraftIDs.subtract((communityArticleDrafts[communityID] ?? []).map(\.id))
                communityArticleDrafts[communityID] = drafts
                articleDraftIDs.formUnion(drafts.map(\.id))
                for item in drafts { articlePublishedAt.removeValue(forKey: item.id) }
                for item in drafts { articleRolePermissions[item.id] = item.communityArticle.rolePermissions }
                allResults += drafts
            }
            for item in results { articleRolePermissions[item.id] = item.communityArticle.rolePermissions }
            await hydrateUsers(ids: allResults.map(\.article.creatorId))
            await loadAttachmentURLs(objectIDs: allResults.compactMap(\.article.thumbnailImageId))
        } catch is CancellationError {
            return
        } catch {
            errorMessage = userMessage(for: error)
        }
    }

    func loadCommunityArticle(communityID: String, articleID: String) async {
        guard let client else { return }
        do {
            let result = try await client.articles.communityArticle(
                communityID: communityID,
                articleID: articleID
            )
            articleDetails[articleID] = result.article
            articleRolePermissions[articleID] = result.communityArticle.rolePermissions
            if let published = result.communityArticle.published {
                articleDraftIDs.remove(articleID)
                articlePublishedAt[articleID] = published
            } else {
                articleDraftIDs.insert(articleID)
                articlePublishedAt.removeValue(forKey: articleID)
            }
            await hydrateUsers(ids: [result.article.creatorId])
            await loadAttachmentURLs(objectIDs: [result.article.headerImageId].compactMap { $0 })
        } catch {
            errorMessage = userMessage(for: error)
        }
    }

    func loadUserArticle(userID: String, articleID: String) async {
        guard let client else { return }
        do {
            let result = try await client.articles.userArticle(userID: userID, articleID: articleID)
            articleDetails[articleID] = result.article
            if let published = result.userArticle.published {
                articleDraftIDs.remove(articleID)
                articlePublishedAt[articleID] = published
            } else {
                articleDraftIDs.insert(articleID)
                articlePublishedAt.removeValue(forKey: articleID)
            }
            await loadAttachmentURLs(objectIDs: [result.article.headerImageId].compactMap { $0 })
        } catch {
            errorMessage = userMessage(for: error)
        }
    }

    func createUserArticle(
        title: String,
        preview: String,
        text: String,
        tags: [String],
        publish: Bool
    ) async -> UserArticleDetail? {
        guard let client, let userID = store.ownUser?.id else { return nil }
        do {
            let created = try await client.articles.createUserArticle(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                previewText: preview.trimmingCharacters(in: .whitespacesAndNewlines),
                text: text,
                tags: tags,
                published: publish ? ISO8601DateFormatter().string(from: Date()) : nil
            )
            if publish {
                userArticles[userID] = [created.preview]
                    + (userArticles[userID] ?? []).filter { $0.id != created.preview.id }
                articleDraftIDs.remove(created.article.articleId)
                if let published = created.userArticle.published {
                    articlePublishedAt[created.article.articleId] = published
                }
            } else {
                userArticleDrafts[userID] = [created.preview]
                    + (userArticleDrafts[userID] ?? []).filter { $0.id != created.preview.id }
                articleDraftIDs.insert(created.article.articleId)
                articlePublishedAt.removeValue(forKey: created.article.articleId)
            }
            articleDetails[created.article.articleId] = created.article
            return created
        } catch {
            errorMessage = userMessage(for: error)
            return nil
        }
    }

    func createCommunityArticle(
        community: Community,
        title: String,
        preview: String,
        text: String,
        tags: [String],
        publish: Bool
    ) async -> CommunityArticleDetail? {
        guard let client, community.canManageArticles else { return nil }
        let permissions = community.defaultArticleRolePermissions
        guard !permissions.isEmpty else {
            errorMessage = "This community has no Public or Member role for article visibility."
            return nil
        }
        do {
            let created = try await client.articles.createCommunityArticle(
                communityID: community.id,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                previewText: preview.trimmingCharacters(in: .whitespacesAndNewlines),
                text: text,
                tags: tags,
                rolePermissions: permissions,
                published: publish ? ISO8601DateFormatter().string(from: Date()) : nil
            )
            articleDetails[created.article.articleId] = created.article
            articleRolePermissions[created.article.articleId] = created.communityArticle.rolePermissions
            if publish {
                communityArticles[community.id] = [created.preview]
                    + (communityArticles[community.id] ?? []).filter { $0.id != created.preview.id }
                articleDraftIDs.remove(created.article.articleId)
                if let published = created.communityArticle.published {
                    articlePublishedAt[created.article.articleId] = published
                }
            } else {
                communityArticleDrafts[community.id] = [created.preview]
                    + (communityArticleDrafts[community.id] ?? []).filter { $0.id != created.preview.id }
                articleDraftIDs.insert(created.article.articleId)
                articlePublishedAt.removeValue(forKey: created.article.articleId)
            }
            return created
        } catch {
            errorMessage = userMessage(for: error)
            return nil
        }
    }

    func updateArticle(
        owner: ArticleOwner,
        articleID: String,
        title: String,
        preview: String,
        text: String,
        tags: [String],
        publish: Bool
    ) async -> Bool {
        guard let client else { return false }
        let published = publish
            ? (articlePublishedAt[articleID] ?? ISO8601DateFormatter().string(from: Date()))
            : nil
        do {
            switch owner {
            case .user(let userID):
                guard userID == store.ownUser?.id else { return false }
                try await client.articles.updateUserArticle(
                    articleID: articleID,
                    title: title,
                    previewText: preview,
                    text: text,
                    tags: tags,
                    published: published
                )
                await loadUserProfile(userID: userID)
                await loadUserArticle(userID: userID, articleID: articleID)
            case .community(let communityID):
                guard let community = store.communities[communityID], community.canManageArticles else {
                    return false
                }
                try await client.articles.updateCommunityArticle(
                    communityID: communityID,
                    articleID: articleID,
                    title: title,
                    previewText: preview,
                    text: text,
                    tags: tags,
                    rolePermissions: articleRolePermissions[articleID]
                        ?? community.defaultArticleRolePermissions,
                    published: published
                )
                await loadCommunityArticles(communityID: communityID)
                await loadCommunityArticle(communityID: communityID, articleID: articleID)
            }
            if publish {
                articleDraftIDs.remove(articleID)
                if let published { articlePublishedAt[articleID] = published }
            } else {
                articleDraftIDs.insert(articleID)
                articlePublishedAt.removeValue(forKey: articleID)
            }
            return true
        } catch {
            errorMessage = userMessage(for: error)
            return false
        }
    }

    func deleteArticle(owner: ArticleOwner, articleID: String) async -> Bool {
        guard let client else { return false }
        do {
            switch owner {
            case .user(let userID):
                guard userID == store.ownUser?.id else { return false }
                try await client.articles.deleteUserArticle(articleID: articleID)
                await loadUserProfile(userID: userID)
            case .community(let communityID):
                guard store.communities[communityID]?.canManageArticles == true else { return false }
                try await client.articles.deleteCommunityArticle(
                    communityID: communityID,
                    articleID: articleID
                )
                await loadCommunityArticles(communityID: communityID)
            }
            articleDetails.removeValue(forKey: articleID)
            articleDraftIDs.remove(articleID)
            articlePublishedAt.removeValue(forKey: articleID)
            return true
        } catch {
            errorMessage = userMessage(for: error)
            return false
        }
    }

    func loadArticleComments(
        owner: ArticleOwner,
        article: ArticleDetail,
        focusing messageID: String? = nil
    ) async {
        let access = articleAccess(owner: owner, article: article)
        await loadMessages(access: access, channelID: article.channelId, focusing: messageID)
        try? await client?.articles.joinCommentRoom(access: access)
    }

    func leaveArticleComments(owner: ArticleOwner, article: ArticleDetail) async {
        try? await client?.articles.leaveCommentRoom(access: articleAccess(owner: owner, article: article))
    }

    func sendArticleComment(owner: ArticleOwner, article: ArticleDetail, text: String) async -> Bool {
        guard !articleDraftIDs.contains(article.articleId) else {
            errorMessage = "Comments are read-only while this article is a draft."
            return false
        }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, let client else { return false }
        do {
            let sent = try await client.messages.send(
                access: articleAccess(owner: owner, article: article),
                text: value
            )
            store.applyOwnWrite(sent)
            return true
        } catch {
            errorMessage = userMessage(for: error)
            return false
        }
    }

    private func articleAccess(owner: ArticleOwner, article: ArticleDetail) -> MessageAccess {
        switch owner {
        case .community(let communityID):
            .communityArticle(
                communityID,
                articleId: article.articleId,
                channelId: article.channelId
            )
        case .user(let userID):
            .userArticle(userID, articleId: article.articleId, channelId: article.channelId)
        }
    }

    func updateAccount(
        displayName: String,
        description: String,
        homepage: String,
        email: String,
        dmNotifications: Bool,
        newPassword: String
    ) async -> Bool {
        guard let client, let userID = store.ownUser?.id else { return false }
        do {
            try await client.profiles.updateCGAccount(
                displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
                description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                homepage: homepage.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            try await client.profiles.updateOwnData(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                dmNotifications: dmNotifications
            )
            let password = newPassword.trimmingCharacters(in: .whitespacesAndNewlines)
            if !password.isEmpty { try await client.profiles.setPassword(password) }
            store.seed(users: try await client.profiles.users(ids: [userID]))
            profileDetails[userID] = try await client.profiles.details(userID: userID)
            return true
        } catch {
            errorMessage = userMessage(for: error)
            return false
        }
    }

    func uploadProfileImage(_ data: Data) async -> Bool {
        guard let client, let userID = store.ownUser?.id else { return false }
        guard data.count <= 8 * 1_024 * 1_024 else {
            errorMessage = "That image is larger than the instance’s 8 MB upload limit."
            return false
        }
        do {
            let upload = try await client.files.uploadImage(data, type: .userProfileImage)
            store.seed(users: try await client.profiles.users(ids: [userID]))
            await loadAttachmentURLs(objectIDs: [upload.imageId])
            return true
        } catch {
            errorMessage = userMessage(for: error)
            return false
        }
    }

    func startChat(with userID: String) async -> Chat? {
        guard let client else { return nil }
        do {
            let chat = try await client.chats.start(otherUserID: userID)
            store.seed(chat: chat)
            selectChat(chat.id)
            return chat
        } catch {
            errorMessage = userMessage(for: error)
            return nil
        }
    }

    func loadChannelMembers(channel: Channel) async {
        guard let client else { return }
        do {
            var members = try await client.communities.channelMembers(
                communityID: channel.communityId,
                channelID: channel.channelId,
                offset: 0,
                limit: 100
            )
            var loadedCount = members.all.count
            while loadedCount < members.count {
                let page = try await client.communities.channelMembers(
                    communityID: channel.communityId,
                    channelID: channel.channelId,
                    offset: loadedCount,
                    limit: 100
                )
                let pageCount = page.all.count
                guard pageCount > 0 else { break }
                members = members.appending(page)
                loadedCount += pageCount
            }
            channelMembers[channel.channelId] = members
            await refreshUsers(ids: members.all.map(\.userId))
        } catch is CancellationError {
            return
        } catch {
            errorMessage = userMessage(for: error)
        }
    }

    func loadChatMembers(chat: Chat) async {
        await refreshUsers(ids: chat.userIds)
    }

    func discoverCommunities(query: String = "") async {
        guard let client, !isLoadingCommunities else { return }
        isLoadingCommunities = true
        defer { isLoadingCommunities = false }
        do {
            let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
            communityResults = try await client.communities.list(
                search: value.isEmpty ? nil : value,
                sort: value.isEmpty ? .popular : .new
            )
            await loadAttachmentURLs(
                objectIDs: communityResults.flatMap {
                    [$0.logoSmallId, $0.logoLargeId, $0.headerImageId].compactMap { $0 }
                }
            )
        } catch is CancellationError {
            return
        } catch {
            errorMessage = userMessage(for: error)
        }
    }

    func joinCommunity(id: String) async -> CommunityJoinOutcome {
        guard let client else { return .failed }
        do {
            guard let community = try await client.communities.join(id: id) else { return .pending }
            store.seed(community: community)
            await loadCommunityMedia([community])
            selectCommunity(community.id)
            return .joined
        } catch {
            errorMessage = userMessage(for: error)
            return .failed
        }
    }

    func createCommunity(
        title: String,
        shortDescription: String,
        description: String,
        tags: [String],
        iconData: Data,
        sidebarImageData: Data
    ) async -> Community? {
        guard let client else { return nil }
        do {
            async let iconUpload = client.files.uploadImage(iconData, type: .communityLogoSmall)
            async let sidebarUpload = client.files.uploadImage(sidebarImageData, type: .communityLogoLarge)
            let (icon, sidebar) = try await (iconUpload, sidebarUpload)
            let community = try await client.communities.create(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                shortDescription: shortDescription.trimmingCharacters(in: .whitespacesAndNewlines),
                description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                tags: tags,
                logoSmallID: icon.imageId,
                logoLargeID: sidebar.imageId
            )
            store.seed(community: community)
            await loadCommunityMedia([community])
            selectCommunity(community.id)
            return community
        } catch {
            errorMessage = userMessage(for: error)
            return nil
        }
    }

    func updateCommunity(
        _ community: Community,
        title: String,
        shortDescription: String,
        description: String,
        tags: [String],
        links: [CommunityLink],
        iconData: Data?,
        sidebarImageData: Data?,
        heroImageData: Data?
    ) async -> Bool {
        guard let client else { return false }
        do {
            try await client.communities.update(
                id: community.id,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                shortDescription: shortDescription.trimmingCharacters(in: .whitespacesAndNewlines),
                description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                tags: tags,
                links: links
            )
            if let iconData {
                let upload = try await client.files.uploadImage(
                    iconData,
                    type: .communityLogoSmall,
                    communityID: community.id
                )
                store.applyCommunityFields(
                    id: community.id,
                    fields: ["logoSmallId": .string(upload.imageId)]
                )
                await loadAttachmentURLs(objectIDs: [upload.imageId], force: true)
            }
            if let sidebarImageData {
                let upload = try await client.files.uploadImage(
                    sidebarImageData,
                    type: .communityLogoLarge,
                    communityID: community.id
                )
                store.applyCommunityFields(
                    id: community.id,
                    fields: ["logoLargeId": .string(upload.imageId)]
                )
                await loadAttachmentURLs(objectIDs: [upload.imageId], force: true)
            }
            if let heroImageData {
                let upload = try await client.files.uploadImage(
                    heroImageData,
                    type: .communityHeaderImage,
                    communityID: community.id
                )
                store.applyCommunityFields(
                    id: community.id,
                    fields: ["headerImageId": .string(upload.imageId)]
                )
                await loadAttachmentURLs(objectIDs: [upload.imageId], force: true)
            }
            guard let refreshed = try? await client.communities.detail(id: community.id) else { return true }
            store.seed(community: refreshed)
            await loadCommunityMedia([refreshed])
            return true
        } catch {
            errorMessage = userMessage(for: error)
            return false
        }
    }

    func loadCommunityMembers(communityID: String, search: String? = nil, roleID: String? = nil) async {
        guard let client else { return }
        do {
            let normalizedSearch = search?.trimmingCharacters(in: .whitespacesAndNewlines)
            let result = try await client.communities.members(
                communityID: communityID,
                search: normalizedSearch?.isEmpty == false ? normalizedSearch : nil,
                roleID: roleID
            )
            communityMemberLists[communityID] = result
            await hydrateUsers(ids: (result.online + result.offline).map(\.userId))
        } catch is CancellationError {
            return
        } catch {
            errorMessage = userMessage(for: error)
        }
    }

    func loadCommunityBans(communityID: String) async {
        guard let client else { return }
        do {
            let bans = try await client.communities.bannedUsers(communityID: communityID)
            communityBans[communityID] = bans
            await hydrateUsers(ids: bans.map(\.userId))
        } catch is CancellationError {
            return
        } catch {
            errorMessage = userMessage(for: error)
        }
    }

    func unbanUser(communityID: String, userID: String) async -> Bool {
        guard let client else { return false }
        do {
            try await client.communities.setBlockState(
                communityID: communityID,
                userID: userID,
                state: nil
            )
            await loadCommunityBans(communityID: communityID)
            return true
        } catch {
            errorMessage = userMessage(for: error)
            return false
        }
    }

    func saveCommunityOnboarding(communityID: String, options: JSONValue) async -> Bool {
        guard let client else { return false }
        do {
            let password = try await client.communities.communityPassword(communityID: communityID)
            try await client.communities.setOnboardingOptions(
                communityID: communityID,
                options: options,
                password: password
            )
            await refreshCommunity(communityID)
            return true
        } catch {
            errorMessage = userMessage(for: error)
            return false
        }
    }

    func loadPendingApprovals(communityID: String) async {
        guard let client else { return }
        do {
            let results = try await client.communities.pendingApprovals(communityID: communityID)
            communityPendingApprovals[communityID] = results
            await hydrateUsers(ids: results.map(\.userId))
        } catch is CancellationError {
            return
        } catch {
            errorMessage = userMessage(for: error)
        }
    }

    func decidePendingApproval(
        communityID: String,
        userID: String,
        state: String
    ) async -> Bool {
        guard let client else { return false }
        do {
            try await client.communities.setPendingApproval(
                communityID: communityID,
                userID: userID,
                state: state
            )
            await loadPendingApprovals(communityID: communityID)
            await refreshCommunity(communityID)
            return true
        } catch {
            errorMessage = userMessage(for: error)
            return false
        }
    }

    func setCommunityPersonalNewsletter(communityID: String, enabled: Bool) async -> Bool {
        guard let client else { return false }
        do {
            try await client.communities.setPersonalNewsletter(
                communityID: communityID,
                enabled: enabled
            )
            await refreshCommunity(communityID)
            return true
        } catch {
            errorMessage = userMessage(for: error)
            return false
        }
    }

    func giveSpark(to communityID: String, amount: Int) async -> Bool {
        guard let client, let balance = store.ownUser?.pointBalance else { return false }
        guard amount >= 1_000 else {
            errorMessage = "The minimum amount is 1,000 Spark."
            return false
        }
        guard Double(amount) <= balance else {
            errorMessage = "You don’t have enough Spark for that contribution."
            return false
        }
        do {
            try await client.communities.giveSpark(communityID: communityID, amount: amount)
            await refreshHome()
            return true
        } catch {
            errorMessage = userMessage(for: error)
            return false
        }
    }

    func setCommunityUserBots(communityID: String, allowed: Bool) async -> Bool {
        guard let client else { return false }
        do {
            try await client.communities.setAllowUserBots(
                communityID: communityID,
                allowed: allowed
            )
            await refreshCommunity(communityID)
            return true
        } catch {
            errorMessage = userMessage(for: error)
            return false
        }
    }

    func setCommunityNotifications(
        communityID: String,
        state: CommunityNotificationState
    ) async -> Bool {
        guard let client else { return false }
        do {
            try await client.communities.updateNotificationState(
                communityID: communityID,
                state: state
            )
            await refreshCommunity(communityID)
            return true
        } catch {
            errorMessage = userMessage(for: error)
            return false
        }
    }

    func createCommunityRole(communityID: String, title: String) async -> Bool {
        guard let client else { return false }
        do {
            _ = try await client.communities.createRole(
                communityID: communityID,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            await refreshCommunity(communityID)
            return true
        } catch {
            errorMessage = userMessage(for: error)
            return false
        }
    }

    func updateCommunityRole(
        communityID: String,
        roleID: String,
        title: String?,
        description: String?,
        permissions: [String]?
    ) async -> Bool {
        guard let client else { return false }
        do {
            try await client.communities.updateRole(
                communityID: communityID,
                roleID: roleID,
                title: title,
                description: description,
                permissions: permissions
            )
            await refreshCommunity(communityID)
            return true
        } catch {
            errorMessage = userMessage(for: error)
            return false
        }
    }

    func deleteCommunityRole(communityID: String, roleID: String) async -> Bool {
        guard let client else { return false }
        do {
            try await client.communities.deleteRole(communityID: communityID, roleID: roleID)
            await refreshCommunity(communityID)
            return true
        } catch {
            errorMessage = userMessage(for: error)
            return false
        }
    }

    func setCommunityMemberRoles(
        communityID: String,
        userID: String,
        previous: Set<String>,
        selected: Set<String>
    ) async -> Bool {
        guard let client else { return false }
        do {
            let additions = Array(selected.subtracting(previous))
            let removals = Array(previous.subtracting(selected))
            try await client.communities.addUserToRoles(
                communityID: communityID,
                userID: userID,
                roleIDs: additions
            )
            try await client.communities.removeUserFromRoles(
                communityID: communityID,
                userID: userID,
                roleIDs: removals
            )
            await loadCommunityMembers(communityID: communityID)
            return true
        } catch {
            errorMessage = userMessage(for: error)
            return false
        }
    }

    func saveCommunityArea(
        communityID: String,
        areaID: String?,
        title: String,
        order: Int
    ) async -> Bool {
        guard let client else { return false }
        do {
            if let areaID {
                try await client.communities.updateArea(
                    communityID: communityID,
                    areaID: areaID,
                    title: title
                )
            } else {
                try await client.communities.createArea(
                    communityID: communityID,
                    title: title,
                    order: order
                )
            }
            await refreshCommunity(communityID)
            return true
        } catch {
            errorMessage = userMessage(for: error)
            return false
        }
    }

    func deleteCommunityArea(communityID: String, areaID: String) async -> Bool {
        guard let client else { return false }
        do {
            try await client.communities.deleteArea(communityID: communityID, areaID: areaID)
            await refreshCommunity(communityID)
            return true
        } catch {
            errorMessage = userMessage(for: error)
            return false
        }
    }

    func saveCommunityChannel(
        communityID: String,
        channelID: String?,
        areaID: String?,
        title: String,
        url: String?,
        order: Int,
        description: String?,
        emoji: String?,
        roleAccess: [ChannelRoleAccess]
    ) async -> Bool {
        guard let client else { return false }
        do {
            if let channelID {
                try await client.communities.updateChannel(
                    communityID: communityID,
                    channelID: channelID,
                    areaID: areaID,
                    title: title,
                    url: url,
                    order: order,
                    description: description,
                    emoji: emoji,
                    roleAccess: roleAccess
                )
            } else {
                guard let areaID else {
                    errorMessage = "Create or choose an area before adding a channel."
                    return false
                }
                try await client.communities.createChannel(
                    communityID: communityID,
                    areaID: areaID,
                    title: title,
                    url: url,
                    order: order,
                    description: description,
                    emoji: emoji,
                    roleAccess: roleAccess
                )
            }
            await refreshCommunity(communityID)
            return true
        } catch {
            errorMessage = userMessage(for: error)
            return false
        }
    }

    func deleteCommunityChannel(communityID: String, channelID: String) async -> Bool {
        guard let client else { return false }
        do {
            try await client.communities.deleteChannel(
                communityID: communityID,
                channelID: channelID
            )
            await refreshCommunity(communityID)
            return true
        } catch {
            errorMessage = userMessage(for: error)
            return false
        }
    }

    private func refreshCommunity(_ communityID: String) async {
        guard let client, let refreshed = try? await client.communities.detail(id: communityID) else { return }
        store.seed(community: refreshed)
        await loadCommunityMedia([refreshed])
    }

    func refreshCommunityHome(communityID: String) async {
        await refreshCommunity(communityID)
        await loadCommunityArticles(communityID: communityID)
    }

    func leaveCommunity(id: String) async -> Bool {
        guard let client else { return false }
        do {
            _ = try await client.communities.leave(id: id)
            store.removeCommunity(id: id)
            if selectedCommunityID == id {
                selectCommunity(nil)
                selectChannel(nil)
            }
            return true
        } catch {
            errorMessage = userMessage(for: error)
            return false
        }
    }

    func report(
        type: ReportType,
        targetID: String,
        reason: ReportReason,
        message: String
    ) async -> Bool {
        guard let client else { return false }
        do {
            let details = message.trimmingCharacters(in: .whitespacesAndNewlines)
            try await client.reports.create(
                type: type,
                targetID: targetID,
                reason: reason,
                message: details.isEmpty ? nil : details
            )
            return true
        } catch {
            errorMessage = userMessage(for: error)
            return false
        }
    }

    func beginReply(to message: Message) {
        editingMessage = nil
        replyingTo = message
    }

    func beginEditing(_ message: Message) {
        replyingTo = nil
        pendingImageAttachment = nil
        editingMessage = message
        draftMessage = message.body.plainText
        draftMentions = message.body.mentions
    }

    func cancelComposerContext() {
        replyingTo = nil
        editingMessage = nil
        pendingImageAttachment = nil
        draftMessage = ""
        draftMentions = [:]
    }

    func insertMention(_ user: UserProfile) {
        let alias = user.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !alias.isEmpty else { return }
        draftMentions[alias] = user.id
        if !draftMessage.isEmpty && !draftMessage.hasSuffix(" ") && !draftMessage.hasSuffix("\n") {
            draftMessage += " "
        }
        draftMessage += "@\(alias) "
    }

    func uploadMessageImage(_ data: Data) async {
        guard let client, !isUploadingAttachment else { return }
        guard data.count <= 8 * 1_024 * 1_024 else {
            errorMessage = "That image is larger than the instance’s 8 MB upload limit."
            return
        }
        isUploadingAttachment = true
        defer { isUploadingAttachment = false }
        do {
            let result = try await client.files.uploadImage(data, type: .channelAttachmentImage)
            guard let largeImageID = result.largeImageId else {
                errorMessage = "The instance did not return the large image needed for this attachment."
                return
            }
            pendingImageAttachment = MessageImageAttachment(
                imageId: result.imageId,
                largeImageId: largeImageID
            )
            await loadAttachmentURLs(objectIDs: [result.imageId, largeImageID])
        } catch {
            errorMessage = userMessage(for: error)
        }
    }

    func removePendingImage() {
        pendingImageAttachment = nil
    }

    func deleteMessage(_ message: Message, access: MessageAccess) async {
        guard let client else { return }
        do {
            try await client.messages.delete(
                access: access,
                messageID: message.id,
                creatorID: message.creatorId
            )
            store.applyOwnDelete(messageID: message.id, channelID: message.channelId)
            if editingMessage?.id == message.id { cancelComposerContext() }
        } catch {
            errorMessage = userMessage(for: error)
        }
    }

    func setReaction(_ reaction: String?, on message: Message, access: MessageAccess) async {
        guard let client else { return }
        do {
            if let reaction {
                try await client.messages.setReaction(
                    access: access,
                    messageID: message.id,
                    reaction: reaction
                )
            } else {
                try await client.messages.unsetReaction(access: access, messageID: message.id)
            }
            store.applyOwnReaction(
                messageID: message.id,
                channelID: message.channelId,
                reaction: reaction
            )
        } catch {
            errorMessage = userMessage(for: error)
        }
    }

    private func loadMessages(
        access: MessageAccess,
        channelID: String,
        focusing messageID: String? = nil
    ) async {
        guard let client else { return }
        do {
            let messages: [Message]
            let lastRead: String?
            if let messageID {
                let target = try await client.messages.byIDs(access: access, messageIDs: [messageID])
                guard let focused = target.first else {
                    errorMessage = "That message is no longer available."
                    return
                }
                async let before = client.messages.load(
                    access: access,
                    order: .descending,
                    createdBefore: focused.createdAt,
                    createdAfter: nil
                )
                async let after = client.messages.load(
                    access: access,
                    order: .ascending,
                    createdBefore: nil,
                    createdAfter: focused.createdAt
                )
                let (older, newer) = try await (before, after)
                messages = older + target + newer
                lastRead = focused.createdAt
            } else {
                messages = try await client.messages.load(access: access)
                lastRead = messages.map(\.createdAt).max()
            }
            store.seed(messages, channelId: channelID)
            await hydrateUsers(ids: messages.map(\.creatorId))
            await loadAttachmentURLs(
                objectIDs: messages.flatMap(\.imageAttachments).flatMap { [$0.imageId, $0.largeImageId] }
            )
            if let lastRead {
                try? await client.messages.setLastRead(access: access, date: lastRead)
            }
        } catch is CancellationError {
            return
        } catch {
            errorMessage = userMessage(for: error)
        }
    }

    private func sendMessage(access: MessageAccess) async {
        let text = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (!text.isEmpty || pendingImageAttachment != nil), let client else { return }
        if let editingMessage {
            guard !text.isEmpty else { return }
            do {
                let result = try await client.messages.edit(
                    access: access,
                    messageID: editingMessage.id,
                    text: text,
                    mentions: draftMentions
                )
                store.applyOwnEdit(
                    messageID: editingMessage.id,
                    channelID: editingMessage.channelId,
                    body: .composed(text, mentions: draftMentions),
                    editedAt: result.editedAt
                )
                resetComposerContext()
                draftMessage = ""
            } catch {
                errorMessage = userMessage(for: error)
            }
            return
        }
        let reply = replyingTo
        let attachment = pendingImageAttachment
        let mentions = draftMentions
        guard let creatorID = store.ownUser?.id else { return }
        let id = UUID()
        let pending = PendingMessage(
            id: id.uuidString.lowercased(),
            creatorID: creatorID,
            access: access,
            text: text,
            mentions: mentions,
            parentMessageID: reply?.id,
            imageAttachments: attachment.map { [$0] } ?? [],
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
        draftMessage = ""
        draftMentions = [:]
        replyingTo = nil
        pendingImageAttachment = nil
        store.enqueue(pending)
        await deliverPendingMessage(pending)
    }

    func retryPendingMessage(_ id: String) async {
        guard let pending = store.pendingMessages[id] else { return }
        await deliverPendingMessage(pending)
    }

    func discardPendingMessage(_ id: String) {
        store.discardPending(id: id)
    }

    private func deliverPendingMessage(_ pending: PendingMessage) async {
        guard let client else { return }
        store.updatePending(id: pending.id, state: .sending)
        do {
            let sent = try await client.messages.send(
                access: pending.access,
                text: pending.text,
                mentions: pending.mentions,
                parentMessageID: pending.parentMessageID,
                imageAttachments: pending.imageAttachments,
                id: UUID(uuidString: pending.id) ?? UUID()
            )
            store.completePending(id: pending.id, with: sent)
            await loadAttachmentURLs(
                objectIDs: sent.imageAttachments.flatMap { [$0.imageId, $0.largeImageId] }
            )
        } catch is CancellationError {
            store.updatePending(id: pending.id, state: .queued)
        } catch let error as APIError {
            let message = userMessage(for: error)
            store.updatePending(id: pending.id, state: .failed, error: message)
            errorMessage = message
        } catch {
            store.updatePending(id: pending.id, state: .queued, error: userMessage(for: error))
            realtimeNotice = "Message queued — it will send when the connection returns."
        }
    }

    private func flushPendingMessages() async {
        guard !isFlushingOutbox else { return }
        isFlushingOutbox = true
        defer { isFlushingOutbox = false }
        let pending = store.pendingMessages.values
            .filter { $0.state != .failed }
            .sorted { $0.createdAt < $1.createdAt }
        for message in pending { await deliverPendingMessage(message) }
    }

    private func loadAttachmentURLs(objectIDs: [String], force: Bool = false) async {
        guard let client else { return }
        let now = Date()
        let missing = Array(Set(objectIDs)).filter { id in
            force || attachmentURLs[id] == nil || (attachmentURLExpirations[id] ?? .distantPast) <= now
        }
        guard !missing.isEmpty else { return }
        do {
            for signed in try await client.files.signedURLs(objectIDs: missing) {
                if let url = URL(string: signed.url) {
                    attachmentURLs[signed.objectId] = url
                    attachmentURLExpirations[signed.objectId] = Self.parseISODate(signed.validUntil)
                        ?? now.addingTimeInterval(300)
                }
            }
        } catch {
            // A message remains readable when its optional media URL cannot be
            // refreshed. Pull-to-refresh retries this without hiding the text.
        }
    }

    private static func parseISODate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private func loadCommunityMedia(_ communities: [Community]) async {
        await loadAttachmentURLs(
            objectIDs: communities.flatMap {
                [$0.logoSmallId, $0.logoLargeId, $0.headerImageId].compactMap { $0 }
            }
        )
    }

    private func refreshCommunityPresentation(communityIDs: [String]) async {
        guard let client else { return }
        var refreshed: [Community] = []
        for id in communityIDs {
            if let community = try? await client.communities.detail(id: id) {
                store.seed(community: community)
                refreshed.append(community)
            }
        }
        await loadCommunityMedia(refreshed)
    }

    private func hydrateUsers(ids: [String]) async {
        guard let client else { return }
        let missing = Array(Set(ids)).filter { store.users[$0] == nil }
        guard !missing.isEmpty else { return }
        do {
            let users = try await client.profiles.users(ids: missing)
            store.seed(users: users)
            await loadAttachmentURLs(objectIDs: users.compactMap(\.imageID))
        } catch {
            // Names and avatars are enhancement data. The primary content remains usable.
        }
    }

    private func refreshUsers(ids: [String]) async {
        guard let client else { return }
        let unique = Array(Set(ids))
        guard !unique.isEmpty else { return }
        do {
            let users = try await client.profiles.users(ids: unique)
            store.seed(users: users)
            await loadAttachmentURLs(objectIDs: users.compactMap(\.imageID))
        } catch {
            // Presence can be refreshed again while the drawer remains open.
        }
    }

    private func resetComposerContext() {
        replyingTo = nil
        editingMessage = nil
        pendingImageAttachment = nil
        draftMentions = [:]
    }

    func logout() async {
        guard let client else { return }
        isWorking = true
        defer { isWorking = false }
        var remoteError: Error?
        do { try await client.auth.logout() } catch { remoteError = error }

        removeRealtimeListeners()
        dismissInAppNotification()
        realtime?.close()
        realtime = nil
        await client.transport.clearCookies()
        UserDefaults.standard.removeObject(forKey: Keys.deviceID(client.instance))
        UserDefaults.standard.removeObject(forKey: Keys.cachedLogin(client.instance))
        selectedCommunityID = nil
        selectedChannelID = nil
        selectedChatID = nil
        attachmentURLs = [:]
        attachmentURLExpirations = [:]
        await store.clearPersistentData()
        store.reset()
        store.detachPersistence()
        offlineDatabase = nil
        phase = .authentication

        do {
            try DeviceKeyStore.delete(for: client.instance)
            signingKey = try DeviceKeyStore.loadOrCreate(for: client.instance)
        } catch {
            signingKey = nil
            errorMessage = userMessage(for: error)
            return
        }
        if let remoteError {
            // Local credentials are authoritative for signing out this device.
            // The server call is best-effort and must never retain local access.
            errorMessage = "You were signed out on this device. The instance could not confirm the logout: \(userMessage(for: remoteError))"
        }
    }

    func chooseAnotherInstance() {
        removeRealtimeListeners()
        dismissInAppNotification()
        realtime?.close()
        realtime = nil
        client = nil
        instanceConfig = nil
        errorMessage = nil
        selectedCommunityID = nil
        selectedChannelID = nil
        selectedChatID = nil
        attachmentURLs = [:]
        attachmentURLExpirations = [:]
        store.reset()
        store.detachPersistence()
        offlineDatabase = nil
        phase = .instance
    }

    private func didAuthenticate(_ session: AuthSession, offline: Bool = false) async {
        guard let client else { return }
        do {
            let database = try OfflineDatabase(
                fileURL: OfflineDatabase.defaultURL(
                    instance: client.instance,
                    userID: session.response.ownData.id
                ),
                scope: "\(client.instance.description)|\(session.response.ownData.id)"
            )
            offlineDatabase = database
            await store.configurePersistence(database)
        } catch {
            // Persistence failure must not block an otherwise healthy session.
            offlineDatabase = nil
        }
        store.hydrate(from: session.response)
        if !offline { await hydrateUsers(ids: [session.response.ownData.id]) }
        UserDefaults.standard.set(session.deviceId, forKey: Keys.deviceID(client.instance))
        saveCachedResponse(session.response, for: client.instance)
        let communityIDs = Set(session.response.communities.map(\.id))
        let channelIDs = Set(session.response.communities.flatMap(\.channels).map(\.channelId))
        let chatIDs = Set(session.response.chats.map(\.id))
        let savedCommunityID = UserDefaults.standard.string(forKey: Keys.communityID(client.instance))
        let savedChannelID = UserDefaults.standard.string(forKey: Keys.channelID(client.instance))
        let savedChatID = UserDefaults.standard.string(forKey: Keys.chatID(client.instance))
        selectedCommunityID = savedCommunityID.flatMap { communityIDs.contains($0) ? $0 : nil }
        selectedChannelID = savedChannelID.flatMap { channelIDs.contains($0) ? $0 : nil }
        selectedChatID = savedChatID.flatMap { chatIDs.contains($0) ? $0 : nil }
        restoreDraft(
            for: selectedChatID.map { "chat:\($0)" }
                ?? selectedChannelID.map { "channel:\($0)" }
        )
        phase = .home
        if !offline {
            await refreshCommunityPresentation(
                communityIDs: session.response.communities.map(\.id)
            )
        }

        guard !offline else { return }

        await startRealtime(session)
        // Warm the read-only public directory after authentication so Discover
        // opens immediately and restored sessions continuously smoke-test the
        // deployed community-list contract.
        await discoverCommunities()
    }

    private func startRealtime(_ session: AuthSession) async {
        guard let client, realtime == nil else { return }
        let realtime = client.realtime()
        self.realtime = realtime
        store.attach(to: realtime)
        notificationListenerID = realtime.onEvent { [weak self] event in
            self?.handleRealtimeEvent(event)
        }
        realtimeStatusListenerID = realtime.onStatus { [weak self] status in
            guard let self else { return }
            switch status {
            case .authenticated:
                self.realtimeNotice = nil
                Task { await self.flushPendingMessages() }
            case .disconnected, .reconnecting:
                self.realtimeNotice = "Reconnecting live updates…"
            case .authenticationFailed:
                self.realtimeNotice = "Live updates are unavailable. Pull to refresh."
            case .connected:
                break
            }
        }
        do {
            try await realtime.connect()
            try await realtime.login(deviceId: session.deviceId, deviceKey: session.deviceKey)
            realtimeNotice = nil
        } catch {
            // REST remains fully usable. Socket reconnection can be retried in
            // a later lifecycle pass without invalidating the authenticated UI.
            realtimeNotice = "Live updates are temporarily unavailable. Pull to refresh."
        }
    }

    private func handleRealtimeEvent(_ event: RealtimeEvent) {
        if Self.requiresCommunityRefresh(event) {
            realtimeRefreshTask?.cancel()
            realtimeRefreshTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                await self?.refreshHome()
            }
        }
        guard event.type == .notification,
              case .object(let payload) = event.payload,
              payload["action"]?.stringValue == "new",
              let data = payload["data"],
              let encoded = try? JSONEncoder().encode(data),
              let notification = try? JSONDecoder().decode(AppNotification.self, from: encoded),
              !presentedNotificationIDs.contains(notification.id),
              !isViewing(notification.destination) else { return }
        presentedNotificationIDs.insert(notification.id)
        if presentedNotificationIDs.count > 200 {
            presentedNotificationIDs.removeAll(keepingCapacity: true)
            presentedNotificationIDs.insert(notification.id)
        }
        notificationDismissTask?.cancel()
        inAppNotification = notification
        notificationDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            self?.inAppNotification = nil
        }
    }

    private static func requiresCommunityRefresh(_ event: RealtimeEvent) -> Bool {
        switch event.type {
        case .channel, .area, .role, .membership, .myRoles, .plugin:
            true
        default:
            false
        }
    }

    private func removeRealtimeListeners() {
        if let notificationListenerID { realtime?.removeListener(notificationListenerID) }
        if let realtimeStatusListenerID { realtime?.removeStatusListener(realtimeStatusListenerID) }
        notificationListenerID = nil
        realtimeStatusListenerID = nil
        realtimeRefreshTask?.cancel()
        realtimeRefreshTask = nil
    }

    private var currentConversationPersistenceID: String? {
        if let selectedChatID { return "chat:\(selectedChatID)" }
        if let selectedChannelID { return "channel:\(selectedChannelID)" }
        return nil
    }

    private func scheduleDraftPersistence() {
        guard !isRestoringDraft,
              let database = offlineDatabase,
              let conversationID = currentConversationPersistenceID else { return }
        let text = draftMessage
        draftPersistenceTask?.cancel()
        draftPersistenceTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            try? await database.saveDraft(text, conversationID: conversationID)
        }
    }

    private func persistCurrentDraftImmediately() {
        draftPersistenceTask?.cancel()
        guard !isRestoringDraft,
              let database = offlineDatabase,
              let conversationID = currentConversationPersistenceID else { return }
        let text = draftMessage
        Task { try? await database.saveDraft(text, conversationID: conversationID) }
    }

    private func restoreDraft(for conversationID: String?) {
        draftPersistenceTask?.cancel()
        isRestoringDraft = true
        draftMessage = ""
        isRestoringDraft = false
        guard let conversationID, let database = offlineDatabase else { return }
        Task { [weak self] in
            let text = (try? await database.draft(conversationID: conversationID)) ?? ""
            guard let self, self.currentConversationPersistenceID == conversationID else { return }
            self.isRestoringDraft = true
            self.draftMessage = text
            self.isRestoringDraft = false
        }
    }

    private func isViewing(_ destination: NotificationDestination?) -> Bool {
        switch destination {
        case .channel(_, let channelID, _): selectedChannelID == channelID
        case .chat(let chatID, _, _): selectedChatID == chatID
        default: false
        }
    }

    private func restoreSession(
        client: CommonGroundClient,
        signingKey: any DeviceSigningKey
    ) async -> Bool {
        guard let deviceID = savedDeviceID(for: client.instance) else { return false }
        do {
            let session = try await client.auth.loginWithDevice(
                deviceId: deviceID,
                deviceKey: signingKey
            )
            await didAuthenticate(session)
            return true
        } catch let error as APIError where Self.isStaleDeviceError(error) {
            _ = try? resetLocalDeviceIdentity(for: client.instance)
            return false
        } catch {
            // If fresh device reauthentication is temporarily unavailable, an
            // already-valid cookie may still support the last local snapshot.
        }

        let status: LoginStatus
        do { status = try await client.auth.checkLoginStatus() } catch { return false }
        guard let userID = status.userId,
              let response = cachedResponse(for: client.instance),
              response.ownData.id == userID else {
            UserDefaults.standard.removeObject(forKey: Keys.cachedLogin(client.instance))
            return false
        }
        await didAuthenticate(
            AuthSession(response: response, deviceId: deviceID, deviceKey: signingKey)
        )
        return true
    }

    private func preparePasswordLogin(
        client: CommonGroundClient,
        signingKey: any DeviceSigningKey
    ) async throws -> PasswordLoginPreparation {
        guard let oldDeviceID = savedDeviceID(for: client.instance) else {
            return PasswordLoginPreparation(deviceKey: signingKey, retirementClient: nil)
        }

        let cleanupClient = CommonGroundClient(
            instance: client.instance,
            sessionConfiguration: .ephemeral
        )
        do {
            _ = try await cleanupClient.auth.loginWithDevice(
                deviceId: oldDeviceID,
                deviceKey: signingKey
            )
            return PasswordLoginPreparation(
                deviceKey: signingKey,
                retirementClient: cleanupClient
            )
        } catch let error as APIError where Self.isStaleDeviceError(error) {
            let replacement = try resetLocalDeviceIdentity(for: client.instance)
            return PasswordLoginPreparation(deviceKey: replacement, retirementClient: nil)
        } catch {
            // Cleanup is best-effort. A password login must remain available if
            // the old device cannot be reached for an unrelated transient reason.
            return PasswordLoginPreparation(deviceKey: signingKey, retirementClient: nil)
        }
    }

    private func resetLocalDeviceIdentity(for instance: InstanceURL) throws -> any DeviceSigningKey {
        UserDefaults.standard.removeObject(forKey: Keys.deviceID(instance))
        UserDefaults.standard.removeObject(forKey: Keys.cachedLogin(instance))
        try DeviceKeyStore.delete(for: instance)
        let replacement = try DeviceKeyStore.loadOrCreate(for: instance)
        signingKey = replacement
        return replacement
    }

    private func savedDeviceID(for instance: InstanceURL) -> String? {
        UserDefaults.standard.string(forKey: Keys.deviceID(instance))
    }

    private func cachedResponse(for instance: InstanceURL) -> LoginResponse? {
        guard let data = UserDefaults.standard.data(forKey: Keys.cachedLogin(instance)) else {
            return nil
        }
        return try? JSONDecoder().decode(LoginResponse.self, from: data)
    }

    private func saveCachedResponse(_ response: LoginResponse, for instance: InstanceURL) {
        guard let data = try? JSONEncoder().encode(response) else { return }
        UserDefaults.standard.set(data, forKey: Keys.cachedLogin(instance))
    }

    private static func isStaleDeviceError(_ error: APIError) -> Bool {
        error.code == "INVALID_SIGNATURE" || error.code == "NOT_FOUND"
    }

    private func perform(
        activity: String,
        authentication: Bool = false,
        operation: () async throws -> Void
    ) async {
        guard !isWorking else { return }
        isWorking = true
        self.activity = activity
        errorMessage = nil
        defer {
            isWorking = false
            self.activity = ""
        }
        do { try await operation() }
        catch { errorMessage = userMessage(for: error, authentication: authentication) }
    }

    private func userMessage(for error: Error, authentication: Bool = false) -> String {
        if let api = error as? APIError {
            switch api.code {
            case "NOT_ALLOWED": return authentication
                ? "Those credentials weren’t accepted."
                : "This action isn’t allowed for your account."
            case "EXISTS_ALREADY": return "That email or profile name is already in use."
            case "CAPTCHA_FAILED": return "The registration challenge expired. Please try again."
            case "RATE_LIMIT_EXCEEDED": return "This instance is receiving too many requests. Try later."
            case "INSUFFICIENT_BALANCE": return "You don’t have enough Spark for that contribution."
            default: return "The instance returned \(api.code)."
            }
        }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    private enum Keys {
        static let instance = "selectedInstance"
        static func deviceID(_ instance: InstanceURL) -> String {
            "deviceID.\(instance.description)"
        }
        static func cachedLogin(_ instance: InstanceURL) -> String {
            "cachedLogin.\(instance.description)"
        }
        static func communityID(_ instance: InstanceURL) -> String {
            "communityID.\(instance.description)"
        }
        static func channelID(_ instance: InstanceURL) -> String {
            "channelID.\(instance.description)"
        }
        static func chatID(_ instance: InstanceURL) -> String {
            "chatID.\(instance.description)"
        }
    }

    private struct PasswordLoginPreparation {
        let deviceKey: any DeviceSigningKey
        let retirementClient: CommonGroundClient?
    }

    private enum AppError: Error, LocalizedError {
        case noInstance
        case noSavedDevice
        case savedDeviceExpired
        var errorDescription: String? {
            switch self {
            case .noInstance: return "Connect to an instance first."
            case .noSavedDevice: return "No saved device login was found."
            case .savedDeviceExpired: return "This saved device login expired. Sign in with your password to reconnect it."
            }
        }
    }
}
