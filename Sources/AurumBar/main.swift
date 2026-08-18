import AppKit
import AurumBarCore
import AurumBarRuntime
import Darwin

private let alreadyRunningExitCode: Int32 = 75

public enum RuntimeControl {
    public static let stopNotification = Notification.Name("com.back.aurumbar.stop")
    private static let fileManager = FileManager.default

    private static var applicationSupportURL: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AurumBar", isDirectory: true)
    }

    public static var lockFileURL: URL {
        applicationSupportURL.appendingPathComponent("aurumbar.lock")
    }

    private static var logFileURL: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/AurumBar/aurumbar.log")
    }

    public static func startInBackground() throws {
        try fileManager.createDirectory(
            at: logFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        if !fileManager.fileExists(atPath: logFileURL.path) {
            guard fileManager.createFile(
                atPath: logFileURL.path,
                contents: nil,
                attributes: [.posixPermissions: 0o600]
            ) else {
                throw RuntimeControlError.logFileUnavailable
            }
        }

        let logHandle = try FileHandle(forWritingTo: logFileURL)
        defer { try? logHandle.close() }
        try logHandle.seekToEnd()
        guard let inputHandle = FileHandle(forReadingAtPath: "/dev/null") else {
            throw RuntimeControlError.standardInputUnavailable
        }
        defer { try? inputHandle.close() }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nohup")
        process.arguments = [try currentExecutablePath(), "run"]
        process.standardInput = inputHandle
        process.standardOutput = logHandle
        process.standardError = logHandle
        try process.run()

        Thread.sleep(forTimeInterval: 0.2)
        guard !process.isRunning else { return }
        if process.terminationStatus == alreadyRunningExitCode {
            return
        }
        throw RuntimeControlError.launchFailed(process.terminationStatus)
    }

    public static func requestStop() {
        DistributedNotificationCenter.default().postNotificationName(
            stopNotification,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
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

public enum RuntimeControlError: LocalizedError {
    case executablePathUnavailable
    case launchFailed(Int32)
    case logFileUnavailable
    case standardInputUnavailable

    public var errorDescription: String? {
        switch self {
        case .executablePathUnavailable:
            return "无法确定 AurumBar 可执行文件路径"
        case let .launchFailed(status):
            return "AurumBar 后台进程启动失败（退出码 \(status)）"
        case .logFileUnavailable:
            return "无法创建 AurumBar 日志文件"
        case .standardInputUnavailable:
            return "无法打开 /dev/null"
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
    print("AurumBar \(AurumBarVersion.current)")
    exit(0)
case "--reset-key":
    do {
        try KeychainStore().delete()
        print("已删除 AurumBar AppKey，下次启动会重新提示。")
        exit(0)
    } catch {
        fputs("\(error.localizedDescription)\n", stderr)
        exit(1)
    }
case "--help", "-h", nil:
    printHelp()
    exit(0)
case "start":
    guard arguments.count == 1 else {
        fputs("错误：start 不接受其他参数\n", stderr)
        exit(64)
    }
    do {
        try RuntimeControl.startInBackground()
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

let instanceLock: SingleInstanceLock
do {
    instanceLock = try SingleInstanceLock(fileURL: RuntimeControl.lockFileURL)
} catch SingleInstanceLockError.alreadyLocked {
    fputs("AurumBar: 已有一个实例在运行\n", stderr)
    exit(alreadyRunningExitCode)
} catch {
    fputs("\(error.localizedDescription)\n", stderr)
    exit(1)
}

let application = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
application.setActivationPolicy(.accessory)
application.delegate = delegate
application.run()
_ = instanceLock
