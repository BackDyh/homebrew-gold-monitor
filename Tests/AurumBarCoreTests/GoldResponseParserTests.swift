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

    func testQuotaErrorsAreRecognized() {
        let payloads: [[String: Any]] = [
            ["resultcode": "112", "reason": "request exceeds the limit!", "error_code": 10012],
            ["resultcode": "112", "reason": "超过次数限制", "error_code": "10013"],
            ["resultcode": "112", "reason": "Request Exceeds The Limit"],
        ]
        for payload in payloads {
            XCTAssertThrowsError(try GoldResponseParser.parse(json: payload)) {
                XCTAssertEqual($0 as? GoldAPIError, .quotaExceeded)
            }
        }
    }

    func testOtherAPIErrorsKeepReason() {
        XCTAssertThrowsError(try GoldResponseParser.parse(json: [
            "resultcode": "101",
            "reason": "KEY ERROR!",
            "error_code": 10001,
        ])) {
            XCTAssertEqual($0 as? GoldAPIError, .apiError("KEY ERROR!"))
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

    func testPrefersValidAu9999OverPlaceholderUppercaseVariant() throws {
        for placeholderKey in ["1", "7", "99"] {
            let json: [String: Any] = [
                "resultcode": "200",
                "result": [[
                    placeholderKey: ["variety": "AU99.99", "latestpri": "--", "limit": "NaN%"],
                    "4": ["variety": "Au99.99", "latestpri": "899.01", "limit": "-0.28%"],
                ]],
            ]

            let quote = try GoldResponseParser.parse(json: json)
            XCTAssertEqual(quote.name, "Au99.99")
            XCTAssertEqual(quote.price, "899.01")
        }
    }

    func testFallsBackToUppercaseVariantWhenPreferredIsUnavailable() throws {
        let quote = try GoldResponseParser.parse(json: [
            "resultcode": "200",
            "result": [[
                "4": ["variety": "Au99.99", "latestpri": "--"],
                "12": ["variety": "AU99.99", "latestpri": "899.50"],
            ]],
        ])

        XCTAssertEqual(quote.price, "899.5")
    }

    func testReportsPreferredErrorWhenNoCandidateIsValid() {
        XCTAssertThrowsError(try GoldResponseParser.parse(json: [
            "resultcode": "200",
            "result": [[
                "4": ["variety": "Au99.99", "latestpri": "--"],
                "12": ["variety": "AU99.99", "latestpri": "--"],
            ]],
        ])) {
            XCTAssertEqual($0 as? GoldAPIError, .quoteUnavailable)
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
