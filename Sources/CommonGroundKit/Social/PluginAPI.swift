import Foundation

public struct PluginAPI: Sendable {
    private let transport: HTTPTransport
    public init(transport: HTTPTransport) { self.transport = transport }

    public func appStore(query: String? = nil, limit: Int = 50, offset: Int = 0) async throws -> [AppStorePlugin] {
        let response: AppStorePluginResponse = try await transport.call(
            "Plugins/getAppstorePlugins",
            body: AppStorePluginRequest(query: query, tags: nil, limit: limit, offset: offset)
        )
        return response.plugins
    }

    public func install(
        pluginID: String,
        ownerCommunityID: String,
        communityID: String
    ) async throws {
        let _: PluginOKResponse = try await transport.call(
            "Plugins/clonePlugin",
            body: ClonePluginRequest(
                copiedFromCommunityId: ownerCommunityID,
                targetCommunityId: communityID,
                pluginId: pluginID
            )
        )
    }

    public func remove(id: String) async throws {
        let _: PluginOKResponse = try await transport.call(
            "Plugins/deletePlugin",
            body: PluginIDRequest(id: id)
        )
    }

    public func acceptPermissions(pluginID: String, permissions: [String]) async throws {
        let _: PluginOKResponse = try await transport.call(
            "Plugins/acceptPluginPermissions",
            body: AcceptPluginPermissionsRequest(pluginId: pluginID, permissions: permissions)
        )
    }

    public func request(_ request: String, signature: String) async throws -> PluginBridgeResponse {
        try await transport.call(
            "Plugins/pluginRequest",
            body: PluginBridgeRequest(request: request, signature: signature)
        )
    }
}

private struct AppStorePluginRequest: Encodable, Sendable {
    let query: String?
    let tags: [String]?
    let limit: Int
    let offset: Int
}
private struct AppStorePluginResponse: Decodable, Sendable { let plugins: [AppStorePlugin] }
private struct ClonePluginRequest: Encodable, Sendable {
    let copiedFromCommunityId: String
    let targetCommunityId: String
    let pluginId: String
}
private struct PluginIDRequest: Encodable, Sendable { let id: String }
private struct AcceptPluginPermissionsRequest: Encodable, Sendable {
    let pluginId: String
    let permissions: [String]
}
private struct PluginBridgeRequest: Encodable, Sendable {
    let request: String
    let signature: String
}
private struct PluginOKResponse: Decodable, Sendable { let ok: Bool }
