import Foundation

final class PreferencesStore {
    private enum Keys {
        static let baseURL = "baseURL"
        static let timezone = "timezone"
        static let refreshInterval = "refreshInterval"
        static let tokenExpiresAt = "tokenExpiresAt"
        static let rememberPassword = "rememberPassword"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        registerDefaults()
    }

    var baseURL: String {
        get { defaults.string(forKey: Keys.baseURL) ?? "https://ccodex.net" }
        set { defaults.set(newValue, forKey: Keys.baseURL) }
    }

    var timezoneIdentifier: String {
        get { defaults.string(forKey: Keys.timezone) ?? "Asia/Shanghai" }
        set { defaults.set(newValue, forKey: Keys.timezone) }
    }

    var refreshInterval: TimeInterval {
        get {
            let value = defaults.double(forKey: Keys.refreshInterval)
            return value > 0 ? value : 120
        }
        set { defaults.set(newValue, forKey: Keys.refreshInterval) }
    }

    var tokenExpiresAt: TimeInterval? {
        get {
            let value = defaults.double(forKey: Keys.tokenExpiresAt)
            return value > 0 ? value : nil
        }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Keys.tokenExpiresAt)
            } else {
                defaults.removeObject(forKey: Keys.tokenExpiresAt)
            }
        }
    }

    var rememberPassword: Bool {
        get { defaults.object(forKey: Keys.rememberPassword) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.rememberPassword) }
    }

    private func registerDefaults() {
        defaults.register(defaults: [
            Keys.baseURL: "https://ccodex.net",
            Keys.timezone: "Asia/Shanghai",
            Keys.refreshInterval: 120.0,
            Keys.rememberPassword: true,
        ])
    }
}
