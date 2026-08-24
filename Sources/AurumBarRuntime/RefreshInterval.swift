import Foundation

public struct RefreshInterval: Equatable, Sendable {
    public static let allowedMinutes = 1 ... 24 * 60
    public static let defaultValue = RefreshInterval(minutes: 30)!

    public let minutes: Int

    public init?(minutes: Int) {
        guard Self.allowedMinutes.contains(minutes) else { return nil }
        self.minutes = minutes
    }

    public init?(minutesText: String) {
        let value = minutesText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let minutes = Int(value) else { return nil }
        self.init(minutes: minutes)
    }

    public var timeInterval: TimeInterval {
        TimeInterval(minutes * 60)
    }

    public var displayText: String {
        guard minutes >= 60 else { return "\(minutes) 分钟" }

        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        guard remainingMinutes > 0 else { return "\(hours) 小时" }
        return "\(hours) 小时 \(remainingMinutes) 分钟"
    }
}

public final class RefreshIntervalStore {
    private let defaults: UserDefaults
    private let intervalKey = "automatic-refresh-interval-minutes"

    public init(defaults: UserDefaults? = UserDefaults(suiteName: "com.back.aurumbar")) {
        self.defaults = defaults ?? .standard
    }

    public func load() -> RefreshInterval {
        RefreshInterval(minutes: defaults.integer(forKey: intervalKey)) ?? .defaultValue
    }

    public func save(_ interval: RefreshInterval) {
        defaults.set(interval.minutes, forKey: intervalKey)
    }
}
