import AurumBarCore
import Foundation
import XCTest

final class GoldAPIClientTests: XCTestCase {
    override func setUp() {
        super.setUp()
        StubURLProtocol.handler = nil
        StubURLProtocol.attempts = 0
    }

    override func tearDown() {
        StubURLProtocol.handler = nil
        StubURLProtocol.attempts = 0
        super.tearDown()
    }

    func testRetriesTransientNetworkFailureThenSucceeds() async throws {
        StubURLProtocol.handler = { request, attempt in
            if attempt == 1 {
                throw URLError(.timedOut)
            }
            return (Self.response(for: request, status: 200), Self.successData)
        }

        let quote = try await makeClient(maximumAttempts: 3).fetch(apiKey: "test")

        XCTAssertEqual(quote.price, "954.01")
        XCTAssertEqual(StubURLProtocol.attempts, 2)
    }

    func testRetriesServerErrorButNotClientError() async {
        StubURLProtocol.handler = { request, _ in
            (Self.response(for: request, status: 503), Data())
        }
        do {
            _ = try await makeClient(maximumAttempts: 3).fetch(apiKey: "test")
            XCTFail("Expected HTTP error")
        } catch {
            XCTAssertEqual(error as? GoldAPIError, .httpStatus(503))
            XCTAssertEqual(StubURLProtocol.attempts, 3)
        }

        StubURLProtocol.attempts = 0
        StubURLProtocol.handler = { request, _ in
            (Self.response(for: request, status: 401), Data())
        }
        do {
            _ = try await makeClient(maximumAttempts: 3).fetch(apiKey: "test")
            XCTFail("Expected HTTP error")
        } catch {
            XCTAssertEqual(error as? GoldAPIError, .httpStatus(401))
            XCTAssertEqual(StubURLProtocol.attempts, 1)
        }
    }

    func testDoesNotRetryUnavailableQuote() async {
        StubURLProtocol.handler = { request, _ in
            let data = Data("""
            {"resultcode":"200","result":[{"7":{"variety":"Au99.99","latestpri":"--"}}]}
            """.utf8)
            return (Self.response(for: request, status: 200), data)
        }

        do {
            _ = try await makeClient(maximumAttempts: 3).fetch(apiKey: "test")
            XCTFail("Expected unavailable quote")
        } catch {
            XCTAssertEqual(error as? GoldAPIError, .quoteUnavailable)
            XCTAssertEqual(StubURLProtocol.attempts, 1)
        }
    }

    func testUsesVersionedUserAgentAndEncodedAPIKey() async throws {
        var capturedRequest: URLRequest?
        StubURLProtocol.handler = { request, _ in
            capturedRequest = request
            return (Self.response(for: request, status: 200), Self.successData)
        }

        _ = try await makeClient().fetch(apiKey: "a key&value")

        XCTAssertEqual(
            capturedRequest?.value(forHTTPHeaderField: "User-Agent"),
            AurumBarVersion.userAgent
        )
        let components = capturedRequest?.url.flatMap {
            URLComponents(url: $0, resolvingAgainstBaseURL: false)
        }
        XCTAssertEqual(
            components?.queryItems?.first(where: { $0.name == "key" })?.value,
            "a key&value"
        )
    }

    func testCancellationStopsRetryDelay() async throws {
        StubURLProtocol.handler = { _, _ in throw URLError(.timedOut) }
        let client = makeClient(maximumAttempts: 3, retryBaseDelay: 10)
        let task = Task { try await client.fetch(apiKey: "test") }

        try await waitForAttempts(1)
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            XCTAssertEqual(StubURLProtocol.attempts, 1)
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
    }

    private func makeClient(
        maximumAttempts: Int = 1,
        retryBaseDelay: TimeInterval = 0
    ) -> GoldAPIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return GoldAPIClient(
            session: URLSession(configuration: configuration),
            maximumAttempts: maximumAttempts,
            retryBaseDelay: retryBaseDelay
        )
    }

    private func waitForAttempts(_ count: Int) async throws {
        for _ in 0 ..< 100 where StubURLProtocol.attempts < count {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertGreaterThanOrEqual(StubURLProtocol.attempts, count)
    }

    private static let successData = Data("""
    {"resultcode":"200","result":[{"7":{"variety":"Au99.99","latestpri":"954.01","limit":"1.41%","time":"2026-08-17 09:14:52"}}]}
    """.utf8)

    private static func response(for request: URLRequest, status: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: nil,
            headerFields: nil
        )!
    }
}

private final class StubURLProtocol: URLProtocol {
    static var handler: ((URLRequest, Int) throws -> (HTTPURLResponse, Data))?
    static var attempts = 0

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.attempts += 1
        do {
            guard let handler = Self.handler else {
                throw URLError(.unknown)
            }
            let (response, data) = try handler(request, Self.attempts)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
