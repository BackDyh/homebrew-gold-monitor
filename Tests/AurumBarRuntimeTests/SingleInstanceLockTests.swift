import AurumBarRuntime
import Foundation
import XCTest

final class SingleInstanceLockTests: XCTestCase {
    func testOnlyOneOwnerCanHoldLock() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("aurumbar.lock")

        var first: SingleInstanceLock? = try SingleInstanceLock(
            fileURL: fileURL,
            processID: 123
        )
        XCTAssertThrowsError(try SingleInstanceLock(fileURL: fileURL, processID: 456)) {
            XCTAssertEqual($0 as? SingleInstanceLockError, .alreadyLocked)
        }

        first = nil
        XCTAssertNoThrow(try SingleInstanceLock(fileURL: fileURL, processID: 456))
        _ = first
    }

    func testStalePIDContentDoesNotPreventLock() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("aurumbar.lock")
        try "99999\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let lock = try SingleInstanceLock(fileURL: fileURL, processID: 321)
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "321\n")
        _ = lock
    }
}
