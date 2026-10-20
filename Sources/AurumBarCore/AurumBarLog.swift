import Foundation

public enum AurumBarLog {
    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        return formatter
    }()
    private static let lock = NSLock()

    public static func write(_ message: String, date: Date = Date()) {
        let line = lock.withLock { "\(formatter.string(from: date)) AurumBar: \(message)\n" }
        fputs(line, stderr)
    }
}
