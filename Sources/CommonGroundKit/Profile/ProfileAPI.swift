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

    public func updateOwnData(email: String? = nil, dmNotifications: Bool? = nil) async throws {
        let _: EmptyResponse = try await transport.call(
            "User/updateOwnData",
            body: UpdateOwnDataRequest(email: email, dmNotifications: dmNotifications)
        )
    }

    public func updateCGAccount(
        displayName: String,
        description: String,
        homepage: String
    ) async throws {
        let _: EmptyResponse = try await transport.call(
            "User/updateUserAccount",
            body: UpdateCGAccountRequest(
                type: "cg",
                displayName: displayName,
                description: description,
                homepage: homepage,
                links: []
            )
        )
    }

    public func setPassword(_ password: String) async throws {
        let _: EmptyResponse = try await transport.call(
            "User/setPassword",
            body: PasswordRequest(password: password)
        )
    }
}

private struct UserIDsRequest: Encodable, Sendable { let userIds: [String] }
private struct UserIDRequest: Encodable, Sendable { let userId: String }
private struct StatusRequest: Encodable, Sendable { let status: String }
private struct UpdateOwnDataRequest: Encodable, Sendable {
    let email: String?
    let dmNotifications: Bool?
}
private struct UpdateCGAccountRequest: Encodable, Sendable {
    struct Link: Encodable, Sendable {
        let url: String
        let text: String
    }
    let type: String
    let displayName: String
    let description: String
    let homepage: String
    let links: [Link]
}
private struct PasswordRequest: Encodable, Sendable { let password: String }
private struct SearchUsersRequest: Encodable, Sendable {
    let query: String
    let limit: Int
    let offset: Int
    let tags: [String]?
}
