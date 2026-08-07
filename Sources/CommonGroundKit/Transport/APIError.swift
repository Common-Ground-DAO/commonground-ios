import Foundation

public struct APIError: Error, Equatable, LocalizedError, Sendable {
    public let code: String
    public let route: String
    public let httpStatus: Int

    public init(code: String, route: String, httpStatus: Int) {
        self.code = code
        self.route = route
        self.httpStatus = httpStatus
    }

    public var errorDescription: String? { "\(route) failed: \(code)" }
}

public struct TransportError: Error, Equatable, LocalizedError, Sendable {
    public let message: String
    public let route: String
    public let httpStatus: Int?

    public init(_ message: String, route: String, httpStatus: Int? = nil) {
        self.message = message
        self.route = route
        self.httpStatus = httpStatus
    }

    public var errorDescription: String? { "\(route): \(message)" }
}

public struct EmptyResponse: Codable, Equatable, Sendable {
    public init() {}
}
