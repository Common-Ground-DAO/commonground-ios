import Foundation

public final class CommonGroundClient: @unchecked Sendable {
    public let instance: InstanceURL
    public let transport: HTTPTransport
    public let instanceAPI: InstanceAPI
    public let auth: AuthAPI
    public let communities: CommunityAPI
    public let messages: MessageAPI
    public let chats: ChatAPI
    public let notifications: NotificationAPI
    public let profiles: ProfileAPI
    public let articles: ArticleAPI
    public let reports: ReportAPI
    public let files: FileAPI
    public let plugins: PluginAPI

    public init(instance: InstanceURL, sessionConfiguration: URLSessionConfiguration? = nil) {
        self.instance = instance
        let transport = HTTPTransport(
            baseURL: instance.url,
            sessionConfiguration: sessionConfiguration
        )
        self.transport = transport
        self.instanceAPI = InstanceAPI(transport: transport)
        self.auth = AuthAPI(transport: transport)
        self.communities = CommunityAPI(transport: transport)
        self.messages = MessageAPI(transport: transport)
        self.chats = ChatAPI(transport: transport)
        self.notifications = NotificationAPI(transport: transport)
        self.profiles = ProfileAPI(transport: transport)
        self.articles = ArticleAPI(transport: transport)
        self.reports = ReportAPI(transport: transport)
        self.files = FileAPI(transport: transport)
        self.plugins = PluginAPI(transport: transport)
    }

    @MainActor
    public func realtime() -> RealtimeClient {
        RealtimeClient(transport: transport)
    }
}
