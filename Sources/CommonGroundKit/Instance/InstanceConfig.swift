import Foundation

public enum CaptchaProvider: String, Codable, Sendable {
    case altcha
    case recaptcha
    case off
}

public struct InstanceFeatures: Codable, Equatable, Sendable {
    public let email: Bool?
    public let twitterAuth: Bool?
    public let calls: Bool?
    public let imageFilter: Bool?
}

public struct InstanceConfig: Codable, Equatable, Sendable {
    public let deployment: String?
    public let appUrl: String?
    public let cgidUrl: String?
    public let recaptchaSiteKey: String?
    public let captchaProvider: CaptchaProvider?
    public let activeChains: [String]?
    public let features: InstanceFeatures?
    public let giphyApiKey: String?
    public let walletConnectProjectId: String?
}

public struct InstanceAPI: Sendable {
    private let transport: HTTPTransport

    public init(transport: HTTPTransport) {
        self.transport = transport
    }

    public func config() async throws -> InstanceConfig {
        try await transport.getJSON("Instance/config")
    }
}
