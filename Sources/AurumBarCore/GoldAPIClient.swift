import Foundation

public final class GoldAPIClient: @unchecked Sendable {
    public static let endpoint = "https://web.juhe.cn/finance/gold/shgold"

    private let session: URLSession
    private let endpoint: String
    private let timeout: TimeInterval
    private let maximumAttempts: Int
    private let retryBaseDelay: TimeInterval

    public init(
        session: URLSession = .shared,
        endpoint: String = GoldAPIClient.endpoint,
        timeout: TimeInterval = 10,
        maximumAttempts: Int = 3,
        retryBaseDelay: TimeInterval = 1
    ) {
        self.session = session
        self.endpoint = endpoint
        self.timeout = timeout
        self.maximumAttempts = max(1, maximumAttempts)
        self.retryBaseDelay = max(0, retryBaseDelay)
    }

    public func fetch(apiKey: String) async throws -> GoldQuote {
        guard var components = URLComponents(string: endpoint) else {
            throw GoldAPIError.invalidResponse
        }
        components.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "v", value: "1"),
        ]
        guard let url = components.url else {
            throw GoldAPIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("no-cache, no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue(AurumBarVersion.userAgent, forHTTPHeaderField: "User-Agent")

        return try await perform(request)
    }

    private func perform(_ request: URLRequest) async throws -> GoldQuote {
        for attempt in 1 ... maximumAttempts {
            try Task.checkCancellation()

            do {
                let (data, response) = try await session.data(for: request)
                try Task.checkCancellation()

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw GoldAPIError.invalidResponse
                }
                guard (200 ..< 300).contains(httpResponse.statusCode) else {
                    if shouldRetry(statusCode: httpResponse.statusCode),
                       attempt < maximumAttempts
                    {
                        try await waitBeforeRetry(after: attempt)
                        continue
                    }
                    throw GoldAPIError.httpStatus(httpResponse.statusCode)
                }

                let quote = try GoldResponseParser.parse(data: data)
                try Task.checkCancellation()
                return quote
            } catch is CancellationError {
                throw CancellationError()
            } catch let urlError as URLError {
                if Task.isCancelled || urlError.code == .cancelled {
                    throw CancellationError()
                }
                if shouldRetry(urlError), attempt < maximumAttempts {
                    try await waitBeforeRetry(after: attempt)
                    continue
                }
                throw GoldAPIError.network(urlError.localizedDescription)
            } catch let apiError as GoldAPIError {
                throw apiError
            } catch {
                throw GoldAPIError.network(error.localizedDescription)
            }
        }

        throw GoldAPIError.invalidResponse
    }

    private func waitBeforeRetry(after attempt: Int) async throws {
        let delay = retryBaseDelay * pow(2, Double(attempt - 1))
        fputs(
            "AurumBar: 第 \(attempt) 次请求失败，\(delay) 秒后进行网络重试\n",
            stderr
        )
        guard delay > 0 else {
            try Task.checkCancellation()
            return
        }
        let nanoseconds = UInt64(delay * 1_000_000_000)
        try await Task.sleep(nanoseconds: nanoseconds)
    }

    private func shouldRetry(_ error: URLError) -> Bool {
        [
            .timedOut,
            .cannotFindHost,
            .cannotConnectToHost,
            .dnsLookupFailed,
            .networkConnectionLost,
            .notConnectedToInternet,
            .resourceUnavailable,
        ].contains(error.code)
    }

    private func shouldRetry(statusCode: Int) -> Bool {
        [500, 502, 503, 504].contains(statusCode)
    }
}
