import Foundation

final class CCodexAPI {
    private let session: URLSession

    init(session: URLSession? = nil) {
        self.session = session ?? Self.makeSession()
    }

    func fetchSnapshot(baseURL: String, timezone: String, userID: String) async throws -> QuotaSnapshot {
        let (dateString, startTimestamp, endTimestamp) = Self.todayRange(timezone: timezone)

        let status: StatusInfoData = try await getEnvelope(
            baseURL: baseURL,
            path: "/api/status",
            queryItems: [],
            userID: userID,
            type: StatusInfoData.self
        )

        let stat: LogSelfStatData = try await getEnvelope(
            baseURL: baseURL,
            path: "/api/log/self/stat",
            queryItems: [
                URLQueryItem(name: "type", value: "0"),
                URLQueryItem(name: "token_name", value: ""),
                URLQueryItem(name: "model_name", value: ""),
                URLQueryItem(name: "start_timestamp", value: String(startTimestamp)),
                URLQueryItem(name: "end_timestamp", value: String(endTimestamp)),
                URLQueryItem(name: "group", value: ""),
            ],
            userID: userID,
            type: LogSelfStatData.self
        )

        let subscriptionSelf: SubscriptionSelfData = try await getEnvelope(
            baseURL: baseURL,
            path: "/api/subscription/self",
            queryItems: [],
            userID: userID,
            type: SubscriptionSelfData.self
        )

        let userSelf: UserSelfData = try await getEnvelope(
            baseURL: baseURL,
            path: "/api/user/self",
            queryItems: [],
            userID: userID,
            type: UserSelfData.self
        )

        let currency = CurrencyDisplay(status: status)

        let todayUsed = currency.convertQuota(stat.quota ?? userSelf.usedQuota ?? 0)
        let activeSubscription = subscriptionSelf.subscriptions.first?.subscription
        let dailyLimit = activeSubscription?.amountTotal.map(currency.convertQuota(_:))
        let subscriptionUsed = activeSubscription?.amountUsed.map(currency.convertQuota(_:))
        let remaining = dailyLimit.flatMap { limit in
            subscriptionUsed.map { limit - $0 }
        }

        return QuotaSnapshot(
            dateString: dateString,
            totalActualCost: todayUsed,
            totalStandardCost: todayUsed,
            backendDailyUsageUSD: subscriptionUsed,
            dailyLimitUSD: dailyLimit,
            remainingUSD: remaining,
            groupName: userSelf.group,
            rateMultiplier: nil,
            currencySymbol: currency.symbol,
            rpm: stat.rpm,
            tpm: stat.tpm,
            fetchedAt: Date()
        )
    }

    func beginLogin(baseURL: String, email: String, password: String) async throws -> LoginAttemptResult {
        let payload = [
            "username": email,
            "password": password,
        ]
        let result: AuthLoginData = try await postEnvelope(
            baseURL: baseURL,
            path: "/api/user/login",
            payload: payload,
            userID: nil,
            type: AuthLoginData.self
        )

        if result.requireTwoFactor == true {
            return .requiresTwoFactor("请输入两步验证码")
        }
        return .authenticated(result)
    }

    func completeTwoFactorLogin(baseURL: String, code: String) async throws -> AuthLoginData {
        let payload = ["code": code]
        let result: AuthLoginData = try await postEnvelope(
            baseURL: baseURL,
            path: "/api/user/login/2fa",
            payload: payload,
            userID: nil,
            type: AuthLoginData.self
        )

        if result.requireTwoFactor == true {
            throw CCodexAPIError.apiFailure(nil, "请输入两步验证码")
        }
        return result
    }

    func fetchCurrentUser(baseURL: String, userID: String) async throws -> UserSelfData {
        try await getEnvelope(
            baseURL: baseURL,
            path: "/api/user/self",
            queryItems: [],
            userID: userID,
            type: UserSelfData.self
        )
    }

    func clearCookies(baseURL: String) {
        guard let base = URL(string: baseURL), let host = base.host else { return }
        let storage = session.configuration.httpCookieStorage ?? HTTPCookieStorage.shared
        let normalizedHost = host.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()

        for cookie in storage.cookies ?? [] {
            let cookieDomain = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
            guard !cookieDomain.isEmpty else { continue }
            if normalizedHost == cookieDomain || normalizedHost.hasSuffix(".\(cookieDomain)") {
                storage.deleteCookie(cookie)
            }
        }
    }

