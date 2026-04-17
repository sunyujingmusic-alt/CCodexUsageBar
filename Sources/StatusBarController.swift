import AppKit
import Foundation

@MainActor
final class StatusBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let preferences: PreferencesStore
    private let api: CCodexAPI
    private let authManager: AuthManager

    private var timer: Timer?
    private var state: FetchState = .idle
    private var preferencesWindowController: PreferencesWindowController?
    private var loginWindowController: LoginWindowController?
    private var loadingMessage = "正在刷新"

    private let usedItem = NSMenuItem(title: "今日已消费：--", action: nil, keyEquivalent: "")
    private let limitItem = NSMenuItem(title: "今日上限：--", action: nil, keyEquivalent: "")
    private let remainingItem = NSMenuItem(title: "今日剩余：--", action: nil, keyEquivalent: "")
    private let groupItem = NSMenuItem(title: "套餐组：--", action: nil, keyEquivalent: "")
    private let updatedItem = NSMenuItem(title: "更新时间：--", action: nil, keyEquivalent: "")
    private let statusItemMessage = NSMenuItem(title: "状态：待刷新", action: nil, keyEquivalent: "")

    init(preferences: PreferencesStore, api: CCodexAPI, authManager: AuthManager) {
        self.preferences = preferences
        self.api = api
        self.authManager = authManager
        super.init()
        configureMenu()
        configureStatusItem()
        scheduleTimer()

        if authManager.hasAutomaticCredentials() {
            refreshNow()
        } else {
            state = .failed("请先登录 CCodex 账号")
            render()
            openLogin()
        }
    }

    private func configureStatusItem() {
        statusItem.button?.title = "额度 --"
        statusItem.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        statusItem.menu = menu
    }

    private func configureMenu() {
        [usedItem, limitItem, remainingItem, groupItem, updatedItem, statusItemMessage].forEach {
            $0.isEnabled = false
            menu.addItem($0)
        }
        menu.addItem(.separator())

        let refresh = NSMenuItem(title: "手动刷新", action: #selector(refreshMenuAction), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)

        let login = NSMenuItem(title: "登录…", action: #selector(openLoginMenuAction), keyEquivalent: "l")
        login.target = self
        menu.addItem(login)

        let logout = NSMenuItem(title: "退出登录", action: #selector(logoutMenuAction), keyEquivalent: "")
        logout.target = self
        menu.addItem(logout)

        let settings = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: preferences.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshNow()
            }
        }
    }

    func refreshNow() {
        loadingMessage = "正在刷新"
        state = .loading
        render()

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let userID = try await self.authManager.ensureValidSessionUserID()
                let snapshot = try await self.api.fetchSnapshot(
                    baseURL: self.preferences.baseURL,
                    timezone: self.preferences.timezoneIdentifier,
                    userID: userID
                )
                self.state = .loaded(snapshot)
                self.render()
            } catch {
                let message = self.userFacingMessage(for: error)
                self.state = .failed(message)
                self.render()
                if self.shouldPromptLogin(for: error) {
                    self.openLogin()
                }
            }
        }
    }

    private func render() {
        switch state {
        case .idle:
            statusItem.button?.title = "额度 --"
            statusItemMessage.title = "状态：待刷新"
        case .loading:
            statusItem.button?.title = "同步中…"
            statusItemMessage.title = "状态：\(loadingMessage)"
        case .failed(let message):
            statusItem.button?.title = "额度 --"
            usedItem.title = "今日已消费：--"
            limitItem.title = "今日上限：--"
            remainingItem.title = "今日剩余：--"
            groupItem.title = "套餐组：--"
            updatedItem.title = "更新时间：--"
            statusItemMessage.title = "状态：\(message)"
        case .loaded(let snapshot):
            statusItem.button?.title = titleForMenuBar(snapshot: snapshot)
            usedItem.title = "今日已消费：\(Self.money(snapshot.totalActualCost, symbol: snapshot.currencySymbol))"
            limitItem.title = "今日上限：\(snapshot.dailyLimitUSD.map { Self.money($0, symbol: snapshot.currencySymbol) } ?? "--")"
            remainingItem.title = "今日剩余：\(snapshot.remainingUSD.map { Self.money($0, symbol: snapshot.currencySymbol) } ?? "--")"
            groupItem.title = "套餐组：\(snapshot.groupName ?? "--")"
            updatedItem.title = "更新时间：\(Self.time(snapshot.fetchedAt))"
            statusItemMessage.title = "状态：已同步"
        }
    }

    private func titleForMenuBar(snapshot: QuotaSnapshot) -> String {
        guard let remaining = snapshot.remainingUSD else {
            return "额度 --"
        }
        if remaining >= 0 {
            return "余 \(Self.shortMoney(remaining, symbol: snapshot.currencySymbol))"
        } else {
            return "超 \(Self.shortMoney(abs(remaining), symbol: snapshot.currencySymbol))"
        }
    }

    private func openLogin() {
        if loginWindowController == nil {
            loginWindowController = LoginWindowController(authManager: authManager) { [weak self] in
                self?.refreshNow()
            }
        }
        loginWindowController?.showAndActivate()
    }

    @objc private func refreshMenuAction() {
        refreshNow()
    }

    @objc private func openLoginMenuAction() {
        openLogin()
    }

    @objc private func logoutMenuAction() {
        do {
            try authManager.logout(clearSavedPassword: true)
            state = .failed("已退出登录，请重新登录")
            render()
            openLogin()
        } catch {
            state = .failed(userFacingMessage(for: error))
            render()
        }
    }

    @objc private func openSettings() {
        if preferencesWindowController == nil {
            preferencesWindowController = PreferencesWindowController(
                preferences: preferences,
                onSave: { [weak self] in
                    self?.scheduleTimer()
                    self?.refreshNow()
                }
            )
        }
        preferencesWindowController?.showAndActivate()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func shouldPromptLogin(for error: Error) -> Bool {
        if let authError = error as? AuthManagerError {
            switch authError {
            case .notLoggedIn, .twoFactorManualReloginRequired:
                return true
            case .invalidLoginResponse, .twoFactorCodeRequired:
                return false
            }
        }
        if let apiError = error as? CCodexAPIError {
            switch apiError {
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
        return false
    }

    private func userFacingMessage(for error: Error) -> String {
        if let localized = (error as? LocalizedError)?.errorDescription, !localized.isEmpty {
            return localized
        }
        return error.localizedDescription
    }

    private static func money(_ value: Double, symbol: String) -> String {
        String(format: "%@%.2f", symbol, value)
    }

    private static func shortMoney(_ value: Double, symbol: String) -> String {
        String(format: "%@%.2f", symbol, value)
    }

    private static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
}
