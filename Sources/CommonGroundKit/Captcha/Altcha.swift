import CryptoKit
import Foundation

public struct CaptchaConfig: Codable, Equatable, Sendable {
    public let provider: CaptchaProvider
}

public struct AltchaChallenge: Codable, Equatable, Sendable {
    public let parameters: AltchaChallengeParameters
    public let signature: String
}

/// ALTCHA signs the complete parameters object. `fields` deliberately keeps
/// unknown additive fields so encoding the registration token cannot alter
/// the signed challenge.
public struct AltchaChallengeParameters: Codable, Equatable, Sendable {
    public let fields: [String: JSONValue]

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        var result: [String: JSONValue] = [:]
        for key in container.allKeys {
            result[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
        }
        fields = result
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKey.self)
        for (name, value) in fields {
            try container.encode(value, forKey: DynamicCodingKey(name))
        }
    }

    public var algorithm: String? { fields["algorithm"]?.stringValue }
    public var nonce: String? { fields["nonce"]?.stringValue }
    public var salt: String? { fields["salt"]?.stringValue }
    public var keyPrefix: String? { fields["keyPrefix"]?.stringValue }
    public var cost: Int? { fields["cost"]?.numberValue.map(Int.init) }
    public var keyLength: Int? { fields["keyLength"]?.numberValue.map(Int.init) }
    public var expiresAt: Double? { fields["expiresAt"]?.numberValue }
}

public struct AltchaSolution: Codable, Equatable, Sendable {
    public let counter: Int
    public let derivedKey: String
    public let time: Double
}

public struct CaptchaService: Sendable {
    private let transport: HTTPTransport

    public init(transport: HTTPTransport) {
        self.transport = transport
    }

    public func config() async throws -> CaptchaConfig {
        try await transport.getJSON("Captcha/config")
    }

    public func challenge() async throws -> AltchaChallenge {
        let challenge: AltchaChallenge = try await transport.getJSON("Captcha/challenge")
        guard challenge.parameters.keyPrefix != nil, !challenge.signature.isEmpty else {
            throw CaptchaError.invalidChallenge
        }
        return challenge
    }

    public func registrationToken(timeout: TimeInterval = 90) async throws -> String {
        switch try await config().provider {
        case .off:
            return "stub"
        case .recaptcha:
            throw CaptchaError.recaptchaRequiresInteractiveFallback
        case .altcha:
            let value = try await challenge()
            guard let solution = try await AltchaSolver.solve(value, timeout: timeout) else {
                throw CaptchaError.timedOut
            }
            return try Self.buildToken(challenge: value, solution: solution)
        }
    }

    public static func buildToken(
        challenge: AltchaChallenge,
        solution: AltchaSolution
    ) throws -> String {
        let payload = Payload(challenge: challenge, solution: solution)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return try encoder.encode(payload).base64EncodedString()
    }

    private struct Payload: Encodable {
        let challenge: AltchaChallenge
        let solution: AltchaSolution
    }
}

public enum AltchaSolver {
    public static func solve(
        _ challenge: AltchaChallenge,
        timeout: TimeInterval = 90
    ) async throws -> AltchaSolution? {
        try await Task.detached(priority: .userInitiated) {
            try solveSynchronously(challenge, timeout: timeout)
        }.value
    }

    private static func solveSynchronously(
        _ challenge: AltchaChallenge,
        timeout: TimeInterval
    ) throws -> AltchaSolution? {
        let parameters = challenge.parameters
        guard parameters.algorithm == "PBKDF2/SHA-256" else {
            throw CaptchaError.unsupportedAlgorithm(parameters.algorithm ?? "missing")
        }
        guard let nonce = parameters.nonce.flatMap(Data.init(hex:)),
              let salt = parameters.salt.flatMap(Data.init(hex:)),
              let prefix = parameters.keyPrefix.flatMap(Data.init(hex:)),
              let cost = parameters.cost, cost > 0,
              let keyLength = parameters.keyLength, keyLength > 0 else {
            throw CaptchaError.invalidChallenge
        }

        let startedAt = Date()
        var counter = 0
        while counter <= Int(UInt32.max) {
            if counter.isMultiple(of: 10) {
                if Task.isCancelled { throw CancellationError() }
                if Date().timeIntervalSince(startedAt) > timeout { return nil }
            }
            var bigEndianCounter = UInt32(counter).bigEndian
            var password = nonce
            withUnsafeBytes(of: &bigEndianCounter) { password.append(contentsOf: $0) }
            let derived = pbkdf2SHA256(
                password: password,
                salt: salt,
                iterations: cost,
                keyLength: keyLength
            )
            if derived.starts(with: prefix) {
                let milliseconds = Date().timeIntervalSince(startedAt) * 1_000
                return AltchaSolution(
                    counter: counter,
                    derivedKey: derived.hexString,
                    time: (milliseconds * 10).rounded(.down) / 10
                )
            }
            counter += 1
        }
        return nil
    }

    static func pbkdf2SHA256(
        password: Data,
        salt: Data,
        iterations: Int,
        keyLength: Int
    ) -> Data {
        precondition(iterations > 0 && keyLength > 0)
        let key = SymmetricKey(data: password)
        let hashLength = 32
        let blockCount = (keyLength + hashLength - 1) / hashLength
        var output = Data()
        output.reserveCapacity(blockCount * hashLength)

        for block in 1...blockCount {
            var index = UInt32(block).bigEndian
            var firstInput = salt
            withUnsafeBytes(of: &index) { firstInput.append(contentsOf: $0) }
            var previous = Data(HMAC<SHA256>.authenticationCode(for: firstInput, using: key))
            var accumulator = [UInt8](previous)

            if iterations > 1 {
                for _ in 2...iterations {
                    previous = Data(HMAC<SHA256>.authenticationCode(for: previous, using: key))
                    for offset in accumulator.indices {
                        accumulator[offset] ^= previous[offset]
                    }
                }
            }
            output.append(contentsOf: accumulator)
        }
        return output.prefix(keyLength)
    }
}

public enum CaptchaError: Error, LocalizedError, Equatable {
    case invalidChallenge
    case unsupportedAlgorithm(String)
    case timedOut
    case recaptchaRequiresInteractiveFallback

    public var errorDescription: String? {
        switch self {
        case .invalidChallenge: return "The instance returned an invalid ALTCHA challenge."
        case .unsupportedAlgorithm(let algorithm): return "Unsupported ALTCHA algorithm: \(algorithm)."
        case .timedOut: return "The ALTCHA proof of work timed out. Please try again."
        case .recaptchaRequiresInteractiveFallback:
            return "This instance requires reCAPTCHA. Native registration is not available yet; use its web sign-up flow."
        }
    }
}

private struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.init(stringValue) }
    init?(intValue: Int) { return nil }
}

private extension Data {
    init?(hex: String) {
        guard hex.count.isMultiple(of: 2) else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }

    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}
