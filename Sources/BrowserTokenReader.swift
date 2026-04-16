import Foundation

struct BrowserTokenImport {
    let browserName: String
    let token: String
}

enum BrowserTokenReaderError: LocalizedError {
    case noSupportedBrowserFound
    case browserNotRunning
    case noWindow(String)
    case automationDenied(String)
    case javaScriptFromAppleEventsDisabled(String)
    case noTokenFound(String)
    case scriptFailed(String)

    var errorDescription: String? {
        switch self {
        case .noSupportedBrowserFound:
            return "未找到受支持的浏览器（Google Chrome / Chromium / Brave / Edge）"
        case .browserNotRunning:
            return "没有检测到已打开的受支持浏览器窗口"
        case .noWindow(let browser):
            return "\(browser) 已启动，但没有可用窗口"
        case .automationDenied(let browser):
            return "未允许本 App 控制 \(browser)。请在系统设置里允许自动化后重试"
        case .javaScriptFromAppleEventsDisabled(let browser):
            return "\(browser) 未开启“允许 Apple 事件中的 JavaScript”"
        case .noTokenFound(let browser):
            return "已连到 \(browser)，但当前 ccodex 登录态里没有 auth_token"
        case .scriptFailed(let message):
            return "浏览器读取失败：\(message)"
        }
    }
}

struct BrowserTokenReader: Sendable {
    private let browserCandidates = [
        "Google Chrome",
        "Chromium",
        "Brave Browser",
        "Microsoft Edge",
    ]

    func importToken() async throws -> BrowserTokenImport {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: try self.importTokenSync())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func importTokenSync() throws -> BrowserTokenImport {
        guard hasAnyInstalledBrowser() else {
            throw BrowserTokenReaderError.noSupportedBrowserFound
        }

        var sawRunningBrowser = false
        var lastMeaningfulError: Error?

        for browser in browserCandidates where isInstalled(browser) {
            do {
                let token = try runImport(browserName: browser)
                guard !token.isEmpty else {
                    throw BrowserTokenReaderError.noTokenFound(browser)
                }
                return BrowserTokenImport(browserName: browser, token: token)
            } catch BrowserTokenReaderError.browserNotRunning {
                continue
            } catch BrowserTokenReaderError.noWindow(let name) {
                sawRunningBrowser = true
                lastMeaningfulError = BrowserTokenReaderError.noWindow(name)
            } catch {
                sawRunningBrowser = true
                lastMeaningfulError = error
            }
        }

        if let lastMeaningfulError {
            throw lastMeaningfulError
        }
        if !sawRunningBrowser {
            throw BrowserTokenReaderError.browserNotRunning
        }
        throw BrowserTokenReaderError.scriptFailed("未知错误")
    }

    private func hasAnyInstalledBrowser() -> Bool {
        browserCandidates.contains(where: isInstalled)
    }

    private func isInstalled(_ browserName: String) -> Bool {
        let fileManager = FileManager.default
        let candidates = [
            "/Applications/\(browserName).app",
            "\(NSHomeDirectory())/Applications/\(browserName).app",
        ]
        return candidates.contains(where: fileManager.fileExists(atPath:))
    }

    private func runImport(browserName: String) throws -> String {
        let script = appleScript(for: browserName)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        let out = String(data: outData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let err = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if process.terminationStatus == 0 {
            if out == "__BROWSER_NOT_RUNNING__" {
                throw BrowserTokenReaderError.browserNotRunning
            }
            if out == "__NO_WINDOW__" {
                throw BrowserTokenReaderError.noWindow(browserName)
            }
            if out.isEmpty {
                throw BrowserTokenReaderError.noTokenFound(browserName)
            }
            return out
        }

        let merged = [out, err].filter { !$0.isEmpty }.joined(separator: "\n")
        if merged.contains("-1743") || merged.localizedCaseInsensitiveContains("Not authorized to send Apple events") {
            throw BrowserTokenReaderError.automationDenied(browserName)
        }
        if merged.contains("通过 AppleScript 执行 JavaScript 的功能已关闭") ||
            merged.localizedCaseInsensitiveContains("JavaScript from Apple Events") ||
            merged.localizedCaseInsensitiveContains("Allow JavaScript from Apple Events") {
            throw BrowserTokenReaderError.javaScriptFromAppleEventsDisabled(browserName)
        }
        throw BrowserTokenReaderError.scriptFailed(merged.isEmpty ? "osascript exit \(process.terminationStatus)" : merged)
    }

    private func appleScript(for browserName: String) -> String {
        let escapedName = browserName.replacingOccurrences(of: "\"", with: "\\\"")
        return """
        tell application \"System Events\"
          set appNames to name of every process
        end tell
        if appNames does not contain \"\(escapedName)\" then
          return \"__BROWSER_NOT_RUNNING__\"
        end if

        tell application \"\(escapedName)\"
          if not (exists window 1) then
            return \"__NO_WINDOW__\"
          end if

          set winRef to front window
          set tabCount to (count of tabs of winRef)
          set newTab to make new tab at end of tabs of winRef
          set active tab index of winRef to (tabCount + 1)
          set URL of newTab to \"https://ccodex.net/usage\"
          delay 2.0
          set tokenValue to execute newTab javascript \"localStorage.getItem('auth_token') || ''\"
          close newTab
          return tokenValue
        end tell
        """
    }
}
