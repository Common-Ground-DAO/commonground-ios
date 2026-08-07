import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public actor HTTPTransport {
    public let baseURL: URL
    private let apiBasePath: String
    private let session: URLSession
    private let cookieStorage: HTTPCookieStorage
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

        let configuration = sessionConfiguration ?? .default
        let storage = configuration.httpCookieStorage ?? HTTPCookieStorage.shared
        configuration.httpCookieStorage = storage
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always
        self.cookieStorage = storage
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
            return (data, http)
        } catch let error as TransportError {
            throw error
        } catch {
            throw TransportError("network error: \(error.localizedDescription)", route: route)
        }
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
                "response data does not match the contract: \(error.localizedDescription)",
                route: route,
                httpStatus: response.statusCode
            )
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
