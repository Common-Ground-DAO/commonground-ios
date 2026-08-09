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
            store.apply(
                RealtimeEvent(
                    type: .community,
                    payload: .object([
                        "action": .string("update"),
                        "data": .object([
                            "id": .string(response.communities[0].id),
                            "pointBalance": .number(12_345),
                        ]),
                    ]),
                    receivedAt: Date()
                )
            )
            XCTAssertEqual(store.communities[response.communities[0].id]?.pointBalance, 12_345)
            store.applyCommunityFields(
                id: response.communities[0].id,
                fields: ["headerImageId": .string("fresh-hero")]
            )
            XCTAssertEqual(
                store.communities[response.communities[0].id]?.headerImageId,
                "fresh-hero"
            )
            store.apply(
                RealtimeEvent(
                    type: .userOwnData,
                    payload: .object([
                        "data": .object(["pointBalance": .number(54_321)]),
                    ]),
                    receivedAt: Date()
                )
            )
            XCTAssertEqual(store.ownUser?.pointBalance, 54_321)
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

    func testTypingPresenceRoutesFlatEventsStopsAndExpires() async throws {
        let access = MessageAccess.community(
            "33333333-3333-3333-3333-333333333333",
            channelId: "44444444-4444-4444-4444-444444444444"
        )
        let accessJSON = try JSONDecoder().decode(
            JSONValue.self,
            from: JSONEncoder().encode(access)
        )
        @Sendable func event(userID: String, isTyping: Bool) -> RealtimeEvent {
            RealtimeEvent(
                type: .typing,
                payload: .object([
                    "access": accessJSON,
                    "userId": .string(userID),
                    "isTyping": .bool(isTyping),
                ]),
                receivedAt: Date()
            )
        }

        let store = await MainActor.run { SyncStore(typingExpiry: .milliseconds(120)) }
        await MainActor.run {
            store.apply(event(userID: "user-a", isTyping: true))
            store.apply(event(userID: "user-b", isTyping: true))
            XCTAssertEqual(store.typingUserIDs(for: access), ["user-a", "user-b"])

            store.apply(event(userID: "user-a", isTyping: false))
            XCTAssertEqual(store.typingUserIDs(for: access), ["user-b"])
        }

        try await Task.sleep(for: .milliseconds(180))
        await MainActor.run {
            XCTAssertTrue(store.typingUserIDs(for: access).isEmpty)
            XCTAssertNil(store.typingUsersByAccess[access])
        }
        XCTAssertEqual(RealtimeEventName.typing.rawValue, "cliTypingEvent")
    }

    func testUserPresenceRealtimePatchUpdatesCachedProfile() async throws {
        let user = try JSONDecoder().decode(
            UserProfile.self,
            from: Data(#"{"id":"11111111-1111-1111-1111-111111111111","isBot":false,"botOwner":null,"onlineStatus":"offline","isFollowed":false,"isFollower":false,"createdAt":"2026-08-07T00:00:00.000Z","updatedAt":"2026-08-07T00:00:00.000Z","bannerImageId":null,"displayAccount":"cg","accounts":[{"type":"cg","displayName":"alice","imageId":null,"extraData":null}],"premiumFeatures":[],"followingCount":0,"followerCount":0,"tags":[]}"#.utf8)
        )
        let store = await MainActor.run { SyncStore() }

        await MainActor.run {
            store.seed(users: [user])
            store.apply(
                RealtimeEvent(
                    type: .userData,
                    payload: .object([
                        "data": .object([
                            "id": .string(user.id),
                            "onlineStatus": .string("online"),
                            "updatedAt": .string("2026-08-08T12:00:00.000Z"),
                        ]),
                    ]),
                    receivedAt: Date()
                )
            )

            XCTAssertEqual(store.users[user.id]?.onlineStatus, "online")
            XCTAssertEqual(store.users[user.id]?.updatedAt, "2026-08-08T12:00:00.000Z")
        }
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

    func testCommunityDiscoveryCreateAndUpdateContracts() async throws {
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
                    body: #"{"status":"OK","data":[{"id":"11111111-1111-1111-1111-111111111111","url":"ios-builders","title":"iOS Builders","logoSmallId":"icon-1","logoLargeId":"sidebar-1","headerImageId":"hero-1","shortDescription":"Native app people","memberCount":"42","tags":["swift"],"createdAt":"2026-08-07T00:00:00.000Z","updatedAt":"2026-08-07T00:00:00.000Z"}]}"#
                )
            case "/api/v2/Community/createCommunity":
                let body = try XCTUnwrap(Self.bodyData(request))
                let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
                XCTAssertEqual(object["logoSmallId"] as? String, "icon-upload")
                XCTAssertEqual(object["logoLargeId"] as? String, "sidebar-upload")
                XCTAssertTrue(object["headerImageId"] is NSNull)
                return Self.response(
                    request,
                    status: 200,
                    body: #"{"status":"OK","data":{"id":"11111111-1111-1111-1111-111111111111","url":"ios-builders","title":"iOS Builders","description":"Native apps","links":[{"url":"https://example.org","text":"Website"}],"tags":["swift"],"createdAt":"2026-08-07T00:00:00.000Z","updatedAt":"2026-08-07T00:00:00.000Z","memberCount":"1","myRoleIds":["role-admin"],"channels":[],"areas":[],"roles":[{"id":"role-admin","permissions":["COMMUNITY_MANAGE_INFO"]}],"calls":[]}}"#
                )
            case "/api/v2/Community/updateCommunity":
                let body = try XCTUnwrap(Self.bodyData(request))
                let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
                XCTAssertEqual(object["id"] as? String, "11111111-1111-1111-1111-111111111111")
                XCTAssertEqual(object["title"] as? String, "Updated Builders")
                XCTAssertEqual((object["links"] as? [[String: String]])?.first?["url"], "https://example.org")
                return Self.response(request, status: 200, body: #"{"status":"OK","data":null}"#)
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
        XCTAssertEqual(communities[0].logoSmallId, "icon-1")
        XCTAssertEqual(communities[0].logoLargeId, "sidebar-1")
        XCTAssertEqual(communities[0].headerImageId, "hero-1")
        let created = try await api.create(
            title: "iOS Builders",
            tags: ["swift"],
            logoSmallID: "icon-upload",
            logoLargeID: "sidebar-upload"
        )
        XCTAssertEqual(created.title, "iOS Builders")
        XCTAssertTrue(created.canManageInfo)
        XCTAssertEqual(created.description, "Native apps")
        XCTAssertEqual(created.links.first?.text, "Website")
        try await api.update(
            id: created.id,
            title: "Updated Builders",
            shortDescription: "Native people",
            description: "A community",
            tags: ["swift"],
            links: [CommunityLink(url: "https://example.org", text: "Website")]
        )
    }

    func testChannelMemberListSeparatesOnlineAndOfflineMembers() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/v2/Community/getChannelMemberList")
            let body = try XCTUnwrap(Self.bodyData(request))
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(object["communityId"] as? String, "community-1")
            XCTAssertEqual(object["channelId"] as? String, "channel-1")
            XCTAssertEqual(object["offset"] as? Int, 0)
            XCTAssertEqual(object["limit"] as? Int, 100)
            return Self.response(
                request,
                status: 200,
                body: #"{"status":"OK","data":{"count":3,"adminCount":1,"moderatorCount":0,"writerCount":1,"readerCount":0,"offlineCount":1,"admin":[["user-online-admin",["role-admin"]]],"moderator":[],"writer":[["user-online-writer",["role-writer"]]],"reader":[],"offline":[["user-offline",["role-member"]]]}}"#
            )
        }
        let api = CommunityAPI(
            transport: HTTPTransport(
                baseURL: URL(string: "https://example.org")!,
                sessionConfiguration: configuration()
            )
        )
        let members = try await api.channelMembers(
            communityID: "community-1",
            channelID: "channel-1"
        )
        XCTAssertEqual(members.count, 3)
        XCTAssertEqual(members.online.map(\.userId), ["user-online-admin", "user-online-writer"])
        XCTAssertEqual(members.offline.map(\.userId), ["user-offline"])
        XCTAssertEqual(members.all.count, 3)
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

    func testMessageContextLoadingContracts() async throws {
        let access = MessageAccess.community(
            "44444444-4444-4444-4444-444444444444",
            channelId: "33333333-3333-3333-3333-333333333333"
        )
        let api = MessageAPI(
            transport: HTTPTransport(
                baseURL: URL(string: "https://example.org")!,
                sessionConfiguration: configuration()
            )
        )

        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/v2/Message/messagesById")
            let object = try XCTUnwrap(
                JSONSerialization.jsonObject(with: XCTUnwrap(Self.bodyData(request)))
                    as? [String: Any]
            )
            XCTAssertEqual(object["messageIds"] as? [String], ["target-message"])
            return Self.response(request, status: 200, body: #"{"status":"OK","data":[]}"#)
        }
        let messagesByID = try await api.byIDs(access: access, messageIDs: ["target-message"])
        XCTAssertTrue(messagesByID.isEmpty)

        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/v2/Message/loadMessages")
            let object = try XCTUnwrap(
                JSONSerialization.jsonObject(with: XCTUnwrap(Self.bodyData(request)))
                    as? [String: Any]
            )
            XCTAssertEqual(object["order"] as? String, "ASC")
            XCTAssertEqual(object["createdAfter"] as? String, "2026-08-08T12:00:00.000Z")
            XCTAssertNil(object["createdBefore"])
            return Self.response(request, status: 200, body: #"{"status":"OK","data":[]}"#)
        }
        let messagesAfter = try await api.load(
            access: access,
            order: .ascending,
            createdBefore: nil,
            createdAfter: "2026-08-08T12:00:00.000Z"
        )
        XCTAssertTrue(messagesAfter.isEmpty)
    }

    func testMessageDeltaAndURLPreviewContracts() async throws {
        let access = MessageAccess.community("community-1", channelId: "channel-1")
        let api = MessageAPI(
            transport: HTTPTransport(
                baseURL: URL(string: "https://example.org")!,
                sessionConfiguration: configuration()
            )
        )
        var routes: [String] = []
        MockURLProtocol.handler = { request in
            let path = try XCTUnwrap(request.url?.path)
            routes.append(path)
            let body = try XCTUnwrap(Self.bodyData(request))
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            switch path {
            case "/api/v2/Message/loadUpdates":
                XCTAssertEqual(object["createdStart"] as? String, "2026-08-08T10:00:00.000Z")
                XCTAssertEqual(object["createdEnd"] as? String, "2026-08-08T11:00:00.000Z")
                XCTAssertEqual(object["updatedAfter"] as? String, "2026-08-08T10:30:00.000Z")
                return Self.response(
                    request,
                    status: 200,
                    body: #"{"status":"OK","data":{"updated":[],"deleted":["message-1"]}}"#
                )
            case "/api/v2/Message/getUrlPreview":
                XCTAssertEqual(object["url"] as? String, "https://example.com/story")
                return Self.response(
                    request,
                    status: 200,
                    body: #"{"status":"OK","data":{"title":"Story","description":"Preview","imageId":"image-1","url":"https://example.com/story"}}"#
                )
            default:
                XCTFail("Unexpected route \(path)")
                return Self.response(request, status: 404, body: #"{"status":"ERROR"}"#)
            }
        }

        let updates = try await api.updates(
            access: access,
            createdStart: "2026-08-08T10:00:00.000Z",
            createdEnd: "2026-08-08T11:00:00.000Z",
            updatedAfter: "2026-08-08T10:30:00.000Z"
        )
        XCTAssertEqual(updates.deleted, ["message-1"])
        let preview = try await api.urlPreview("https://example.com/story")
        XCTAssertEqual(preview.title, "Story")
        XCTAssertEqual(preview.imageId, "image-1")
        XCTAssertEqual(routes, ["/api/v2/Message/loadUpdates", "/api/v2/Message/getUrlPreview"])
    }

    func testCommunityExtensionsAndPluginContracts() async throws {
        var routes: [String] = []
        MockURLProtocol.handler = { request in
            let path = try XCTUnwrap(request.url?.path)
            routes.append(path)
            let object = try XCTUnwrap(
                JSONSerialization.jsonObject(with: XCTUnwrap(Self.bodyData(request))) as? [String: Any]
            )
            switch path {
            case "/api/v2/Community/updateChannel":
                XCTAssertEqual(object["pinnedMessageIds"] as? [String], ["m1", "m2"])
                return Self.response(request, status: 200, body: #"{"status":"OK"}"#)
            case "/api/v2/Community/addCommunityToken":
                XCTAssertEqual(object["contractId"] as? String, "token-1")
                XCTAssertEqual(object["order"] as? Int, 2)
                return Self.response(request, status: 200, body: #"{"status":"OK"}"#)
            case "/api/v2/Community/removeCommunityToken":
                XCTAssertEqual(object["contractId"] as? String, "token-1")
                return Self.response(request, status: 200, body: #"{"status":"OK"}"#)
            case "/api/v2/Community/buyCommunityPremiumFeature":
                XCTAssertEqual(object["featureName"] as? String, "PRO")
                XCTAssertEqual(object["duration"] as? String, "year")
                return Self.response(request, status: 200, body: #"{"status":"OK"}"#)
            case "/api/v2/Community/setPremiumFeatureAutoRenew":
                XCTAssertEqual(object["featureName"] as? String, "PRO")
                XCTAssertEqual(object["autoRenew"] as? String, "YEAR")
                return Self.response(request, status: 200, body: #"{"status":"OK"}"#)
            case "/api/v2/Community/updateRole":
                XCTAssertEqual(object["type"] as? String, "CUSTOM_AUTO_ASSIGN")
                let assignment = try XCTUnwrap(object["assignmentRules"] as? [String: Any])
                XCTAssertEqual(assignment["type"] as? String, "token")
                let rules = try XCTUnwrap(assignment["rules"] as? [String: Any])
                let rule = try XCTUnwrap(rules["rule1"] as? [String: Any])
                XCTAssertEqual(rule["contractId"] as? String, "token-1")
                XCTAssertEqual(rule["amount"] as? String, "10")
                return Self.response(request, status: 200, body: #"{"status":"OK"}"#)
            case "/api/v2/Community/getNewsletterHistory":
                XCTAssertEqual(object["timeframe"] as? String, "90days")
                return Self.response(
                    request,
                    status: 200,
                    body: #"{"status":"OK","data":{"entries":[{"id":"article-1","title":"Update","creatorId":"user-1","markAsNewsletter":true,"sentAsNewsletter":null,"url":"update"}]}}"#
                )
            case "/api/v2/Community/sendArticleAsEmail":
                XCTAssertEqual(object["articleId"] as? String, "article-1")
                return Self.response(request, status: 200, body: #"{"status":"OK"}"#)
            case "/api/v2/Plugins/getAppstorePlugins":
                XCTAssertEqual(object["query"] as? String, "calendar")
                return Self.response(
                    request,
                    status: 200,
                    body: #"{"status":"OK","data":{"plugins":[{"pluginId":"plugin-1","ownerCommunityId":"owner-1","url":"https://app.example","description":"Calendar","permissions":{"mandatory":["COMMUNITY_INFO"],"optional":["USER_INFO"]},"imageId":null,"name":"Calendar","communityCount":"4","appstoreEnabled":true,"tags":["productivity"]}]}}"#
                )
            case "/api/v2/Plugins/clonePlugin":
                XCTAssertEqual(object["copiedFromCommunityId"] as? String, "owner-1")
                XCTAssertEqual(object["targetCommunityId"] as? String, "community-1")
                return Self.response(request, status: 200, body: #"{"status":"OK","data":{"ok":true}}"#)
            case "/api/v2/Plugins/acceptPluginPermissions":
                XCTAssertEqual(object["pluginId"] as? String, "installed-1")
                XCTAssertEqual(object["permissions"] as? [String], ["COMMUNITY_INFO", "USER_INFO"])
                return Self.response(request, status: 200, body: #"{"status":"OK","data":{"ok":true}}"#)
            case "/api/v2/Plugins/deletePlugin":
                XCTAssertEqual(object["id"] as? String, "installed-1")
                return Self.response(request, status: 200, body: #"{"status":"OK","data":{"ok":true}}"#)
            default:
                XCTFail("Unexpected route \(path)")
                return Self.response(request, status: 404, body: #"{"status":"ERROR"}"#)
            }
        }
        let transport = HTTPTransport(
            baseURL: URL(string: "https://example.org")!,
            sessionConfiguration: configuration()
        )
        let community = CommunityAPI(transport: transport)
        let plugins = PluginAPI(transport: transport)
        try await community.setPinnedMessages(
            communityID: "community-1",
            channelID: "channel-1",
            messageIDs: ["m1", "m2", "m3"]
        )
        try await community.addToken(communityID: "community-1", contractID: "token-1", order: 2)
        try await community.removeToken(communityID: "community-1", contractID: "token-1")
        try await community.buyPremium(communityID: "community-1", feature: "PRO", duration: "year")
        try await community.setPremiumAutoRenew(
            communityID: "community-1",
            feature: "PRO",
            autoRenew: "YEAR"
        )
        try await community.updateRole(
            communityID: "community-1",
            roleID: "role-1",
            title: "Holders",
            description: "Token holders",
            permissions: ["COMMUNITY_MANAGE_ARTICLES"],
            type: "CUSTOM_AUTO_ASSIGN",
            assignmentRules: .object([
                "type": .string("token"),
                "rules": .object([
                    "rule1": .object([
                        "type": .string("ERC20"),
                        "contractId": .string("token-1"),
                        "amount": .string("10"),
                    ]),
                ]),
            ])
        )
        let history = try await community.newsletterHistory(
            communityID: "community-1",
            timeframe: "90days"
        )
        XCTAssertEqual(history.first?.title, "Update")
        try await community.sendArticleAsNewsletter(communityID: "community-1", articleID: "article-1")
        let catalog = try await plugins.appStore(query: "calendar")
        XCTAssertEqual(catalog.first?.communityCount, 4)
        try await plugins.install(pluginID: "plugin-1", ownerCommunityID: "owner-1", communityID: "community-1")
        try await plugins.acceptPermissions(
            pluginID: "installed-1",
            permissions: ["COMMUNITY_INFO", "USER_INFO"]
        )
        try await plugins.remove(id: "installed-1")
        XCTAssertEqual(routes.count, 12)
    }

    func testNotificationDestinationsAndPersistence() throws {
        func notification(_ json: String) throws -> AppNotification {
            try JSONDecoder().decode(AppNotification.self, from: Data(json.utf8))
        }
        let base = #""type":"Mention","id":"n1","text":"hello","createdAt":"2026-08-08T12:00:00.000Z","updatedAt":"2026-08-08T12:00:00.000Z","read":false"#
        let channel = try notification(
            "{\(base),\"subjectItemId\":\"m1\",\"subjectCommunityId\":\"c1\",\"subjectUserId\":\"u1\",\"subjectArticleId\":null,\"extraData\":{\"type\":\"channelData\",\"channelId\":\"ch1\"}}"
        )
        XCTAssertEqual(
            channel.destination,
            .channel(communityID: "c1", channelID: "ch1", messageID: "m1")
        )
        XCTAssertTrue(channel.isPersisted)

        let article = try notification(
            "{\(base),\"subjectItemId\":\"comment1\",\"subjectCommunityId\":null,\"subjectUserId\":\"u1\",\"subjectArticleId\":\"a1\",\"extraData\":{\"type\":\"articleData\",\"articleId\":\"a1\",\"articleOwner\":{\"type\":\"user\",\"userId\":\"owner1\"}}}"
        )
        XCTAssertEqual(
            article.destination,
            .article(owner: .user("owner1"), articleID: "a1", messageID: "comment1")
        )

        let directMessage = try notification(
            "{\(base.replacingOccurrences(of: "Mention", with: "DM")),\"subjectItemId\":\"m2\",\"subjectCommunityId\":null,\"subjectUserId\":\"u2\",\"subjectArticleId\":null,\"extraData\":{\"type\":\"chatData\",\"chatId\":\"chat1\",\"channelId\":\"ch2\"}}"
        )
        XCTAssertEqual(
            directMessage.destination,
            .chat(chatID: "chat1", channelID: "ch2", messageID: "m2")
        )
        XCTAssertFalse(directMessage.isPersisted)
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
                let messageBody = try XCTUnwrap(object["body"] as? [String: Any])
                let content = try XCTUnwrap(messageBody["content"] as? [[String: Any]])
                XCTAssertTrue(content.contains { node in
                    node["type"] as? String == "mention"
                        && node["alias"] as? String == "alice"
                        && node["userId"] as? String == "22222222-2222-2222-2222-222222222222"
                })
                return Self.response(
                    request,
                    status: 200,
                    body: #"{"status":"OK","data":{"editedAt":"2026-08-07T01:00:00.000Z"}}"#
                )
            case "/api/v2/Message/deleteMessage":
                XCTAssertEqual(object["creatorId"] as? String, "22222222-2222-2222-2222-222222222222")
            case "/api/v2/Message/deleteAllUserMessages":
                XCTAssertEqual(object["creatorId"] as? String, "22222222-2222-2222-2222-222222222222")
                XCTAssertNil(object["messageId"])
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
        let edit = try await api.edit(
            access: access,
            messageID: messageID,
            text: "edited @alice",
            mentions: ["alice": "22222222-2222-2222-2222-222222222222"]
        )
        XCTAssertEqual(edit.editedAt, "2026-08-07T01:00:00.000Z")
        try await api.delete(
            access: access,
            messageID: messageID,
            creatorID: "22222222-2222-2222-2222-222222222222"
        )
        try await api.deleteAll(
            access: access,
            creatorID: "22222222-2222-2222-2222-222222222222"
        )
        try await api.setReaction(access: access, messageID: messageID, reaction: "👍")
        try await api.unsetReaction(access: access, messageID: messageID)
        XCTAssertEqual(routes.count, 5)
    }

    func testSyncStoreOrdersMixedISOTimestampsAndDeduplicatesRealtimeEvents() async throws {
        let earlier = Message(
            id: "earlier",
            creatorId: "user",
            channelId: "channel",
            body: .text("earlier"),
            attachments: [],
            editedAt: nil,
            createdAt: "2026-08-08T12:00:00Z",
            updatedAt: "2026-08-08T12:00:00Z",
            reactions: [:],
            ownReaction: nil,
            parentMessageId: nil
        )
        let later = Message(
            id: "later",
            creatorId: "user",
            channelId: "channel",
            body: .text("later"),
            attachments: [],
            editedAt: nil,
            createdAt: "2026-08-08T12:00:00.500Z",
            updatedAt: "2026-08-08T12:00:00.500Z",
            reactions: [:],
            ownReaction: nil,
            parentMessageId: nil
        )

        await MainActor.run {
            let store = SyncStore()
            store.seed([later, earlier], channelId: "channel")
            XCTAssertEqual(store.orderedMessages(channelId: "channel").map(\.id), ["earlier", "later"])

            let notificationData: JSONValue = .object([
                "type": .string("Mention"),
                "id": .string("notification-1"),
                "text": .string("Mentioned you"),
                "createdAt": .string("2026-08-08T12:00:00Z"),
                "updatedAt": .string("2026-08-08T12:00:00Z"),
                "read": .bool(false),
            ])
            let notificationEvent = RealtimeEvent(
                type: .notification,
                payload: .object(["action": .string("new"), "data": notificationData]),
                receivedAt: Date()
            )
            store.apply(notificationEvent)
            store.apply(notificationEvent)
            XCTAssertEqual(store.unreadNotificationCount, 1)

            let chatData: JSONValue = .object([
                "id": .string("chat-1"),
                "channelId": .string("dm-channel"),
                "userIds": .array([.string("user")]),
                "adminIds": .array([]),
                "createdAt": .string("2026-08-08T12:00:00Z"),
                "updatedAt": .string("2026-08-08T12:00:00Z"),
                "unread": .number(1),
                "lastRead": .null,
                "lastMessage": .null,
            ])
            store.apply(
                RealtimeEvent(
                    type: .chat,
                    payload: .object(["action": .string("new"), "data": chatData]),
                    receivedAt: Date()
                )
            )
            XCTAssertEqual(store.chats["chat-1"]?.unread, 1)
            store.apply(
                RealtimeEvent(
                    type: .chat,
                    payload: .object([
                        "action": .string("update"),
                        "data": .object([
                            "id": .string("chat-1"),
                            "channelId": .string("dm-channel"),
                            "unread": .number(2),
                        ]),
                    ]),
                    receivedAt: Date()
                )
            )
            XCTAssertEqual(store.chats["chat-1"]?.unread, 2)
        }
    }

    func testOfflineDatabasePersistsMessagesOutboxAndDrafts() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "cg-offline-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let fileURL = directory.appending(path: "cache.sqlite3")
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try OfflineDatabase(fileURL: fileURL, scope: "test-account")
        let access = MessageAccess.community("community", channelId: "channel")
        let message = Message(
            id: "message",
            creatorId: "user",
            channelId: "channel",
            body: .text("Saved offline"),
            attachments: [],
            editedAt: nil,
            createdAt: "2026-08-08T12:00:00Z",
            updatedAt: "2026-08-08T12:00:00Z",
            reactions: [:],
            ownReaction: nil,
            parentMessageId: nil
        )
        let pending = PendingMessage(
            id: "11111111-1111-1111-1111-111111111111",
            creatorID: "user",
            access: access,
            text: "Queued offline",
            mentions: [:],
            parentMessageID: nil,
            imageAttachments: [],
            createdAt: "2026-08-08T12:01:00Z"
        )

        try await database.save(messages: [message])
        try await database.save(pendingMessage: pending)
        try await database.saveDraft("A durable draft", conversationID: "channel:channel")

        let snapshot = try await database.loadSnapshot()
        XCTAssertEqual(snapshot.messages, [message])
        XCTAssertEqual(snapshot.pendingMessages, [pending])
        let restoredDraft = try await database.draft(conversationID: "channel:channel")
        XCTAssertEqual(restoredDraft, "A durable draft")

        try await database.removePendingMessage(id: pending.id)
        let finalSnapshot = try await database.loadSnapshot()
        XCTAssertTrue(finalSnapshot.pendingMessages.isEmpty)
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

    func testCommunityImageUploadIncludesCommunityID() async throws {
        MockURLProtocol.handler = { request in
            let body = try XCTUnwrap(Self.bodyData(request))
            let string = String(decoding: body, as: UTF8.self)
            XCTAssertTrue(string.contains("communityLogoLarge"))
            XCTAssertTrue(string.contains("community-1"))
            return Self.response(request, status: 200, body: #"{"imageId":"sidebar-image","largeImageId":null}"#)
        }
        let api = FileAPI(
            transport: HTTPTransport(
                baseURL: URL(string: "https://example.org")!,
                sessionConfiguration: configuration()
            )
        )
        let result = try await api.uploadImage(
            Data([0x01]),
            type: .communityLogoLarge,
            communityID: "community-1"
        )
        XCTAssertEqual(result.imageId, "sidebar-image")
    }

    func testArticleImageUploadOmitsCommunityID() async throws {
        MockURLProtocol.handler = { request in
            let body = try XCTUnwrap(Self.bodyData(request))
            let string = String(decoding: body, as: UTF8.self)
            XCTAssertTrue(string.contains("articleImage"))
            XCTAssertFalse(string.contains("communityId"))
            return Self.response(
                request,
                status: 200,
                body: #"{"imageId":"event-image","largeImageId":"event-image-large"}"#
            )
        }
        let api = FileAPI(
            transport: HTTPTransport(
                baseURL: URL(string: "https://example.org")!,
                sessionConfiguration: configuration()
            )
        )
        let result = try await api.uploadImage(Data([0x01]), type: .articleImage)
        XCTAssertEqual(result.largeImageId, "event-image-large")
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

    func testArticleListsAndStructuredDetailMatchBackendContract() async throws {
        var routes: [String] = []
        MockURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            routes.append(path)
            let requestBody = try XCTUnwrap(Self.bodyData(request))
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: requestBody) as? [String: Any])
            XCTAssertEqual(object["limit"] as? Int, 30)
            XCTAssertEqual(object["order"] as? String, "DESC")
            XCTAssertEqual(object["orderBy"] as? String, "published")
            if path.hasPrefix("/api/v2/Community") {
                XCTAssertEqual(object["communityId"] as? String, "community-1")
                return Self.response(
                    request,
                    status: 200,
                    body: #"{"status":"OK","data":[{"communityArticle":{"communityId":"community-1","articleId":"article-1","url":"hello","published":"2026-08-07T00:00:00.000Z","updatedAt":"2026-08-07T00:00:00.000Z","rolePermissions":[],"sentAsNewsletter":null,"markAsNewsletter":false},"article":{"articleId":"article-1","title":"Hello","previewText":"Preview","thumbnailImageId":null,"headerImageId":null,"creatorId":"user-1","tags":["news"],"commentCount":"2","latestCommentTimestamp":null}}]}"#
                )
            }
            XCTAssertEqual(object["userId"] as? String, "user-1")
            return Self.response(
                request,
                status: 200,
                body: #"{"status":"OK","data":[{"userArticle":{"userId":"user-1","articleId":"article-2","url":null,"published":"2026-08-07T00:00:00.000Z","updatedAt":"2026-08-07T00:00:00.000Z"},"article":{"articleId":"article-2","title":"Profile post","previewText":null,"thumbnailImageId":null,"headerImageId":null,"creatorId":"user-1","tags":[],"commentCount":0,"latestCommentTimestamp":null}}]}"#
            )
        }
        let api = ArticleAPI(
            transport: HTTPTransport(
                baseURL: URL(string: "https://example.org")!,
                sessionConfiguration: configuration()
            )
        )
        let community = try await api.communityArticles(communityID: "community-1")
        let user = try await api.userArticles(userID: "user-1")
        XCTAssertEqual(community.first?.article.commentCount, 2)
        XCTAssertEqual(user.first?.article.title, "Profile post")
        XCTAssertEqual(routes, ["/api/v2/Community/getArticleList", "/api/v2/User/getArticleList"])
    }

    func testCreateUserArticleEncodesRequiredNullFields() async throws {
        var routes: [String] = []
        MockURLProtocol.handler = { request in
            let path = try XCTUnwrap(request.url?.path)
            routes.append(path)
            let body = try XCTUnwrap(Self.bodyData(request))
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(path, "/api/v2/User/createArticle")
            let userArticle = try XCTUnwrap(object["userArticle"] as? [String: Any])
            let article = try XCTUnwrap(object["article"] as? [String: Any])
            XCTAssertTrue(userArticle["url"] is NSNull)
            XCTAssertEqual(userArticle["published"] as? String, "2026-08-08T00:00:00.000Z")
            XCTAssertTrue(article["thumbnailImageId"] is NSNull)
            XCTAssertTrue(article["headerImageId"] is NSNull)
            XCTAssertEqual(article["previewText"] as? String, "A short preview")
            let content = try XCTUnwrap(article["content"] as? [String: Any])
            XCTAssertEqual(content["version"] as? String, "2")
            return Self.response(
                request,
                status: 200,
                body: #"{"status":"OK","data":{"userArticle":{"userId":"11111111-1111-4111-8111-111111111111","articleId":"22222222-2222-4222-8222-222222222222","url":null,"published":"2026-08-08T00:00:00.000Z","updatedAt":"2026-08-08T00:00:00.000Z"},"article":{"articleId":"22222222-2222-4222-8222-222222222222","title":"Native publishing","previewText":"A short preview","thumbnailImageId":null,"headerImageId":null,"creatorId":"11111111-1111-4111-8111-111111111111","tags":["ios"],"commentCount":0,"latestCommentTimestamp":null,"content":{"version":"2","content":[{"type":"text","value":"Hello"}]},"channelId":"33333333-3333-4333-8333-333333333333"}}}"#
            )
        }
        let api = ArticleAPI(
            transport: HTTPTransport(
                baseURL: URL(string: "https://example.org")!,
                sessionConfiguration: configuration()
            )
        )
        let result = try await api.createUserArticle(
            title: "Native publishing",
            previewText: "A short preview",
            text: "Hello",
            tags: ["ios"],
            published: "2026-08-08T00:00:00.000Z"
        )
        XCTAssertEqual(result.article.title, "Native publishing")
        XCTAssertEqual(result.userArticle.published, "2026-08-08T00:00:00.000Z")
        XCTAssertEqual(result.userArticle.updatedAt, "2026-08-08T00:00:00.000Z")
        XCTAssertEqual(result.preview.article.title, "Native publishing")
        XCTAssertEqual(routes, ["/api/v2/User/createArticle"])
    }

    func testArticleDetailFlattensStructuredContent() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/v2/User/getArticleDetailView")
            return Self.response(
                request,
                status: 200,
                body: #"{"status":"OK","data":{"userArticle":{"userId":"user-1","articleId":"article-1","url":null,"published":"2026-08-07T00:00:00.000Z","updatedAt":"2026-08-07T00:00:00.000Z"},"article":{"articleId":"article-1","title":"Hello","previewText":"Preview","thumbnailImageId":null,"headerImageId":null,"creatorId":"user-1","tags":[],"commentCount":0,"latestCommentTimestamp":null,"content":{"version":"2","content":[{"type":"header","value":[{"type":"text","value":"Heading"}]},{"type":"newline"},{"type":"text","value":"Body"}]},"channelId":"channel-1"}}}"#
            )
        }
        let api = ArticleAPI(
            transport: HTTPTransport(
                baseURL: URL(string: "https://example.org")!,
                sessionConfiguration: configuration()
            )
        )
        let detail = try await api.userArticle(userID: "user-1", articleID: "article-1")
        XCTAssertEqual(detail.article.markdownSource, "## Heading\nBody")
    }

    func testMarkdownArticleParserPreservesLinesAndBlockStructure() {
        let blocks = MarkdownArticleBlock.parse(
            "First **bold** line\nSecond line\n\n## Heading\n- bullet\n2. numbered\n> quote\n```\nlet value = 1\n```"
        )
        XCTAssertEqual(
            blocks.map(\.kind),
            [
                .paragraph,
                .paragraph,
                .spacer,
                .heading(2),
                .unordered,
                .ordered("2"),
                .quote,
                .code,
            ]
        )
        XCTAssertEqual(blocks[0].text, "First **bold** line")
        XCTAssertEqual(blocks[1].text, "Second line")
        XCTAssertEqual(blocks[4].text, "bullet")
        XCTAssertEqual(blocks[7].text, "let value = 1")
    }

    func testArticleDraftAndCommentRoomContracts() async throws {
        var routes: [String] = []
        MockURLProtocol.handler = { request in
            let path = try XCTUnwrap(request.url?.path)
            routes.append(path)
            let body = try XCTUnwrap(Self.bodyData(request))
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            switch path {
            case "/api/v2/User/getArticleList":
                XCTAssertEqual(object["drafts"] as? Bool, true)
                XCTAssertEqual(object["userId"] as? String, "user-1")
                return Self.response(request, status: 200, body: #"{"status":"OK","data":[]}"#)
            case "/api/v2/Message/joinArticleEventRoom", "/api/v2/Message/leaveArticleEventRoom":
                let access = try XCTUnwrap(object["access"] as? [String: Any])
                XCTAssertEqual(access["articleId"] as? String, "article-1")
                XCTAssertEqual(access["articleCommunityId"] as? String, "community-1")
                XCTAssertEqual(access["channelId"] as? String, "channel-1")
                return Self.response(request, status: 200, body: #"{"status":"OK"}"#)
            default:
                XCTFail("Unexpected route \(path)")
                return Self.response(request, status: 404, body: #"{"status":"ERROR"}"#)
            }
        }
        let api = ArticleAPI(
            transport: HTTPTransport(
                baseURL: URL(string: "https://example.org")!,
                sessionConfiguration: configuration()
            )
        )
        _ = try await api.userArticles(userID: "user-1", drafts: true)
        let access = MessageAccess.communityArticle(
            "community-1",
            articleId: "article-1",
            channelId: "channel-1"
        )
        try await api.joinCommentRoom(access: access)
        try await api.leaveCommentRoom(access: access)
        XCTAssertEqual(routes, [
            "/api/v2/User/getArticleList",
            "/api/v2/Message/joinArticleEventRoom",
            "/api/v2/Message/leaveArticleEventRoom",
        ])
    }

    func testCommunityManagementContracts() async throws {
        var routes: [String] = []
        MockURLProtocol.handler = { request in
            let path = try XCTUnwrap(request.url?.path)
            routes.append(path)
            let body = try XCTUnwrap(Self.bodyData(request))
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            switch path {
            case "/api/v2/Community/getMemberList":
                XCTAssertEqual(object["roleId"] as? String, "role-member")
                return Self.response(
                    request,
                    status: 200,
                    body: #"{"status":"OK","data":{"totalCount":2,"resultCount":2,"roles":[["role-member",2]],"online":[["user-1",["role-member"]]],"offline":[["user-2",["role-member"]]]}}"#
                )
            case "/api/v2/Community/setUserBlockState":
                XCTAssertTrue(object["until"] is NSNull)
                XCTAssertTrue(object["blockState"] is NSNull)
                return Self.response(request, status: 200, body: #"{"status":"OK"}"#)
            case "/api/v2/Community/createRole":
                XCTAssertTrue(object["imageId"] is NSNull)
                XCTAssertTrue(object["assignmentRules"] is NSNull)
                XCTAssertTrue(object["description"] is NSNull)
                return Self.response(request, status: 200, body: #"{"status":"OK","data":{"id":"role-new"}}"#)
            case "/api/v2/Community/addUserToRoles", "/api/v2/Community/removeUserFromRoles":
                XCTAssertEqual(object["userId"] as? String, "user-1")
                XCTAssertEqual(object["communityId"] as? String, "community-1")
                XCTAssertEqual(object["roleIds"] as? [String], ["role-new"])
                return Self.response(request, status: 200, body: #"{"status":"OK"}"#)
            case "/api/v2/Community/getCommunityPassword":
                return Self.response(request, status: 200, body: #"{"status":"OK","data":{"password":"secret"}}"#)
            case "/api/v2/Community/setOnboardingOptions":
                XCTAssertEqual(object["password"] as? String, "secret")
                let options = try XCTUnwrap(object["onboardingOptions"] as? [String: Any])
                XCTAssertEqual((options["manuallyApprove"] as? [String: Any])?["enabled"] as? Bool, true)
                return Self.response(request, status: 200, body: #"{"status":"OK"}"#)
            case "/api/v2/Community/updateCommunity":
                if object["enablePersonalNewsletter"] != nil {
                    XCTAssertEqual(object["enablePersonalNewsletter"] as? Bool, true)
                } else {
                    XCTAssertEqual(object["allowUserBots"] as? Bool, false)
                }
                return Self.response(request, status: 200, body: #"{"status":"OK"}"#)
            case "/api/v2/Community/givePointsToCommunity":
                XCTAssertEqual(object["communityId"] as? String, "community-1")
                XCTAssertEqual(object["amount"] as? Int, 5_000)
                return Self.response(request, status: 200, body: #"{"status":"OK"}"#)
            case "/api/v2/Community/updateNotificationState":
                let data = try XCTUnwrap(object["data"] as? [[String: Any]])
                XCTAssertEqual(data.first?["communityId"] as? String, "community-1")
                XCTAssertEqual(data.first?["notifyMentions"] as? Bool, true)
                XCTAssertEqual(data.first?["notifyPosts"] as? Bool, false)
                XCTAssertEqual(data.first?["notifyCalls"] as? Bool, false)
                return Self.response(request, status: 200, body: #"{"status":"OK"}"#)
            case "/api/v2/Community/createChannel":
                XCTAssertTrue(object["url"] is NSNull)
                let permissions = try XCTUnwrap(object["rolePermissions"] as? [[String: Any]])
                XCTAssertEqual(permissions.count, 1)
                XCTAssertEqual(permissions.first?["roleId"] as? String, "role-member")
                return Self.response(request, status: 200, body: #"{"status":"OK"}"#)
            default:
                XCTFail("Unexpected route \(path)")
                return Self.response(request, status: 404, body: #"{"status":"ERROR"}"#)
            }
        }
        let api = CommunityAPI(
            transport: HTTPTransport(
                baseURL: URL(string: "https://example.org")!,
                sessionConfiguration: configuration()
            )
        )
        let members = try await api.members(communityID: "community-1", roleID: "role-member")
        XCTAssertEqual(members.online.first?.userId, "user-1")
        try await api.setBlockState(communityID: "community-1", userID: "user-1", state: nil)
        let roleID = try await api.createRole(communityID: "community-1", title: "Writers")
        XCTAssertEqual(roleID, "role-new")
        try await api.addUserToRoles(communityID: "community-1", userID: "user-1", roleIDs: ["role-new"])
        try await api.removeUserFromRoles(communityID: "community-1", userID: "user-1", roleIDs: ["role-new"])
        let password = try await api.communityPassword(communityID: "community-1")
        XCTAssertEqual(password, "secret")
        try await api.setOnboardingOptions(
            communityID: "community-1",
            options: .object(["manuallyApprove": .object(["enabled": .bool(true)])]),
            password: password
        )
        try await api.setPersonalNewsletter(communityID: "community-1", enabled: true)
        try await api.setAllowUserBots(communityID: "community-1", allowed: false)
        try await api.giveSpark(communityID: "community-1", amount: 5_000)
        try await api.updateNotificationState(
            communityID: "community-1",
            state: CommunityNotificationState(
                notifyMentions: true,
                notifyReplies: true,
                notifyPosts: false,
                notifyEvents: true,
                notifyCalls: false
            )
        )
        try await api.createChannel(
            communityID: "community-1",
            areaID: "area-1",
            title: "Writing",
            url: nil,
            order: 1,
            description: nil,
            emoji: "✍️",
            roleAccess: [
                ChannelRoleAccess(
                    roleId: "role-admin",
                    roleTitle: "Admin",
                    permissions: ["CHANNEL_EXISTS", "CHANNEL_READ", "CHANNEL_WRITE", "CHANNEL_MODERATE"]
                ),
                ChannelRoleAccess(
                    roleId: "role-member",
                    roleTitle: "Member",
                    permissions: ["CHANNEL_EXISTS", "CHANNEL_READ"]
                )
            ]
        )
        XCTAssertEqual(routes.count, 12)
    }

    func testEmptyCommunityNotificationStateUsesServerDefaults() throws {
        let state = try JSONDecoder().decode(
            CommunityNotificationState.self,
            from: Data("{}".utf8)
        )
        XCTAssertTrue(state.notifyMentions)
        XCTAssertTrue(state.notifyReplies)
        XCTAssertTrue(state.notifyPosts)
        XCTAssertTrue(state.notifyEvents)
        XCTAssertTrue(state.notifyCalls)
    }

    func testProfileUpdateContracts() async throws {
        var routes: [String] = []
        MockURLProtocol.handler = { request in
            routes.append(request.url?.path ?? "")
            let body = try XCTUnwrap(Self.bodyData(request))
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            if request.url?.path.hasSuffix("updateUserAccount") == true {
                XCTAssertEqual(object["type"] as? String, "cg")
                XCTAssertEqual(object["displayName"] as? String, "Alice")
                XCTAssertEqual(object["description"] as? String, "Hello")
            } else {
                XCTAssertEqual(object["email"] as? String, "alice@example.org")
                XCTAssertEqual(object["dmNotifications"] as? Bool, false)
            }
            return Self.response(request, status: 200, body: #"{"status":"OK"}"#)
        }
        let api = ProfileAPI(
            transport: HTTPTransport(
                baseURL: URL(string: "https://example.org")!,
                sessionConfiguration: configuration()
            )
        )
        try await api.updateCGAccount(
            displayName: "Alice",
            description: "Hello",
            homepage: "https://example.org"
        )
        try await api.updateOwnData(email: "alice@example.org", dmNotifications: false)
        XCTAssertEqual(routes, ["/api/v2/User/updateUserAccount", "/api/v2/User/updateOwnData"])
    }

    func testCommunityEventLifecycleContract() async throws {
        let eventJSON = #"{"id":"event-1","type":"external","communityId":"community-1","eventCreator":"user-1","url":"swift-night","title":"Swift Night","description":{"version":"2","content":[{"type":"text","value":"Talks"},{"type":"newline"},{"type":"text","value":"Drinks"}]},"externalUrl":"https://example.org/event","location":"Berlin","scheduleDate":"2026-08-09T18:00:00.000Z","duration":90,"createdAt":"2026-08-08T18:00:00.000Z","deletedAt":null,"updatedAt":"2026-08-08T18:00:00.000Z","callId":null,"imageId":null,"rolePermissions":[{"roleId":"role-member","roleTitle":"Member","permissions":["EVENT_PREVIEW","EVENT_ATTEND"]}],"participantIds":["user-1"],"participantCount":"1","isSelfAttending":true}"#
        var routes: [String] = []
        MockURLProtocol.handler = { request in
            let path = try XCTUnwrap(request.url?.path)
            routes.append(path)
            let object = try XCTUnwrap(
                JSONSerialization.jsonObject(with: XCTUnwrap(Self.bodyData(request))) as? [String: Any]
            )
            switch path {
            case "/api/v2/Community/getEventList":
                XCTAssertEqual(object["communityId"] as? String, "community-1")
                return Self.response(request, status: 200, body: #"{"status":"OK","data":[\#(eventJSON)]}"#)
            case "/api/v2/Community/getMyEvents":
                XCTAssertNil(object["beforeId"])
                return Self.response(request, status: 200, body: #"{"status":"OK","data":[\#(eventJSON)]}"#)
            case "/api/v2/Community/createCommunityEvent":
                XCTAssertEqual(object["type"] as? String, "external")
                XCTAssertEqual(object["externalUrl"] as? String, "https://example.org/event")
                XCTAssertEqual(object["duration"] as? Int, 90)
                XCTAssertTrue(object["url"] is NSNull)
                XCTAssertTrue(object["imageId"] is NSNull)
                let permissions = try XCTUnwrap(object["rolePermissions"] as? [[String: Any]])
                XCTAssertEqual(permissions.first?["roleTitle"] as? String, "Member")
                return Self.response(request, status: 200, body: #"{"status":"OK","data":\#(eventJSON)}"#)
            case "/api/v2/Community/updateCommunityEvent":
                XCTAssertEqual(object["id"] as? String, "event-1")
                XCTAssertEqual(object["title"] as? String, "Updated Swift Night")
                return Self.response(request, status: 200, body: #"{"status":"OK","data":\#(eventJSON)}"#)
            case "/api/v2/Community/addEventParticipant", "/api/v2/Community/removeEventParticipant":
                XCTAssertEqual(object["eventId"] as? String, "event-1")
                return Self.response(request, status: 200, body: #"{"status":"OK"}"#)
            case "/api/v2/Community/deleteCommunityEvent":
                XCTAssertEqual(object["eventId"] as? String, "event-1")
                XCTAssertEqual(object["communityId"] as? String, "community-1")
                return Self.response(request, status: 200, body: #"{"status":"OK"}"#)
            default:
                XCTFail("Unexpected route \(path)")
                return Self.response(request, status: 404, body: #"{"status":"ERROR"}"#)
            }
        }
        let api = CommunityAPI(
            transport: HTTPTransport(
                baseURL: URL(string: "https://example.org")!,
                sessionConfiguration: configuration()
            )
        )
        let listed = try await api.events(communityID: "community-1")
        XCTAssertEqual(listed.first?.descriptionText, "Talks\nDrinks")
        XCTAssertEqual(listed.first?.participantCount, 1)
        let mine = try await api.myEvents()
        XCTAssertEqual(mine.map(\.id), ["event-1"])
        let created = try await api.createEvent(
            communityID: "community-1",
            type: .external,
            title: "Swift Night",
            description: "Talks\nDrinks",
            duration: 90,
            imageID: nil,
            scheduledAt: "2026-08-09T18:00:00.000Z",
            rolePermissions: [
                CommunityEventRolePermission(
                    roleId: "role-member",
                    roleTitle: "Member",
                    permissions: ["EVENT_PREVIEW", "EVENT_ATTEND"]
                ),
            ],
            externalURL: "https://example.org/event",
            location: "Berlin"
        )
        XCTAssertEqual(created.title, "Swift Night")
        _ = try await api.updateEvent(
            id: "event-1",
            type: .external,
            title: "Updated Swift Night",
            description: "Talks\nDrinks",
            duration: 90,
            imageID: nil,
            scheduledAt: "2026-08-09T18:00:00.000Z",
            rolePermissions: [
                CommunityEventRolePermission(
                    roleId: "role-member",
                    roleTitle: "Member",
                    permissions: ["EVENT_PREVIEW", "EVENT_ATTEND"]
                ),
            ],
            externalURL: "https://example.org/event",
            location: "Berlin"
        )
        try await api.attendEvent(id: "event-1")
        try await api.leaveEvent(id: "event-1")
        try await api.deleteEvent(communityID: "community-1", eventID: "event-1")
        XCTAssertEqual(routes.count, 7)
    }

    func testPluginSignedBridgeContract() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/v2/Plugins/pluginRequest")
            let object = try XCTUnwrap(
                JSONSerialization.jsonObject(with: XCTUnwrap(Self.bodyData(request))) as? [String: Any]
            )
            XCTAssertEqual(object["request"] as? String, "signed-inner-request")
            XCTAssertEqual(object["signature"] as? String, "plugin-signature")
            return Self.response(
                request,
                status: 200,
                body: #"{"status":"OK","data":{"response":"signed-inner-response","signature":"server-signature"}}"#
            )
        }
        let api = PluginAPI(
            transport: HTTPTransport(
                baseURL: URL(string: "https://example.org")!,
                sessionConfiguration: configuration()
            )
        )
        let response = try await api.request("signed-inner-request", signature: "plugin-signature")
        XCTAssertEqual(response.response, "signed-inner-response")
        XCTAssertEqual(response.signature, "server-signature")
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

    /// Opt-in live integration probe for an existing account. Credentials are
    /// supplied through the environment and are never stored in the repository.
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
        for eventCommunity in login.response.communities.filter({
            $0.canManageEvents && !$0.defaultEventRolePermissions.isEmpty
        }) {
            let event = try await client.communities.createEvent(
                communityID: eventCommunity.id,
                type: .external,
                title: "iOS event contract probe",
                description: "This disposable event verifies the deployed create contract.",
                duration: 30,
                imageID: nil,
                scheduledAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(3_600)),
                rolePermissions: eventCommunity.defaultEventRolePermissions,
                externalURL: "https://example.org/commonground-ios-event-probe",
                location: nil
            )
            XCTAssertEqual(event.communityId, eventCommunity.id)
            try await client.communities.deleteEvent(
                communityID: eventCommunity.id,
                eventID: event.id
            )
        }
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
