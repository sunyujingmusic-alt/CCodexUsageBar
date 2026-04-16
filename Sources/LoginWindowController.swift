import AppKit
import SwiftUI

@MainActor
final class LoginWindowController: NSWindowController, NSWindowDelegate {
    private let viewModel: LoginViewModel

    init(authManager: AuthManager, onSuccess: @escaping () -> Void) {
        self.viewModel = LoginViewModel(
            initialEmail: authManager.storedEmail(),
            initialRememberPassword: authManager.shouldRememberPassword(),
            submitAction: { email, password, rememberPassword in
                try await authManager.login(email: email, password: password, rememberPassword: rememberPassword)
            },
            onSuccess: onSuccess
        )

        let hosting = NSHostingController(rootView: LoginView(viewModel: viewModel))
        let window = NSWindow(contentViewController: hosting)
        window.title = "登录 CCodex"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 460, height: 250))
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
    @Published var password: String = ""
    @Published var rememberPassword: Bool
    @Published var isSubmitting = false
    @Published var errorMessage: String = ""

    private let submitAction: (String, String, Bool) async throws -> Void
    private let onSuccess: () -> Void
    var closeWindow: (() -> Void)?

    init(initialEmail: String, initialRememberPassword: Bool, submitAction: @escaping (String, String, Bool) async throws -> Void, onSuccess: @escaping () -> Void) {
        self.email = initialEmail
        self.rememberPassword = initialRememberPassword
        self.submitAction = submitAction
        self.onSuccess = onSuccess
    }

    func submit() {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedEmail.isEmpty else {
            errorMessage = "请输入邮箱"
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
                try await self.submitAction(trimmedEmail, trimmedPassword, self.rememberPassword)
                self.isSubmitting = false
                self.password = ""
                self.closeWindow?()
                self.onSuccess()
            } catch {
                self.isSubmitting = false
                self.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}

private struct LoginView: View {
    @ObservedObject var viewModel: LoginViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("登录 CCodex")
                .font(.headline)

            Text("首次登录后，App 会自动保存 token 并在后台续期。")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 12) {
                    Text("邮箱")
                        .frame(width: 84, alignment: .leading)
                    TextField("you@example.com", text: $viewModel.email)
                        .textFieldStyle(.roundedBorder)
                }
                HStack(alignment: .center, spacing: 12) {
                    Text("密码")
                        .frame(width: 84, alignment: .leading)
                    SecureField("输入 CCodex 密码", text: $viewModel.password)
                        .textFieldStyle(.roundedBorder)
                }
                Toggle("将密码保存在本机钥匙串，以便 refresh 失效时自动重登", isOn: $viewModel.rememberPassword)
            }

            if !viewModel.errorMessage.isEmpty {
                Text(viewModel.errorMessage)
                    .foregroundColor(.red)
                    .font(.footnote)
            }

            HStack {
                Spacer()
                Button(viewModel.isSubmitting ? "登录中…" : "登录") {
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
