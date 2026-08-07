@testable import CommonGroundKit
import CryptoKit
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest

final class CommonGroundKitTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockURLProtocol.handler = nil
    }

    func testInstanceURLNormalizesAndRejectsRemoteHTTP() throws {
        XCTAssertEqual(try InstanceURL("cg.mogged.eu/").description, "https://cg.mogged.eu")
        XCTAssertEqual(try InstanceURL("http://127.0.0.1:18080").description, "http://127.0.0.1:18080")
        XCTAssertThrowsError(try InstanceURL("http://example.org"))
        XCTAssertThrowsError(try InstanceURL("https://example.org/a/path"))
    }

    func testTransportUnwrapsSuccessfulEnvelope() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/v2/Test/echo")
            return Self.response(request, status: 200, body: #"{"status":"OK","data":{"value":"yes"}}"#)
        }
        let transport = HTTPTransport(
            baseURL: URL(string: "https://example.org")!,
            sessionConfiguration: configuration()
        )
        let result: Echo = try await transport.call("Test/echo", body: Echo(value: "request"))
        XCTAssertEqual(result.value, "yes")
    }

    func testTransportThrowsAPIErrorFromHTTP200() async throws {
        MockURLProtocol.handler = { request in
            Self.response(request, status: 200, body: #"{"status":"ERROR","error":"LOGIN_REQUIRED"}"#)
        }
        let transport = HTTPTransport(
            baseURL: URL(string: "https://example.org")!,
            sessionConfiguration: configuration()
        )
        do {
            let _: Echo = try await transport.call("Chat/getChats")
            XCTFail("Expected an API error")
        } catch let error as APIError {
            XCTAssertEqual(error.code, "LOGIN_REQUIRED")
            XCTAssertEqual(error.httpStatus, 200)
        }
    }

    func testBareInstanceConfig() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            return Self.response(
                request,
                status: 200,
                body: #"{"deployment":"prod","appUrl":"https://example.org","captchaProvider":"altcha","activeChains":[]}"#
            )
        }
        let transport = HTTPTransport(
            baseURL: URL(string: "https://example.org")!,
            sessionConfiguration: configuration()
        )
        let config = try await InstanceAPI(transport: transport).config()
        XCTAssertEqual(config.captchaProvider, .altcha)
        XCTAssertEqual(config.appUrl, "https://example.org")
    }

    func testPBKDF2SHA256KnownVector() {
        let derived = AltchaSolver.pbkdf2SHA256(
            password: Data("password".utf8),
            salt: Data("salt".utf8),
            iterations: 2,
            keyLength: 32
        )
        XCTAssertEqual(hex(derived), "ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43")
    }

    func testAltchaSolveAndLosslessTokenRoundTrip() async throws {
        let nonce = Data([0])
        let salt = Data([0])
        var counter = UInt32(0).bigEndian
        var password = nonce
        withUnsafeBytes(of: &counter) { password.append(contentsOf: $0) }
        let derived = AltchaSolver.pbkdf2SHA256(password: password, salt: salt, iterations: 1, keyLength: 32)
        let prefix = String(hex(derived).prefix(4))
        let json = #"{"parameters":{"algorithm":"PBKDF2/SHA-256","nonce":"00","salt":"00","cost":1,"keyLength":32,"keyPrefix":"\#(prefix)","expiresAt":1999999999,"futureField":"preserved"},"signature":"abc123"}"#
        let challenge = try JSONDecoder().decode(AltchaChallenge.self, from: Data(json.utf8))
        let solution = try await AltchaSolver.solve(challenge, timeout: 1)
        XCTAssertEqual(solution?.counter, 0)

        let token = try CaptchaService.buildToken(challenge: challenge, solution: XCTUnwrap(solution))
        let decoded = try XCTUnwrap(Data(base64Encoded: token))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: decoded) as? [String: Any])
        let encodedChallenge = try XCTUnwrap(object["challenge"] as? [String: Any])
        let parameters = try XCTUnwrap(encodedChallenge["parameters"] as? [String: Any])
        XCTAssertEqual(parameters["futureField"] as? String, "preserved")
    }

    func testSoftwareDeviceSignatureIsP1363() async throws {
        let key = try SoftwareDeviceKey()
        let encoded = try await key.signSecret("01234567890123456789")
        XCTAssertEqual(Data(base64Encoded: encoded)?.count, 64)
        XCTAssertEqual(key.publicJWK.crv, "P-256")
        XCTAssertFalse(key.publicJWK.x.contains("="))
    }

    func testDERToP1363PadsCoordinates() throws {
        // SEQUENCE(INTEGER 1, INTEGER 0x80 with DER sign padding)
        let der = Data([0x30, 0x08, 0x02, 0x01, 0x01, 0x02, 0x03, 0x00, 0x80, 0x01])
        let raw = try SecureEnclaveDeviceKey.p1363Signature(fromDER: der, coordinateSize: 2)
        XCTAssertEqual(raw, Data([0x00, 0x01, 0x80, 0x01]))
    }

    func testStructuredTextBodyPreservesNewlines() {
        let body = MessageBody.text("hello\n\nworld")
        XCTAssertEqual(body.version, "1")
        XCTAssertEqual(body.plainText, "hello\n\nworld")
    }

    func testRegistrationProfileEncodesRequiredNullImageID() throws {
        let profile = CreateUserRequest.CGProfile(displayName: "alice")
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(profile)) as? [String: Any]
        )
        XCTAssertTrue(object["imageId"] is NSNull)
    }

    func testMessageCreateEncodesRequiredNullParentID() async throws {
        MockURLProtocol.handler = { request in
            let body = try XCTUnwrap(Self.bodyData(request))
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertTrue(object["parentMessageId"] is NSNull)
            let response = #"{"status":"OK","data":{"id":"11111111-1111-1111-1111-111111111111","creatorId":"22222222-2222-2222-2222-222222222222","channelId":"33333333-3333-3333-3333-333333333333","body":{"version":"1","content":[{"type":"text","value":"hello"}]},"attachments":[],"editedAt":null,"createdAt":"2026-08-07T00:00:00.000Z","updatedAt":"2026-08-07T00:00:00.000Z","reactions":{},"ownReaction":null,"parentMessageId":null}}"#
            return Self.response(request, status: 200, body: response)
        }
        let transport = HTTPTransport(
            baseURL: URL(string: "https://example.org")!,
            sessionConfiguration: configuration()
        )
        let api = MessageAPI(transport: transport)
        let access = MessageAccess.community(
            "44444444-4444-4444-4444-444444444444",
            channelId: "33333333-3333-3333-3333-333333333333"
        )
        let message = try await api.send(access: access, text: "hello")
        XCTAssertEqual(message.body.plainText, "hello")
    }

    private func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return configuration
    }

    private static func response(
        _ request: URLRequest,
        status: Int,
        body: String
    ) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, Data(body.utf8))
    }

    private static func bodyData(_ request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var result = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4_096)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: 4_096)
            guard count >= 0 else { return nil }
            if count == 0 { break }
            result.append(buffer, count: count)
        }
        return result
    }

    private func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}

private struct Echo: Codable, Sendable {
    let value: String
}

private final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let (response, data) = try Self.handler!(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
