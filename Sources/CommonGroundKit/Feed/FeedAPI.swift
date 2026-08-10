import Foundation

public struct FeedAPI: Sendable {
    private let transport: HTTPTransport

    public init(transport: HTTPTransport) {
        self.transport = transport
    }

    public func posts(
        scope: PostFeedScope = .explore,
        actorTypes: [FeedPostKind] = FeedPostKind.allCases,
        topics: [String] = [],
        verification: FeedVerification = .both,
        beforePublishedAt: String? = nil,
        beforePostID: String? = nil,
        limit: Int = 30
    ) async throws -> [FeedPost] {
        let before: FeedCursor?
        if let beforePublishedAt, let beforePostID {
            before = FeedCursor(publishedAt: beforePublishedAt, postId: beforePostID)
        } else {
            before = nil
        }
        return try await transport.call(
            "Feed/getPostList",
            body: FeedPostListRequest(
                scope: scope,
                actorTypes: actorTypes,
                topics: topics.isEmpty ? nil : topics,
                verification: verification,
                before: before,
                limit: min(max(limit, 1), 30)
            )
        )
    }
}

private struct FeedCursor: Encodable, Sendable {
    let publishedAt: String
    let postId: String
}

private struct FeedPostListRequest: Encodable, Sendable {
    let scope: PostFeedScope
    let actorTypes: [FeedPostKind]
    let topics: [String]?
    let verification: FeedVerification
    let before: FeedCursor?
    let limit: Int
}
