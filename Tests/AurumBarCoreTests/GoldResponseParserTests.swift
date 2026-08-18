import Testing
import AurumBarCore
import Foundation

@Suite(.serialized)
struct GoldResponseParserTests {
    @Test func parsesAu9999AndNormalizesPrice() throws {
        let quote = try GoldResponseParser.parse(json: successfulJSON(price: "0940.700"))

        #expect(quote.name == "Au99.99")
        #expect(quote.price == "940.7")
        #expect(quote.changePercent == "+0.31%")
    }

    @Test func acceptsNumericResultCodeAndPrice() throws {
        let quote = try GoldResponseParser.parse(json: successfulJSON(
            resultCode: 200,
            price: NSNumber(value: 954.01)
        ))

        #expect(quote.price == "954.01")
    }

    @Test func mapsMissingAndNullPriceToUnavailable() {
        for value: Any? in [nil, NSNull(), "", "  ", "--", "-", "—", "null", "NIL"] {
            #expect(throws: GoldAPIError.quoteUnavailable) {
                try GoldResponseParser.parse(json: successfulJSON(price: value))
            }
        }
    }

    @Test func rejectsMalformedPricesCompletely() {
        let invalid: [Any] = [
            "940.70abc", "1,234.50", "1e3", "NaN", "Infinity", "940.1.2",
            "0", "-1", true, ["940"], ["value": "940"],
        ]

        for value in invalid {
            #expect {
                try GoldResponseParser.parse(json: successfulJSON(price: value))
            } throws: { error in
                if case .invalidPrice = error as? GoldAPIError {
                    return true
                }
                return false
            }
        }
    }

    @Test func nullOptionalFieldsUseFallbacks() throws {
        var json = successfulJSON(price: "940.70")
        var result = json["result"] as! [[String: Any]]
        var market = result[0]
        var quote = market["7"] as! [String: Any]
        quote["limit"] = NSNull()
        quote["time"] = NSNull()
        market["7"] = quote
        result[0] = market
        json["result"] = result

        let parsed = try GoldResponseParser.parse(json: json)
        #expect(parsed.changePercent == "--")
        #expect(parsed.sourceTime == "--")
    }

    @Test func nullReasonUsesFallback() {
        #expect(throws: GoldAPIError.apiError("未知错误")) {
            try GoldResponseParser.parse(json: [
                "resultcode": "112",
                "reason": NSNull(),
            ])
        }
    }

    @Test func invalidOrMissingResultCodeIsInvalidResponse() {
        for value: Any? in [nil, NSNull(), true, ["200"]] {
            var json: [String: Any] = ["result": []]
            if let value { json["resultcode"] = value }
            #expect(throws: GoldAPIError.invalidResponse) {
                try GoldResponseParser.parse(json: json)
            }
        }
    }

    @Test func missingMarketData() {
        #expect(throws: GoldAPIError.missingMarketData) {
            try GoldResponseParser.parse(json: [
                "resultcode": "200",
                "result": [[:]],
            ])
        }
    }

    private func successfulJSON(
        resultCode: Any = "200",
        price: Any? = "940.70"
    ) -> [String: Any] {
        var record: [String: Any] = [
            "variety": "Au99.99",
            "limit": "+0.31%",
            "time": "2026-08-14 15:30:00",
        ]
        if let price { record["latestpri"] = price }
        return [
            "resultcode": resultCode,
            "result": [[
                "4": ["variety": "Au100g", "latestpri": "939.10"],
                "7": record,
            ]],
        ]
    }
}
