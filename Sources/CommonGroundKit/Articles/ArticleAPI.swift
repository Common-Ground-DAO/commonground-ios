import Foundation

public struct ArticleAPI: Sendable {
    private let transport: HTTPTransport
    public init(transport: HTTPTransport) { self.transport = transport }

    public func communityArticles(
        communityID: String,
        drafts: Bool = false,
        limit: Int = 30
    ) async throws -> [CommunityArticlePreview] {
        try await transport.call(
            "Community/getArticleList",
            body: ArticleListRequest(
                communityId: communityID,
                userId: nil,
                limit: limit,
                drafts: drafts ? true : nil
            )
        )
    }

    public func globalCommunityArticles(
        scope: CommunityFeedScope,
        anyCommunityTopics: [String] = [],
        publishedBefore: String? = nil,
        beforeID: String? = nil,
        limit: Int = 30
    ) async throws -> [CommunityArticlePreview] {
        try await transport.call(
            "Community/getArticleList",
            body: GlobalCommunityArticleListRequest(
                publishedBefore: publishedBefore,
                beforeId: beforeID,
                limit: limit,
                verification: scope,
                anyCommunityTags: anyCommunityTopics.isEmpty ? nil : anyCommunityTopics
            )
        )
    }

    public func communityArticle(communityID: String, articleID: String) async throws -> CommunityArticleDetail {
        try await transport.call(
            "Community/getArticleDetailView",
            body: CommunityArticleRequest(communityId: communityID, articleId: articleID)
        )
    }

    public func userArticles(
        userID: String,
        drafts: Bool = false,
        limit: Int = 30
    ) async throws -> [UserArticlePreview] {
        try await transport.call(
            "User/getArticleList",
            body: ArticleListRequest(
                communityId: nil,
                userId: userID,
                limit: limit,
                drafts: drafts ? true : nil
            )
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

    public func createCommunityArticle(
        communityID: String,
        title: String,
        previewText: String,
        text: String,
        tags: [String],
        rolePermissions: [ArticleRolePermission],
        published: String? = ISO8601DateFormatter().string(from: Date())
    ) async throws -> CommunityArticleDetail {
        try await transport.call(
            "Community/createArticle",
            body: CreateCommunityArticleRequest(
                communityArticle: .init(
                    communityId: communityID,
                    url: nil,
                    published: published,
                    rolePermissions: rolePermissions
                ),
                article: .init(
                    title: title,
                    previewText: previewText,
                    thumbnailImageId: nil,
                    headerImageId: nil,
                    content: Self.content(text),
                    tags: tags
                )
            )
        )
    }

    public func updateUserArticle(
        articleID: String,
        title: String,
        previewText: String,
        text: String,
        tags: [String],
        published: String?
    ) async throws {
        let _: UpdateUserArticleResponse = try await transport.call(
            "User/updateArticle",
            body: UpdateUserArticleRequest(
                userArticle: .init(articleId: articleID, published: published),
                article: .init(
                    articleId: articleID,
                    title: title,
                    previewText: previewText,
                    content: Self.content(text),
                    tags: tags
                )
            )
        )
    }

    public func updateCommunityArticle(
        communityID: String,
        articleID: String,
        title: String,
        previewText: String,
        text: String,
        tags: [String],
        rolePermissions: [ArticleRolePermission],
        published: String?
    ) async throws {
        let _: EmptyResponse = try await transport.call(
            "Community/updateArticle",
            body: UpdateCommunityArticleRequest(
                communityArticle: .init(
                    communityId: communityID,
                    articleId: articleID,
                    published: published,
                    rolePermissions: rolePermissions
                ),
                article: .init(
                    articleId: articleID,
                    title: title,
                    previewText: previewText,
                    content: Self.content(text),
                    tags: tags
                )
            )
        )
    }

    public func deleteUserArticle(articleID: String) async throws {
        let _: EmptyResponse = try await transport.call(
            "User/deleteArticle",
            body: DeleteUserArticleRequest(articleId: articleID)
        )
    }

    public func deleteCommunityArticle(communityID: String, articleID: String) async throws {
        let _: EmptyResponse = try await transport.call(
            "Community/deleteArticle",
            body: DeleteCommunityArticleRequest(communityId: communityID, articleId: articleID)
        )
    }

    public func joinCommentRoom(access: MessageAccess) async throws {
        let _: EmptyResponse = try await transport.call(
            "Message/joinArticleEventRoom",
            body: ArticleRoomRequest(access: access)
        )
    }

    public func leaveCommentRoom(access: MessageAccess) async throws {
        let _: EmptyResponse = try await transport.call(
            "Message/leaveArticleEventRoom",
            body: ArticleRoomRequest(access: access)
        )
    }

    private static func content(_ text: String) -> JSONValue {
        .object([
            "version": .string("2"),
            "content": .array(text.components(separatedBy: "\n").enumerated().flatMap { index, line in
                var nodes: [JSONValue] = index == 0 ? [] : [.object(["type": .string("newline")])]
                if !line.isEmpty {
                    nodes.append(.object(["type": .string("text"), "value": .string(line)]))
                }
                return nodes
            })
        ])
    }
}

private struct ArticleListRequest: Encodable, Sendable {
    let communityId: String?
    let userId: String?
    let order = "DESC"
    let orderBy = "published"
    let limit: Int
    let drafts: Bool?
}

private struct GlobalCommunityArticleListRequest: Encodable, Sendable {
    let order = "DESC"
    let orderBy = "published"
    let publishedBefore: String?
    let beforeId: String?
    let limit: Int
    let verification: CommunityFeedScope
    let anyCommunityTags: [String]?
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

        private enum CodingKeys: String, CodingKey { case url, published }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            if let url { try container.encode(url, forKey: .url) }
            else { try container.encodeNil(forKey: .url) }
            if let published { try container.encode(published, forKey: .published) }
            else { try container.encodeNil(forKey: .published) }
        }
    }
    struct ArticleData: Encodable, Sendable {
        let title: String
        let previewText: String
        let thumbnailImageId: String?
        let headerImageId: String?
        let content: JSONValue
        let tags: [String]

