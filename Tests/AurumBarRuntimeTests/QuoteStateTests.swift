import AurumBarCore
import AurumBarRuntime
import Foundation
import XCTest

final class QuoteStateTests: XCTestCase {
    private let quote = GoldQuote(
        name: "Au99.99",
        price: "950.2",
        changePercent: "+0.1%",
        sourceTime: "2026-08-17 15:00:00"
    )

    func testFirstFailureUpdatesTooltip() {
        let presentation = StatusPresentation.make(
            for: .failed(message: "网络不可用", previous: nil)
        )

        XCTAssertEqual(presentation.statusTitle, "Au —")
        XCTAssertEqual(presentation.toolTip, "获取失败：网络不可用")
        XCTAssertTrue(presentation.isWarning)
    }

    func testFailureWithPreviousQuoteExplainsStalePrice() {
        let presentation = StatusPresentation.make(
            for: .failed(message: "超时", previous: quote)
        )

        XCTAssertEqual(presentation.statusTitle, "950.2")
        XCTAssertTrue(presentation.toolTip.contains("显示上次有效行情"))
        XCTAssertTrue(presentation.detailsText.contains("最近错误：超时"))
    }

    func testUnavailableIsNotWarning() {
        let presentation = StatusPresentation.make(for: .unavailable(previous: quote))

        XCTAssertFalse(presentation.isWarning)
        XCTAssertTrue(presentation.toolTip.contains("暂无新行情"))
    }

    func testErrorNotificationResetsAfterRecovery() {
        var policy = ErrorNotificationPolicy()
        let start = Date(timeIntervalSince1970: 1_000)

        XCTAssertTrue(policy.shouldNotify(message: "A", at: start, cooldown: 3_600))
        XCTAssertFalse(policy.shouldNotify(
            message: "A",
            at: start.addingTimeInterval(3_599),
            cooldown: 3_600
        ))
        XCTAssertTrue(policy.shouldNotify(
            message: "A",
            at: start.addingTimeInterval(3_600),
            cooldown: 3_600
        ))

        policy.reset()
        XCTAssertTrue(policy.shouldNotify(
            message: "A",
            at: start.addingTimeInterval(3_601),
            cooldown: 3_600
        ))
    }
}
