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

    func testInjectedCookieStoresRemainIsolated() async throws {
        MockURLProtocol.handler = { request in
            Self.response(
                request,
                status: 200,
                body: #"{"status":"OK","data":{"value":"yes"}}"#,
                headers: ["Set-Cookie": "session=one; Path=/; Secure; HttpOnly"]
            )
        }
        let first = HTTPTransport(
            baseURL: URL(string: "https://example.org")!,
            sessionConfiguration: configuration()
        )
        let _: Echo = try await first.call("Test/echo")
        let firstCookie = await first.cookieHeader()
        XCTAssertEqual(firstCookie, "session=one")

        let second = HTTPTransport(
            baseURL: URL(string: "https://example.org")!,
            sessionConfiguration: configuration()
        )
        let secondCookie = await second.cookieHeader()
        XCTAssertNil(secondCookie)
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

    func testLoginResponseMatchesBackendContract() async throws {
        MockURLProtocol.handler = { request in
            let body = #"""
            {
              "status": "OK",
              "data": {
                "ownData": {
                  "id": "11111111-1111-1111-1111-111111111111",
                  "onlineStatus": "offline",
                  "createdAt": "2026-08-07T00:00:00.000Z",
                  "updatedAt": "2026-08-07T00:00:00.000Z",
                  "bannerImageId": null,
                  "displayAccount": "cg",
                  "accounts": [{"type":"cg","displayName":"alice","imageId":null,"extraData":null}],
                  "premiumFeatures": [],
                  "followingCount": 0,
                  "followerCount": 0,
                  "tags": null,
                  "communityOrder": [],
                  "finishedTutorials": [],
                  "newsletter": false,
                  "weeklyNewsletter": false,
                  "dmNotifications": true,
                  "email": "alice@example.org",
                  "features": {},
                  "emailVerified": true,
                  "trustScore": "0",
                  "pointBalance": 0,
                  "passkeys": [],
                  "extraData": {}
                },
                "deviceId": "22222222-2222-2222-2222-222222222222",
                "webPushSubscription": null,
                "communities": [{
                  "id": "33333333-3333-3333-3333-333333333333",
                  "url": "test",
                  "title": "Test",
                  "createdAt": "2026-08-07T00:00:00.000Z",
                  "updatedAt": "2026-08-07T00:00:00.000Z",
                  "memberCount": 1,
                  "myRoleIds": [],
                  "channels": [{
                    "communityId": "33333333-3333-3333-3333-333333333333",
                    "channelId": "44444444-4444-4444-4444-444444444444",
                    "areaId": null,
                    "title": "general",
                    "url": null,
                    "order": 0,
                    "description": null,
                    "emoji": null,
                    "updatedAt": "2026-08-07T00:00:00.000Z",
                    "lastRead": "2026-08-07T00:00:00.000Z",
                    "lastMessageDate": null,
                    "pinnedMessageIds": null,
                    "rolePermissions": []
                  }],
                  "areas": [],
                  "roles": [],
                  "calls": []
                }],
                "chats": [{
                  "id": "55555555-5555-5555-5555-555555555555",
                  "channelId": "66666666-6666-6666-6666-666666666666",
                  "userIds": [],
                  "adminIds": [],
                  "createdAt": "2026-08-07T00:00:00.000Z",
                  "updatedAt": "2026-08-07T00:00:00.000Z",
                  "unread": 3,
                  "lastRead": "2026-08-07T00:00:00.000Z",
                  "lastMessage": null
                }],
                "unreadNotificationCount": "2"
              }
            }
            """#
            return Self.response(request, status: 200, body: body)
        }
        let transport = HTTPTransport(
            baseURL: URL(string: "https://example.org")!,
            sessionConfiguration: configuration()
        )

        let response: LoginResponse = try await transport.call("User/login", body: Echo(value: "request"))

        XCTAssertEqual(response.ownData.displayName, "alice")
        XCTAssertNil(response.communities[0].channels[0].areaId)
        XCTAssertEqual(response.chats[0].unread, 3)

        await MainActor.run {
            let store = SyncStore()
            store.hydrate(from: response)
            XCTAssertEqual(store.chats[response.chats[0].id]?.unread, 3)
            store.reset()
            XCTAssertNil(store.ownUser)
            XCTAssertTrue(store.communities.isEmpty)
            XCTAssertTrue(store.chats.isEmpty)
            XCTAssertTrue(store.messages.isEmpty)
            XCTAssertEqual(store.unreadNotificationCount, 0)
        }
    }

    func testNotificationContractNormalizesUnreadCountAndNullContext() async throws {
        MockURLProtocol.handler = { request in
            switch request.url?.path {
            case "/api/v2/Notification/loadNotifications":
                return Self.response(
                    request,
                    status: 200,
                    body: #"{"status":"OK","data":[{"type":"General","id":"11111111-1111-1111-1111-111111111111","text":"Welcome","createdAt":"2026-08-07T00:00:00.000Z","updatedAt":"2026-08-07T00:00:00.000Z","read":false,"subjectItemId":null,"subjectCommunityId":null,"subjectUserId":null,"subjectArticleId":null,"extraData":null}]}"#
                )
            case "/api/v2/Notification/getUnreadCount":
                return Self.response(request, status: 200, body: #"{"status":"OK","data":"1"}"#)
            default:
                XCTFail("Unexpected route \(request.url?.path ?? "nil")")
                return Self.response(request, status: 500, body: #"{"status":"ERROR","error":"UNKNOWN"}"#)
            }
        }
        let api = NotificationAPI(
            transport: HTTPTransport(
                baseURL: URL(string: "https://example.org")!,
                sessionConfiguration: configuration()
            )
        )

        let notifications = try await api.load()
        XCTAssertEqual(notifications[0].text, "Welcome")
        XCTAssertNil(notifications[0].extraData)
        let unreadCount = try await api.unreadCount()
        XCTAssertEqual(unreadCount, 1)
    }

    func testUserSearchHydratesPublicProfileContract() async throws {
        MockURLProtocol.handler = { request in
            switch request.url?.path {
            case "/api/v2/Search/searchUsers":
                return Self.response(
                    request,
                    status: 200,
                    body: #"{"status":"OK","data":[{"id":"11111111-1111-1111-1111-111111111111","matchPriority":"4","matchedAccountTypes":["cg"]}]}"#
                )
            case "/api/v2/User/getUserData":
                return Self.response(
                    request,
                    status: 200,
                    body: #"{"status":"OK","data":[{"id":"11111111-1111-1111-1111-111111111111","isBot":false,"botOwner":null,"onlineStatus":"online","isFollowed":true,"isFollower":false,"createdAt":"2026-08-07T00:00:00.000Z","updatedAt":"2026-08-07T00:00:00.000Z","bannerImageId":null,"displayAccount":"cg","accounts":[{"type":"cg","displayName":"alice","imageId":null,"extraData":null}],"premiumFeatures":[],"followingCount":2,"followerCount":3,"tags":["swift"]}]}"#
                )
            default:
                XCTFail("Unexpected route \(request.url?.path ?? "nil")")
                return Self.response(request, status: 500, body: #"{"status":"ERROR","error":"UNKNOWN"}"#)
            }
        }
        let api = ProfileAPI(
            transport: HTTPTransport(
                baseURL: URL(string: "https://example.org")!,
                sessionConfiguration: configuration()
            )
        )

        let hits = try await api.searchUsers(query: "ali")
        XCTAssertEqual(hits[0].matchPriority, 4)
        let users = try await api.users(ids: hits.map(\.id))
        XCTAssertEqual(users[0].displayName, "alice")
        XCTAssertTrue(users[0].isFollowed)
        XCTAssertEqual(users[0].tags, ["swift"])
    }

    func testCommunityDiscoveryNormalizesCountAndCreateSendsRequiredNullImages() async throws {
        MockURLProtocol.handler = { request in
            switch request.url?.path {
            case "/api/v2/Community/getCommunityList":
                let body = try XCTUnwrap(Self.bodyData(request))
                let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
                XCTAssertEqual(object["offset"] as? Int, 0)
                XCTAssertEqual(object["sort"] as? String, "popular")
                XCTAssertEqual(object["limit"] as? Int, 50)
                return Self.response(
                    request,
                    status: 200,
                    body: #"{"status":"OK","data":[{"id":"11111111-1111-1111-1111-111111111111","url":"ios-builders","title":"iOS Builders","shortDescription":"Native app people","memberCount":"42","tags":["swift"],"createdAt":"2026-08-07T00:00:00.000Z","updatedAt":"2026-08-07T00:00:00.000Z"}]}"#
                )
            case "/api/v2/Community/createCommunity":
                let body = try XCTUnwrap(Self.bodyData(request))
                let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
                XCTAssertTrue(object["logoSmallId"] is NSNull)
                XCTAssertTrue(object["logoLargeId"] is NSNull)
                XCTAssertTrue(object["headerImageId"] is NSNull)
                return Self.response(
                    request,
                    status: 200,
                    body: #"{"status":"OK","data":{"id":"11111111-1111-1111-1111-111111111111","url":"ios-builders","title":"iOS Builders","createdAt":"2026-08-07T00:00:00.000Z","updatedAt":"2026-08-07T00:00:00.000Z","memberCount":"1","myRoleIds":[],"channels":[],"areas":[],"roles":[],"calls":[]}}"#
                )
            default:
                XCTFail("Unexpected route \(request.url?.path ?? "nil")")
                return Self.response(request, status: 500, body: #"{"status":"ERROR","error":"UNKNOWN"}"#)
            }
        }
        let api = CommunityAPI(
            transport: HTTPTransport(
                baseURL: URL(string: "https://example.org")!,
                sessionConfiguration: configuration()
            )
        )

        let communities = try await api.list()
        XCTAssertEqual(communities[0].memberCount, 42)
        XCTAssertEqual(communities[0].tags, ["swift"])
        let created = try await api.create(title: "iOS Builders", tags: ["swift"])
        XCTAssertEqual(created.title, "iOS Builders")
    }

    func testReportContractUsesModerationRouteAndReasonCode() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/v2/Report/createReport")
            let body = try XCTUnwrap(Self.bodyData(request))
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(object["type"] as? String, "MESSAGE")
            XCTAssertEqual(object["reason"] as? String, "abusive-content")
            XCTAssertEqual(object["message"] as? String, "details")
            return Self.response(request, status: 200, body: #"{"status":"OK"}"#)
        }
        let api = ReportAPI(
            transport: HTTPTransport(
                baseURL: URL(string: "https://example.org")!,
                sessionConfiguration: configuration()
            )
        )

        try await api.create(
            type: .message,
            targetID: "11111111-1111-1111-1111-111111111111",
            reason: .abusiveContent,
            message: "details"
        )
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

    func testReplyMentionAndImageAttachmentRequestShape() async throws {
        MockURLProtocol.handler = { request in
            let body = try XCTUnwrap(Self.bodyData(request))
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(object["parentMessageId"] as? String, "55555555-5555-5555-5555-555555555555")
            let content = try XCTUnwrap((object["body"] as? [String: Any])?["content"] as? [[String: Any]])
            XCTAssertEqual(content.first(where: { $0["type"] as? String == "mention" })?["userId"] as? String, "66666666-6666-6666-6666-666666666666")
            let attachments = try XCTUnwrap(object["attachments"] as? [[String: Any]])
            XCTAssertEqual(attachments[0]["type"] as? String, "image")
            let response = #"{"status":"OK","data":{"id":"11111111-1111-1111-1111-111111111111","creatorId":"22222222-2222-2222-2222-222222222222","channelId":"33333333-3333-3333-3333-333333333333","body":{"version":"1","content":[{"type":"mention","userId":"66666666-6666-6666-6666-666666666666","alias":"alice"},{"type":"text","value":" hello"}]},"attachments":[{"type":"image","imageId":"77777777-7777-7777-7777-777777777777","largeImageId":"88888888-8888-8888-8888-888888888888"}],"editedAt":null,"createdAt":"2026-08-07T00:00:00.000Z","updatedAt":"2026-08-07T00:00:00.000Z","reactions":{},"ownReaction":null,"parentMessageId":"55555555-5555-5555-5555-555555555555"}}"#
            return Self.response(request, status: 200, body: response)
        }
        let api = MessageAPI(
            transport: HTTPTransport(
                baseURL: URL(string: "https://example.org")!,
                sessionConfiguration: configuration()
            )
        )
        let message = try await api.send(
            access: .community(
                "44444444-4444-4444-4444-444444444444",
                channelId: "33333333-3333-3333-3333-333333333333"
            ),
            text: "@alice hello",
            mentions: ["alice": "66666666-6666-6666-6666-666666666666"],
            parentMessageID: "55555555-5555-5555-5555-555555555555",
            imageAttachments: [
                MessageImageAttachment(
                    imageId: "77777777-7777-7777-7777-777777777777",
                    largeImageId: "88888888-8888-8888-8888-888888888888"
                )
            ]
        )
        XCTAssertEqual(message.parentMessageId, "55555555-5555-5555-5555-555555555555")
        XCTAssertEqual(message.imageAttachments.count, 1)
        XCTAssertEqual(message.body.plainText, "@alice hello")
    }

    func testRichMessageMutationContracts() async throws {
        var routes: [String] = []
        MockURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            routes.append(path)
            let body = try XCTUnwrap(Self.bodyData(request))
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(
                (object["access"] as? [String: Any])?["channelId"] as? String,
                "33333333-3333-3333-3333-333333333333"
            )
            switch path {
            case "/api/v2/Message/editMessage":
                XCTAssertEqual(object["id"] as? String, "11111111-1111-1111-1111-111111111111")
                return Self.response(
                    request,
                    status: 200,
                    body: #"{"status":"OK","data":{"editedAt":"2026-08-07T01:00:00.000Z"}}"#
                )
            case "/api/v2/Message/deleteMessage":
                XCTAssertEqual(object["creatorId"] as? String, "22222222-2222-2222-2222-222222222222")
            case "/api/v2/Message/setReaction":
                XCTAssertEqual(object["reaction"] as? String, "👍")
            case "/api/v2/Message/unsetReaction":
                XCTAssertNil(object["reaction"])
            default:
                XCTFail("Unexpected route \(path)")
            }
            return Self.response(request, status: 200, body: #"{"status":"OK"}"#)
        }
        let api = MessageAPI(
            transport: HTTPTransport(
                baseURL: URL(string: "https://example.org")!,
                sessionConfiguration: configuration()
            )
        )
        let access = MessageAccess.community(
            "44444444-4444-4444-4444-444444444444",
            channelId: "33333333-3333-3333-3333-333333333333"
        )
        let messageID = "11111111-1111-1111-1111-111111111111"
        let edit = try await api.edit(access: access, messageID: messageID, text: "edited")
        XCTAssertEqual(edit.editedAt, "2026-08-07T01:00:00.000Z")
        try await api.delete(
            access: access,
            messageID: messageID,
            creatorID: "22222222-2222-2222-2222-222222222222"
        )
        try await api.setReaction(access: access, messageID: messageID, reaction: "👍")
        try await api.unsetReaction(access: access, messageID: messageID)
        XCTAssertEqual(routes.count, 4)
    }

    func testImageUploadUsesMultipartAndAcceptsBareSuccess() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/v2/File/uploadImage")
            XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
            let body = try XCTUnwrap(Self.bodyData(request))
            let string = String(decoding: body, as: UTF8.self)
            XCTAssertTrue(string.contains("name=\"uploaded\"; filename=\"photo.jpg\""))
            XCTAssertTrue(string.contains("name=\"options\""))
            XCTAssertTrue(string.contains("channelAttachmentImage"))
            XCTAssertTrue(body.range(of: Data([0x01, 0x02, 0x03])) != nil)
            return Self.response(
                request,
                status: 200,
                body: #"{"imageId":"11111111-1111-1111-1111-111111111111","largeImageId":"22222222-2222-2222-2222-222222222222"}"#
            )
        }
        let api = FileAPI(
            transport: HTTPTransport(
                baseURL: URL(string: "https://example.org")!,
                sessionConfiguration: configuration()
            )
        )

        let result = try await api.uploadImage(
            Data([0x01, 0x02, 0x03]),
            type: .channelAttachmentImage,
            filename: "photo.jpg"
        )
        XCTAssertEqual(result.largeImageId, "22222222-2222-2222-2222-222222222222")
    }

    func testMessageLoadTreatsNullReactionsAsEmpty() async throws {
        MockURLProtocol.handler = { request in
            let response = #"{"status":"OK","data":[{"id":"11111111-1111-1111-1111-111111111111","creatorId":"22222222-2222-2222-2222-222222222222","channelId":"33333333-3333-3333-3333-333333333333","body":{"version":"1","content":[{"type":"text","value":"legacy"}]},"attachments":[],"editedAt":null,"createdAt":"2026-08-07T00:00:00.000Z","updatedAt":"2026-08-07T00:00:00.000Z","reactions":null,"ownReaction":null,"parentMessageId":null}]}"#
            return Self.response(request, status: 200, body: response)
        }
        let api = MessageAPI(
            transport: HTTPTransport(
                baseURL: URL(string: "https://example.org")!,
                sessionConfiguration: configuration()
            )
        )
        let messages = try await api.load(
            access: .community(
                "44444444-4444-4444-4444-444444444444",
                channelId: "33333333-3333-3333-3333-333333333333"
            )
        )

        XCTAssertEqual(messages[0].body.plainText, "legacy")
        XCTAssertEqual(messages[0].reactions, [:])
    }

    /// Opt-in compatibility probe for the deployed development instance. It
    /// creates a disposable account, logs out, then exercises password login
    /// against the real response payload. It is skipped during normal tests.
    func testLiveRegistrationAndPasswordLoginContract() async throws {
        guard ProcessInfo.processInfo.environment["COMMON_GROUND_LIVE_AUTH"] == "1" else {
            throw XCTSkip("Set COMMON_GROUND_LIVE_AUTH=1 to run the live auth probe")
        }

        let suffix = UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
        let email = "ios-e2e-\(suffix.prefix(16))@example.org"
        let displayName = "ios\(suffix.prefix(12))"
        let password = "Cg!\(suffix)9a"
        let instance = try InstanceURL("https://cg.mogged.eu")
        let registrationClient = CommonGroundClient(
            instance: instance,
            sessionConfiguration: .ephemeral
        )
        let registration = try await registrationClient.auth.register(
            email: email,
            password: password,
            displayName: displayName,
            deviceKey: SoftwareDeviceKey()
        )
        XCTAssertEqual(registration.response.ownData.email, email)
        try await registrationClient.auth.logout()

        let loginClient = CommonGroundClient(
            instance: instance,
            sessionConfiguration: .ephemeral
        )
        let login = try await loginClient.auth.loginWithPassword(
            aliasOrEmail: email,
            password: password,
            deviceKey: SoftwareDeviceKey()
        )
        XCTAssertEqual(login.response.ownData.id, registration.response.ownData.id)
        try await loginClient.auth.logout()
    }

    /// Login-only live probe for an existing account. Credentials are supplied
    /// through the environment and are never stored in the repository.
    func testLiveExistingAccountPasswordLoginContract() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let email = environment["COMMON_GROUND_LIVE_EMAIL"],
              let password = environment["COMMON_GROUND_LIVE_PASSWORD"] else {
            throw XCTSkip("Set live email/password variables to run the existing-account probe")
        }
        let client = CommonGroundClient(
            instance: try InstanceURL("https://cg.mogged.eu"),
            sessionConfiguration: .ephemeral
        )
        let login = try await client.auth.loginWithPassword(
            aliasOrEmail: email,
            password: password,
            deviceKey: SoftwareDeviceKey()
        )
        XCTAssertEqual(login.response.ownData.email, email)
        let selectedChannel = try XCTUnwrap(
            login.response.communities
                .flatMap(\.channels)
                .sorted(by: { $0.order < $1.order })
                .first
        )
        let selectedCommunity = try XCTUnwrap(
            login.response.communities.first { community in
                community.channels.contains { $0.channelId == selectedChannel.channelId }
            }
        )
        let messages = try await client.messages.load(
            access: .community(
                selectedCommunity.id,
                channelId: selectedChannel.channelId
            )
        )
        let latestOwn = messages
            .filter { $0.creatorId == login.response.ownData.id }
            .max(by: { $0.createdAt < $1.createdAt })
        let notifications = try await client.notifications.load()
        let unreadCount = try await client.notifications.unreadCount()
        let publicCommunities = try await client.communities.list(limit: 10)
        let hits = try await client.profiles.searchUsers(query: login.response.ownData.displayName)
        let profiles = try await client.profiles.users(ids: [login.response.ownData.id])
        XCTAssertTrue(hits.contains(where: { $0.id == login.response.ownData.id }))
        XCTAssertEqual(profiles.first?.id, login.response.ownData.id)
        print(
            "LIVE_AUTH_SELECTED community=\(selectedCommunity.title) " +
            "communityID=\(selectedCommunity.id) channel=\(selectedChannel.title) " +
            "channelID=\(selectedChannel.channelId) messages=\(messages.count) " +
            "latestOwnID=\(latestOwn?.id ?? "none") latestOwnAt=\(latestOwn?.createdAt ?? "none") " +
            "notifications=\(notifications.count) unread=\(unreadCount) " +
            "publicCommunities=\(publicCommunities.count)"
        )
        try await client.auth.logout()
    }

    private func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return configuration
    }

    private static func response(
        _ request: URLRequest,
        status: Int,
        body: String,
        headers: [String: String] = [:]
    ) -> (HTTPURLResponse, Data) {
        var responseHeaders = ["Content-Type": "application/json"]
        responseHeaders.merge(headers) { _, new in new }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: nil,
            headerFields: responseHeaders
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
