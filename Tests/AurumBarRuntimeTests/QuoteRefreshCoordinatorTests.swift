import AurumBarCore
import AurumBarRuntime
import Foundation
import XCTest

@MainActor
final class QuoteRefreshCoordinatorTests: XCTestCase {
    func testReplacingKeyDiscardsStaleResult() async throws {
        let fetcher = ControlledFetcher()
        let coordinator = QuoteRefreshCoordinator(apiKey: "old", fetcher: fetcher)
        var events: [QuoteRefreshCoordinator.Event] = []
        coordinator.onEvent = { events.append($0) }

        coordinator.refresh()
        try await fetcher.waitForRequests(1)
        coordinator.replaceAPIKey("new")
        try await fetcher.waitForRequests(2)

        fetcher.succeed(key: "old", price: "900")
        fetcher.succeed(key: "new", price: "950")
        try await waitUntil { !coordinator.isRefreshing }

        let prices = events.compactMap { event -> String? in
            guard case let .succeeded(quote) = event else { return nil }
            return quote.price
        }
        XCTAssertEqual(prices, ["950"])
    }

    func testDuplicateRefreshIsCoalesced() async throws {
        let fetcher = ControlledFetcher()
        let coordinator = QuoteRefreshCoordinator(apiKey: "key", fetcher: fetcher)

        coordinator.refresh()
        coordinator.refresh()
        coordinator.refresh()
        try await fetcher.waitForRequests(1)

        XCTAssertEqual(fetcher.requestedKeys, ["key"])
        fetcher.succeed(key: "key", price: "950")
        try await waitUntil { !coordinator.isRefreshing }
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        for _ in 0 ..< 100 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Condition did not become true")
    }
}

private final class ControlledFetcher: GoldQuoteFetching, @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [String: CheckedContinuation<GoldQuote, Error>] = [:]
    private var keys: [String] = []

    var requestedKeys: [String] {
        lock.withLock { keys }
    }

    func fetch(apiKey: String) async throws -> GoldQuote {
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock {
                keys.append(apiKey)
                continuations[apiKey] = continuation
            }
        }
    }

    func waitForRequests(_ count: Int) async throws {
        for _ in 0 ..< 100 {
            if requestedKeys.count >= count { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Expected \(count) requests, got \(requestedKeys.count)")
    }

    func succeed(key: String, price: String) {
        let continuation = lock.withLock { continuations.removeValue(forKey: key) }
        continuation?.resume(returning: GoldQuote(
            name: "Au99.99",
            price: price,
            changePercent: "0%",
            sourceTime: "now"
        ))
    }
}
