import Foundation

public enum GoldResponseParser {
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

        let resultCode = String(describing: payload["resultcode"] ?? "")
        guard resultCode == "200" else {
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

        let price = stringValue(record["latestpri"])
        guard
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
            price: price,
            changePercent: stringValue(record["limit"], fallback: "--"),
            sourceTime: stringValue(record["time"], fallback: "--")
        )
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
        guard let value else { return fallback }
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? fallback : trimmed
        }
        return String(describing: value)
    }
}
