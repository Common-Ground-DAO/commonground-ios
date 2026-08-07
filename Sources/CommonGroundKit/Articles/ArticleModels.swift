import Foundation

public struct ArticlePreview: Decodable, Equatable, Identifiable, Sendable {
    public let articleId: String
    public let title: String
    public let previewText: String?
    public let thumbnailImageId: String?
    public let headerImageId: String?
    public let creatorId: String
    public let tags: [String]
    public let commentCount: Int
    public let latestCommentTimestamp: String?

    public var id: String { articleId }

    private enum CodingKeys: String, CodingKey {
        case articleId, title, previewText, thumbnailImageId, headerImageId
        case creatorId, tags, commentCount, latestCommentTimestamp
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        articleId = try container.decode(String.self, forKey: .articleId)
        title = try container.decode(String.self, forKey: .title)
        previewText = try container.decodeIfPresent(String.self, forKey: .previewText)
        thumbnailImageId = try container.decodeIfPresent(String.self, forKey: .thumbnailImageId)
        headerImageId = try container.decodeIfPresent(String.self, forKey: .headerImageId)
        creatorId = try container.decode(String.self, forKey: .creatorId)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        if let number = try? container.decode(Int.self, forKey: .commentCount) {
            commentCount = number
        } else if let string = try? container.decode(String.self, forKey: .commentCount) {
            commentCount = Int(string) ?? 0
        } else {
            commentCount = 0
        }
        latestCommentTimestamp = try container.decodeIfPresent(String.self, forKey: .latestCommentTimestamp)
    }
}

public struct ArticleDetail: Decodable, Equatable, Sendable {
    public let articleId: String
    public let title: String
    public let previewText: String?
    public let thumbnailImageId: String?
    public let headerImageId: String?
    public let creatorId: String
    public let tags: [String]
    public let commentCount: Int
    public let latestCommentTimestamp: String?
    public let content: JSONValue
    public let channelId: String

    public var markdownSource: String {
        guard case .object(let root) = content else { return "" }
        if root["version"]?.stringValue == "1" { return root["text"]?.stringValue ?? "" }
        guard case .array(let nodes) = root["content"] else { return "" }
        return nodes.compactMap { node -> String? in
            guard case .object(let value) = node else { return nil }
            switch value["type"]?.stringValue {
            case "newline": return "\n"
            case "text": return value["value"]?.stringValue
            case "link":
                guard let label = value["value"]?.stringValue else { return nil }
                let destination = label.hasPrefix("http") ? label : "https://\(label)"
                return "[\(label)](<\(destination)>)"
            case "richTextLink":
                guard let label = value["value"]?.stringValue,
                      let destination = value["url"]?.stringValue else { return nil }
                return "[\(label)](<\(destination)>)"
            case "header":
                guard case .array(let parts) = value["value"] else { return nil }
                return "## " + parts.compactMap { $0.objectValue?["value"]?.stringValue }.joined()
            case "articleImage":
                guard let caption = value["caption"]?.stringValue, !caption.isEmpty else { return nil }
                return "*\(caption)*"
            default: return nil
            }
        }.joined()
    }

    public var plainText: String { markdownSource }

    private enum CodingKeys: String, CodingKey {
        case articleId, title, previewText, thumbnailImageId, headerImageId
        case creatorId, tags, commentCount, latestCommentTimestamp, content, channelId
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        articleId = try container.decode(String.self, forKey: .articleId)
        title = try container.decode(String.self, forKey: .title)
        previewText = try container.decodeIfPresent(String.self, forKey: .previewText)
        thumbnailImageId = try container.decodeIfPresent(String.self, forKey: .thumbnailImageId)
        headerImageId = try container.decodeIfPresent(String.self, forKey: .headerImageId)
        creatorId = try container.decode(String.self, forKey: .creatorId)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        if let number = try? container.decode(Int.self, forKey: .commentCount) {
            commentCount = number
        } else if let string = try? container.decode(String.self, forKey: .commentCount) {
            commentCount = Int(string) ?? 0
        } else {
            commentCount = 0
        }
        latestCommentTimestamp = try container.decodeIfPresent(String.self, forKey: .latestCommentTimestamp)
        content = try container.decode(JSONValue.self, forKey: .content)
        channelId = try container.decode(String.self, forKey: .channelId)
    }
}

public struct CommunityArticle: Decodable, Equatable, Sendable {
    public let communityId: String
    public let articleId: String
    public let url: String?
    public let published: String?
    public let updatedAt: String
}

public struct UserArticle: Decodable, Equatable, Sendable {
    public let userId: String
    public let articleId: String
    public let url: String?
    public let published: String?
    public let updatedAt: String
}

public struct CommunityArticlePreview: Decodable, Equatable, Identifiable, Sendable {
    public let communityArticle: CommunityArticle
    public let article: ArticlePreview
    public var id: String { article.id }
}

public struct UserArticlePreview: Decodable, Equatable, Identifiable, Sendable {
    public let userArticle: UserArticle
    public let article: ArticlePreview
    public var id: String { article.id }
}

public struct CommunityArticleDetail: Decodable, Equatable, Sendable {
    public let communityArticle: CommunityArticle
    public let article: ArticleDetail
}

public struct UserArticleDetail: Decodable, Equatable, Sendable {
    public let userArticle: UserArticle
    public let article: ArticleDetail
}
