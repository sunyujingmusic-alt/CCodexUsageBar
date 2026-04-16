import Foundation

final class CCodexAPI {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchSnapshot(baseURL: String, timezone: String, token: String) async throws -> QuotaSnapshot {
        let dateString = Self.todayString(timezone: timezone)

        let usage: UsageStatsData = try await getEnvelope(
            baseURL: baseURL,
            path: "/api/v1/usage/stats",
            queryItems: [
                URLQueryItem(name: "start_date", value: dateString),
                URLQueryItem(name: "end_date", value: dateString),
                URLQueryItem(name: "timezone", value: timezone),
            ],
            token: token,
            type: UsageStatsData.self
        )

        let subscriptions: [SubscriptionData] = try await getEnvelope(
            baseURL: baseURL,
            path: "/api/v1/subscriptions/active",
            queryItems: [URLQueryItem(name: "timezone", value: timezone)],
            token: token,
            type: [SubscriptionData].self
        )

        let active = subscriptions.first
        let group = active?.group

        let actualCost = usage.totalActualCost ?? 0
        let standardCost = usage.totalCost ?? 0
        let dailyLimit = group?.dailyLimitUSD
        let remaining = dailyLimit.map { $0 - actualCost }

        return QuotaSnapshot(
            dateString: dateString,
            totalActualCost: actualCost,
            totalStandardCost: standardCost,
            backendDailyUsageUSD: active?.dailyUsageUSD,
            dailyLimitUSD: dailyLimit,
            remainingUSD: remaining,
            groupName: group?.name,
            rateMultiplier: group?.rateMultiplier,
            fetchedAt: Date()
        )
    }

    func login(baseURL: String, email: String, password: String) async throws -> AuthLoginData {
        let payload = [
            "email": email,
            "password": password,
        ]
        return try await postEnvelope(baseURL: baseURL, path: "/api/v1/auth/login", payload: payload, type: AuthLoginData.self)
    }

    func refresh(baseURL: String, refreshToken: String) async throws -> AuthRefreshData {
        let payload = [
            "refresh_token": refreshToken,
        ]
        return try await postEnvelope(baseURL: baseURL, path: "/api/v1/auth/refresh", payload: payload, type: AuthRefreshData.self)
    }

    private func getEnvelope<T: Decodable>(baseURL: String, path: String, queryItems: [URLQueryItem], token: String, type: T.Type) async throws -> T {
        let request = try makeRequest(
            baseURL: baseURL,
            path: path,
            method: "GET",
            queryItems: queryItems,
            token: token,
            jsonBody: nil
        )
        return try await sendEnvelope(request, as: type)
    }

    private func postEnvelope<T: Decodable>(baseURL: String, path: String, payload: [String: String], type: T.Type) async throws -> T {
        let request = try makeRequest(
            baseURL: baseURL,
            path: path,
            method: "POST",
            queryItems: [],
            token: nil,
            jsonBody: try JSONSerialization.data(withJSONObject: payload)
        )
        return try await sendEnvelope(request, as: type)
    }

    private func makeRequest(baseURL: String, path: String, method: String, queryItems: [URLQueryItem], token: String?, jsonBody: Data?) throws -> URLRequest {
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
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
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
        if let code = envelope.code, code != 0 {
            throw NSError(
                domain: "CCodexAPI",
                code: code,
                userInfo: [NSLocalizedDescriptionKey: envelope.message ?? "API error"]
            )
        }
        guard let data = envelope.data else {
            throw NSError(
                domain: "CCodexAPI",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: envelope.message ?? "Missing data"]
            )
        }
        return data
    }

    private func send<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> T {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "CCodexAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "No HTTP response"])
        }
        guard (200 ... 299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            throw NSError(domain: "CCodexAPI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: body])
        }
        return try JSONDecoder().decode(type, from: data)
    }

    private static func todayString(timezone: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: timezone) ?? .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
