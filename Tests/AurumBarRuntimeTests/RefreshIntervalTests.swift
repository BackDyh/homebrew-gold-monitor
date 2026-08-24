import AurumBarRuntime
import Foundation
import XCTest

final class RefreshIntervalTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "RefreshIntervalTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testValidatesCustomMinuteInput() {
        XCTAssertEqual(RefreshInterval(minutesText: " 45 ")?.minutes, 45)
        XCTAssertNil(RefreshInterval(minutesText: "0"))
        XCTAssertNil(RefreshInterval(minutesText: "1441"))
        XCTAssertNil(RefreshInterval(minutesText: "1.5"))
        XCTAssertNil(RefreshInterval(minutesText: "abc"))
    }

    func testFormatsMinutesAndHours() {
        XCTAssertEqual(RefreshInterval(minutes: 15)?.displayText, "15 分钟")
        XCTAssertEqual(RefreshInterval(minutes: 60)?.displayText, "1 小时")
        XCTAssertEqual(RefreshInterval(minutes: 90)?.displayText, "1 小时 30 分钟")
    }

    func testStoreUsesDefaultAndPersistsCustomInterval() throws {
        let store = RefreshIntervalStore(defaults: defaults)

        XCTAssertEqual(store.load(), .defaultValue)

        let custom = try XCTUnwrap(RefreshInterval(minutes: 75))
        store.save(custom)

        XCTAssertEqual(store.load(), custom)
    }

    func testStoreFallsBackWhenPersistedValueIsInvalid() {
        defaults.set(0, forKey: "automatic-refresh-interval-minutes")

        XCTAssertEqual(
            RefreshIntervalStore(defaults: defaults).load(),
            .defaultValue
        )
    }
}
