import CryptoKit
import Foundation
import Security

public struct DevicePublicJWK: Codable, Equatable, Sendable {
    public let crv = "P-256"
    public let ext = true
    public let keyOps = ["verify"]
    public let kty = "EC"
    public let x: String
    public let y: String

    enum CodingKeys: String, CodingKey {
        case crv, ext, kty, x, y
        case keyOps = "key_ops"
    }

    public init(x: String, y: String) {
        self.x = x
        self.y = y
    }
}

public protocol DeviceSigningKey: Sendable {
    var publicJWK: DevicePublicJWK { get }
    func signSecret(_ secret: String) async throws -> String
}

public final class SecureEnclaveDeviceKey: DeviceSigningKey, @unchecked Sendable {
    private let privateKey: SecKey
    public let publicJWK: DevicePublicJWK

    private init(privateKey: SecKey) throws {
        self.privateKey = privateKey
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw DeviceKeyError.publicKeyUnavailable
        }
        var error: Unmanaged<CFError>?
        guard let representation = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            if let error { throw error.takeRetainedValue() }
            throw DeviceKeyError.publicKeyUnavailable
        }
        self.publicJWK = try Self.makeJWK(fromX963: representation)
    }

    public static func loadOrCreate(tag: Data) throws -> SecureEnclaveDeviceKey {
        if let existing = try load(tag: tag) {
            return try SecureEnclaveDeviceKey(privateKey: existing)
        }

        var accessError: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .privateKeyUsage,
            &accessError
        ) else {
            throw accessError!.takeRetainedValue()
        }

        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits: 256,
            kSecAttrTokenID: kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs: [
                kSecAttrIsPermanent: true,
                kSecAttrApplicationTag: tag,
                kSecAttrAccessControl: access
            ]
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw error!.takeRetainedValue()
        }
        return try SecureEnclaveDeviceKey(privateKey: key)
    }

    public func signSecret(_ secret: String) async throws -> String {
        let message = Data(secret.utf8)
        var error: Unmanaged<CFError>?
        guard let derSignature = SecKeyCreateSignature(
            privateKey,
            .ecdsaSignatureMessageX962SHA256,
            message as CFData,
            &error
        ) as Data? else {
            throw error!.takeRetainedValue()
        }
        let rawSignature = try Self.p1363Signature(fromDER: derSignature, coordinateSize: 32)
        return rawSignature.base64EncodedString()
    }

    private static func load(tag: Data) throws -> SecKey? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassKey,
            kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrApplicationTag: tag,
            kSecReturnRef: true
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let key = result else {
            throw DeviceKeyError.keychain(status)
        }
        return (key as! SecKey)
    }

    private static func makeJWK(fromX963 data: Data) throws -> DevicePublicJWK {
        guard data.count == 65, data.first == 0x04 else {
            throw DeviceKeyError.invalidPublicKey
        }
        let x = data[data.index(after: data.startIndex)..<data.index(data.startIndex, offsetBy: 33)]
        let y = data[data.index(data.startIndex, offsetBy: 33)..<data.endIndex]
        return DevicePublicJWK(x: Data(x).base64URLString, y: Data(y).base64URLString)
    }

    /// Security.framework returns an ASN.1 DER ECDSA signature. Common Ground
    /// validates WebCrypto's fixed-width IEEE-P1363 representation (r || s).
    static func p1363Signature(fromDER der: Data, coordinateSize: Int) throws -> Data {
        var cursor = 0
        guard readByte(der, &cursor) == 0x30 else { throw DeviceKeyError.invalidSignature }
        _ = try readLength(der, &cursor)
        guard readByte(der, &cursor) == 0x02 else { throw DeviceKeyError.invalidSignature }
        let rLength = try readLength(der, &cursor)
        guard cursor + rLength <= der.count else { throw DeviceKeyError.invalidSignature }
        let r = der[cursor..<(cursor + rLength)]
        cursor += rLength
        guard readByte(der, &cursor) == 0x02 else { throw DeviceKeyError.invalidSignature }
        let sLength = try readLength(der, &cursor)
        guard cursor + sLength <= der.count else { throw DeviceKeyError.invalidSignature }
        let s = der[cursor..<(cursor + sLength)]
        return try fixedWidthInteger(r, size: coordinateSize) + fixedWidthInteger(s, size: coordinateSize)
    }

    private static func readByte(_ data: Data, _ cursor: inout Int) -> UInt8? {
        guard cursor < data.count else { return nil }
        defer { cursor += 1 }
        return data[cursor]
    }

    private static func readLength(_ data: Data, _ cursor: inout Int) throws -> Int {
        guard let first = readByte(data, &cursor) else { throw DeviceKeyError.invalidSignature }
        if first & 0x80 == 0 { return Int(first) }
        let byteCount = Int(first & 0x7f)
        guard byteCount > 0, byteCount <= 4 else { throw DeviceKeyError.invalidSignature }
        var result = 0
        for _ in 0..<byteCount {
            guard let byte = readByte(data, &cursor) else { throw DeviceKeyError.invalidSignature }
            result = (result << 8) | Int(byte)
        }
        return result
    }

    private static func fixedWidthInteger(_ bytes: Data.SubSequence, size: Int) throws -> Data {
        var value = Data(bytes)
        while value.count > size, value.first == 0 { value.removeFirst() }
        guard value.count <= size else { throw DeviceKeyError.invalidSignature }
        return Data(repeating: 0, count: size - value.count) + value
    }
}

