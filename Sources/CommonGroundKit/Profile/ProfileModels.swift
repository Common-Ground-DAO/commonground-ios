import Foundation

public struct UserProfile: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let isBot: Bool
    public let botOwner: JSONValue?
    public let onlineStatus: String
    public let isFollowed: Bool
    public let isFollower: Bool
    public let createdAt: String
    public let updatedAt: String
    public let bannerImageId: String?
    public let displayAccount: String
    public let accounts: [ProfileItem]
    public let premiumFeatures: [JSONValue]
    public let followingCount: Int
    public let followerCount: Int
    public let tags: [String]?

    enum CodingKeys: String, CodingKey {
        case id, isBot, botOwner, onlineStatus, isFollowed, isFollower
        case createdAt, updatedAt, bannerImageId, displayAccount, accounts
        case premiumFeatures, followingCount, followerCount, tags
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        isBot = try container.decodeIfPresent(Bool.self, forKey: .isBot) ?? false
        botOwner = try container.decodeIfPresent(JSONValue.self, forKey: .botOwner)
        onlineStatus = try container.decode(String.self, forKey: .onlineStatus)
        isFollowed = try container.decodeIfPresent(Bool.self, forKey: .isFollowed) ?? false
        isFollower = try container.decodeIfPresent(Bool.self, forKey: .isFollower) ?? false
        createdAt = try container.decode(String.self, forKey: .createdAt)
        updatedAt = try container.decode(String.self, forKey: .updatedAt)
        bannerImageId = try container.decodeIfPresent(String.self, forKey: .bannerImageId)
        displayAccount = try container.decode(String.self, forKey: .displayAccount)
        accounts = try container.decode([ProfileItem].self, forKey: .accounts)
        premiumFeatures = try container.decodeIfPresent([JSONValue].self, forKey: .premiumFeatures) ?? []
        followingCount = try container.decode(Int.self, forKey: .followingCount)
        followerCount = try container.decode(Int.self, forKey: .followerCount)
        tags = try container.decodeIfPresent([String].self, forKey: .tags)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(isBot, forKey: .isBot)
        try container.encodeIfPresent(botOwner, forKey: .botOwner)
        try container.encode(onlineStatus, forKey: .onlineStatus)
        try container.encode(isFollowed, forKey: .isFollowed)
        try container.encode(isFollower, forKey: .isFollower)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(bannerImageId, forKey: .bannerImageId)
        try container.encode(displayAccount, forKey: .displayAccount)
        try container.encode(accounts, forKey: .accounts)
        try container.encode(premiumFeatures, forKey: .premiumFeatures)
        try container.encode(followingCount, forKey: .followingCount)
        try container.encode(followerCount, forKey: .followerCount)
        try container.encodeIfPresent(tags, forKey: .tags)
    }

    public var displayName: String {
        accounts.first(where: { $0.type == displayAccount })?.displayName
            ?? accounts.first?.displayName
            ?? "Common Ground member"
    }

    public var imageID: String? {
        accounts.first(where: { $0.type == displayAccount })?.imageId
            ?? accounts.first?.imageId
    }

    func replacingFollowed(_ value: Bool) -> UserProfile {
        UserProfile(
            id: id,
            isBot: isBot,
            botOwner: botOwner,
            onlineStatus: onlineStatus,
            isFollowed: value,
            isFollower: isFollower,
            createdAt: createdAt,
            updatedAt: updatedAt,
            bannerImageId: bannerImageId,
            displayAccount: displayAccount,
            accounts: accounts,
            premiumFeatures: premiumFeatures,
            followingCount: followingCount,
            followerCount: followerCount,
            tags: tags
        )
    }

    private init(
        id: String,
        isBot: Bool,
        botOwner: JSONValue?,
        onlineStatus: String,
        isFollowed: Bool,
        isFollower: Bool,
        createdAt: String,
        updatedAt: String,
        bannerImageId: String?,
        displayAccount: String,
        accounts: [ProfileItem],
        premiumFeatures: [JSONValue],
        followingCount: Int,
        followerCount: Int,
        tags: [String]?
    ) {
        self.id = id
        self.isBot = isBot
        self.botOwner = botOwner
        self.onlineStatus = onlineStatus
        self.isFollowed = isFollowed
        self.isFollower = isFollower
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.bannerImageId = bannerImageId
        self.displayAccount = displayAccount
        self.accounts = accounts
        self.premiumFeatures = premiumFeatures
        self.followingCount = followingCount
        self.followerCount = followerCount
        self.tags = tags
    }
}

public struct UserSearchHit: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let matchPriority: Int?
    public let matchedAccountTypes: [String]?

    enum CodingKeys: String, CodingKey {
        case id, matchPriority, matchedAccountTypes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        if let value = try? container.decode(Int.self, forKey: .matchPriority) {
            matchPriority = value
        } else if let value = try? container.decode(String.self, forKey: .matchPriority) {
            matchPriority = Int(value)
        } else {
            matchPriority = nil
        }
        matchedAccountTypes = try container.decodeIfPresent([String].self, forKey: .matchedAccountTypes)
    }
}

public enum SuggestedUserReasonType: String, Codable, Equatable, Sendable {
    case sharedCommunity
    case followedByFollowing
    case popular
}

public struct SuggestedUserReason: Codable, Equatable, Sendable {
    public let type: SuggestedUserReasonType
    public let communityId: String?
    public let mutualCount: Int?
}

public struct SuggestedUser: Codable, Equatable, Identifiable, Sendable {
    public let userId: String
    public let reason: SuggestedUserReason
    public var id: String { userId }
}

public struct SuggestedUsersPage: Codable, Equatable, Sendable {
    public let users: [SuggestedUser]
    public let nextCursor: String?
}

public struct UserProfileDetails: Decodable, Equatable, Sendable {
    public let detailledProfiles: [ProfileItem]
    public let wallets: [JSONValue]
}
