import Foundation
import SocketIO

public enum RealtimeEventName: String, CaseIterable, Codable, Sendable {
    case message = "cliMessageEvent"
    case community = "cliCommunityEvent"
    case channel = "cliChannelEvent"
    case area = "cliAreaEvent"
    case role = "cliRoleEvent"
    case plugin = "cliPluginEvent"
    case membership = "cliMembershipEvent"
    case myRoles = "cliMyRolesEvent"
    case chat = "cliChatEvent"
    case channelLastRead = "cliChannelLastRead"
    case notification = "cliNotificationEvent"
    case userData = "cliUserData"
    case userOwnData = "cliUserOwnData"
    case wallet = "cliWalletEvent"
    case call = "cliCallEvent"
    case botScopes = "cliBotScopesEvent"
    case cgIDSignResponse = "cliCgIdSignResponse"
}

public struct RealtimeEvent: Equatable, Sendable {
    public let type: RealtimeEventName
    public let payload: JSONValue
    public let receivedAt: Date
}

public struct BuildGreeting: Equatable, Sendable {
    public let buildId: String
    public let serverTime: Double
}

public enum RealtimeConnectionStatus: Equatable, Sendable {
    case connected
    case authenticated
    case reconnecting
    case disconnected
    case authenticationFailed
}

/// Socket.IO transport for `/api/ws/`. Session cookies establish the socket;
/// `login` then performs the required in-band device-signature handshake.
@MainActor
public final class RealtimeClient: ObservableObject {
    @Published public private(set) var connected = false
    @Published public private(set) var greeting: BuildGreeting?
    @Published public private(set) var latestEvent: RealtimeEvent?

    private let transport: HTTPTransport
    private var manager: SocketManager?
    private var socket: SocketIOClient?
    private var listeners: [UUID: @MainActor (RealtimeEvent) -> Void] = [:]
    private var statusListeners: [UUID: @MainActor (RealtimeConnectionStatus) -> Void] = [:]
    private var authentication: (deviceID: String, deviceKey: any DeviceSigningKey)?
    private var isAuthenticating = false
    private var isClosing = false

    public init(transport: HTTPTransport) {
        self.transport = transport
    }

    public func connect(reconnects: Bool = true) async throws {
        guard socket == nil else { throw RealtimeError.alreadyConnected }
        let retryDelays: [UInt64] = [400_000_000, 1_000_000_000]
        var lastError: Error?

        for attempt in 0...retryDelays.count {
            do {
                try await connectOnce(reconnects: reconnects)
                return
            } catch {
                tearDownSocket()
                if error is CancellationError { throw error }
                lastError = error
                guard attempt < retryDelays.count else { break }
                try await Task.sleep(nanoseconds: retryDelays[attempt])
            }
        }
        throw lastError ?? RealtimeError.connectionFailed("unknown")
    }

    private func connectOnce(reconnects: Bool) async throws {
        let cookie = await transport.cookieHeader()
        var configuration: SocketIOClientConfiguration = [
            .path("/api/ws/"),
            .forceWebsockets(true),
            .reconnects(reconnects),
            .log(false)
        ]
        if let cookie { configuration.insert(.extraHeaders(["Cookie": cookie])) }

        let manager = SocketManager(socketURL: transport.baseURL, config: configuration)
        let socket = manager.defaultSocket
        self.manager = manager
        self.socket = socket

        socket.on(clientEvent: .connect) { [weak self] _, _ in
            guard let self else { return }
            self.connected = true
            self.publishStatus(.connected)
            guard self.authentication != nil else { return }
            Task { @MainActor [weak self] in
                await self?.reauthenticateAfterReconnect()
            }
        }
        socket.on(clientEvent: .disconnect) { [weak self] _, _ in
            guard let self else { return }
            self.connected = false
            self.publishStatus(self.isClosing ? .disconnected : .reconnecting)
        }
        socket.on(clientEvent: .error) { [weak self] _, _ in
            guard let self, self.authentication != nil else { return }
            self.publishStatus(.reconnecting)
        }

        socket.on("buildId") { [weak self] data, _ in
            guard let buildId = data.first as? String else { return }
            let time = (data.dropFirst().first as? NSNumber)?.doubleValue ?? 0
            self?.greeting = BuildGreeting(buildId: buildId, serverTime: time)
        }
        for eventName in RealtimeEventName.allCases {
            socket.on(eventName.rawValue) { [weak self] data, _ in
                guard let self else { return }
                let payload = Self.jsonValue(from: data.first) ?? .object([:])
                let event = RealtimeEvent(type: eventName, payload: payload, receivedAt: Date())
                self.latestEvent = event
                for listener in self.listeners.values { listener(event) }
            }
        }

        try await withCheckedThrowingContinuation { continuation in
            var resumed = false
            socket.once(clientEvent: .connect) { [weak self] _, _ in
                guard !resumed else { return }
                resumed = true
                self?.connected = true
                continuation.resume()
            }
            socket.once(clientEvent: .error) { data, _ in
                guard !resumed else { return }
                resumed = true
                continuation.resume(throwing: RealtimeError.connectionFailed(String(describing: data.first ?? "unknown")))
            }
            socket.connect()
        }
    }

