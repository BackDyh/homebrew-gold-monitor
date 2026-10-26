import AurumBarRuntime
import Foundation
import XCTest

final class DailyRequestCounterTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "DailyRequestCounterTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testCountsRequestsAndReservesManualRefreshes() {
        let counter = DailyRequestCounter(defaults: defaults)
        let now = shanghai("2026-10-26 10:00")
        for _ in 0 ..< 3 { counter.record(at: now) }

        XCTAssertEqual(counter.count(on: now), 3)
        XCTAssertEqual(counter.remainingAutomatic(on: now), 50 - 5 - 3)
    }

    func testResetsAtShanghaiMidnight() {
        let counter = DailyRequestCounter(defaults: defaults)
        counter.record(at: shanghai("2026-10-26 23:59"))

        XCTAssertEqual(counter.count(on: shanghai("2026-10-26 23:59")), 1)
        XCTAssertEqual(counter.count(on: shanghai("2026-10-27 00:00")), 0)

        counter.record(at: shanghai("2026-10-27 00:01"))
        XCTAssertEqual(counter.count(on: shanghai("2026-10-27 00:01")), 1)
    }

    func testRemainingNeverGoesNegative() {
        let counter = DailyRequestCounter(defaults: defaults)
        let now = shanghai("2026-10-26 10:00")
        for _ in 0 ..< 60 { counter.record(at: now) }

        XCTAssertEqual(counter.remainingAutomatic(on: now), 0)
    }

    func testDailyLimitCanBeOverridden() {
        defaults.set(100, forKey: "daily-request-limit")
        let counter = DailyRequestCounter(defaults: defaults)

        XCTAssertEqual(counter.dailyLimit, 100)
        XCTAssertEqual(counter.remainingAutomatic(on: shanghai("2026-10-26 10:00")), 95)
    }

    private func shanghai(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: text)!
    }
}
