import AurumBarCore
import Darwin
import Foundation

/// AppKey 保存在仅当前用户可读写的文件中。
/// ad-hoc 签名的二进制每次升级 cdhash 都会变，放在钥匙串里会反复弹出授权窗口。
public final class AppKeyStore {
    public static var defaultFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AurumBar/appkey")
    }

    private let fileURL: URL
    private let legacyKeychain: KeychainStore?
    private let fileManager: FileManager

    public init(
        fileURL: URL = AppKeyStore.defaultFileURL,
        legacyKeychain: KeychainStore? = KeychainStore(),
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.legacyKeychain = legacyKeychain
        self.fileManager = fileManager
    }

    public func load() throws -> String? {
        if let key = try loadFromFile() {
            return key
        }
        return try migrateFromKeychain()
    }

    public func save(_ key: String) throws {
        let directory = fileURL.deletingLastPathComponent()
        let temporaryURL = directory.appendingPathComponent(".appkey-\(UUID().uuidString)")
        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            guard fileManager.createFile(
                atPath: temporaryURL.path,
                contents: Data(key.utf8),
                attributes: [.posixPermissions: 0o600]
            ) else {
                throw CocoaError(.fileWriteUnknown)
            }
            guard rename(temporaryURL.path, fileURL.path) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw AppKeyStoreError.file(operation: .save, message: error.localizedDescription)
        }
    }

    public func delete() throws {
        do {
            if fileManager.fileExists(atPath: fileURL.path) {
                try fileManager.removeItem(at: fileURL)
            }
        } catch {
            throw AppKeyStoreError.file(operation: .delete, message: error.localizedDescription)
        }
        try legacyKeychain?.delete()
    }

    private func loadFromFile() throws -> String? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        let data: Data
        do {
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            data = try Data(contentsOf: fileURL)
        } catch {
            throw AppKeyStoreError.file(operation: .read, message: error.localizedDescription)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw AppKeyStoreError.invalidData
        }
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : key
    }

    private func migrateFromKeychain() throws -> String? {
        guard let legacyKeychain else { return nil }
        let legacyKey: String?
        do {
            legacyKey = try legacyKeychain.load()
        } catch {
            AurumBarLog.write("无法从钥匙串迁移 AppKey，需要重新输入：\(error.localizedDescription)")
            return nil
        }
        guard let legacyKey, !legacyKey.isEmpty else { return nil }

        try save(legacyKey)
        do {
            try legacyKeychain.delete()
        } catch {
            AurumBarLog.write("AppKey 已迁移，但删除钥匙串旧条目失败：\(error.localizedDescription)")
        }
        AurumBarLog.write("AppKey 已从钥匙串迁移到本地文件")
        return legacyKey
    }
}

public enum AppKeyStoreError: LocalizedError, Equatable {
    public enum Operation: String {
        case read = "读取"
        case save = "保存"
        case delete = "删除"
    }

    case file(operation: Operation, message: String)
    case invalidData

    public var errorDescription: String? {
        switch self {
        case let .file(operation, message):
            return "\(operation.rawValue) AppKey 文件失败：\(message)"
        case .invalidData:
            return "AppKey 文件内容无效"
        }
    }
}
