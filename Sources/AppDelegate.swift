import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let preferences = PreferencesStore()
        let tokenStore = KeychainTokenStore()
        let api = CCodexAPI()
        let authManager = AuthManager(preferences: preferences, tokenStore: tokenStore, api: api)
        statusBarController = StatusBarController(
            preferences: preferences,
            tokenStore: tokenStore,
            api: api,
            authManager: authManager
        )
    }
}
