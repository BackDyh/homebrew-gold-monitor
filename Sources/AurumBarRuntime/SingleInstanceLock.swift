import Darwin
import Foundation

public final class SingleInstanceLock {
    private let fileDescriptor: Int32

    public init(fileURL: URL, processID: pid_t = getpid()) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let descriptor = open(fileURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            throw SingleInstanceLockError.openFailed(errno)
        }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let error = errno
            close(descriptor)
            if error == EWOULDBLOCK {
                throw SingleInstanceLockError.alreadyLocked
            }
            throw SingleInstanceLockError.lockFailed(error)
        }

        guard ftruncate(descriptor, 0) == 0 else {
            let error = errno
            close(descriptor)
            throw SingleInstanceLockError.writeFailed(error)
        }
        let contents = "\(processID)\n"
        let writeResult = contents.withCString { pointer in
            write(descriptor, pointer, strlen(pointer))
        }
        guard writeResult == contents.utf8.count else {
            let error = errno
            close(descriptor)
            throw SingleInstanceLockError.writeFailed(error)
        }

        fileDescriptor = descriptor
    }

    deinit {
        flock(fileDescriptor, LOCK_UN)
        close(fileDescriptor)
    }
}

public enum SingleInstanceLockError: LocalizedError, Equatable {
    case alreadyLocked
    case openFailed(Int32)
    case lockFailed(Int32)
    case writeFailed(Int32)

    public var errorDescription: String? {
        switch self {
        case .alreadyLocked:
            return "AurumBar 已在运行"
        case let .openFailed(code):
            return "无法打开 AurumBar 运行锁：\(String(cString: strerror(code)))"
        case let .lockFailed(code):
            return "无法获取 AurumBar 运行锁：\(String(cString: strerror(code)))"
        case let .writeFailed(code):
            return "无法写入 AurumBar 运行锁：\(String(cString: strerror(code)))"
        }
    }
}
