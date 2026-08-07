import Foundation

public struct AuthAPI: Sendable {
    private let transport: HTTPTransport
    private let captcha: CaptchaService

    public init(transport: HTTPTransport) {
        self.transport = transport
        self.captcha = CaptchaService(transport: transport)
    }

    public func register(
        email: String,
        password: String,
        displayName: String,
        deviceKey: any DeviceSigningKey,
        captchaToken: String? = nil
    ) async throws -> AuthSession {
        let token: String
        if let captchaToken {
            token = captchaToken
        } else {
            token = try await captcha.registrationToken()
        }
        let request = CreateUserRequest(
            recaptchaToken: token,
            device: DeviceDescriptor(publicKey: deviceKey.publicJWK),
            useEmailAndPassword: .init(email: email, password: password),
            useCgProfile: .init(displayName: displayName)
        )
        let response: LoginResponse = try await transport.call("User/createUser", body: request)
        return AuthSession(response: response, deviceId: response.deviceId, deviceKey: deviceKey)
    }

    public func loginWithPassword(
        aliasOrEmail: String,
        password: String,
        deviceKey: any DeviceSigningKey
    ) async throws -> AuthSession {
        let request = PasswordLoginRequest(
            aliasOrEmail: aliasOrEmail,
            password: password,
            device: DeviceDescriptor(publicKey: deviceKey.publicJWK)
        )
        let response: LoginResponse = try await transport.call("User/login", body: request)
        return AuthSession(response: response, deviceId: response.deviceId, deviceKey: deviceKey)
    }

    public func getSignableSecret() async throws -> String {
        try await transport.call("User/getSignableSecret")
    }

    public func loginWithDevice(
        deviceId: String,
        deviceKey: any DeviceSigningKey
    ) async throws -> AuthSession {
        let secret = try await getSignableSecret()
        let signature = try await deviceKey.signSecret(secret)
        let request = DeviceLoginRequest(
            deviceId: deviceId,
            secret: secret,
            base64Signature: signature
        )
        let response: LoginResponse = try await transport.call("User/login", body: request)
        return AuthSession(response: response, deviceId: response.deviceId, deviceKey: deviceKey)
    }

    public func checkLoginStatus() async throws -> LoginStatus {
        try await transport.call("User/checkLoginStatus")
    }

    /// Logout soft-deletes the server device. Callers must also discard the
    /// matching local key and device id; `AppModel.logout()` does this in the app.
    public func logout() async throws {
        let _: EmptyResponse = try await transport.call("User/logout")
    }
}
