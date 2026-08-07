import CommonGroundKit
import Foundation
import SwiftUI

enum CommunityJoinOutcome {
    case joined
    case pending
    case failed
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
    @Published var draftMessage = ""
    @Published private(set) var draftMentions: [String: String] = [:]
    @Published var replyingTo: Message?
    @Published var editingMessage: Message?
    @Published var pendingImageAttachment: MessageImageAttachment?
    @Published var isUploadingAttachment = false
    @Published private(set) var attachmentURLs: [String: URL] = [:]
    @Published var isLoadingNotifications = false
    @Published var isSearchingUsers = false
    @Published private(set) var userSearchResultIDs: [String] = []
    @Published var isLoadingCommunities = false
    @Published private(set) var communityResults: [CommunitySummary] = []

    let store = SyncStore()
    private(set) var client: CommonGroundClient?
    private var signingKey: (any DeviceSigningKey)?
    private var realtime: RealtimeClient?
    private var didAttemptLaunchRestore = false

    var savedDeviceID: String? {
        guard let instance = try? InstanceURL(instanceInput) else { return nil }
        return savedDeviceID(for: instance)
    }

    var instanceHost: String {
        client?.instance.url.host ?? "Common Ground"
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
            let config = try await client.instanceAPI.config()
            self.client = client
            self.instanceConfig = config
            self.instanceInput = instance.description
            UserDefaults.standard.set(instance.description, forKey: Keys.instance)
            let signingKey = try DeviceKeyStore.loadOrCreate(for: instance)
            self.signingKey = signingKey
            if !(await self.restoreSession(client: client, signingKey: signingKey)) {
                self.phase = .authentication
            }
        }
    }

    func signIn(alias: String, password: String) async {
        await perform(activity: "Signing in…") {
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
        await perform(activity: "Solving the privacy-friendly challenge…") {
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
        await perform(activity: "Signing with this device…") {
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

    func loadMessages(channel: Channel) async {
        await loadMessages(
            access: .community(channel.communityId, channelId: channel.channelId),
            channelID: channel.channelId
        )
    }

    func loadMessages(chat: Chat) async {
        await loadMessages(
            access: .chat(chat.id, channelId: chat.channelId),
            channelID: chat.channelId
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
        selectedCommunityID = id
        guard let client else { return }
        UserDefaults.standard.set(id, forKey: Keys.communityID(client.instance))
    }

    func selectChannel(_ id: String?) {
        resetComposerContext()
        selectedChannelID = id
        selectedChatID = nil
        guard let client else { return }
        UserDefaults.standard.set(id, forKey: Keys.channelID(client.instance))
    }

    func selectChat(_ id: String?) {
        resetComposerContext()
        selectedChatID = id
        selectedChannelID = nil
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
        guard let client, store.notifications[id]?.read == false else { return }
        do {
            try await client.notifications.markAsRead(id)
            store.markNotificationRead(id)
        } catch {
            errorMessage = userMessage(for: error)
        }
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
        tags: [String]
    ) async -> Community? {
        guard let client else { return nil }
        do {
            let community = try await client.communities.create(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                shortDescription: shortDescription.trimmingCharacters(in: .whitespacesAndNewlines),
                description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                tags: tags
            )
            store.seed(community: community)
            selectCommunity(community.id)
            return community
        } catch {
            errorMessage = userMessage(for: error)
            return nil
        }
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
        draftMentions = [:]
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

    private func loadMessages(access: MessageAccess, channelID: String) async {
        guard let client else { return }
        do {
            let messages = try await client.messages.load(access: access)
            store.seed(messages, channelId: channelID)
            await loadAttachmentURLs(
                objectIDs: messages.flatMap(\.imageAttachments).flatMap { [$0.imageId, $0.largeImageId] }
            )
            if let lastRead = messages.last?.createdAt {
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
                    text: text
                )
                store.applyOwnEdit(
                    messageID: editingMessage.id,
                    channelID: editingMessage.channelId,
                    body: .text(text),
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
        draftMessage = ""
        draftMentions = [:]
        replyingTo = nil
        pendingImageAttachment = nil
        do {
            let sent = try await client.messages.send(
                access: access,
                text: text,
                mentions: mentions,
                parentMessageID: reply?.id,
                imageAttachments: attachment.map { [$0] } ?? []
            )
            store.applyOwnWrite(sent)
            await loadAttachmentURLs(
                objectIDs: sent.imageAttachments.flatMap { [$0.imageId, $0.largeImageId] }
            )
        } catch {
            draftMessage = text
            replyingTo = reply
            pendingImageAttachment = attachment
            draftMentions = mentions
            errorMessage = userMessage(for: error)
        }
    }

    private func loadAttachmentURLs(objectIDs: [String]) async {
        guard let client else { return }
        let missing = Array(Set(objectIDs)).filter { attachmentURLs[$0] == nil }
        guard !missing.isEmpty else { return }
        do {
            for signed in try await client.files.signedURLs(objectIDs: missing) {
                if let url = URL(string: signed.url) { attachmentURLs[signed.objectId] = url }
            }
        } catch {
            // A message remains readable when its optional media URL cannot be
            // refreshed. Pull-to-refresh retries this without hiding the text.
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
        do {
            try await client.auth.logout()
            realtime?.close()
            await client.transport.clearCookies()
            UserDefaults.standard.removeObject(forKey: Keys.deviceID(client.instance))
            UserDefaults.standard.removeObject(forKey: Keys.cachedLogin(client.instance))
            selectedCommunityID = nil
            selectedChannelID = nil
            selectedChatID = nil
            store.reset()
            phase = .authentication
            try DeviceKeyStore.delete(for: client.instance)
            signingKey = try DeviceKeyStore.loadOrCreate(for: client.instance)
        } catch {
            errorMessage = userMessage(for: error)
        }
    }

    func chooseAnotherInstance() {
        realtime?.close()
        realtime = nil
        client = nil
        instanceConfig = nil
        errorMessage = nil
        selectedCommunityID = nil
        selectedChannelID = nil
        selectedChatID = nil
        store.reset()
        phase = .instance
    }

    private func didAuthenticate(_ session: AuthSession) async {
        guard let client else { return }
        store.hydrate(from: session.response)
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
        phase = .home

        let realtime = client.realtime()
        self.realtime = realtime
        store.attach(to: realtime)
        do {
            try await realtime.connect()
            try await realtime.login(deviceId: session.deviceId, deviceKey: session.deviceKey)
            realtimeNotice = nil
        } catch {
            // REST remains fully usable. Socket reconnection can be retried in
            // a later lifecycle pass without invalidating the authenticated UI.
            realtimeNotice = "Live updates are temporarily unavailable. Pull to refresh."
        }
        // Warm the read-only public directory after authentication so Discover
        // opens immediately and restored sessions continuously smoke-test the
        // deployed community-list contract.
        await discoverCommunities()
    }

    private func restoreSession(
        client: CommonGroundClient,
        signingKey: any DeviceSigningKey
    ) async -> Bool {
        let status: LoginStatus
        do {
            status = try await client.auth.checkLoginStatus()
        } catch {
            // A transient status-check failure should not destroy a cache that
            // may still match a valid rolling session on the next launch.
            return false
        }
        guard let userID = status.userId,
              let deviceID = savedDeviceID(for: client.instance),
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

    private func perform(activity: String, operation: () async throws -> Void) async {
        guard !isWorking else { return }
        isWorking = true
        self.activity = activity
        errorMessage = nil
        defer {
            isWorking = false
            self.activity = ""
        }
        do { try await operation() }
        catch { errorMessage = userMessage(for: error) }
    }

    private func userMessage(for error: Error) -> String {
        if let api = error as? APIError {
            switch api.code {
            case "NOT_ALLOWED": return "Those credentials weren’t accepted."
            case "EXISTS_ALREADY": return "That email or profile name is already in use."
            case "CAPTCHA_FAILED": return "The registration challenge expired. Please try again."
            case "RATE_LIMIT_EXCEEDED": return "This instance is receiving too many requests. Try later."
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
