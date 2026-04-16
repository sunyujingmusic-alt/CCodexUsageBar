import AppKit
import SwiftUI

final class PreferencesWindowController: NSWindowController, NSWindowDelegate {
    private let preferences: PreferencesStore
    private let onSave: () -> Void

    init(preferences: PreferencesStore, onSave: @escaping () -> Void) {
        self.preferences = preferences
        self.onSave = onSave

        let view = PreferencesView(
            initialBaseURL: preferences.baseURL,
            initialTimezone: preferences.timezoneIdentifier,
            initialRefreshInterval: Int(preferences.refreshInterval),
            onSave: { [weak preferences] baseURL, timezone, refreshInterval in
                preferences?.baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                preferences?.timezoneIdentifier = timezone.trimmingCharacters(in: .whitespacesAndNewlines)
                preferences?.refreshInterval = TimeInterval(max(15, refreshInterval))
                onSave()
            }
        )

        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "CCodex 设置"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 520, height: 240))
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showAndActivate() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct PreferencesView: View {
    @State private var baseURL: String
    @State private var timezone: String
    @State private var refreshInterval: Int
    let onSave: (String, String, Int) -> Void

    init(initialBaseURL: String, initialTimezone: String, initialRefreshInterval: Int, onSave: @escaping (String, String, Int) -> Void) {
        _baseURL = State(initialValue: initialBaseURL)
        _timezone = State(initialValue: initialTimezone)
        _refreshInterval = State(initialValue: max(15, initialRefreshInterval))
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("CCodex 菜单栏额度监视器")
                .font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 12) {
                    Text("Base URL")
                        .frame(width: 90, alignment: .leading)
                    TextField("https://ccodex.net", text: $baseURL)
                        .textFieldStyle(.roundedBorder)
                }
                HStack(alignment: .center, spacing: 12) {
                    Text("Timezone")
                        .frame(width: 90, alignment: .leading)
                    TextField("Asia/Shanghai", text: $timezone)
                        .textFieldStyle(.roundedBorder)
                }
                HStack(alignment: .center, spacing: 12) {
                    Text("刷新间隔")
                        .frame(width: 90, alignment: .leading)
                    Stepper(value: $refreshInterval, in: 15 ... 3600, step: 15) {
                        Text("\(refreshInterval) 秒")
                    }
                }
            }

            Text("登录改为通过菜单栏中的“登录…”完成；首次登录后，App 会自己保存 token 并自动续期。")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("保存") {
                    onSave(baseURL, timezone, refreshInterval)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