    private func getEnvelope<T: Decodable>(
        baseURL: String,
        path: String,
        queryItems: [URLQueryItem],
        userID: String?,
        type: T.Type
    ) async throws -> T {
        let request = try makeRequest(
            baseURL: baseURL,
            path: path,
            method: "GET",
            queryItems: queryItems,
            userID: userID,
            jsonBody: nil
        )
        return try await sendEnvelope(request, as: type)
    }

    private func postEnvelope<T: Decodable>(
        baseURL: String,
        path: String,
        payload: [String: String],
        userID: String?,
        type: T.Type
    ) async throws -> T {
        let request = try makeRequest(
            baseURL: baseURL,
            path: path,
            method: "POST",
            queryItems: [],
            userID: userID,
            jsonBody: try JSONSerialization.data(withJSONObject: payload)
        )
        return try await sendEnvelope(request, as: type)
    }

    private func makeRequest(
        baseURL: String,
        path: String,
        method: String,
        queryItems: [URLQueryItem],
        userID: String?,
        jsonBody: Data?
    ) throws -> URLRequest {
        guard var components = URLComponents(string: baseURL) else {
            throw URLError(.badURL)
        }
        components.path = path
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.defaultUserAgent, forHTTPHeaderField: "User-Agent")
        if let origin = Self.originString(from: components) {
            request.setValue(origin, forHTTPHeaderField: "Origin")
        }
        request.setValue(Self.refererString(baseURL: baseURL, path: path, userID: userID), forHTTPHeaderField: "Referer")
        if let userID, !userID.isEmpty {
            request.setValue(userID, forHTTPHeaderField: "New-API-User")
        }
        if let jsonBody {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = jsonBody
        }
        request.timeoutInterval = 30
        return request
    }

    private func sendEnvelope<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> T {
        let envelope: APIEnvelope<T> = try await send(request, as: APIEnvelope<T>.self)

        if let success = envelope.success, success == false {
            throw failure(code: envelope.code, message: envelope.message)
        }
        if let code = envelope.code, code != 0 {
            throw failure(code: code, message: envelope.message)
        }
        guard let data = envelope.data else {
            throw CCodexAPIError.missingData(envelope.message ?? "Missing data")
        }
        return data
    }

    private func send<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> T {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CCodexAPIError.invalidResponse
        }

        guard (200 ... 299).contains(http.statusCode) else {
            let message = responseMessage(from: data)
            if http.statusCode == 401 || http.statusCode == 403 {
                throw CCodexAPIError.unauthorized(message)
            }
            throw CCodexAPIError.httpStatus(http.statusCode, message)
        }

        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            let body = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            throw CCodexAPIError.decodingFailed(body)
        }
    }

    private func failure(code: Int?, message: String?) -> CCodexAPIError {
        let resolvedMessage = message ?? "API error"
        if code == 401 || code == 403 || Self.looksUnauthorized(message: resolvedMessage) {
            return .unauthorized(resolvedMessage)
        }
        return .apiFailure(code, resolvedMessage)
    }

    private func responseMessage(from data: Data) -> String {
        if let envelope = try? JSONDecoder().decode(APIEnvelope<MessageOnly>.self, from: data),
           let message = envelope.message, !message.isEmpty {
            return message
        }
        if let decoded = String(data: data, encoding: .utf8), !decoded.isEmpty {
            return decoded
        }
        return "HTTP request failed"
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpCookieStorage = HTTPCookieStorage.shared
        configuration.httpShouldSetCookies = true
        return URLSession(configuration: configuration)
    }

    private static let defaultUserAgent = "CCodexUsageBar/1.0 (macOS)"

    private static func originString(from components: URLComponents) -> String? {
        guard let scheme = components.scheme, let host = components.host else { return nil }
        if let port = components.port {
            return "\(scheme)://\(host):\(port)"
        }
        return "\(scheme)://\(host)"
    }

    private static func refererString(baseURL: String, path: String, userID: String?) -> String {
        let trimmed = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        if path == "/api/user/login" || path == "/api/user/login/2fa" {
            return trimmed + "/login"
        }
        if userID != nil {
            return trimmed + "/console"
        }
        return trimmed
    }

    private static func looksUnauthorized(message: String) -> Bool {
        let normalized = message.lowercased()
        return normalized.contains("unauthorized")
            || normalized.contains("not logged in")
            || normalized.contains("login")
            || message.contains("未登录")
            || message.contains("登录")
    }

    private static func todayRange(timezone: String) -> (String, Int, Int) {
        let timeZone = TimeZone(identifier: timezone) ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let now = Date()
        let start = calendar.startOfDay(for: now)
        return (todayString(timezone: timezone), Int(start.timeIntervalSince1970), Int(now.timeIntervalSince1970))
    }

    private static func todayString(timezone: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: timezone) ?? .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}

