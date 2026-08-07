import Foundation
import Security

/// Persists one instance's URLSession cookies without using the process-wide
/// cookie jar. Failures are intentionally best-effort: authentication still
/// works for the current process even when Keychain persistence is unavailable.
struct PersistentCookieStore: Sendable {
    private static let service = "org.commonground.ios.session-cookies"
    private let account: String

    init(baseURL: URL) {
        account = baseURL.absoluteString
    }

    func load() -> [HTTPCookie] {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Self.service,
            kSecAttrAccount: account,
            kSecReturnData: true
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let stored = try? JSONDecoder().decode([StoredCookie].self, from: data) else {
            return []
        }
        let now = Date()
        return stored.compactMap { item in
            guard item.expiresAt.map({ $0 > now }) ?? true else { return nil }
            return item.cookie
        }
    }

    func save(_ cookies: [HTTPCookie]) {
        let now = Date()
        let stored = cookies
            .filter { $0.expiresDate.map { $0 > now } ?? true }
            .map(StoredCookie.init)
        guard let data = try? JSONEncoder().encode(stored) else { return }

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Self.service,
            kSecAttrAccount: account
        ]
        if stored.isEmpty {
            SecItemDelete(query as CFDictionary)
            return
        }

        let status = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData: data] as CFDictionary
        )
        guard status == errSecItemNotFound else { return }
        var attributes = query
        attributes[kSecValueData] = data
        attributes[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
    }

    func clear() {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Self.service,
            kSecAttrAccount: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

private struct StoredCookie: Codable {
    let name: String
    let value: String
    let domain: String
    let path: String
    let expiresAt: Date?
    let isSecure: Bool

    init(_ cookie: HTTPCookie) {
        name = cookie.name
        value = cookie.value
        domain = cookie.domain
        path = cookie.path
        expiresAt = cookie.expiresDate
        isSecure = cookie.isSecure
    }

    var cookie: HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: value,
            .domain: domain,
            .path: path
        ]
        if let expiresAt { properties[.expires] = expiresAt }
        if isSecure { properties[.secure] = "TRUE" }
        return HTTPCookie(properties: properties)
    }
}