        private enum CodingKeys: String, CodingKey {
            case title, previewText, thumbnailImageId, headerImageId, content, tags
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(title, forKey: .title)
            try container.encode(previewText, forKey: .previewText)
            if let thumbnailImageId { try container.encode(thumbnailImageId, forKey: .thumbnailImageId) }
            else { try container.encodeNil(forKey: .thumbnailImageId) }
            if let headerImageId { try container.encode(headerImageId, forKey: .headerImageId) }
            else { try container.encodeNil(forKey: .headerImageId) }
            try container.encode(content, forKey: .content)
            try container.encode(tags, forKey: .tags)
        }
    }
    let userArticle: UserData
    let article: ArticleData
}

private struct CreateCommunityArticleRequest: Encodable, Sendable {
    struct CommunityData: Encodable, Sendable {
        let communityId: String
        let url: String?
        let published: String?
        let rolePermissions: [ArticleRolePermission]

        private enum CodingKeys: String, CodingKey {
            case communityId, url, published, rolePermissions
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(communityId, forKey: .communityId)
            if let url { try container.encode(url, forKey: .url) }
            else { try container.encodeNil(forKey: .url) }
            if let published { try container.encode(published, forKey: .published) }
            else { try container.encodeNil(forKey: .published) }
            try container.encode(rolePermissions, forKey: .rolePermissions)
        }
    }

    let communityArticle: CommunityData
    let article: CreateUserArticleRequest.ArticleData
}

private struct UpdateArticleData: Encodable, Sendable {
    let articleId: String
    let title: String
    let previewText: String
    let content: JSONValue
    let tags: [String]
}

private struct UpdateUserArticleRequest: Encodable, Sendable {
    struct UserData: Encodable, Sendable {
        let articleId: String
        let published: String?

        private enum CodingKeys: String, CodingKey { case articleId, published }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(articleId, forKey: .articleId)
            if let published { try container.encode(published, forKey: .published) }
            else { try container.encodeNil(forKey: .published) }
        }
    }
    let userArticle: UserData
    let article: UpdateArticleData
}

private struct UpdateUserArticleResponse: Decodable, Sendable {
    struct UserData: Decodable, Sendable { let updatedAt: String }
    let userArticle: UserData
}

private struct UpdateCommunityArticleRequest: Encodable, Sendable {
    struct CommunityData: Encodable, Sendable {
        let communityId: String
        let articleId: String
        let published: String?
        let rolePermissions: [ArticleRolePermission]

        private enum CodingKeys: String, CodingKey {
            case communityId, articleId, published, rolePermissions
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(communityId, forKey: .communityId)
            try container.encode(articleId, forKey: .articleId)
            if let published { try container.encode(published, forKey: .published) }
            else { try container.encodeNil(forKey: .published) }
            try container.encode(rolePermissions, forKey: .rolePermissions)
        }
    }
    let communityArticle: CommunityData
    let article: UpdateArticleData
}

private struct DeleteUserArticleRequest: Encodable, Sendable { let articleId: String }
private struct DeleteCommunityArticleRequest: Encodable, Sendable {
    let communityId: String
    let articleId: String
}
private struct ArticleRoomRequest: Encodable, Sendable { let access: MessageAccess }
