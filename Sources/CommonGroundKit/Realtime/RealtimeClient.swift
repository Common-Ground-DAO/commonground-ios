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

    public init(transport: HTTPTransport) {
        self.transport = transport
    }

    public func connect(reconnects: Bool = true) async throws {
        guard socket == nil else { throw RealtimeError.alreadyConnected }
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

    public func close() {
        socket?.disconnect()
        socket = nil
        manager = nil
        connected = false
        greeting = nil
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
