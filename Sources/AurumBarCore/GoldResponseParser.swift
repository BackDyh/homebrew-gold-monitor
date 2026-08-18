import CoreFoundation
import Foundation

public enum GoldResponseParser {
    private static let pricePattern = try! NSRegularExpression(
        pattern: #"^[0-9]+(?:\.[0-9]+)?$"#
    )

    public static func parse(data: Data) throws -> GoldQuote {
        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw GoldAPIError.invalidResponse
        }
        return try parse(json: json)
    }

    public static func parse(json: Any) throws -> GoldQuote {
        guard let payload = json as? [String: Any] else {
            throw GoldAPIError.invalidResponse
        }

        guard let resultCode = resultCode(payload["resultcode"]) else {
            throw GoldAPIError.invalidResponse
        }
        guard resultCode == 200 else {
            let reason = stringValue(payload["reason"], fallback: "未知错误")
            throw GoldAPIError.apiError(reason)
        }

        guard
            let result = payload["result"] as? [[String: Any]],
            let market = result.first,
            let record = market.values.compactMap({ $0 as? [String: Any] }).first(where: {
                normalizedVariety($0["variety"]) == "au9999"
            })
        else {
            throw GoldAPIError.missingMarketData
        }

        let rawPrice = record["latestpri"]
        guard rawPrice != nil, !(rawPrice is NSNull) else {
            throw GoldAPIError.quoteUnavailable
        }
        guard let scalarPrice = scalarString(rawPrice) else {
            throw GoldAPIError.invalidPrice(String(describing: rawPrice!))
        }
        let price = scalarPrice.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPrice = price.lowercased()
        if price.isEmpty || ["--", "-", "—", "null", "nil"].contains(normalizedPrice) {
            throw GoldAPIError.quoteUnavailable
        }

        let range = NSRange(price.startIndex ..< price.endIndex, in: price)
        guard
            Self.pricePattern.firstMatch(in: price, range: range)?.range == range,
            let decimal = Decimal(
                string: price,
                locale: Locale(identifier: "en_US_POSIX")
            ),
            decimal > 0
        else {
            throw GoldAPIError.invalidPrice(price)
        }

        return GoldQuote(
            name: stringValue(record["variety"], fallback: "Au99.99"),
            price: NSDecimalNumber(decimal: decimal).stringValue,
            changePercent: stringValue(record["limit"], fallback: "--"),
            sourceTime: stringValue(record["time"], fallback: "--")
        )
    }

    private static func resultCode(_ value: Any?) -> Int? {
        if let string = scalarString(value), let code = Int(string) {
            return code
        }
        return nil
    }

    private static func normalizedVariety(_ value: Any?) -> String {
        stringValue(value)
            .lowercased()
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: " ", with: "")
    }

    private static func stringValue(
        _ value: Any?,
        fallback: String = ""
    ) -> String {
        guard let value = scalarString(value) else { return fallback }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private static func scalarString(_ value: Any?) -> String? {
        guard let value, !(value is NSNull) else { return nil }
        if let string = value as? String {
            return string
        }
        if let number = value as? NSNumber,
           CFGetTypeID(number) != CFBooleanGetTypeID()
        {
            return number.stringValue
        }
        return nil
    }
}
