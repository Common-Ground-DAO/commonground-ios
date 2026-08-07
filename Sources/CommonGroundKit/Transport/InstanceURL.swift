import Foundation

public struct InstanceURL: Codable, Hashable, Sendable, CustomStringConvertible {
    public let url: URL

    public init(_ input: String) throws {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.contains("://") { value = "https://" + value }
        guard var components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = components.host,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              components.path.isEmpty || components.path == "/" else {
            throw ValidationError.invalidInstanceURL
        }
        if scheme == "http" && !Self.isLoopback(host) {
            throw ValidationError.insecureRemoteInstance
        }
        components.scheme = scheme
        components.path = ""
        guard let normalized = components.url else {
            throw ValidationError.invalidInstanceURL
        }
        self.url = normalized
    }

    public var description: String { url.absoluteString }

    public enum ValidationError: Error, LocalizedError {
        case invalidInstanceURL
        case insecureRemoteInstance

        public var errorDescription: String? {
            switch self {
            case .invalidInstanceURL:
                return "Enter an HTTP or HTTPS instance address without a path."
            case .insecureRemoteInstance:
                return "Remote instances must use HTTPS. HTTP is allowed only for local development."
            }
        }
    }

    private static func isLoopback(_ host: String) -> Bool {
        host == "localhost" || host == "127.0.0.1" || host == "::1"
    }
}
