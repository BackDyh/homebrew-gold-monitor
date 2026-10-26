import AurumBarRuntime
import Foundation
import Security
import XCTest

final class AppKeyStoreTests: XCTestCase {
    private var directory: URL!
    private var fileURL: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppKeyStoreTests-\(UUID().uuidString)")
        fileURL = directory.appendingPathComponent("AurumBar/appkey")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testSaveWritesOwnerOnlyFileAndLoadsIt() throws {
        let store = AppKeyStore(fileURL: fileURL, legacyKeychain: nil)
        try store.save("secret")

        XCTAssertEqual(try store.load(), "secret")
        XCTAssertEqual(try permissions(of: fileURL), 0o600)
        XCTAssertEqual(try permissions(of: fileURL.deletingLastPathComponent()), 0o700)
    }

    func testSaveReplacesExistingKey() throws {
        let store = AppKeyStore(fileURL: fileURL, legacyKeychain: nil)
        try store.save("old")
        try store.save("new")

        XCTAssertEqual(try store.load(), "new")
    }

    func testLoadTightensLoosePermissionsAndTrimsWhitespace() throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("  secret\n".utf8).write(to: fileURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: fileURL.path)

        let store = AppKeyStore(fileURL: fileURL, legacyKeychain: nil)
        XCTAssertEqual(try store.load(), "secret")
        XCTAssertEqual(try permissions(of: fileURL), 0o600)
    }

    func testMigratesFromKeychainOnceAndRemovesLegacyItem() throws {
        let backend = InMemoryKeychainBackend(value: "legacy")
        let store = AppKeyStore(fileURL: fileURL, legacyKeychain: KeychainStore(backend: backend))

        XCTAssertEqual(try store.load(), "legacy")
        XCTAssertNil(backend.value)
        XCTAssertEqual(backend.reads, 1)

        XCTAssertEqual(try store.load(), "legacy")
        XCTAssertEqual(backend.reads, 1)
    }

    func testDeniedKeychainMigrationFallsBackToPrompt() throws {
        let backend = InMemoryKeychainBackend(value: "legacy", copyStatus: errSecAuthFailed)
        let store = AppKeyStore(fileURL: fileURL, legacyKeychain: KeychainStore(backend: backend))

        XCTAssertNil(try store.load())
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testDeleteRemovesFileAndLegacyItem() throws {
        let backend = InMemoryKeychainBackend(value: "legacy")
        let store = AppKeyStore(fileURL: fileURL, legacyKeychain: KeychainStore(backend: backend))
        try store.save("secret")

        try store.delete()
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertNil(backend.value)
        XCTAssertNil(try store.load())

        try store.delete()
    }

    private func permissions(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as! NSNumber).intValue
    }
}

private final class InMemoryKeychainBackend: KeychainBackend {
    private(set) var value: String?
    private(set) var reads = 0
    private let copyStatus: OSStatus

    init(value: String?, copyStatus: OSStatus = errSecSuccess) {
        self.value = value
        self.copyStatus = copyStatus
    }

    func copyMatching(_ query: CFDictionary, result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
        reads += 1
        guard copyStatus == errSecSuccess else { return copyStatus }
        guard let value else { return errSecItemNotFound }
        result?.pointee = Data(value.utf8) as CFData
        return errSecSuccess
    }

    func update(_ query: CFDictionary, attributes: CFDictionary) -> OSStatus {
        errSecItemNotFound
    }

    func add(_ attributes: CFDictionary) -> OSStatus {
        errSecSuccess
    }

    func delete(_ query: CFDictionary) -> OSStatus {
        guard value != nil else { return errSecItemNotFound }
        value = nil
        return errSecSuccess
    }
}
