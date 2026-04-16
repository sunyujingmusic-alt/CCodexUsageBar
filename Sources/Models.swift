import Foundation

struct APIEnvelope<T: Decodable>: Decodable {
    let code: Int?
    let message: String?
    let data: T?
}

struct UsageStatsData: Decodable {
    let totalRequests: Int?
    let totalInputTokens: Double?
    let totalOutputTokens: Double?
    let totalCacheTokens: Double?
    let totalTokens: Double?
    let totalCost: Double?
    let totalActualCost: Double?
    let averageDurationMs: Double?

    enum CodingKeys: String, CodingKey {
        case totalRequests = "total_requests"
        case totalInputTokens = "total_input_tokens"
        case totalOutputTokens = "total_output_tokens"
        case totalCacheTokens = "total_cache_tokens"
        case totalTokens = "total_tokens"
        case totalCost = "total_cost"
        case totalActualCost = "total_actual_cost"
        case averageDurationMs = "average_duration_ms"
    }
}

struct SubscriptionData: Decodable {
    let dailyUsageUSD: Double?
    let group: SubscriptionGroup?

    enum CodingKeys: String, CodingKey {
        case dailyUsageUSD = "daily_usage_usd"
        case group
    }
}

struct SubscriptionGroup: Decodable {
    let name: String?
    let dailyLimitUSD: Double?
    let rateMultiplier: Double?

    enum CodingKeys: String, CodingKey {
        case name
        case dailyLimitUSD = "daily_limit_usd"
        case rateMultiplier = "rate_multiplier"
    }
}

struct QuotaSnapshot {
    let dateString: String
    let totalActualCost: Double
    let totalStandardCost: Double
    let backendDailyUsageUSD: Double?
    let dailyLimitUSD: Double?
    let remainingUSD: Double?
    let groupName: String?
    let rateMultiplier: Double?
    let fetchedAt: Date
}

struct AuthUser: Decodable {
    let id: Int?
    let email: String?
    let username: String?
    let role: String?
}

struct AuthLoginData: Decodable {
    let requiresTwoFactor: Bool?
    let accessToken: String?
    let refreshToken: String?
    let expiresIn: Int?
    let user: AuthUser?
    let tempToken: String?
    let userEmailMasked: String?

    enum CodingKeys: String, CodingKey {
        case requiresTwoFactor = "requires_2fa"
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case user
        case tempToken = "temp_token"
        case userEmailMasked = "user_email_masked"
    }
}

struct AuthRefreshData: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

enum FetchState {
    case idle
    case loading
    case loaded(QuotaSnapshot)
    case failed(String)
}
