import Foundation

public enum PostFeedScope: String, Codable, CaseIterable, Hashable, Sendable {
    case following
    case explore
}

public enum FeedPostKind: String, Codable, CaseIterable, Hashable, Sendable {
    case user
    case community
}

public enum FeedVerification: String, Codable, CaseIterable, Hashable, Sendable {
    case verified
    case unverified
    case both
}

public struct FeedActor: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let imageId: String?
    public let url: String?
}

public struct FeedCreator: Codable, Equatable, Sendable {
    public let userId: String
    public let displayName: String
    public let imageId: String?
}

public enum FeedMediaType: String, Codable, Sendable {
    case image
    case video
}

public enum FeedMediaSize: String, Codable, Sendable {
    case small
    case medium
    case large
}

public struct FeedPostMedia: Codable, Equatable, Identifiable, Sendable {
    public let type: FeedMediaType
    public let objectId: String
    public let largeObjectId: String?
    public let caption: String?
    public let size: FeedMediaSize?
    public let width: Int?
    public let height: Int?
    public let posterImageId: String?
    public let durationMs: Int?

    public var id: String {
        [type.rawValue, objectId, largeObjectId, posterImageId].compactMap { $0 }.joined(separator: ":")
    }
}

public struct FeedPostViewer: Codable, Equatable, Sendable {
    public let canEdit: Bool
    public let canDelete: Bool
    public let canComment: Bool
}

public struct FeedPost: Codable, Equatable, Identifiable, Sendable {
    public let postId: String
    public let kind: FeedPostKind
    public let actor: FeedActor
    public let creator: FeedCreator?
    public let publishedAt: String
    public let editedAt: String?
    public let bodyPreview: JSONValue
    public let isTruncated: Bool
    public let media: [FeedPostMedia]
    public let commentCount: Int
    public let permalink: String?
    public let viewer: FeedPostViewer

    public var id: String { postId }
    public var markdownSource: String { bodyPreview.articleMarkdownSource }
    public var mediaObjectIDs: [String] {
        var ids = [actor.imageId, creator?.imageId].compactMap { $0 }
        for item in media {
            ids.append(item.objectId)
            if let largeObjectId = item.largeObjectId { ids.append(largeObjectId) }
            if let posterImageId = item.posterImageId { ids.append(posterImageId) }
        }
        return ids
    }
}
