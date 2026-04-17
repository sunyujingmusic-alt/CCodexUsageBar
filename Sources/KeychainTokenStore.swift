import Foundation

final class KeychainTokenStore {
    private struct Storage: Codable {
        var email: String?
        var password: String?
    }

    private let fileURL: URL
    private let queue = DispatchQueue(label: "net.ccodex.usagebar.store")

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("CCodexUsageBar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("credentials.json")
    }

    func loadEmail() -> String? { queue.sync { loadStorage().email } }
    func loadPassword() -> String? { queue.sync { loadStorage().password } }

    func saveEmail(_ value: String) throws { try update { $0.email = value } }
    func savePassword(_ value: String) throws { try update { $0.password = value } }

    func clearEmail() throws { try update { $0.email = nil } }
    func clearPassword() throws { try update { $0.password = nil } }

    private func update(_ mutate: (inout Storage) -> Void) throws {
        try queue.sync {
            var storage = loadStorage()
            mutate(&storage)
            try saveStorage(storage)
        }
    }

    private func loadStorage() -> Storage {
        guard let data = try? Data(contentsOf: fileURL) else { return Storage() }
        return (try? JSONDecoder().decode(Storage.self, from: data)) ?? Storage()
    }

    private func saveStorage(_ storage: Storage) throws {
        let data = try JSONEncoder().encode(storage)
        try data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}
