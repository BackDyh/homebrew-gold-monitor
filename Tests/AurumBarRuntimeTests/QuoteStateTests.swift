import Testing
import AurumBarCore
import AurumBarRuntime
import Foundation

struct QuoteStateTests {
    private let quote = GoldQuote(
        name: "Au99.99",
        price: "950.2",
        changePercent: "+0.1%",
        sourceTime: "2026-08-17 15:00:00"
    )

    @Test func firstFailureUpdatesTooltip() {
        let presentation = StatusPresentation.make(
            for: .failed(message: "网络不可用", previous: nil)
        )

        #expect(presentation.statusTitle == "Au —")
        #expect(presentation.toolTip == "获取失败：网络不可用")
        #expect(presentation.isWarning)
    }

    @Test func failureWithPreviousQuoteExplainsStalePrice() {
        let presentation = StatusPresentation.make(
            for: .failed(message: "超时", previous: quote)
        )

        #expect(presentation.statusTitle == "950.2")
        #expect(presentation.toolTip.contains("显示上次有效行情"))
        #expect(presentation.detailsText.contains("最近错误：超时"))
    }

    @Test func unavailableIsNotWarning() {
        let presentation = StatusPresentation.make(for: .unavailable(previous: quote))

        #expect(!presentation.isWarning)
        #expect(presentation.toolTip.contains("暂无新行情"))
    }

    @Test func errorNotificationResetsAfterRecovery() {
        var policy = ErrorNotificationPolicy()
        let start = Date(timeIntervalSince1970: 1_000)

        let first = policy.shouldNotify(message: "A", at: start, cooldown: 3_600)
        #expect(first)
        let suppressed = policy.shouldNotify(
            message: "A",
            at: start.addingTimeInterval(3_599),
            cooldown: 3_600
        )
        #expect(!suppressed)
        let afterCooldown = policy.shouldNotify(
            message: "A",
            at: start.addingTimeInterval(3_600),
            cooldown: 3_600
        )
        #expect(afterCooldown)

        policy.reset()
        let afterReset = policy.shouldNotify(
            message: "A",
            at: start.addingTimeInterval(3_601),
            cooldown: 3_600
        )
        #expect(afterReset)
    }
}
