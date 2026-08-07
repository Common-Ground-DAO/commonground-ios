import Foundation

public struct ProfileAPI: Sendable {
    private let transport: HTTPTransport

    public init(transport: HTTPTransport) {
        self.transport = transport
    }

    public func users(ids: [String]) async throws -> [UserProfile] {
        try await transport.call("User/getUserData", body: UserIDsRequest(userIds: ids))
    }

    public func details(userID: String) async throws -> UserProfileDetails {
        try await transport.call(
            "User/getUserProfileDetails",
            body: UserIDRequest(userId: userID)
        )
    }

    public func searchUsers(
        query: String,
        limit: Int = 20,
        offset: Int = 0,
        tags: [String]? = nil
    ) async throws -> [UserSearchHit] {
        try await transport.call(
            "Search/searchUsers",
            body: SearchUsersRequest(
                query: query,
                limit: limit,
                offset: offset,
                tags: tags
            )
        )
    }

    public func follow(userID: String) async throws {
        let _: EmptyResponse = try await transport.call(
            "User/followUser",
            body: UserIDRequest(userId: userID)
        )
    }

    public func unfollow(userID: String) async throws {
        let _: EmptyResponse = try await transport.call(
            "User/unfollowUser",
            body: UserIDRequest(userId: userID)
        )
    }

    public func setOwnStatus(_ status: String) async throws {
        let _: EmptyResponse = try await transport.call(
            "User/setOwnStatus",
            body: StatusRequest(status: status)
        )
    }
}

private struct UserIDsRequest: Encodable, Sendable { let userIds: [String] }
private struct UserIDRequest: Encodable, Sendable { let userId: String }
private struct StatusRequest: Encodable, Sendable { let status: String }
private struct SearchUsersRequest: Encodable, Sendable {
    let query: String
    let limit: Int
    let offset: Int
    let tags: [String]?
}
