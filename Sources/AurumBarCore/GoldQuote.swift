import Foundation

public struct GoldQuote: Codable, Equatable, Sendable {
    public let name: String
    public let price: String
    public let changePercent: String
    public let sourceTime: String

    public init(
        name: String,
        price: String,
        changePercent: String,
        sourceTime: String
    ) {
        self.name = name
        self.price = price
        self.changePercent = changePercent
        self.sourceTime = sourceTime
    }
}

public enum GoldAPIError: LocalizedError, Equatable {
    case invalidResponse
    case httpStatus(Int)
    case apiError(String)
    case missingMarketData
    case quoteUnavailable
    case invalidPrice(String)
    case network(String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "接口没有返回有效数据"
        case let .httpStatus(statusCode):
            return "接口 HTTP 状态异常：\(statusCode)"
        case let .apiError(reason):
            return "接口错误：\(reason)"
        case .missingMarketData:
            return "接口结果中缺少 Au99.99 行情"
        case .quoteUnavailable:
            return "接口暂时没有返回有效行情"
        case let .invalidPrice(price):
            return "接口返回了无效价格：\(price.isEmpty ? "空值" : price)"
        case let .network(message):
            return "网络请求失败：\(message)"
        }
    }
}
