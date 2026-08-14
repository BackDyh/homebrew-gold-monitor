import AurumBarCore
import Foundation

var failures = 0

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
    check(error == .invalidPrice("--"), "拒绝无效价格")
} catch {
    failures += 1
    fputs("✗ 无效价格错误类型不正确：\(error)\n", stderr)
}

if failures > 0 {
    fputs("AurumBar checks failed: \(failures)\n", stderr)
    exit(1)
}

print("AurumBar checks passed")
