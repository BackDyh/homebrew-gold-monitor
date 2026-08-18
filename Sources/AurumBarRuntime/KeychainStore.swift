import Foundation
import Security

public protocol KeychainBackend {
    func copyMatching(_ query: CFDictionary, result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus
    func update(_ query: CFDictionary, attributes: CFDictionary) -> OSStatus
    func add(_ attributes: CFDictionary) -> OSStatus
    func delete(_ query: CFDictionary) -> OSStatus
}

public struct SystemKeychainBackend: KeychainBackend {
    public init() {}

    public func copyMatching(
        _ query: CFDictionary,
        result: UnsafeMutablePointer<CFTypeRef?>?
    ) -> OSStatus {
        SecItemCopyMatching(query, result)
    }

    public func update(_ query: CFDictionary, attributes: CFDictionary) -> OSStatus {
        SecItemUpdate(query, attributes)
    }

    public func add(_ attributes: CFDictionary) -> OSStatus {
        SecItemAdd(attributes, nil)
    }

    public func delete(_ query: CFDictionary) -> OSStatus {
        SecItemDelete(query)
    }
}

public final class KeychainStore {
    private let service: String
    private let account: String
    private let backend: KeychainBackend

    public init(
        service: String = "com.back.aurumbar",
        account: String = "juhe-gold-app-key",
        backend: KeychainBackend = SystemKeychainBackend()
    ) {
        self.service = service
        self.account = account
        self.backend = backend
    }

    public func load() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = backend.copyMatching(query as CFDictionary, result: &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainError.status(operation: .read, status: status)
        }
        guard let data = item as? Data,
              let value = String(data: data, encoding: .utf8)
        else {
            throw KeychainError.invalidData
        }
        return value
    }

    public func save(_ value: String) throws {
        let data = Data(value.utf8)
        let attributes = [kSecValueData as String: data]
        let updateStatus = backend.update(
            baseQuery as CFDictionary,
            attributes: attributes as CFDictionary
        )

        if updateStatus == errSecItemNotFound {
            var item = baseQuery
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = backend.add(item as CFDictionary)
            guard addStatus == errSecSuccess else {
                throw KeychainError.status(operation: .save, status: addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw KeychainError.status(operation: .save, status: updateStatus)
        }
    }

    public func delete() throws {
        let status = backend.delete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.status(operation: .delete, status: status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

public enum KeychainError: LocalizedError, Equatable {
    public enum Operation: String {
        case read = "读取"
        case save = "保存"
        case delete = "删除"
    }

    case status(operation: Operation, status: OSStatus)
    case invalidData

    public var errorDescription: String? {
        switch self {
        case let .status(operation, status):
            let message = SecCopyErrorMessageString(status, nil) as String?
            return "从钥匙串\(operation.rawValue) AppKey 失败：\(message ?? String(status))"
        case .invalidData:
            return "钥匙串中的 AppKey 数据无效"
        }
    }
}
