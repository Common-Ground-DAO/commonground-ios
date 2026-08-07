import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public actor HTTPTransport {
    public let baseURL: URL
    private let apiBasePath: String
    private let session: URLSession
    private let cookieStorage: HTTPCookieStorage
    private let cookiePersistence: PersistentCookieStore?
    private let extraHeaders: [String: String]

    public init(
        baseURL: URL,
        apiBasePath: String = "/api/v2",
        extraHeaders: [String: String] = [:],
        sessionConfiguration: URLSessionConfiguration? = nil
    ) {
        self.baseURL = baseURL
        self.apiBasePath = apiBasePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.extraHeaders = extraHeaders

        let configuration = sessionConfiguration ?? .ephemeral
        let storage = configuration.httpCookieStorage
            ?? URLSessionConfiguration.ephemeral.httpCookieStorage!
        let persistence = sessionConfiguration == nil
            ? PersistentCookieStore(baseURL: baseURL)
            : nil
        configuration.httpCookieStorage = storage
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always
        self.cookieStorage = storage
        self.cookiePersistence = persistence
        if let persistence {
            for cookie in persistence.load() { storage.setCookie(cookie) }
        }
        self.session = URLSession(configuration: configuration)
    }

    public func call<Response: Decodable & Sendable, Body: Encodable & Sendable>(
        _ route: String,
        body: Body,
        as responseType: Response.Type = Response.self
    ) async throws -> Response {
        var request = URLRequest(url: try endpoint(route))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyExtraHeaders(to: &request)
        request.httpBody = try Self.encoder.encode(body)

        let (data, response) = try await perform(request, route: route)
        return try decodeEnvelope(data, response: response, route: route, as: responseType)
    }

    public func call<Response: Decodable & Sendable>(
        _ route: String,
        as responseType: Response.Type = Response.self
    ) async throws -> Response {
        try await call(route, body: EmptyRequest(), as: responseType)
    }

    public func getJSON<Response: Decodable & Sendable>(
        _ route: String,
        as responseType: Response.Type = Response.self
    ) async throws -> Response {
        var request = URLRequest(url: try endpoint(route))
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        applyExtraHeaders(to: &request)
        let (data, response) = try await perform(request, route: route)
        guard (200..<300).contains(response.statusCode) else {
            throw TransportError(
                "unexpected HTTP \(response.statusCode)",
                route: route,
                httpStatus: response.statusCode
            )
        }
        do {
            return try Self.decoder.decode(Response.self, from: data)
        } catch {
            throw TransportError(
                "response is not valid JSON: \(error.localizedDescription)",
                route: route,
                httpStatus: response.statusCode
            )
        }
    }

    public func cookieHeader() -> String? {
        let cookies = cookieStorage.cookies(for: baseURL) ?? []
        guard !cookies.isEmpty else { return nil }
        return HTTPCookie.requestHeaderFields(with: cookies)["Cookie"]
    }

    public func clearCookies() {
        for cookie in cookieStorage.cookies(for: baseURL) ?? [] {
            cookieStorage.deleteCookie(cookie)
        }
        cookiePersistence?.clear()
    }

    private func endpoint(_ route: String) throws -> URL {
        let cleanRoute = route.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(baseURL.absoluteString)/\(apiBasePath)/\(cleanRoute)") else {
            throw TransportError("invalid route URL", route: route)
        }
        return url
    }

    private func applyExtraHeaders(to request: inout URLRequest) {
        for (name, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: name)
        }
    }

    private func perform(_ request: URLRequest, route: String) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw TransportError("response is not HTTP", route: route)
            }
            captureCookies(from: http, requestURL: request.url)
            return (data, http)
        } catch let error as TransportError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw TransportError("network error: \(error.localizedDescription)", route: route)
        }
    }

    private func captureCookies(from response: HTTPURLResponse, requestURL: URL?) {
        guard let requestURL else { return }
        var headers: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            headers[String(describing: key)] = String(describing: value)
        }
        for cookie in HTTPCookie.cookies(withResponseHeaderFields: headers, for: requestURL) {
            if let expiration = cookie.expiresDate, expiration <= Date() {
                cookieStorage.deleteCookie(cookie)
            } else {
                cookieStorage.setCookie(cookie)
            }
        }
        cookiePersistence?.save(cookieStorage.cookies(for: baseURL) ?? [])
    }

    private func decodeEnvelope<Response: Decodable>(
        _ data: Data,
        response: HTTPURLResponse,
        route: String,
        as type: Response.Type
    ) throws -> Response {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw TransportError("response is not JSON", route: route, httpStatus: response.statusCode)
        }
        guard let envelope = object as? [String: Any], let status = envelope["status"] as? String else {
            throw TransportError("response is not an API envelope", route: route, httpStatus: response.statusCode)
        }
        if status == "ERROR", let code = envelope["error"] as? String {
            throw APIError(code: code, route: route, httpStatus: response.statusCode)
        }
        guard status == "OK" else {
            throw TransportError("response has an unknown envelope status", route: route, httpStatus: response.statusCode)
        }
        if Response.self == EmptyResponse.self {
            return EmptyResponse() as! Response
        }
        guard let payload = envelope["data"] else {
            throw TransportError("successful response has no data", route: route, httpStatus: response.statusCode)
        }
        do {
            let payloadData = try JSONSerialization.data(withJSONObject: payload, options: [.fragmentsAllowed])
            return try Self.decoder.decode(Response.self, from: payloadData)
        } catch {
            throw TransportError(
                "response data does not match the contract: \(Self.decodingDescription(error))",
                route: route,
                httpStatus: response.statusCode
            )
        }
    }

    private static func decodingDescription(_ error: Error) -> String {
        func path(_ context: DecodingError.Context) -> String {
            let value = context.codingPath.map(\.stringValue).joined(separator: ".")
            return value.isEmpty ? "<root>" : value
        }

        guard let decodingError = error as? DecodingError else {
            return error.localizedDescription
        }
        switch decodingError {
        case .keyNotFound(let key, let context):
            return "missing key '\(key.stringValue)' at \(path(context)): \(context.debugDescription)"
        case .typeMismatch(let type, let context):
            return "expected \(type) at \(path(context)): \(context.debugDescription)"
        case .valueNotFound(let type, let context):
            return "missing \(type) value at \(path(context)): \(context.debugDescription)"
        case .dataCorrupted(let context):
            return "invalid data at \(path(context)): \(context.debugDescription)"
        @unknown default:
            return error.localizedDescription
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return encoder
    }()

    private static let decoder = JSONDecoder()
}

private struct EmptyRequest: Encodable, Sendable {}
