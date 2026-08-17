import AppKit
import Darwin

enum RuntimeControl {
    static let stopNotification = Notification.Name("com.back.aurumbar.stop")
    private static let fileManager = FileManager.default

    private static var applicationSupportURL: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AurumBar", isDirectory: true)
    }

    private static var pidFileURL: URL {
        applicationSupportURL.appendingPathComponent("aurumbar.pid")
    }

    private static var logFileURL: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/AurumBar/aurumbar.log")
    }

    static func startInBackground() throws -> pid_t {
        if let runningPID = runningProcessID() {
            throw RuntimeControlError.alreadyRunning(runningPID)
        }

        try fileManager.createDirectory(
            at: logFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !fileManager.fileExists(atPath: logFileURL.path) {
            fileManager.createFile(atPath: logFileURL.path, contents: nil)
        }

        let logHandle = try FileHandle(forWritingTo: logFileURL)
        try logHandle.seekToEnd()
        let inputHandle = FileHandle(forReadingAtPath: "/dev/null")!
        let executablePath = try currentExecutablePath()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nohup")
        process.arguments = [executablePath, "run"]
        process.standardInput = inputHandle
        process.standardOutput = logHandle
        process.standardError = logHandle
        try process.run()
        try writeProcessID(process.processIdentifier)

        Thread.sleep(forTimeInterval: 0.15)
        guard process.isRunning else {
            try? fileManager.removeItem(at: pidFileURL)
            throw RuntimeControlError.launchFailed(process.terminationStatus)
        }
        return process.processIdentifier
    }

    static func claimCurrentProcess() -> Bool {
        let currentPID = getpid()
        if let runningPID = runningProcessID(), runningPID != currentPID {
            return false
        }
        do {
            try writeProcessID(currentPID)
            return true
        } catch {
            fputs("AurumBar: 无法写入 PID 文件：\(error.localizedDescription)\n", stderr)
            return false
        }
    }

    static func clearCurrentProcess() {
        guard runningProcessID() == getpid() else { return }
        try? fileManager.removeItem(at: pidFileURL)
    }

    static func requestStop() {
        DistributedNotificationCenter.default().postNotificationName(
            stopNotification,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    private static func runningProcessID() -> pid_t? {
        guard
            let rawPID = try? String(contentsOf: pidFileURL, encoding: .utf8),
            let pid = pid_t(rawPID.trimmingCharacters(in: .whitespacesAndNewlines)),
            pid > 1
        else {
            return nil
        }

        if kill(pid, 0) == 0 || errno == EPERM {
            return pid
        }
        try? fileManager.removeItem(at: pidFileURL)
        return nil
    }

    private static func writeProcessID(_ pid: pid_t) throws {
        try fileManager.createDirectory(
            at: applicationSupportURL,
            withIntermediateDirectories: true
        )
        try String(pid).write(to: pidFileURL, atomically: true, encoding: .utf8)
    }

    private static func currentExecutablePath() throws -> String {
        var size: UInt32 = 0
        _NSGetExecutablePath(nil, &size)
        var buffer = [CChar](repeating: 0, count: Int(size))
        guard _NSGetExecutablePath(&buffer, &size) == 0 else {
            throw RuntimeControlError.executablePathUnavailable
        }
        return URL(fileURLWithPath: String(cString: buffer))
            .resolvingSymlinksInPath()
            .path
    }
}

enum RuntimeControlError: LocalizedError {
    case alreadyRunning(pid_t)
    case executablePathUnavailable
    case launchFailed(Int32)

    var errorDescription: String? {
        switch self {
        case let .alreadyRunning(pid):
            return "AurumBar 已在运行（PID \(pid)）"
        case .executablePathUnavailable:
            return "无法确定 AurumBar 可执行文件路径"
        case let .launchFailed(status):
            return "AurumBar 后台进程启动失败（退出码 \(status)）"
        }
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())

func printHelp() {
    print("""
    AurumBar - macOS 菜单栏 Au99.99 黄金价格监控

    用法：
      aurumbar start        静默地在后台启动菜单栏监控
      aurumbar stop         停止正在运行的监控
      aurumbar --version    显示版本
      aurumbar --reset-key  删除钥匙串中的 AppKey
      aurumbar --help       显示帮助
    """)
}

switch arguments.first {
case "--version":
    print("AurumBar 0.1.2")
    exit(0)
case "--reset-key":
    KeychainStore().delete()
    print("已删除 AurumBar AppKey，下次启动会重新提示。")
    exit(0)
case "--help", "-h", nil:
    printHelp()
    exit(0)
case "start":
    guard arguments.count == 1 else {
        fputs("错误：start 不接受其他参数\n", stderr)
        exit(64)
    }
    do {
        _ = try RuntimeControl.startInBackground()
        exit(0)
    } catch RuntimeControlError.alreadyRunning {
        exit(0)
    } catch {
        fputs("\(error.localizedDescription)\n", stderr)
        exit(1)
    }
case "stop":
    guard arguments.count == 1 else {
        fputs("错误：stop 不接受其他参数\n", stderr)
        exit(64)
    }
    RuntimeControl.requestStop()
    print("已发送 AurumBar 停止请求。")
    exit(0)
case "run":
    guard arguments.count == 1 else {
        fputs("错误：run 不接受其他参数\n", stderr)
        exit(64)
    }
default:
    fputs("错误：未知命令 \(arguments[0])\n\n", stderr)
    printHelp()
    exit(64)
}

let application = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
application.setActivationPolicy(.accessory)
application.delegate = delegate
application.run()
