import Foundation

public enum ImageUploadType: String, Encodable, Sendable {
    case userProfileImage
    case userBannerImage
    case articleImage
    case articleContentImage
    case channelAttachmentImage
    case communityHeaderImage
    case communityLogoSmall
    case communityLogoLarge
    case roleImage
}

public struct ImageUploadResult: Codable, Equatable, Sendable {
    public let imageId: String
    public let largeImageId: String?
}

public struct SignedFileURL: Codable, Equatable, Sendable {
    public let objectId: String
    public let url: String
    public let validUntil: String
}

public struct FileAPI: Sendable {
    private let transport: HTTPTransport
    public init(transport: HTTPTransport) { self.transport = transport }

    public func uploadImage(
        _ data: Data,
        type: ImageUploadType,
        communityID: String? = nil,
        filename: String = "upload.jpg",
        mimeType: String = "image/jpeg"
    ) async throws -> ImageUploadResult {
        let options = try String(
            data: JSONEncoder().encode(UploadOptions(type: type, communityId: communityID)),
            encoding: .utf8
        ) ?? "{}"
        return try await transport.callMultipart(
            "File/uploadImage",
            fields: ["options": options],
            fileField: "uploaded",
            filename: filename,
            mimeType: mimeType,
            fileData: data
        )
    }

    public func signedURLs(objectIDs: [String]) async throws -> [SignedFileURL] {
        guard !objectIDs.isEmpty else { return [] }
        return try await transport.call(
            "File/getSignedUrls",
            body: SignedURLsRequest(objectIds: objectIDs)
        )
    }
}

private struct UploadOptions: Encodable, Sendable {
    let type: ImageUploadType
    let communityId: String?
}
private struct SignedURLsRequest: Encodable, Sendable { let objectIds: [String] }
