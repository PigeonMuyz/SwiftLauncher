import Foundation

enum MicrosoftOAuthConfiguration {
    static let clientID = "dfe82d7b-3ea8-46d5-94cd-8fb402a8f6b1"
}

struct MicrosoftSession: Sendable {
    let account: PlayerAccount
    let refreshToken: String
    let minecraftAccessToken: String
}

actor MicrosoftAuthenticationService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func begin(clientID: String) async throws -> MicrosoftDeviceCode {
        guard !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LauncherError.microsoftClientIDMissing
        }
        let response: DeviceCodeResponse = try await postForm(
            url: URL(string: "https://login.microsoftonline.com/consumers/oauth2/v2.0/devicecode")!,
            values: [
                "client_id": clientID,
                "scope": "XboxLive.signin offline_access"
            ]
        )
        guard let verificationURI = URL(string: response.verificationURI) else {
            throw LauncherError.invalidResponse
        }
        return MicrosoftDeviceCode(
            deviceCode: response.deviceCode,
            userCode: response.userCode,
            verificationURI: verificationURI,
            expiresIn: response.expiresIn,
            interval: response.interval,
            message: response.message
        )
    }

    func complete(
        clientID: String,
        deviceCode: MicrosoftDeviceCode,
        progress: @escaping @Sendable (String) async -> Void = { _ in }
    ) async throws -> MicrosoftSession {
        let deadline = Date().addingTimeInterval(TimeInterval(deviceCode.expiresIn))
        var interval = max(deviceCode.interval, 2)
        var microsoftToken: MicrosoftTokenResponse?

        while Date() < deadline {
            try await Task.sleep(for: .seconds(interval))
            do {
                microsoftToken = try await postForm(
                    url: URL(string: "https://login.microsoftonline.com/consumers/oauth2/v2.0/token")!,
                    values: [
                        "client_id": clientID,
                        "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
                        "device_code": deviceCode.deviceCode
                    ]
                )
                break
            } catch AuthenticationPending.pending {
                continue
            } catch AuthenticationPending.slowDown {
                interval += 5
            }
        }

        guard let microsoftToken, let refreshToken = microsoftToken.refreshToken else {
            throw LauncherError.authentication("设备授权已超时")
        }
        await progress("Microsoft 授权成功，正在登录 Xbox Live…")
        return try await exchange(
            microsoftAccessToken: microsoftToken.accessToken,
            refreshToken: refreshToken,
            progress: progress
        )
    }

    func refresh(clientID: String, refreshToken: String) async throws -> MicrosoftSession {
        let token: MicrosoftTokenResponse = try await postForm(
            url: URL(string: "https://login.microsoftonline.com/consumers/oauth2/v2.0/token")!,
            values: [
                "client_id": clientID,
                "grant_type": "refresh_token",
                "refresh_token": refreshToken,
                "scope": "XboxLive.signin offline_access"
            ]
        )
        return try await exchange(
            microsoftAccessToken: token.accessToken,
            refreshToken: token.refreshToken ?? refreshToken,
            progress: { _ in }
        )
    }

    private func exchange(
        microsoftAccessToken: String,
        refreshToken: String,
        progress: @escaping @Sendable (String) async -> Void
    ) async throws -> MicrosoftSession {
        let xboxRequest = XboxAuthenticationRequest(
            properties: .init(
                authMethod: "RPS",
                siteName: "user.auth.xboxlive.com",
                rpsTicket: "d=\(microsoftAccessToken)"
            ),
            relyingParty: "http://auth.xboxlive.com",
            tokenType: "JWT"
        )
        let xbox: XboxTokenResponse = try await postJSON(
            url: URL(string: "https://user.auth.xboxlive.com/user/authenticate")!,
            value: xboxRequest,
            endpoint: "Xbox Live 登录",
            headers: ["x-xbl-contract-version": "1"]
        )
        guard let userHash = xbox.displayClaims.xui.first?.uhs else {
            throw LauncherError.authentication("Xbox 响应缺少用户标识")
        }

        let xstsRequest = XSTSAuthenticationRequest(
            properties: .init(sandboxID: "RETAIL", userTokens: [xbox.token]),
            relyingParty: "rp://api.minecraftservices.com/",
            tokenType: "JWT"
        )
        await progress("Xbox Live 登录成功，正在申请 XSTS 凭证…")
        let xsts: XboxTokenResponse = try await postJSON(
            url: URL(string: "https://xsts.auth.xboxlive.com/xsts/authorize")!,
            value: xstsRequest,
            endpoint: "Xbox XSTS 授权",
            headers: ["x-xbl-contract-version": "1"]
        )

        await progress("Xbox 授权成功，正在登录 Minecraft…")
        let minecraftLogin: MinecraftLoginResponse = try await postJSON(
            url: URL(string: "https://api.minecraftservices.com/authentication/login_with_xbox")!,
            value: MinecraftLoginRequest(identityToken: "XBL3.0 x=\(userHash);\(xsts.token)"),
            endpoint: "Minecraft 登录"
        )

        await progress("Minecraft 登录成功，正在检查 Java 版所有权…")
        let entitlement: EntitlementsResponse = try await getAuthorized(
            URL(string: "https://api.minecraftservices.com/entitlements/mcstore")!,
            token: minecraftLogin.accessToken,
            endpoint: "Minecraft 所有权检查"
        )
        guard !entitlement.items.isEmpty else {
            throw LauncherError.authentication("该账户未检测到 Minecraft Java 版所有权")
        }

        let profile: MinecraftProfile = try await getAuthorized(
            URL(string: "https://api.minecraftservices.com/minecraft/profile")!,
            token: minecraftLogin.accessToken,
            endpoint: "Minecraft 玩家资料"
        )
        return MicrosoftSession(
            account: PlayerAccount(
                username: profile.name,
                profileID: profile.id,
                kind: .microsoft,
                tokenExpiresAt: Date().addingTimeInterval(TimeInterval(minecraftLogin.expiresIn))
            ),
            refreshToken: refreshToken,
            minecraftAccessToken: minecraftLogin.accessToken
        )
    }

    private func postForm<T: Decodable>(url: URL, values: [String: String]) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = values
            .map { key, value in
                "\(key.formEncoded)=\(value.formEncoded)"
            }
            .sorted()
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400,
           let oauthError = try? JSONCoding.makeDecoder().decode(OAuthError.self, from: data) {
            switch oauthError.error {
            case "authorization_pending": throw AuthenticationPending.pending
            case "slow_down": throw AuthenticationPending.slowDown
            default: throw LauncherError.authentication(oauthError.errorDescription ?? oauthError.error)
            }
        }
        try validateAuthenticationResponse(data, response: response, endpoint: "Microsoft OAuth")
        return try JSONCoding.makeDecoder().decode(T.self, from: data)
    }

    private func postJSON<Input: Encodable, Output: Decodable>(
        url: URL,
        value: Input,
        endpoint: String,
        headers: [String: String] = [:]
    ) async throws -> Output {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("SwiftLauncher/1.0", forHTTPHeaderField: "User-Agent")
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.httpBody = try JSONCoding.makeEncoder().encode(value)
        let (data, response) = try await session.data(for: request)
        try validateAuthenticationResponse(data, response: response, endpoint: endpoint)
        return try JSONCoding.makeDecoder().decode(Output.self, from: data)
    }

    private func getAuthorized<T: Decodable>(
        _ url: URL,
        token: String,
        endpoint: String
    ) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("SwiftLauncher/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        try validateAuthenticationResponse(data, response: response, endpoint: endpoint)
        return try JSONCoding.makeDecoder().decode(T.self, from: data)
    }

    private func validateAuthenticationResponse(
        _ data: Data,
        response: URLResponse,
        endpoint: String
    ) throws {
        guard let http = response as? HTTPURLResponse else {
            throw LauncherError.invalidResponse
        }
        guard !(200..<300).contains(http.statusCode) else { return }

        if let xbox = try? JSONCoding.makeDecoder().decode(XboxErrorResponse.self, from: data),
           let code = xbox.xErr {
            let reason = Self.xboxErrorDescription(code)
            throw LauncherError.authentication("\(endpoint)失败：\(reason)（XErr \(code)，HTTP \(http.statusCode)）")
        }

        if let service = try? JSONCoding.makeDecoder().decode(AuthenticationServiceError.self, from: data),
           let message = service.bestMessage {
            if message.localizedCaseInsensitiveContains("invalid app registration") {
                throw LauncherError.minecraftAppRegistrationRequired
            }
            throw LauncherError.authentication("\(endpoint)失败（HTTP \(http.statusCode)）：\(message)")
        }

        let body = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = body.flatMap { $0.isEmpty ? nil : String($0.prefix(240)) }

        if http.statusCode == 403, suffix == nil {
            let hint: String
            if endpoint.contains("Xbox") {
                hint = "请先使用同一账户登录 xbox.com 创建 Xbox 玩家档案，并检查家庭/年龄限制"
            } else if endpoint.contains("Minecraft") {
                hint = "Minecraft 服务拒绝了当前凭证，请确认该账户拥有 Java 版且玩家档案已创建"
            } else {
                hint = "服务拒绝了当前账户或应用授权"
            }
            throw LauncherError.authentication("\(endpoint)失败（HTTP 403）：\(hint)")
        }

        throw LauncherError.authentication(
            suffix.map { "\(endpoint)返回 HTTP \(http.statusCode)：\($0)" }
                ?? "\(endpoint)返回 HTTP \(http.statusCode)"
        )
    }

    nonisolated private static func xboxErrorDescription(_ code: Int64) -> String {
        switch code {
        case 2_148_916_233:
            "该 Microsoft 账户还没有 Xbox 档案，请先登录 xbox.com 创建档案"
        case 2_148_916_235:
            "Xbox Live 在该账户所在地区不可用"
        case 2_148_916_236, 2_148_916_237:
            "该账户需要先完成地区要求的年龄验证"
        case 2_148_916_238:
            "这是受家庭管理的未成年账户，需要成人账户完成授权"
        default:
            "Xbox 服务拒绝了此账户"
        }
    }
}

