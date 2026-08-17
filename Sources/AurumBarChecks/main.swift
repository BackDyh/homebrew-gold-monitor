import AurumBarCore
import Foundation

var failures = 0

final class RetryThenSuccessURLProtocol: URLProtocol {
    static var attempts = 0

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.attempts += 1
        if Self.attempts == 1 {
            client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
            return
        }

        let data = Data("""
        {"resultcode":"200","result":[{"7":{"variety":"Au99.99","latestpri":"954.01","limit":"1.41%","time":"2026-08-17 09:14:52"}}]}
        """.utf8)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class EmptyQuoteURLProtocol: URLProtocol {
    static var attempts = 0

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.attempts += 1
        let data = Data("""
        {"resultcode":"200","result":[{"7":{"variety":"Au99.99","latestpri":"--"}}]}
        """.utf8)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

func fetchSynchronously(
    using client: GoldAPIClient,
    timeout: TimeInterval = 2
) -> Result<GoldQuote, Error>? {
    var output: Result<GoldQuote, Error>?
    client.fetch(apiKey: "test") { output = $0 }

    let deadline = Date(timeIntervalSinceNow: timeout)
    while output == nil, Date() < deadline {
        _ = RunLoop.current.run(
            mode: .default,
            before: Date(timeIntervalSinceNow: 0.01)
        )
    }
    return output
}

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() {
        print("✓ \(message)")
    } else {
        failures += 1
        fputs("✗ \(message)\n", stderr)
    }
}

let successfulJSON: [String: Any] = [
    "resultcode": "200",
    "result": [[
        "4": [
            "variety": "Au100g",
            "latestpri": "939.10",
        ],
        "7": [
            "variety": "Au99.99",
            "latestpri": "940.70",
            "limit": "+0.31%",
            "time": "2026-08-14 15:30:00",
        ],
    ]],
]

do {
    let quote = try GoldResponseParser.parse(json: successfulJSON)
    check(quote.name == "Au99.99", "按品种名定位 Au99.99")
    check(quote.price == "940.70", "解析最新价格")
    check(quote.changePercent == "+0.31%", "解析涨跌幅")
} catch {
    failures += 1
    fputs("✗ 正常行情解析失败：\(error)\n", stderr)
}

do {
    RetryThenSuccessURLProtocol.attempts = 0
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [RetryThenSuccessURLProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }

    let result = fetchSynchronously(
        using: GoldAPIClient(
            session: session,
            maximumAttempts: 3,
            retryBaseDelay: 0
        )
    )
    let quote = try result?.get()
    check(quote?.price == "954.01", "网络瞬时失败后恢复行情")
    check(RetryThenSuccessURLProtocol.attempts == 2, "网络错误进行有限重试")
} catch {
    failures += 1
    fputs("✗ 网络重试测试失败：\(error)\n", stderr)
}

do {
    EmptyQuoteURLProtocol.attempts = 0
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [EmptyQuoteURLProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }

    let result = fetchSynchronously(
        using: GoldAPIClient(
            session: session,
            maximumAttempts: 3,
            retryBaseDelay: 0
        )
    )
    _ = try result?.get()
    failures += 1
    fputs("✗ 空行情没有返回暂时不可用\n", stderr)
} catch let error as GoldAPIError {
    check(error == .quoteUnavailable, "空行情保持暂时不可用语义")
    check(EmptyQuoteURLProtocol.attempts == 1, "空行情不重复消耗 API 次数")
} catch {
    failures += 1
    fputs("✗ 空行情请求测试失败：\(error)\n", stderr)
}

do {
    _ = try GoldResponseParser.parse(json: [
        "resultcode": "112",
        "reason": "请求超过次数限制",
    ])
    failures += 1
    fputs("✗ 接口错误没有抛出\n", stderr)
} catch let error as GoldAPIError {
    check(
        error == .apiError("请求超过次数限制"),
        "保留接口错误原因"
    )
} catch {
    failures += 1
    fputs("✗ 接口错误类型不正确：\(error)\n", stderr)
}

do {
    _ = try GoldResponseParser.parse(json: [
        "resultcode": "200",
        "result": [[
            "7": [
                "variety": "Au99.99",
                "latestpri": "--",
            ],
        ]],
    ])
    failures += 1
    fputs("✗ 无效价格没有抛出\n", stderr)
} catch let error as GoldAPIError {
    check(error == .quoteUnavailable, "识别暂无行情的价格占位符")
    check(!error.localizedDescription.contains("休市"), "不把空行情误判为休市")
} catch {
    failures += 1
    fputs("✗ 暂无行情错误类型不正确：\(error)\n", stderr)
}

do {
    _ = try GoldResponseParser.parse(json: [
        "resultcode": "200",
        "result": [[:]],
    ])
    failures += 1
    fputs("✗ 缺少行情记录没有抛出\n", stderr)
} catch let error as GoldAPIError {
    check(error == .missingMarketData, "识别接口缺少行情记录")
} catch {
    failures += 1
    fputs("✗ 缺少行情记录错误类型不正确：\(error)\n", stderr)
}

do {
    _ = try GoldResponseParser.parse(json: [
        "resultcode": "200",
        "result": [[
            "7": [
                "variety": "Au99.99",
                "latestpri": "not-a-price",
            ],
        ]],
    ])
    failures += 1
    fputs("✗ 非数字价格没有抛出\n", stderr)
} catch let error as GoldAPIError {
    check(error == .invalidPrice("not-a-price"), "仍然拒绝真正的无效价格")
} catch {
    failures += 1
    fputs("✗ 无效价格错误类型不正确：\(error)\n", stderr)
}

do {
    let quote = GoldQuote(
        name: "Au99.99",
        price: "954.01",
        changePercent: "1.41%",
        sourceTime: "2026-08-17 09:14:52"
    )
    let restored = try JSONDecoder().decode(
        GoldQuote.self,
        from: JSONEncoder().encode(quote)
    )
    check(restored == quote, "最近有效行情可跨启动保存")
} catch {
    failures += 1
    fputs("✗ 行情缓存编解码失败：\(error)\n", stderr)
}

if failures > 0 {
    fputs("AurumBar checks failed: \(failures)\n", stderr)
    exit(1)
}

print("AurumBar checks passed")
