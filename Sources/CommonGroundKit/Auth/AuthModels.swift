import Foundation

public struct ProfileItem: Codable, Equatable, Sendable {
    public let type: String
    public let displayName: String?
    public let imageId: String?
    public let extraData: JSONValue?
}

public struct OwnUser: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let onlineStatus: String
    public let createdAt: String
    public let updatedAt: String
    public let bannerImageId: String?
    public let displayAccount: String
    public let accounts: [ProfileItem]
    public let followingCount: Int
    public let followerCount: Int
    public let tags: [String]?
    public let communityOrder: [String]
    public let finishedTutorials: [String]
    public let newsletter: Bool
    public let weeklyNewsletter: Bool
    public let dmNotifications: Bool
    public let email: String?
    public let emailVerified: Bool
    public let trustScore: String
    public let pointBalance: Double
    public let passkeys: [JSONValue]
    public let extraData: [String: JSONValue]

    public var displayName: String {
        accounts.first(where: { $0.type == displayAccount })?.displayName
            ?? accounts.first?.displayName
            ?? "Common Ground member"
    }
}

public struct LoginResponse: Codable, Equatable, Sendable {
    public let ownData: OwnUser
    public let deviceId: String
    public let webPushSubscription: JSONValue?
    public let communities: [Community]
    public let chats: [Chat]
    public let unreadNotificationCount: Int

    enum CodingKeys: String, CodingKey {
        case ownData, deviceId, webPushSubscription, communities, chats, unreadNotificationCount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ownData = try container.decode(OwnUser.self, forKey: .ownData)
        deviceId = try container.decode(String.self, forKey: .deviceId)
        webPushSubscription = try container.decodeIfPresent(JSONValue.self, forKey: .webPushSubscription)
        communities = try container.decode([Community].self, forKey: .communities)
        chats = try container.decode([Chat].self, forKey: .chats)
        if let value = try? container.decode(Int.self, forKey: .unreadNotificationCount) {
            unreadNotificationCount = value
        } else {
            let value = try container.decode(String.self, forKey: .unreadNotificationCount)
            guard let count = Int(value) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .unreadNotificationCount,
                    in: container,
                    debugDescription: "Expected an integer or integer string"
                )
            }
            unreadNotificationCount = count
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(ownData, forKey: .ownData)
        try container.encode(deviceId, forKey: .deviceId)
        try container.encodeIfPresent(webPushSubscription, forKey: .webPushSubscription)
        try container.encode(communities, forKey: .communities)
        try container.encode(chats, forKey: .chats)
        try container.encode(unreadNotificationCount, forKey: .unreadNotificationCount)
    }
}

public struct AuthSession: Sendable {
    public let response: LoginResponse
    public let deviceId: String
    public let deviceKey: any DeviceSigningKey

    public init(
        response: LoginResponse,
        deviceId: String,
        deviceKey: any DeviceSigningKey
    ) {
        self.response = response
        self.deviceId = deviceId
        self.deviceKey = deviceKey
    }
}

struct DeviceDescriptor: Encodable, Sendable {
    let publicKey: DevicePublicJWK
}

struct PasswordLoginRequest: Encodable, Sendable {
    let type = "password"
    let aliasOrEmail: String
    let password: String
    let device: DeviceDescriptor
}

struct DeviceLoginRequest: Encodable, Sendable {
    let type = "device"
    let deviceId: String
    let secret: String
    let base64Signature: String
}

struct CreateUserRequest: Encodable, Sendable {
    let displayAccount = "cg"
    let recaptchaToken: String
    let device: DeviceDescriptor
    let useEmailAndPassword: EmailPassword
    let useCgProfile: CGProfile

    struct EmailPassword: Encodable, Sendable {
        let email: String
        let password: String
    }

    struct CGProfile: Encodable, Sendable {
        let type = "cg"
        let displayName: String
        let imageId: String? = nil
        let extraData = ExtraData()

        enum CodingKeys: String, CodingKey { case type, displayName, imageId, extraData }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(type, forKey: .type)
            try container.encode(displayName, forKey: .displayName)
            try container.encodeNil(forKey: .imageId)
            try container.encode(extraData, forKey: .extraData)
        }
    }

    struct ExtraData: Encodable, Sendable {
        let type = "cg"
        let description = ""
        let homepage = ""
        let links: [Link] = []
    }

    struct Link: Encodable, Sendable {
        let url: String
        let text: String
    }
}

public struct LoginStatus: Codable, Equatable, Sendable {
    public let userId: String?
}
