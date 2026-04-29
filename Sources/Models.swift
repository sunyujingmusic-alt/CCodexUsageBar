import Foundation

struct APIEnvelope<T: Decodable>: Decodable {
    let code: Int?
    let message: String?
    let success: Bool?
    let data: T?

    enum CodingKeys: String, CodingKey {
        case code
        case message
        case success
        case data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decodeLossyIntIfPresent(forKey: .code)
        message = try container.decodeLossyStringIfPresent(forKey: .message)
        success = try container.decodeLossyBoolIfPresent(forKey: .success)
        data = try container.decodeIfPresent(T.self, forKey: .data)
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
    let currencySymbol: String
    let rpm: Double?
    let tpm: Double?
    let fetchedAt: Date
}

struct AuthLoginData: Decodable {
    let displayName: String?
    let group: String?
    let id: String?
    let role: String?
    let status: String?
    let username: String?
    let requireTwoFactor: Bool?

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case group
        case id
        case role
        case status
        case username
        case requireTwoFactor = "require_2fa"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        displayName = try container.decodeLossyStringIfPresent(forKey: .displayName)
        group = try container.decodeLossyStringIfPresent(forKey: .group)
        id = try container.decodeLossyStringIfPresent(forKey: .id)
        role = try container.decodeLossyStringIfPresent(forKey: .role)
        status = try container.decodeLossyStringIfPresent(forKey: .status)
        username = try container.decodeLossyStringIfPresent(forKey: .username)
        requireTwoFactor = try container.decodeLossyBoolIfPresent(forKey: .requireTwoFactor)
    }
}

enum FetchState {
    case idle
    case loading
    case loaded(QuotaSnapshot)
    case failed(String)
}

struct UserSelfData: Decodable {
    let id: String?
    let username: String?
    let group: String?
    let usedQuota: Double?
    let requestCount: Int?
    let quota: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case group
        case usedQuota = "used_quota"
        case requestCount = "request_count"
        case quota
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeLossyStringIfPresent(forKey: .id)
        username = try container.decodeLossyStringIfPresent(forKey: .username)
        group = try container.decodeLossyStringIfPresent(forKey: .group)
        usedQuota = try container.decodeLossyDoubleIfPresent(forKey: .usedQuota)
        requestCount = try container.decodeLossyIntIfPresent(forKey: .requestCount)
        quota = try container.decodeLossyDoubleIfPresent(forKey: .quota)
    }
}

struct StatusInfoData: Decodable {
    let quotaPerUnit: Double?
    let quotaDisplayType: String?
    let customCurrencySymbol: String?
    let usdExchangeRate: Double?
    let customCurrencyExchangeRate: Double?

    enum CodingKeys: String, CodingKey {
        case quotaPerUnit = "quota_per_unit"
        case quotaDisplayType = "quota_display_type"
        case customCurrencySymbol = "custom_currency_symbol"
        case usdExchangeRate = "usd_exchange_rate"
        case customCurrencyExchangeRate = "custom_currency_exchange_rate"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        quotaPerUnit = try container.decodeLossyDoubleIfPresent(forKey: .quotaPerUnit)
        quotaDisplayType = try container.decodeLossyStringIfPresent(forKey: .quotaDisplayType)
        customCurrencySymbol = try container.decodeLossyStringIfPresent(forKey: .customCurrencySymbol)
        usdExchangeRate = try container.decodeLossyDoubleIfPresent(forKey: .usdExchangeRate)
        customCurrencyExchangeRate = try container.decodeLossyDoubleIfPresent(forKey: .customCurrencyExchangeRate)
    }
}

struct LogSelfStatData: Decodable {
    let quota: Double?
    let rpm: Double?
    let tpm: Double?

    enum CodingKeys: String, CodingKey {
        case quota
        case rpm
        case tpm
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        quota = try container.decodeLossyDoubleIfPresent(forKey: .quota)
        rpm = try container.decodeLossyDoubleIfPresent(forKey: .rpm)
        tpm = try container.decodeLossyDoubleIfPresent(forKey: .tpm)
    }
}

struct SubscriptionSelfData: Decodable {
    let subscriptions: [SubscriptionEntry]
}

struct SubscriptionEntry: Decodable {
    let subscription: SubscriptionSummary?
}

struct SubscriptionSummary: Decodable {
    let amountTotal: Double?
    let amountUsed: Double?
    let nextResetTime: String?
    let status: String?

    var isActive: Bool {
        let normalized = (status ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "active" || normalized.contains("生效")
    }

    enum CodingKeys: String, CodingKey {
        case amountTotal = "amount_total"
        case amountUsed = "amount_used"
        case nextResetTime = "next_reset_time"
        case status
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        amountTotal = try container.decodeLossyDoubleIfPresent(forKey: .amountTotal)
        amountUsed = try container.decodeLossyDoubleIfPresent(forKey: .amountUsed)
        nextResetTime = try container.decodeLossyStringIfPresent(forKey: .nextResetTime)
        status = try container.decodeLossyStringIfPresent(forKey: .status)
    }
}

private extension KeyedDecodingContainer {
    func decodeLossyStringIfPresent(forKey key: Key) throws -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return String(value)
        }
        if let value = try? decodeIfPresent(Bool.self, forKey: key) {
            return value ? "true" : "false"
        }
        return nil
    }

    func decodeLossyDoubleIfPresent(forKey key: Key) throws -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return Double(value)
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    func decodeLossyIntIfPresent(forKey key: Key) throws -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return Int(value)
        }
        if let value = try? decodeIfPresent(Bool.self, forKey: key) {
            return value ? 1 : 0
        }
        return nil
    }

    func decodeLossyBoolIfPresent(forKey key: Key) throws -> Bool? {
        if let value = try? decodeIfPresent(Bool.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value != 0
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return value != 0
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            switch normalized {
            case "true", "1", "yes", "y", "ok", "success":
                return true
            case "false", "0", "no", "n", "fail", "failed":
                return false
            default:
                return nil
            }
        }
        return nil
    }
}