private enum AuthenticationPending: Error {
    case pending
    case slowDown
}

private struct DeviceCodeResponse: Decodable {
    let deviceCode: String
    let userCode: String
    let verificationURI: String
    let expiresIn: Int
    let interval: Int
    let message: String

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationURI = "verification_uri"
        case expiresIn = "expires_in"
        case interval
        case message
    }
}

private struct MicrosoftTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
    }
}

private struct OAuthError: Decodable {
    let error: String
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}

private struct XboxAuthenticationRequest: Encodable {
    let properties: Properties
    let relyingParty: String
    let tokenType: String

    struct Properties: Encodable {
        let authMethod: String
        let siteName: String
        let rpsTicket: String

        enum CodingKeys: String, CodingKey {
            case authMethod = "AuthMethod"
            case siteName = "SiteName"
            case rpsTicket = "RpsTicket"
        }
    }

    enum CodingKeys: String, CodingKey {
        case properties = "Properties"
        case relyingParty = "RelyingParty"
        case tokenType = "TokenType"
    }
}

private struct XSTSAuthenticationRequest: Encodable {
    let properties: Properties
    let relyingParty: String
    let tokenType: String

    struct Properties: Encodable {
        let sandboxID: String
        let userTokens: [String]

        enum CodingKeys: String, CodingKey {
            case sandboxID = "SandboxId"
            case userTokens = "UserTokens"
        }
    }

