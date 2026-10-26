import AurumBarRuntime
import Foundation
import XCTest

final class TradingScheduleTests: XCTestCase {
    private let schedule = TradingSchedule.shanghaiGold
    private let thirtyMinutes = RefreshInterval(minutes: 30)!

    func testDaySessionBoundaries() {
        // 2026-10-26 是周一。
        XCTAssertFalse(schedule.isOpen(at: date("2026-10-26 08:59")))
        XCTAssertTrue(schedule.isOpen(at: date("2026-10-26 09:00")))
        XCTAssertTrue(schedule.isOpen(at: date("2026-10-26 12:00")))
        XCTAssertTrue(schedule.isOpen(at: date("2026-10-26 15:29")))
        XCTAssertFalse(schedule.isOpen(at: date("2026-10-26 15:30")))
        XCTAssertFalse(schedule.isOpen(at: date("2026-10-26 19:59")))
    }

    func testNightSessionCrossesMidnight() {
        XCTAssertTrue(schedule.isOpen(at: date("2026-10-26 20:00")))
        XCTAssertTrue(schedule.isOpen(at: date("2026-10-27 01:00")))
        XCTAssertFalse(schedule.isOpen(at: date("2026-10-27 02:30")))
        XCTAssertFalse(schedule.isOpen(at: date("2026-10-27 08:00")))
    }

    func testWeekendIsClosedExceptFridayNightSession() {
        XCTAssertTrue(schedule.isOpen(at: date("2026-10-31 02:00")))
        XCTAssertFalse(schedule.isOpen(at: date("2026-10-31 02:30")))
        XCTAssertFalse(schedule.isOpen(at: date("2026-10-31 10:00")))
        XCTAssertFalse(schedule.isOpen(at: date("2026-10-31 21:00")))
        XCTAssertFalse(schedule.isOpen(at: date("2026-11-01 21:00")))
        XCTAssertFalse(schedule.isOpen(at: date("2026-11-02 01:00")))
    }

    func testInterpretsTimesInShanghaiRegardlessOfLocalTimeZone() {
        let utcNineAM = ISO8601DateFormatter().date(from: "2026-10-26T01:00:00Z")!
        XCTAssertTrue(schedule.isOpen(at: utcNineAM))
    }

    func testRefreshesAtIntervalDuringSession() {
        XCTAssertEqual(
            RefreshPlanner.nextRefresh(after: date("2026-10-26 10:00"), interval: thirtyMinutes),
            date("2026-10-26 10:30")
        )
    }

    func testRefreshesOnceAfterCloseThenWaitsForNextSession() {
        XCTAssertEqual(
            RefreshPlanner.nextRefresh(after: date("2026-10-26 15:10"), interval: thirtyMinutes),
            date("2026-10-26 15:31")
        )
        XCTAssertEqual(
            RefreshPlanner.nextRefresh(after: date("2026-10-26 15:31"), interval: thirtyMinutes),
            date("2026-10-26 20:01")
        )
    }

    func testWeekendWaitsUntilMondayMorning() {
        XCTAssertEqual(
            RefreshPlanner.nextRefresh(after: date("2026-10-31 02:31"), interval: thirtyMinutes),
            date("2026-11-02 09:01")
        )
        XCTAssertEqual(
            RefreshPlanner.nextRefresh(after: date("2026-11-01 12:00"), interval: thirtyMinutes),
            date("2026-11-02 09:01")
        )
    }

    func testOnlyClosingRefreshesHappenOutsideSessionsOverWeekend() {
        var cursor = date("2026-10-30 15:00")
        let end = date("2026-11-02 09:00")
        var count = 0
        while true {
            cursor = RefreshPlanner.nextRefresh(after: cursor, interval: thirtyMinutes)
            guard cursor < end else { break }
            if !schedule.isOpen(at: cursor) { count += 1 }
        }
        XCTAssertEqual(count, 2)
    }

    func testBudgetKeepsShortIntervalWithinDailyLimit() {
        let tenMinutes = RefreshInterval(minutes: 10)!
        let budget = DailyRequestCounter.defaultDailyLimit - DailyRequestCounter.manualReserve
        // 周二的自然日包含周一夜盘后半段、日盘和周二夜盘前半段，开盘时间最长。
        var cursor = date("2026-10-27 00:00")
        let end = date("2026-10-28 00:00")
        var used = 1
        while true {
            cursor = RefreshPlanner.nextRefresh(
                after: cursor,
                interval: tenMinutes,
                remainingRequests: budget - used
            )
            guard cursor < end else { break }
            used += 1
        }

        XCTAssertLessThanOrEqual(used, budget)
        XCTAssertGreaterThan(used, budget - 5)
    }

    func testBudgetDoesNotSlowDownComfortableInterval() {
        XCTAssertEqual(
            RefreshPlanner.nextRefresh(
                after: date("2026-10-26 10:00"),
                interval: thirtyMinutes,
                remainingRequests: 40
            ),
            date("2026-10-26 10:30")
        )
    }

    func testExhaustedBudgetWaitsForNextDayOpen() {
        XCTAssertEqual(
            RefreshPlanner.nextRefresh(
                after: date("2026-10-26 10:00"),
                interval: thirtyMinutes,
                remainingRequests: 0
            ),
            date("2026-10-27 00:00")
        )
        XCTAssertEqual(
            RefreshPlanner.nextRefresh(
                after: date("2026-10-30 22:00"),
                interval: thirtyMinutes,
                remainingRequests: 0
            ),
            date("2026-10-31 00:00")
        )
    }

    func testOpenDurationAcrossCalendarDay() {
        let tuesday = date("2026-10-27 00:00")
        let duration = schedule.openDuration(from: tuesday, to: schedule.startOfNextDay(after: tuesday))
        XCTAssertEqual(duration, TimeInterval((150 + 390 + 240) * 60))
    }

    func testFirstRefreshAfterQuotaPause() {
        XCTAssertEqual(
            RefreshPlanner.firstRefresh(atOrAfter: date("2026-10-27 00:00")),
            date("2026-10-27 00:00")
        )
        XCTAssertEqual(
            RefreshPlanner.firstRefresh(atOrAfter: date("2026-11-01 00:00")),
            date("2026-11-02 09:01")
        )
    }

    func testResumeRefreshesOnlyWhenOpenOrClosingPriceMissed() {
        let night = date("2026-10-26 17:00")
        XCTAssertTrue(RefreshPlanner.shouldRefreshOnResume(at: date("2026-10-26 10:00"), lastSuccess: night))
        XCTAssertTrue(RefreshPlanner.shouldRefreshOnResume(at: night, lastSuccess: nil))
        XCTAssertTrue(RefreshPlanner.shouldRefreshOnResume(at: night, lastSuccess: date("2026-10-26 14:00")))
        XCTAssertFalse(RefreshPlanner.shouldRefreshOnResume(at: night, lastSuccess: date("2026-10-26 15:31")))
    }

    private func date(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: text)!
    }
}
