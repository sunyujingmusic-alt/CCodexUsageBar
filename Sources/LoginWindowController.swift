import AppKit
import SwiftUI

@MainActor
final class LoginWindowController: NSWindowController, NSWindowDelegate {
    private let viewModel: LoginViewModel

    init(authManager: AuthManager, onSuccess: @escaping () -> Void) {
        self.viewModel = LoginViewModel(
            initialEmail: authManager.storedEmail(),
            initialPassword: authManager.storedPassword(),
            initialRememberPassword: authManager.shouldRememberPassword(),
            submitAction: { email, password, rememberPassword in
                try await authManager.beginLogin(email: email, password: password, rememberPassword: rememberPassword)
            },
            twoFactorAction: { code, email, password, rememberPassword in
                try await authManager.completeTwoFactorLogin(code: code, email: email, password: password, rememberPassword: rememberPassword)
            },
            onSuccess: onSuccess
        )

        let hosting = NSHostingController(rootView: LoginView(viewModel: viewModel))
        let window = NSWindow(contentViewController: hosting)
        window.title = "登录 CCodex"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 500, height: 300))
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        viewModel.closeWindow = { [weak window] in
            window?.close()
        }
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

@MainActor
final class LoginViewModel: ObservableObject {
    @Published var email: String
    @Published var password: String
    @Published var twoFactorCode: String = ""
    @Published var rememberPassword: Bool
    @Published var isSubmitting = false
    @Published var errorMessage: String = ""
    @Published var twoFactorHint: String = ""
    @Published var isAwaitingTwoFactor = false

    private let submitAction: (String, String, Bool) async throws -> AuthLoginStep
    private let twoFactorAction: (String, String, String, Bool) async throws -> Void
    private let onSuccess: () -> Void
    var closeWindow: (() -> Void)?

    init(
        initialEmail: String,
        initialPassword: String,
        initialRememberPassword: Bool,
        submitAction: @escaping (String, String, Bool) async throws -> AuthLoginStep,
        twoFactorAction: @escaping (String, String, String, Bool) async throws -> Void,
        onSuccess: @escaping () -> Void
    ) {
        self.email = initialEmail
        self.password = initialPassword
        self.rememberPassword = initialRememberPassword
        self.submitAction = submitAction
        self.twoFactorAction = twoFactorAction
        self.onSuccess = onSuccess
    }

    func submit() {
        if isAwaitingTwoFactor {
            submitTwoFactor()
            return
        }

        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedEmail.isEmpty else {
            errorMessage = "请输入邮箱或用户名"
            return
        }
        guard !trimmedPassword.isEmpty else {
            errorMessage = "请输入密码"
            return
        }

        errorMessage = ""
        isSubmitting = true

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let result = try await self.submitAction(trimmedEmail, trimmedPassword, self.rememberPassword)
                self.isSubmitting = false
                switch result {
                case .authenticated:
                    self.finishSuccessfully()
                case .requiresTwoFactor(let message):
                    self.isAwaitingTwoFactor = true
                    self.twoFactorHint = message
                    self.errorMessage = ""
                    self.twoFactorCode = ""
                }
            } catch {
                self.isSubmitting = false
                self.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    func cancelTwoFactor() {
        isAwaitingTwoFactor = false
        twoFactorCode = ""
        twoFactorHint = ""
        errorMessage = ""
    }

    private func submitTwoFactor() {
        let trimmedCode = twoFactorCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedCode.isEmpty else {
            errorMessage = "请输入两步验证码"
            return
        }

        errorMessage = ""
        isSubmitting = true

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.twoFactorAction(trimmedCode, trimmedEmail, trimmedPassword, self.rememberPassword)
                self.isSubmitting = false
                self.finishSuccessfully()
            } catch {
                self.isSubmitting = false
                self.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func finishSuccessfully() {
        password = ""
        twoFactorCode = ""
        isAwaitingTwoFactor = false
        closeWindow?()
        onSuccess()
    }
}

private struct LoginView: View {
    @ObservedObject var viewModel: LoginViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(viewModel.isAwaitingTwoFactor ? "验证两步验证码" : "登录 CCodex")
                .font(.headline)

            Text(viewModel.isAwaitingTwoFactor
                 ? (viewModel.twoFactorHint.isEmpty ? "账号已开启两步验证，请输入认证器或备用码。" : viewModel.twoFactorHint)
                 : "首次登录后，App 会保留当前会话；如果勾选记住密码，会在会话失效后自动重登。")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 12) {
                    Text("账号")
                        .frame(width: 84, alignment: .leading)
                    TextField("邮箱或用户名", text: $viewModel.email)
                        .textFieldStyle(.roundedBorder)
                        .disabled(viewModel.isAwaitingTwoFactor)
                }
                HStack(alignment: .center, spacing: 12) {
                    Text("密码")
                        .frame(width: 84, alignment: .leading)
                    SecureField("输入 CCodex 密码", text: $viewModel.password)
                        .textFieldStyle(.roundedBorder)
                        .disabled(viewModel.isAwaitingTwoFactor)
                }

                if viewModel.isAwaitingTwoFactor {
                    HStack(alignment: .center, spacing: 12) {
                        Text("验证码")
                            .frame(width: 84, alignment: .leading)
                        TextField("6 位验证码或 8 位备用码", text: $viewModel.twoFactorCode)
                            .textFieldStyle(.roundedBorder)
                    }
                } else {
                    Toggle("将密码保存在本机，以便会话失效时自动重登", isOn: $viewModel.rememberPassword)
                }
            }

            if !viewModel.errorMessage.isEmpty {
                Text(viewModel.errorMessage)
                    .foregroundColor(.red)
                    .font(.footnote)
            }

            HStack {
                if viewModel.isAwaitingTwoFactor {
                    Button("返回") {
                        viewModel.cancelTwoFactor()
                    }
                    .disabled(viewModel.isSubmitting)
                }
                Spacer()
                Button(viewModel.isSubmitting ? (viewModel.isAwaitingTwoFactor ? "验证中…" : "登录中…") : (viewModel.isAwaitingTwoFactor ? "验证" : "登录")) {
                    viewModel.submit()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel.isSubmitting)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