    enum CodingKeys: String, CodingKey {
        case properties = "Properties"
        case relyingParty = "RelyingParty"
        case tokenType = "TokenType"
    }
}

private struct XboxTokenResponse: Decodable {
    let token: String
    let displayClaims: DisplayClaims

    struct DisplayClaims: Decodable {
        let xui: [Claim]
    }

    struct Claim: Decodable {
        let uhs: String
    }

    enum CodingKeys: String, CodingKey {
        case token = "Token"
        case displayClaims = "DisplayClaims"
    }
}

private struct XboxErrorResponse: Decodable {
    let xErr: Int64?

    enum CodingKeys: String, CodingKey {
        case xErr = "XErr"
    }
}

private struct AuthenticationServiceError: Decodable {
    let message: String?
    let error: String?
    let errorMessage: String?
    let developerMessage: String?

    var bestMessage: String? {
        errorMessage ?? message ?? developerMessage ?? error
    }
}

private struct MinecraftLoginRequest: Encodable {
    let identityToken: String
}

private struct MinecraftLoginResponse: Decodable {
    let accessToken: String
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
    }
}

private struct EntitlementsResponse: Decodable {
    let items: [Entitlement]

    struct Entitlement: Decodable {
        let name: String
    }
}

private struct MinecraftProfile: Decodable {
    let id: String
    let name: String
}

private extension String {
    var formEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? self
    }
}