    public func login(deviceId: String, deviceKey: any DeviceSigningKey) async throws {
        authentication = (deviceId, deviceKey)
        try await performLogin(deviceId: deviceId, deviceKey: deviceKey)
        publishStatus(.authenticated)
    }

    private func performLogin(deviceId: String, deviceKey: any DeviceSigningKey) async throws {
        let secretValue = try await emitWithAck("getSignableSecret")
        guard let secret = secretValue as? String else { throw RealtimeError.invalidAcknowledgement }
        let signature = try await deviceKey.signSecret(secret)
        let result = try await emitWithAck(
            "login",
            ["secret": secret, "deviceId": deviceId, "base64Signature": signature]
        )
        guard (result as? String) == "OK" else {
            throw RealtimeError.loginFailed(String(describing: result))
        }
    }

    private func reauthenticateAfterReconnect() async {
        guard let authentication, !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }
        do {
            try await performLogin(
                deviceId: authentication.deviceID,
                deviceKey: authentication.deviceKey
            )
            publishStatus(.authenticated)
        } catch {
            publishStatus(.authenticationFailed)
        }
    }

    public func ping() async throws -> Double {
        let value = try await emitWithAck("cgPing")
        guard let number = value as? NSNumber else { throw RealtimeError.invalidAcknowledgement }
        return number.doubleValue
    }

    @discardableResult
    public func onEvent(_ listener: @escaping @MainActor (RealtimeEvent) -> Void) -> UUID {
        let id = UUID()
        listeners[id] = listener
        return id
    }

    public func removeListener(_ id: UUID) {
        listeners.removeValue(forKey: id)
    }

    @discardableResult
    public func onStatus(
        _ listener: @escaping @MainActor (RealtimeConnectionStatus) -> Void
    ) -> UUID {
        let id = UUID()
        statusListeners[id] = listener
        return id
    }

    public func removeStatusListener(_ id: UUID) {
        statusListeners.removeValue(forKey: id)
    }

    public func close() {
        isClosing = true
        authentication = nil
        tearDownSocket()
        greeting = nil
        publishStatus(.disconnected)
        isClosing = false
    }

    private func tearDownSocket() {
        socket?.removeAllHandlers()
        socket?.disconnect()
        socket = nil
        manager = nil
        connected = false
    }

    private func publishStatus(_ status: RealtimeConnectionStatus) {
        for listener in statusListeners.values { listener(status) }
    }

    private func emitWithAck(_ event: String, _ items: SocketData...) async throws -> Any {
        guard let socket else { throw RealtimeError.notConnected }
        return try await withCheckedThrowingContinuation { continuation in
            socket.emitWithAck(event, with: items).timingOut(after: 15) { data in
                guard let first = data.first else {
                    continuation.resume(throwing: RealtimeError.invalidAcknowledgement)
                    return
                }
                if let value = first as? String, value == SocketAckStatus.noAck.rawValue {
                    continuation.resume(throwing: RealtimeError.acknowledgementTimedOut)
                } else {
                    continuation.resume(returning: first)
                }
            }
        }
    }

    private static func jsonValue(from value: Any?) -> JSONValue? {
        guard let value, JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value) else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }
}

public enum RealtimeError: Error, LocalizedError {
    case alreadyConnected
    case notConnected
    case connectionFailed(String)
    case invalidAcknowledgement
    case acknowledgementTimedOut
    case loginFailed(String)

    public var errorDescription: String? {
        switch self {
        case .alreadyConnected: return "Realtime is already connected."
        case .notConnected: return "Realtime is not connected."
        case .connectionFailed(let reason): return "Realtime connection failed: \(reason)"
        case .invalidAcknowledgement: return "The realtime server returned an invalid acknowledgement."
        case .acknowledgementTimedOut: return "The realtime server did not acknowledge the request."
        case .loginFailed(let reason): return "Realtime login failed: \(reason)"
        }
    }
}
