import Testing
import AurumBarRuntime
import Foundation
import Security

struct KeychainStoreTests {
    @Test func loadDistinguishesNotFoundFromFailure() throws {
        let missing = StubKeychainBackend(copyStatus: errSecItemNotFound)
        #expect(try KeychainStore(backend: missing).load() == nil)

        let denied = StubKeychainBackend(copyStatus: errSecAuthFailed)
        #expect(throws: KeychainError.status(operation: .read, status: errSecAuthFailed)) {
            try KeychainStore(backend: denied).load()
        }
    }

    @Test func loadRejectsInvalidData() {
        let backend = StubKeychainBackend(
            copyStatus: errSecSuccess,
            copiedItem: Data([0xFF]) as CFData
        )
        #expect(throws: KeychainError.invalidData) {
            try KeychainStore(backend: backend).load()
        }
    }

    @Test func saveFallsBackToAdd() throws {
        let backend = StubKeychainBackend(updateStatus: errSecItemNotFound, addStatus: errSecSuccess)
        try KeychainStore(backend: backend).save("secret")
        #expect(backend.addCalls == 1)
    }

    @Test func deleteIsIdempotentButPropagatesFailure() throws {
        try KeychainStore(backend: StubKeychainBackend(deleteStatus: errSecItemNotFound)).delete()

        let denied = StubKeychainBackend(deleteStatus: errSecAuthFailed)
        #expect(throws: KeychainError.status(operation: .delete, status: errSecAuthFailed)) {
            try KeychainStore(backend: denied).delete()
        }
    }
}

private final class StubKeychainBackend: KeychainBackend {
    let copyStatus: OSStatus
    let copiedItem: CFTypeRef?
    let updateStatus: OSStatus
    let addStatus: OSStatus
    let deleteStatus: OSStatus
    private(set) var addCalls = 0

    init(
        copyStatus: OSStatus = errSecItemNotFound,
        copiedItem: CFTypeRef? = nil,
        updateStatus: OSStatus = errSecSuccess,
        addStatus: OSStatus = errSecSuccess,
        deleteStatus: OSStatus = errSecSuccess
    ) {
        self.copyStatus = copyStatus
        self.copiedItem = copiedItem
        self.updateStatus = updateStatus
        self.addStatus = addStatus
        self.deleteStatus = deleteStatus
    }

    func copyMatching(
        _ query: CFDictionary,
        result: UnsafeMutablePointer<CFTypeRef?>?
    ) -> OSStatus {
        result?.pointee = copiedItem
        return copyStatus
    }

    func update(_ query: CFDictionary, attributes: CFDictionary) -> OSStatus {
        updateStatus
    }

    func add(_ attributes: CFDictionary) -> OSStatus {
        addCalls += 1
        return addStatus
    }

    func delete(_ query: CFDictionary) -> OSStatus {
        deleteStatus
    }
}
