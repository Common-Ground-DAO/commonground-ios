import CommonGroundKit
import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    enum Phase { case instance, authentication, home }

    @Published var phase: Phase = .instance
    @Published var instanceInput = UserDefaults.standard.string(forKey: Keys.instance) ?? "https://cg.mogged.eu"
    @Published var instanceConfig: InstanceConfig?
    @Published var isWorking = false
    @Published var activity = ""
    @Published var errorMessage: String?
    @Published var realtimeNotice: String?
    @Published var selectedChannelID: String?
    @Published var draftMessage = ""

    let store = SyncStore()
    private(set) var client: CommonGroundClient?
    private var signingKey: (any DeviceSigningKey)?
    private var realtime: RealtimeClient?

    var savedDeviceID: String? {
        guard let instance = try? InstanceURL(instanceInput) else { return nil }
        return UserDefaults.standard.string(forKey: Keys.deviceID(instance))
    }

    var instanceHost: String {
        client?.instance.url.host ?? "Common Ground"
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
            self.signingKey = try DeviceKeyStore.loadOrCreate(for: instance)
            self.phase = .authentication
        }
    }

    func signIn(alias: String, password: String) async {
        await perform(activity: "Signing in…") {
            guard let client, let signingKey else { throw AppError.noInstance }
            let session = try await client.auth.loginWithPassword(
                aliasOrEmail: alias,
                password: password,
                deviceKey: signingKey
            )
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
            let session = try await client.auth.loginWithDevice(
                deviceId: deviceID,
                deviceKey: signingKey
            )
            await self.didAuthenticate(session)
        }
    }

    func loadMessages(channel: Channel) async {
        guard let client else { return }
        do {
            let access = MessageAccess.community(channel.communityId, channelId: channel.channelId)
            let messages = try await client.messages.load(access: access)
            store.seed(messages, channelId: channel.channelId)
        } catch {
            errorMessage = userMessage(for: error)
        }
    }

    func sendMessage(channel: Channel) async {
        let text = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let client else { return }
        draftMessage = ""
        do {
            let access = MessageAccess.community(channel.communityId, channelId: channel.channelId)
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
            try DeviceKeyStore.delete(for: client.instance)
            UserDefaults.standard.removeObject(forKey: Keys.deviceID(client.instance))
            signingKey = try DeviceKeyStore.loadOrCreate(for: client.instance)
            phase = .authentication
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
        phase = .instance
    }

    private func didAuthenticate(_ session: AuthSession) async {
        guard let client else { return }
        store.hydrate(from: session.response)
        UserDefaults.standard.set(session.deviceId, forKey: Keys.deviceID(client.instance))
        selectedChannelID = session.response.communities
            .flatMap(\.channels)
            .sorted(by: { $0.order < $1.order })
            .first?.channelId
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
    }

    private enum AppError: Error, LocalizedError {
        case noInstance
        case noSavedDevice
        var errorDescription: String? {
            switch self {
            case .noInstance: return "Connect to an instance first."
            case .noSavedDevice: return "No saved device login was found."
            }
        }
    }
}
