import AurumBarCore
import Foundation
import XCTest

final class GoldResponseParserTests: XCTestCase {
    func testParsesAu9999AndNormalizesPrice() throws {
        let quote = try GoldResponseParser.parse(json: successfulJSON(price: "0940.700"))

        XCTAssertEqual(quote.name, "Au99.99")
        XCTAssertEqual(quote.price, "940.7")
        XCTAssertEqual(quote.changePercent, "+0.31%")
    }

    func testAcceptsNumericResultCodeAndPrice() throws {
        let quote = try GoldResponseParser.parse(json: successfulJSON(
            resultCode: 200,
            price: NSNumber(value: 954.01)
        ))

        XCTAssertEqual(quote.price, "954.01")
    }

    func testMapsMissingAndNullPriceToUnavailable() {
        for value: Any? in [nil, NSNull(), "", "  ", "--", "-", "—", "null", "NIL"] {
            XCTAssertThrowsError(try GoldResponseParser.parse(json: successfulJSON(price: value))) {
                XCTAssertEqual($0 as? GoldAPIError, .quoteUnavailable)
            }
        }
    }

    func testRejectsMalformedPricesCompletely() {
        let invalid: [Any] = [
            "940.70abc", "1,234.50", "1e3", "NaN", "Infinity", "940.1.2",
            "0", "-1", true, ["940"], ["value": "940"],
        ]

        for value in invalid {
            XCTAssertThrowsError(try GoldResponseParser.parse(json: successfulJSON(price: value))) {
                guard case .invalidPrice = $0 as? GoldAPIError else {
                    return XCTFail("Expected invalidPrice for \(value), got \($0)")
                }
            }
        }
    }

    func testNullOptionalFieldsUseFallbacks() throws {
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
        XCTAssertEqual(parsed.changePercent, "--")
        XCTAssertEqual(parsed.sourceTime, "--")
    }

    func testNullReasonUsesFallback() {
        XCTAssertThrowsError(try GoldResponseParser.parse(json: [
            "resultcode": "112",
            "reason": NSNull(),
        ])) {
            XCTAssertEqual($0 as? GoldAPIError, .apiError("未知错误"))
        }
    }

    func testInvalidOrMissingResultCodeIsInvalidResponse() {
        for value: Any? in [nil, NSNull(), true, ["200"]] {
            var json: [String: Any] = ["result": []]
            if let value { json["resultcode"] = value }
            XCTAssertThrowsError(try GoldResponseParser.parse(json: json)) {
                XCTAssertEqual($0 as? GoldAPIError, .invalidResponse)
            }
        }
    }

    func testMissingMarketData() {
        XCTAssertThrowsError(try GoldResponseParser.parse(json: [
            "resultcode": "200",
            "result": [[:]],
        ])) {
            XCTAssertEqual($0 as? GoldAPIError, .missingMarketData)
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
