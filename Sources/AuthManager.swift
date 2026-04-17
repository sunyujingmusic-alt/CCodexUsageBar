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

    func storedPassword() -> String {
        guard preferences.rememberPassword else { return "" }
        return tokenStore.loadPassword() ?? ""
    }

    func shouldRememberPassword() -> Bool {
        preferences.rememberPassword
    }

    func hasAutomaticCredentials() -> Bool {
        if let userID = preferences.loggedInUserID, !userID.isEmpty {
            return true
        }
        if preferences.rememberPassword,
           let email = tokenStore.loadEmail(), !email.isEmpty,
           let password = tokenStore.loadPassword(), !password.isEmpty {
            return true
        }
        return false
    }

    func beginLogin(email: String, password: String, rememberPassword: Bool) async throws -> AuthLoginStep {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = try await api.beginLogin(baseURL: preferences.baseURL, email: normalizedEmail, password: normalizedPassword)

        switch result {
        case .authenticated(let user):
            try finishLogin(email: normalizedEmail, password: normalizedPassword, rememberPassword: rememberPassword, user: user)
            return .authenticated
        case .requiresTwoFactor(let message):
            return .requiresTwoFactor(message ?? "请输入两步验证码")
        }
    }

    func completeTwoFactorLogin(code: String, email: String, password: String, rememberPassword: Bool) async throws {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedCode.isEmpty else {
            throw AuthManagerError.twoFactorCodeRequired
        }

        let user = try await api.completeTwoFactorLogin(baseURL: preferences.baseURL, code: normalizedCode)
        try finishLogin(email: normalizedEmail, password: normalizedPassword, rememberPassword: rememberPassword, user: user)
    }

    func ensureValidSessionUserID() async throws -> String {
        if let storedUserID = preferences.loggedInUserID, !storedUserID.isEmpty {
            do {
                let user = try await api.fetchCurrentUser(baseURL: preferences.baseURL, userID: storedUserID)
                let resolvedUserID = user.id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? storedUserID
                if resolvedUserID != storedUserID {
                    preferences.loggedInUserID = resolvedUserID
                }
                return resolvedUserID
            } catch let error as CCodexAPIError {
                guard error.isUnauthorized else {
                    throw error
                }
                preferences.loggedInUserID = nil
                api.clearCookies(baseURL: preferences.baseURL)
            }
        }

        if preferences.rememberPassword,
           let email = tokenStore.loadEmail(), !email.isEmpty,
           let password = tokenStore.loadPassword(), !password.isEmpty {
            switch try await beginLogin(email: email, password: password, rememberPassword: true) {
            case .authenticated:
                if let userID = preferences.loggedInUserID, !userID.isEmpty {
                    return userID
                }
                throw AuthManagerError.invalidLoginResponse
            case .requiresTwoFactor:
                throw AuthManagerError.twoFactorManualReloginRequired
            }
        }

        throw AuthManagerError.notLoggedIn
    }

    func logout(clearSavedPassword: Bool) throws {
        preferences.loggedInUserID = nil
        api.clearCookies(baseURL: preferences.baseURL)

        if clearSavedPassword {
            try tokenStore.clearPassword()
            preferences.rememberPassword = false
        }
    }

    private func finishLogin(email: String, password: String, rememberPassword: Bool, user: AuthLoginData) throws {
        guard let userID = user.id?.trimmingCharacters(in: .whitespacesAndNewlines), !userID.isEmpty else {
            throw AuthManagerError.invalidLoginResponse
        }

        preferences.loggedInUserID = userID
        preferences.rememberPassword = rememberPassword

        try tokenStore.saveEmail(email)
        if rememberPassword {
            try tokenStore.savePassword(password)
        } else {
            try tokenStore.clearPassword()
        }
    }
}

enum AuthLoginStep {
    case authenticated
    case requiresTwoFactor(String)
}

enum AuthManagerError: LocalizedError {
    case notLoggedIn
    case invalidLoginResponse
    case twoFactorCodeRequired
    case twoFactorManualReloginRequired

    var errorDescription: String? {
        switch self {
        case .notLoggedIn:
            return "请先登录 CCodex 账号"
        case .invalidLoginResponse:
            return "登录成功，但没有拿到可用的用户信息"
        case .twoFactorCodeRequired:
            return "请输入两步验证码"
        case .twoFactorManualReloginRequired:
            return "账号开启了两步验证，会话失效后需要手动重新登录一次"
        }
    }
}

private extension CCodexAPIError {
    var isUnauthorized: Bool {
        switch self {
        case .unauthorized:
            return true
        case .httpStatus(let statusCode, _):
            return statusCode == 401 || statusCode == 403
        case .apiFailure(let code, _):
            return code == 401 || code == 403
        case .invalidResponse, .missingData, .decodingFailed:
            return false
        }
    }
}
