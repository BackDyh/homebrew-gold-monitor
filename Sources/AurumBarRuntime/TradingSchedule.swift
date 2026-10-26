import Foundation

/// 上海黄金交易所竞价市场交易时段：周一至周五日盘 9:00–15:30，夜盘 20:00–次日 02:30。
/// 法定节假日休市安排以交易所公告为准，这里不做处理。
public struct TradingSchedule: Sendable {
    public struct Session: Equatable, Sendable {
        public let start: Date
        public let end: Date

        public func contains(_ date: Date) -> Bool {
            start <= date && date < end
        }
    }

    private struct SessionTemplate {
        let startMinute: Int
        let durationMinutes: Int
    }

    private static let weekdaySessions = [
        SessionTemplate(startMinute: 9 * 60, durationMinutes: 6 * 60 + 30),
        SessionTemplate(startMinute: 20 * 60, durationMinutes: 6 * 60 + 30),
    ]

    public static let shanghaiGold = TradingSchedule()

    private let calendar: Calendar

    public init(timeZone: TimeZone = TimeZone(identifier: "Asia/Shanghai")!) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        self.calendar = calendar
    }

    public func isOpen(at date: Date) -> Bool {
        session(containing: date) != nil
    }

    public func session(containing date: Date) -> Session? {
        sessions(around: date).first { $0.contains(date) }
    }

    public func nextSession(after date: Date) -> Session {
        // 一周内必有交易日，往后查 8 天足够。
        sessions(around: date).first { $0.start > date }!
    }

    public func lastClose(atOrBefore date: Date) -> Date? {
        sessions(around: date).last { $0.end <= date }?.end
    }

    public func startOfNextDay(after date: Date) -> Date {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))!
    }

    public func dayKey(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year!, components.month!, components.day!)
    }

    public func openDuration(from start: Date, to end: Date) -> TimeInterval {
        sessions(around: start).reduce(0) { total, session in
            let overlap = min(end, session.end).timeIntervalSince(max(start, session.start))
            return total + max(0, overlap)
        }
    }

    private func sessions(around date: Date) -> [Session] {
        let today = calendar.startOfDay(for: date)
        return (-3 ... 8).flatMap { offset -> [Session] in
            guard
                let day = calendar.date(byAdding: .day, value: offset, to: today),
                (2 ... 6).contains(calendar.component(.weekday, from: day))
            else {
                return []
            }
            return Self.weekdaySessions.compactMap { template in
                guard let start = calendar.date(
                    byAdding: .minute,
                    value: template.startMinute,
                    to: day
                ) else {
                    return nil
                }
                return Session(
                    start: start,
                    end: start.addingTimeInterval(TimeInterval(template.durationMinutes * 60))
                )
            }
        }
    }
}

public enum RefreshPlanner {
    /// 开盘或收盘后稍等片刻再请求，避开接口在整点切换时返回的空行情。
    public static let sessionBoundaryDelay: TimeInterval = 60

    /// `remainingRequests` 为今天还能用于自动刷新的次数；传入后会拉长间隔，
    /// 让剩余次数覆盖到今天剩下的开盘时间，用完则等到次日开盘。
    public static func nextRefresh(
        after date: Date,
        interval: RefreshInterval,
        remainingRequests: Int? = nil,
        schedule: TradingSchedule = .shanghaiGold
    ) -> Date {
        if let remainingRequests, remainingRequests <= 0 {
            return firstRefresh(atOrAfter: schedule.startOfNextDay(after: date), schedule: schedule)
        }
        if let session = schedule.session(containing: date) {
            var spacing = interval.timeInterval
            if let remainingRequests {
                let openLeft = schedule.openDuration(
                    from: date,
                    to: schedule.startOfNextDay(after: date)
                )
                spacing = max(spacing, openLeft / Double(remainingRequests))
            }
            let candidate = date.addingTimeInterval(spacing)
            if candidate < session.end {
                return candidate
            }
            return session.end.addingTimeInterval(sessionBoundaryDelay)
        }
        return schedule.nextSession(after: date).start.addingTimeInterval(sessionBoundaryDelay)
    }

    public static func firstRefresh(
        atOrAfter date: Date,
        schedule: TradingSchedule = .shanghaiGold
    ) -> Date {
        if schedule.isOpen(at: date) { return date }
        return schedule.nextSession(after: date).start.addingTimeInterval(sessionBoundaryDelay)
    }

    /// 休市期间唤醒或启动时，只有在错过了最近一次收盘价时才需要补刷。
    public static func shouldRefreshOnResume(
        at date: Date,
        lastSuccess: Date?,
        schedule: TradingSchedule = .shanghaiGold
    ) -> Bool {
        if schedule.isOpen(at: date) { return true }
        guard let lastSuccess else { return true }
        guard let close = schedule.lastClose(atOrBefore: date) else { return false }
        return lastSuccess < close
    }
}
