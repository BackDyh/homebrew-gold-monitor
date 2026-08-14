import Foundation

struct AppleScriptNotifier {
    private static let script = """
    on run argv
      display notification (item 2 of argv) with title (item 1 of argv)
    end run
    """

    func send(title: String, message: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e",
            Self.script,
            "--",
            title,
            message,
        ]
        do {
            try process.run()
        } catch {
            fputs("AurumBar notification failed: \(error)\n", stderr)
        }
    }
}