/// A P-256 software key used by unit tests and simulators without a Secure
/// Enclave. Production devices always attempt the Secure Enclave first.
public final class SoftwareDeviceKey: DeviceSigningKey, @unchecked Sendable {
    private let key: P256.Signing.PrivateKey
    public let publicJWK: DevicePublicJWK

    public convenience init() throws {
        try self.init(rawRepresentation: P256.Signing.PrivateKey().rawRepresentation)
    }

    init(rawRepresentation: Data) throws {
        key = try P256.Signing.PrivateKey(rawRepresentation: rawRepresentation)
        let publicBytes = key.publicKey.x963Representation
        guard publicBytes.count == 65 else { throw DeviceKeyError.invalidPublicKey }
        publicJWK = DevicePublicJWK(
            x: Data(publicBytes[1..<33]).base64URLString,
            y: Data(publicBytes[33..<65]).base64URLString
        )
    }

    var rawRepresentation: Data { key.rawRepresentation }

    public func signSecret(_ secret: String) async throws -> String {
        let signature = try key.signature(for: Data(secret.utf8))
        return signature.rawRepresentation.base64EncodedString()
    }
}

public enum DeviceKeyStore {
    public static func loadOrCreate(for instance: InstanceURL) throws -> any DeviceSigningKey {
        let digest = SHA256.hash(data: Data(instance.description.utf8))
        let suffix = Data(digest).map { String(format: "%02x", $0) }.joined()
        let tag = Data("org.commonground.ios.device.\(suffix)".utf8)
        do {
            return try SecureEnclaveDeviceKey.loadOrCreate(tag: tag)
        } catch {
            #if targetEnvironment(simulator)
            return try loadOrCreateSoftwareKey(tag: tag)
            #else
            throw error
            #endif
        }
    }

    public static func delete(for instance: InstanceURL) throws {
        let digest = SHA256.hash(data: Data(instance.description.utf8))
        let suffix = Data(digest).map { String(format: "%02x", $0) }.joined()
        let tag = Data("org.commonground.ios.device.\(suffix)".utf8)
        let keyQuery: [CFString: Any] = [kSecClass: kSecClassKey, kSecAttrApplicationTag: tag]
        let genericQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: tag.base64EncodedString(),
            kSecAttrService: "org.commonground.ios.software-device-key"
        ]
        for query in [keyQuery, genericQuery] {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw DeviceKeyError.keychain(status)
            }
        }
    }

    private static func loadOrCreateSoftwareKey(tag: Data) throws -> SoftwareDeviceKey {
        let account = tag.base64EncodedString()
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: account,
            kSecAttrService: "org.commonground.ios.software-device-key",
            kSecReturnData: true
        ]
        var value: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &value)
        if status == errSecSuccess, let data = value as? Data {
            return try SoftwareDeviceKey(rawRepresentation: data)
        }
        guard status == errSecItemNotFound else { throw DeviceKeyError.keychain(status) }
        let key = try SoftwareDeviceKey()
        let add: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: account,
            kSecAttrService: "org.commonground.ios.software-device-key",
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData: key.rawRepresentation
        ]
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw DeviceKeyError.keychain(addStatus) }
        return key
    }
}

public enum DeviceKeyError: Error, LocalizedError {
    case publicKeyUnavailable
    case invalidPublicKey
    case invalidSignature
    case keychain(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .publicKeyUnavailable: return "The device public key is unavailable."
        case .invalidPublicKey: return "The device returned an invalid P-256 public key."
        case .invalidSignature: return "The device returned an invalid ECDSA signature."
        case .keychain(let status): return "Keychain operation failed (\(status))."
        }
    }
}

private extension Data {
    var base64URLString: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
