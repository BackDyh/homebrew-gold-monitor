import Foundation

/// 聚合数据按北京时间自然日重置调用额度，这里按同样的口径计数。
public final class DailyRequestCounter {
    public static let defaultDailyLimit = 50
    public static let manualReserve = 5

    private let defaults: UserDefaults
    private let schedule: TradingSchedule
    private let dayKey = "request-count-day"
    private let countKey = "request-count"
    private let limitKey = "daily-request-limit"

    public init(
        defaults: UserDefaults? = UserDefaults(suiteName: "com.back.aurumbar"),
        schedule: TradingSchedule = .shanghaiGold
    ) {
        self.defaults = defaults ?? .standard
        self.schedule = schedule
    }

    public var dailyLimit: Int {
        let stored = defaults.integer(forKey: limitKey)
        return stored > 0 ? stored : Self.defaultDailyLimit
    }

    public func count(on date: Date = Date()) -> Int {
        guard defaults.string(forKey: dayKey) == schedule.dayKey(for: date) else { return 0 }
        return defaults.integer(forKey: countKey)
    }

    public func record(at date: Date = Date()) {
        let today = schedule.dayKey(for: date)
        let current = count(on: date)
        defaults.set(today, forKey: dayKey)
        defaults.set(current + 1, forKey: countKey)
    }

    public func remainingAutomatic(on date: Date = Date()) -> Int {
        max(0, dailyLimit - Self.manualReserve - count(on: date))
    }
}
