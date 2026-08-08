import CommonGroundKit
import SwiftUI
import UIKit
import WebKit

extension Notification.Name {
    static let commonGroundPluginNavigate = Notification.Name("CommonGroundPluginNavigate")
}

struct PluginRuntimeView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    let community: Community
    let plugin: CommunityPluginInfo

    var body: some View {
        NavigationStack {
            PluginWebView(
                plugin: plugin,
                community: community,
                userID: model.store.ownUser?.id ?? "",
                instanceURL: model.client?.instance.url,
                darkMode: colorScheme == .dark,
                forward: { request, signature in
                    try await model.forwardPluginRequest(request: request, signature: signature)
                },
                requestPermission: { permission in
                    let serverPermission = permission.serverPermission
                    let declared = Set(
                        (plugin.permissions?.mandatory ?? []) + (plugin.permissions?.optional ?? [])
                    )
                    guard declared.contains(serverPermission) else { return false }
                    if Set(plugin.acceptedPermissions ?? []).contains(serverPermission) { return true }
                    guard await PluginPermissionPrompt.confirm(
                        permission: permission.permissionTitle,
                        pluginName: plugin.name
                    ) else { return false }
                    return await model.grantPluginPermission(serverPermission, to: plugin)
                },
                navigate: { destination in
                    await navigate(destination)
                }
            )
            .navigationTitle(plugin.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    if let url = normalizedPluginURL(plugin.url) {
                        ShareLink(item: url) {
                            Label("Share app", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
    }

    @MainActor
    private func navigate(_ destination: String) async -> Bool {
        let resolved: URL?
        if destination.hasPrefix("/"), let base = model.client?.instance.url {
            resolved = URL(string: destination, relativeTo: base)?.absoluteURL
        } else {
            resolved = URL(string: destination)
        }
        guard let url = resolved else { return false }
        if let instance = model.client?.instance.url,
           url.scheme == instance.scheme,
           url.host == instance.host {
            NotificationCenter.default.post(
                name: .commonGroundPluginNavigate,
                object: url.path
            )
            dismiss()
            return true
        }
        guard await PluginPermissionPrompt.confirmExternal(url: url, pluginName: plugin.name) else {
            return false
        }
        return await UIApplication.shared.open(url)
    }
}

private struct PluginWebView: UIViewRepresentable {
    let plugin: CommunityPluginInfo
    let community: Community
    let userID: String
    let instanceURL: URL?
    let darkMode: Bool
    let forward: (String, String) async throws -> PluginBridgeResponse
    let requestPermission: (RequestedPluginPermission) async -> Bool
    let navigate: (String) async -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        let bridge = WKUserScript(
            source: """
            (() => {
              if (window.__commonGroundNativeBridge) return;
              window.__commonGroundNativeBridge = true;
              window.addEventListener('message', event => {
                const data = event.data;
                if (data && typeof data === 'object' && typeof data.request === 'string') {
                  window.webkit.messageHandlers.commonGround.postMessage(data);
                }
              });
            })();
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        configuration.userContentController.addUserScript(bridge)
        configuration.userContentController.add(context.coordinator, name: "commonGround")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        #if DEBUG
        webView.isInspectable = true
        #endif
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        context.coordinator.webView = webView
        if let url = launchURL {
            webView.load(URLRequest(url: url, cachePolicy: .reloadRevalidatingCacheData))
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "commonGround")
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
    }

    private var launchURL: URL? {
        guard let base = normalizedPluginURL(plugin.url),
              var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
        var items = components.queryItems ?? []
        items.removeAll { ["iframeUid", "cg_theme", "cg_bg_color"].contains($0.name) }
        items.append(URLQueryItem(name: "iframeUid", value: Coordinator.makeIframeUID()))
        items.append(URLQueryItem(name: "cg_theme", value: darkMode ? "dark" : "light"))
        items.append(URLQueryItem(name: "cg_bg_color", value: darkMode ? "#161820" : "#F1F1F1"))
        components.queryItems = items
        return components.url
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
        var parent: PluginWebView
        weak var webView: WKWebView?
        private let iframeUID = makeIframeUID()
        private var requestHistory: [Date] = []
        private var sensitiveRequestHistory: [Date] = []

        init(parent: PluginWebView) {
            self.parent = parent
        }

        static func makeIframeUID() -> String {
            UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "commonGround",
                  message.frameInfo.isMainFrame,
                  trusted(message.frameInfo.securityOrigin),
                  let envelope = message.body as? [String: Any],
                  let request = envelope["request"] as? String else { return }
            Task { await handle(request: request, signature: envelope["signature"] as? String) }
        }

        private func handle(request: String, signature: String?) async {
            guard allowRequest(),
                  let data = request.data(using: .utf8),
                  let inner = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let requestID = inner["requestId"] as? String,
                  let pluginID = inner["pluginId"] as? String,
                  pluginID == parent.plugin.id || pluginID == parent.plugin.pluginId,
                  let requestIframeUID = inner["iframeUid"] as? String,
                  requestIframeUID == iframeUID || requestIframeUID == launchIframeUID,
                  let type = inner["type"] as? String else { return }

            do {
                if type == "safeRequest" {
                    let response = await handleSafeRequest(inner)
                    send(response: response, requestID: requestID)
                } else {
                    guard let signature, !signature.isEmpty else {
                        throw PluginBridgeError.invalidSignature
                    }
                    let response = try await parent.forward(request, signature)
                    send(
                        response: ["response": response.response, "signature": response.signature],
                        requestID: requestID
                    )
                }
            } catch {
                send(error: error.localizedDescription, requestID: requestID, pluginID: pluginID)
            }
        }

        private var launchIframeUID: String? {
            webView?.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
                .queryItems?.first { $0.name == "iframeUid" }?.value
        }

        private func handleSafeRequest(_ inner: [String: Any]) async -> [String: Any] {
            let requestID = inner["requestId"] as? String ?? ""
            let pluginID = inner["pluginId"] as? String ?? parent.plugin.id
            guard let data = inner["data"] as? [String: Any],
                  let action = data["type"] as? String else {
                return innerResponse(error: "INVALID_REQUEST", pluginID: pluginID, requestID: requestID)
            }
            switch action {
            case "init":
                return innerResponse(
                    data: [
                        "pluginId": parent.plugin.id,
                        "assignableRoleIds": parent.plugin.config?.canGiveRole == true
                            ? (parent.plugin.config?.giveableRoleIds ?? [])
                            : [],
                        "userId": parent.userID,
                    ],
                    pluginID: pluginID,
                    requestID: requestID
                )
            case "navigate":
                guard allowSensitiveRequest() else {
                    return innerResponse(
                        error: "MAX_NAVIGATES_PER_5_SECS",
                        pluginID: pluginID,
                        requestID: requestID
                    )
                }
                guard let destination = data["to"] as? String else {
                    return innerResponse(error: "INVALID_NAVIGATION", pluginID: pluginID, requestID: requestID)
                }
                let ok = await parent.navigate(destination)
                return innerResponse(
                    data: ["ok": ok],
                    pluginID: pluginID,
                    requestID: requestID
                )
            case "requestPermission":
                guard allowSensitiveRequest() else {
                    return innerResponse(
                        error: "MAX_NAVIGATES_PER_5_SECS",
                        pluginID: pluginID,
                        requestID: requestID
                    )
                }
                guard let raw = data["permission"] as? String,
                      let permission = RequestedPluginPermission(rawValue: raw) else {
                    return innerResponse(error: "UNKNOWN_PERMISSION", pluginID: pluginID, requestID: requestID)
                }
                let ok = await parent.requestPermission(permission)
                return innerResponse(
                    data: ["ok": ok],
                    pluginID: pluginID,
                    requestID: requestID
                )
            default:
                return innerResponse(error: "UNKNOWN_SAFE_REQUEST", pluginID: pluginID, requestID: requestID)
            }
        }

        private func innerResponse(
            data: [String: Any],
            pluginID: String,
            requestID: String
        ) -> [String: Any] {
            let inner: [String: Any] = ["data": data, "pluginId": pluginID, "requestId": requestID]
            return ["response": jsonString(inner)]
        }

        private func innerResponse(error: String, pluginID: String, requestID: String) -> [String: Any] {
            innerResponse(data: ["error": error], pluginID: pluginID, requestID: requestID)
        }

        private func send(error: String, requestID: String, pluginID: String) {
            send(response: innerResponse(error: error, pluginID: pluginID, requestID: requestID), requestID: requestID)
        }

        private func send(response: [String: Any], requestID: String) {
            let clean = response.compactMapValues { value -> Any? in
                if value is NSNull { return value }
                if let optional = value as? OptionalProtocol, optional.isNil { return nil }
                return value
            }
            let envelope: [String: Any] = ["type": requestID, "payload": clean]
            guard JSONSerialization.isValidJSONObject(envelope),
                  let data = try? JSONSerialization.data(withJSONObject: envelope),
                  let json = String(data: data, encoding: .utf8) else { return }
            webView?.evaluateJavaScript("window.postMessage(\(json), '*');")
        }

        private func jsonString(_ object: [String: Any]) -> String {
            guard let data = try? JSONSerialization.data(withJSONObject: object),
                  let result = String(data: data, encoding: .utf8) else { return "{}" }
            return result
        }

        private func allowRequest() -> Bool {
            let cutoff = Date().addingTimeInterval(-60)
            requestHistory.removeAll { $0 < cutoff }
            guard requestHistory.count < 100 else { return false }
            requestHistory.append(Date())
            return true
        }

        private func allowSensitiveRequest() -> Bool {
            let cutoff = Date().addingTimeInterval(-5)
            sensitiveRequestHistory.removeAll { $0 < cutoff }
            guard sensitiveRequestHistory.count < 1 else { return false }
            sensitiveRequestHistory.append(Date())
            return true
        }

        private func trusted(_ origin: WKSecurityOrigin) -> Bool {
            guard let expected = normalizedPluginURL(parent.plugin.url) else { return false }
            let expectedPort = expected.port ?? (expected.scheme == "https" ? 443 : 80)
            let actualPort = origin.port == 0 ? (origin.protocol == "https" ? 443 : 80) : origin.port
            return origin.protocol == expected.scheme
                && origin.host.caseInsensitiveCompare(expected.host ?? "") == .orderedSame
                && actualPort == expectedPort
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url,
                  let expected = normalizedPluginURL(parent.plugin.url) else {
                decisionHandler(.cancel)
                return
            }
            let expectedPort = expected.port ?? (expected.scheme == "https" ? 443 : 80)
            let actualPort = url.port ?? (url.scheme == "https" ? 443 : 80)
            let sameOrigin = url.scheme == expected.scheme
                && url.host?.caseInsensitiveCompare(expected.host ?? "") == .orderedSame
                && actualPort == expectedPort
            if sameOrigin {
                decisionHandler(.allow)
                return
            }
            decisionHandler(.cancel)
            guard navigationAction.navigationType == .linkActivated else { return }
            Task {
                if await PluginPermissionPrompt.confirmExternal(url: url, pluginName: parent.plugin.name) {
                    _ = await UIApplication.shared.open(url)
                }
            }
        }

        func webView(
            _ webView: WKWebView,
            requestMediaCapturePermissionFor origin: WKSecurityOrigin,
            initiatedByFrame frame: WKFrameInfo,
            type: WKMediaCaptureType,
            decisionHandler: @escaping (WKPermissionDecision) -> Void
        ) {
            guard trusted(origin) else {
                decisionHandler(.deny)
                return
            }
            let accepted = Set(parent.plugin.acceptedPermissions ?? [])
            switch type {
            case .camera:
                decisionHandler(accepted.contains("ALLOW_CAMERA") ? .prompt : .deny)
            case .microphone:
                decisionHandler(accepted.contains("ALLOW_MICROPHONE") ? .prompt : .deny)
            case .cameraAndMicrophone:
                decisionHandler(
                    accepted.isSuperset(of: ["ALLOW_CAMERA", "ALLOW_MICROPHONE"]) ? .prompt : .deny
                )
            @unknown default:
                decisionHandler(.deny)
            }
        }
    }
}

enum RequestedPluginPermission: String {
    case email
    case twitter
    case lukso
    case farcaster
    case friends

    var serverPermission: String {
        switch self {
        case .email: "READ_EMAIL"
        case .twitter: "READ_TWITTER"
        case .lukso: "READ_LUKSO"
        case .farcaster: "READ_FARCASTER"
        case .friends: "READ_FRIENDS"
        }
    }

    var permissionTitle: String {
        switch self {
        case .email: "email address"
        case .twitter: "Twitter account"
        case .lukso: "LUKSO account"
        case .farcaster: "Farcaster account"
        case .friends: "friends list"
        }
    }
}

@MainActor
private enum PluginPermissionPrompt {
    static func confirm(permission: String, pluginName: String) async -> Bool {
        await alert(
            title: "Allow \(pluginName)?",
            message: "This app wants access to your \(permission). You can revoke access in Community Settings.",
            approve: "Allow"
        )
    }

    static func confirmExternal(url: URL, pluginName: String) async -> Bool {
        await alert(
            title: "Leave Common Ground?",
            message: "\(pluginName) wants to open \(url.host ?? url.absoluteString).",
            approve: "Open"
        )
    }

    private static func alert(title: String, message: String, approve: String) async -> Bool {
        await withCheckedContinuation { continuation in
            guard let presenter = topViewController() else {
                continuation.resume(returning: false)
                return
            }
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
                continuation.resume(returning: false)
            })
            alert.addAction(UIAlertAction(title: approve, style: .default) { _ in
                continuation.resume(returning: true)
            })
            presenter.present(alert, animated: true)
        }
    }

    private static func topViewController() -> UIViewController? {
        let root = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .rootViewController
        var current = root
        while let presented = current?.presentedViewController { current = presented }
        if let navigation = current as? UINavigationController { return navigation.visibleViewController }
        return current
    }
}

private protocol OptionalProtocol { var isNil: Bool { get } }
extension Optional: OptionalProtocol { fileprivate var isNil: Bool { self == nil } }

private enum PluginBridgeError: LocalizedError {
    case invalidSignature
    var errorDescription: String? { "INVALID_SIGNATURE" }
}

private func normalizedPluginURL(_ raw: String) -> URL? {
    let normalized = raw.contains("://") ? raw : "https://\(raw)"
    guard let url = URL(string: normalized),
          ["https", "http"].contains(url.scheme?.lowercased()),
          url.host != nil else { return nil }
    return url
}
