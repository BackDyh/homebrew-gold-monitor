import AurumBarRuntime
import Foundation
import Security
import XCTest

final class KeychainStoreTests: XCTestCase {
    func testLoadDistinguishesNotFoundFromFailure() throws {
        let missing = StubKeychainBackend(copyStatus: errSecItemNotFound)
        XCTAssertNil(try KeychainStore(backend: missing).load())

        let denied = StubKeychainBackend(copyStatus: errSecAuthFailed)
        XCTAssertThrowsError(try KeychainStore(backend: denied).load()) {
            XCTAssertEqual(
                $0 as? KeychainError,
                .status(operation: .read, status: errSecAuthFailed)
            )
        }
    }

    func testLoadRejectsInvalidData() {
        let backend = StubKeychainBackend(
            copyStatus: errSecSuccess,
            copiedItem: Data([0xFF]) as CFData
        )
        XCTAssertThrowsError(try KeychainStore(backend: backend).load()) {
            XCTAssertEqual($0 as? KeychainError, .invalidData)
        }
    }

    func testSaveFallsBackToAdd() throws {
        let backend = StubKeychainBackend(
            updateStatus: errSecItemNotFound,
            addStatus: errSecSuccess
        )
        try KeychainStore(backend: backend).save("secret")
        XCTAssertEqual(backend.addCalls, 1)
    }

    func testDeleteIsIdempotentButPropagatesFailure() throws {
        try KeychainStore(
            backend: StubKeychainBackend(deleteStatus: errSecItemNotFound)
        ).delete()

        let denied = StubKeychainBackend(deleteStatus: errSecAuthFailed)
        XCTAssertThrowsError(try KeychainStore(backend: denied).delete()) {
            XCTAssertEqual(
                $0 as? KeychainError,
                .status(operation: .delete, status: errSecAuthFailed)
            )
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
