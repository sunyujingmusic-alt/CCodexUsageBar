import Foundation

struct AuthManager {
    private let preferences: PreferencesStore
    private let tokenStore: KeychainTokenStore
    private let api: CCodexAPI

    init(preferences: PreferencesStore, tokenStore: KeychainTokenStore, api: CCodexAPI) {
        self.preferences = preferences
        self.tokenStore = tokenStore
        self.api = api
    }

    func storedEmail() -> String {
        tokenStore.loadEmail() ?? ""
    }

    func shouldRememberPassword() -> Bool {
        preferences.rememberPassword
    }

    func hasAutomaticCredentials() -> Bool {
        if let access = tokenStore.loadAccessToken(), !access.isEmpty { return true }
        if let refresh = tokenStore.loadRefreshToken(), !refresh.isEmpty { return true }
        if preferences.rememberPassword,
           let email = tokenStore.loadEmail(), !email.isEmpty,
           let password = tokenStore.loadPassword(), !password.isEmpty {
            return true
        }
        return false
    }

    func login(email: String, password: String, rememberPassword: Bool) async throws {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = try await api.login(baseURL: preferences.baseURL, email: normalizedEmail, password: password)

        if result.requiresTwoFactor == true {
            throw AuthManagerError.requiresTwoFactor(result.userEmailMasked)
        }

        guard let accessToken = result.accessToken,
              let refreshToken = result.refreshToken,
              let expiresIn = result.expiresIn else {
            throw AuthManagerError.invalidLoginResponse
        }

        try persistSession(accessToken: accessToken, refreshToken: refreshToken, expiresIn: expiresIn)
        try tokenStore.saveEmail(normalizedEmail)
        preferences.rememberPassword = rememberPassword

        if rememberPassword {
            try tokenStore.savePassword(password)
        } else {
            try tokenStore.clearPassword()
        }
    }

    func ensureValidAccessToken() async throws -> String {
        if let token = tokenStore.loadAccessToken(), isAccessTokenFresh(), !token.isEmpty {
            return token
        }

        if let refreshToken = tokenStore.loadRefreshToken(), !refreshToken.isEmpty {
            do {
                return try await refreshUsingRefreshToken(refreshToken)
            } catch {
                try? tokenStore.clearAccessToken()
                try? tokenStore.clearRefreshToken()
                preferences.tokenExpiresAt = nil
            }
        }

        if preferences.rememberPassword,
           let email = tokenStore.loadEmail(), !email.isEmpty,
           let password = tokenStore.loadPassword(), !password.isEmpty {
            try await login(email: email, password: password, rememberPassword: true)
            if let token = tokenStore.loadAccessToken(), !token.isEmpty {
                return token
            }
        }

        throw AuthManagerError.notLoggedIn
    }

    func logout(clearSavedPassword: Bool) throws {
        try tokenStore.clearSession()
        preferences.tokenExpiresAt = nil

        if clearSavedPassword {
            try tokenStore.clearPassword()
            preferences.rememberPassword = false
        }
    }

    private func refreshUsingRefreshToken(_ refreshToken: String) async throws -> String {
        let refreshed = try await api.refresh(baseURL: preferences.baseURL, refreshToken: refreshToken)
        try persistSession(
            accessToken: refreshed.accessToken,
            refreshToken: refreshed.refreshToken,
            expiresIn: refreshed.expiresIn
        )
        return refreshed.accessToken
    }

    private func persistSession(accessToken: String, refreshToken: String, expiresIn: Int) throws {
        try tokenStore.saveAccessToken(accessToken)
        try tokenStore.saveRefreshToken(refreshToken)
        preferences.tokenExpiresAt = Date().addingTimeInterval(TimeInterval(expiresIn)).timeIntervalSince1970
    }

    private func isAccessTokenFresh() -> Bool {
        guard let expiresAt = preferences.tokenExpiresAt else { return false }
        return expiresAt - Date().timeIntervalSince1970 > 60
    }
}

enum AuthManagerError: LocalizedError {
    case notLoggedIn
    case requiresTwoFactor(String?)
    case invalidLoginResponse

    var errorDescription: String? {
        switch self {
        case .notLoggedIn:
            return "请先登录 CCodex 账号"
        case .requiresTwoFactor(let maskedEmail):
            if let maskedEmail, !maskedEmail.isEmpty {
                return "此账号启用了二次验证，需要补充验证码：\(maskedEmail)"
            }
            return "此账号启用了二次验证，当前版本还未完成 TOTP 登录流程"
        case .invalidLoginResponse:
            return "登录成功，但返回的数据不完整"
        }
    }
}
