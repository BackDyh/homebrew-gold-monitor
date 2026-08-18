import AurumBarCore
import Foundation

public enum QuoteViewState: Equatable {
    case starting(previous: GoldQuote?)
    case available(GoldQuote)
    case unavailable(previous: GoldQuote?)
    case failed(message: String, previous: GoldQuote?)
}

public struct StatusPresentation: Equatable {
    public let statusTitle: String
    public let toolTip: String
    public let infoTitle: String
    public let detailsText: String
    public let isWarning: Bool

    public static func make(for state: QuoteViewState) -> StatusPresentation {
        switch state {
        case let .starting(previous):
            if let quote = previous {
                return StatusPresentation(
                    statusTitle: menuPrice(quote.price),
                    toolTip: "正在刷新，显示上次有效行情：\(quote.price) 元/克",
                    infoTitle: "\(quote.price) 元/克（刷新中…）",
                    detailsText: quoteDetails(quote, status: "正在刷新"),
                    isWarning: false
                )
            }
            return StatusPresentation(
                statusTitle: "Au —",
                toolTip: "AurumBar 正在获取行情",
                infoTitle: "正在获取行情…",
                detailsText: "正在获取行情",
                isWarning: false
            )

        case let .available(quote):
            return StatusPresentation(
                statusTitle: menuPrice(quote.price),
                toolTip: "\(quote.name)：\(quote.price) 元/克（\(quote.changePercent)）",
                infoTitle: "\(quote.price) 元/克  \(quote.changePercent)",
                detailsText: quoteDetails(quote, status: "正常"),
                isWarning: false
            )

        case let .unavailable(previous):
            if let quote = previous {
                return StatusPresentation(
                    statusTitle: menuPrice(quote.price),
                    toolTip: "暂无新行情，显示上次有效价格：\(quote.price) 元/克",
                    infoTitle: "\(quote.price) 元/克（上次有效行情）",
                    detailsText: quoteDetails(quote, status: "暂无新行情，显示上次有效价格"),
                    isWarning: false
                )
            }
            return StatusPresentation(
                statusTitle: "Au —",
                toolTip: "接口暂时没有返回有效行情",
                infoTitle: "暂时没有可用行情",
                detailsText: "接口暂时没有返回有效行情",
                isWarning: false
            )

        case let .failed(message, previous):
            if let quote = previous {
                return StatusPresentation(
                    statusTitle: menuPrice(quote.price),
                    toolTip: "显示上次有效行情；最近刷新失败：\(message)",
                    infoTitle: "最近一次刷新失败",
                    detailsText: quoteDetails(quote, status: "最近错误：\(message)"),
                    isWarning: true
                )
            }
            return StatusPresentation(
                statusTitle: "Au —",
                toolTip: "获取失败：\(message)",
                infoTitle: "获取失败：\(message)",
                detailsText: message,
                isWarning: true
            )
        }
    }

    private static func menuPrice(_ price: String) -> String {
        guard let number = Double(price) else { return "Au —" }
        return String(format: "%.1f", number)
    }

    private static func quoteDetails(_ quote: GoldQuote, status: String) -> String {
        [
            "\(quote.name)：\(quote.price) 元/克",
            "涨跌幅：\(quote.changePercent)",
            "行情时间：\(quote.sourceTime)",
            "自动刷新：每 30 分钟",
            "当前状态：\(status)",
        ].joined(separator: "\n")
    }
}

public struct ErrorNotificationPolicy {
    private var activeMessage: String?
    private var lastNotificationDate: Date?

    public init() {}

    public mutating func shouldNotify(
        message: String,
        at date: Date,
        cooldown: TimeInterval
    ) -> Bool {
        let cooldownElapsed = lastNotificationDate.map {
            date.timeIntervalSince($0) >= cooldown
        } ?? true
        guard message != activeMessage || cooldownElapsed else { return false }

        activeMessage = message
        lastNotificationDate = date
        return true
    }

    public mutating func reset() {
        activeMessage = nil
        lastNotificationDate = nil
    }
}
