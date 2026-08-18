import Testing
import AurumBarRuntime
import Foundation

struct SingleInstanceLockTests {
    @Test func onlyOneOwnerCanHoldLock() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("aurumbar.lock")

        var first: SingleInstanceLock? = try SingleInstanceLock(
            fileURL: fileURL,
            processID: 123
        )
        #expect(throws: SingleInstanceLockError.alreadyLocked) {
            try SingleInstanceLock(fileURL: fileURL, processID: 456)
        }

        first = nil
        _ = try SingleInstanceLock(fileURL: fileURL, processID: 456)
        _ = first
    }

    @Test func stalePIDContentDoesNotPreventLock() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("aurumbar.lock")
        try "99999\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let lock = try SingleInstanceLock(fileURL: fileURL, processID: 321)
        #expect(try String(contentsOf: fileURL, encoding: .utf8) == "321\n")
        _ = lock
    }
}
