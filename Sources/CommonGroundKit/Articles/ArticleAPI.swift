import Foundation

public struct ArticleAPI: Sendable {
    private let transport: HTTPTransport
    public init(transport: HTTPTransport) { self.transport = transport }

    public func communityArticles(communityID: String, limit: Int = 30) async throws -> [CommunityArticlePreview] {
        try await transport.call(
            "Community/getArticleList",
            body: ArticleListRequest(communityId: communityID, userId: nil, limit: limit)
        )
    }

    public func communityArticle(communityID: String, articleID: String) async throws -> CommunityArticleDetail {
        try await transport.call(
            "Community/getArticleDetailView",
            body: CommunityArticleRequest(communityId: communityID, articleId: articleID)
        )
    }

    public func userArticles(userID: String, limit: Int = 30) async throws -> [UserArticlePreview] {
        try await transport.call(
            "User/getArticleList",
            body: ArticleListRequest(communityId: nil, userId: userID, limit: limit)
        )
    }

    public func userArticle(userID: String, articleID: String) async throws -> UserArticleDetail {
        try await transport.call(
            "User/getArticleDetailView",
            body: UserArticleRequest(userId: userID, articleId: articleID)
        )
    }

    public func createUserArticle(
        title: String,
        previewText: String,
        text: String,
        tags: [String],
        published: String? = ISO8601DateFormatter().string(from: Date())
    ) async throws -> UserArticleDetail {
        try await transport.call(
            "User/createArticle",
            body: CreateUserArticleRequest(
                userArticle: .init(url: nil, published: published),
                article: .init(
                    title: title,
                    previewText: previewText,
                    thumbnailImageId: nil,
                    headerImageId: nil,
                    content: .object([
                        "version": .string("2"),
                        "content": .array(text.components(separatedBy: "\n").enumerated().flatMap { index, line in
                            var nodes: [JSONValue] = index == 0 ? [] : [.object(["type": .string("newline")])]
                            if !line.isEmpty {
                                nodes.append(.object(["type": .string("text"), "value": .string(line)]))
                            }
                            return nodes
                        })
                    ]),
                    tags: tags
                )
            )
        )
    }
}

private struct ArticleListRequest: Encodable, Sendable {
    let communityId: String?
    let userId: String?
    let order = "DESC"
    let orderBy = "published"
    let limit: Int
}

private struct CommunityArticleRequest: Encodable, Sendable {
    let communityId: String
    let articleId: String
}

private struct UserArticleRequest: Encodable, Sendable {
    let userId: String
    let articleId: String
}

private struct CreateUserArticleRequest: Encodable, Sendable {
    struct UserData: Encodable, Sendable {
        let url: String?
        let published: String?
    }
    struct ArticleData: Encodable, Sendable {
        let title: String
        let previewText: String
        let thumbnailImageId: String?
        let headerImageId: String?
        let content: JSONValue
        let tags: [String]
    }
    let userArticle: UserData
    let article: ArticleData
}
