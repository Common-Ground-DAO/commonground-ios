import CommonGroundKit
import Foundation
import SwiftUI

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
        selectedChannelID = id
        selectedChatID = nil
        guard let client else { return }
        UserDefaults.standard.set(id, forKey: Keys.channelID(client.instance))
    }

    func selectChat(_ id: String?) {
        selectedChatID = id
        selectedChannelID = nil
        guard let client else { return }
        UserDefaults.standard.set(id, forKey: Keys.chatID(client.instance))
    }

    private func loadMessages(access: MessageAccess, channelID: String) async {
        guard let client else { return }
        do {
            let messages = try await client.messages.load(access: access)
            store.seed(messages, channelId: channelID)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = userMessage(for: error)
        }
    }

    private func sendMessage(access: MessageAccess) async {
        let text = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let client else { return }
        draftMessage = ""
        do {
            let sent = try await client.messages.send(access: access, text: text)
            store.applyOwnWrite(sent)
        } catch {
            draftMessage = text
            errorMessage = userMessage(for: error)
        }
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