enum CCodexAPIError: LocalizedError {
    case invalidResponse
    case unauthorized(String)
    case httpStatus(Int, String)
    case apiFailure(Int?, String)
    case missingData(String)
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "服务端响应无效"
        case .unauthorized(let message):
            return Self.userFacingMessage(from: message)
        case .httpStatus(let statusCode, let message):
            if statusCode == 429 {
                return "请求过快，被站点限流了，请稍后再试"
            }
            return Self.userFacingMessage(from: message)
        case .apiFailure(_, let message):
            return Self.userFacingMessage(from: message)
        case .missingData(let message):
            return Self.userFacingMessage(from: message)
        case .decodingFailed(let body):
            return Self.userFacingDecodingFailure(from: body)
        }
    }

    private static func userFacingMessage(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "请求失败" }

        let lowered = trimmed.lowercased()
        if lowered.contains("too many requests") || trimmed.contains("请求过快") || trimmed.contains("限流") {
            return "请求过快，被站点限流了，请稍后再试"
        }
        if lowered.contains("cloudflare") || lowered.contains("cf-chl") || trimmed.contains("Just a moment") {
            return "站点返回了验证/拦截页面，请稍后再试"
        }
        if lowered.contains("<!doctype html") || lowered.contains("<html") {
            return "站点临时返回了网页而不是接口数据，请稍后再试"
        }
        return trimmed
    }

    private static func userFacingDecodingFailure(from body: String) -> String {
        let normalized = userFacingMessage(from: body)
        if normalized == body.trimmingCharacters(in: .whitespacesAndNewlines) {
            return "服务端返回格式发生变化"
        }
        return normalized
    }
}

private struct CurrencyDisplay {
    let symbol: String
    let quotaPerUnit: Double
    let usesCustomCurrency: Bool
    let usdExchangeRate: Double?
    let customCurrencyExchangeRate: Double?

    init(status: StatusInfoData) {
        let normalizedType = status.quotaDisplayType?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""

        usesCustomCurrency = !(normalizedType.isEmpty || normalizedType == "0" || normalizedType == "usd" || normalizedType == "default")
        symbol = usesCustomCurrency ? (status.customCurrencySymbol?.isEmpty == false ? status.customCurrencySymbol! : "$") : "$"
        quotaPerUnit = status.quotaPerUnit ?? 1
        usdExchangeRate = status.usdExchangeRate
        customCurrencyExchangeRate = status.customCurrencyExchangeRate
    }

    func convertQuota(_ quota: Double) -> Double {
        guard quotaPerUnit > 0 else { return quota }

        let usdValue = quota / quotaPerUnit
        guard usesCustomCurrency else { return usdValue }

        if let usdExchangeRate, usdExchangeRate > 0,
           let customCurrencyExchangeRate, customCurrencyExchangeRate > 0 {
            return usdValue * (customCurrencyExchangeRate / usdExchangeRate)
        }
        if let customCurrencyExchangeRate, customCurrencyExchangeRate > 0 {
            return usdValue * customCurrencyExchangeRate
        }
        return usdValue
    }
}

private struct MessageOnly: Decodable {}

enum LoginAttemptResult {
    case authenticated(AuthLoginData)
    case requiresTwoFactor(String?)
}
