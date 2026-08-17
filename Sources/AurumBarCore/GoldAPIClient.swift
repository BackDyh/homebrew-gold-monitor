import Foundation

public final class GoldAPIClient {
    public static let endpoint = "https://web.juhe.cn/finance/gold/shgold"

    private let session: URLSession
    private let timeout: TimeInterval
    private let maximumAttempts: Int
    private let retryBaseDelay: TimeInterval

    public init(
        session: URLSession = .shared,
        timeout: TimeInterval = 10,
        maximumAttempts: Int = 3,
        retryBaseDelay: TimeInterval = 1
    ) {
        self.session = session
        self.timeout = timeout
        self.maximumAttempts = max(1, maximumAttempts)
        self.retryBaseDelay = max(0, retryBaseDelay)
    }

    public func fetch(
        apiKey: String,
        completion: @escaping (Result<GoldQuote, Error>) -> Void
    ) {
        guard var components = URLComponents(string: Self.endpoint) else {
            complete(.failure(GoldAPIError.invalidResponse), completion: completion)
            return
        }
        components.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "v", value: "1"),
        ]
        guard let url = components.url else {
            complete(.failure(GoldAPIError.invalidResponse), completion: completion)
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("no-cache, no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("AurumBar/0.1.2", forHTTPHeaderField: "User-Agent")

        perform(request, attempt: 1, completion: completion)
    }

    private func perform(
        _ request: URLRequest,
        attempt: Int,
        completion: @escaping (Result<GoldQuote, Error>) -> Void
    ) {
        session.dataTask(with: request) { data, response, error in
            if let error {
                if self.shouldRetry(error), attempt < self.maximumAttempts {
                    self.retry(request, after: attempt, completion: completion)
                    return
                }
                self.complete(
                    .failure(GoldAPIError.network(error.localizedDescription)),
                    completion: completion
                )
                return
            }
            guard let httpResponse = response as? HTTPURLResponse else {
                self.complete(
                    .failure(GoldAPIError.invalidResponse),
                    completion: completion
                )
                return
            }

            guard (200 ..< 300).contains(httpResponse.statusCode) else {
                if self.shouldRetry(statusCode: httpResponse.statusCode),
                   attempt < self.maximumAttempts
                {
                    self.retry(request, after: attempt, completion: completion)
                    return
                }
                self.complete(
                    .failure(GoldAPIError.httpStatus(httpResponse.statusCode)),
                    completion: completion
                )
                return
            }

            guard let data else {
                self.complete(
                    .failure(GoldAPIError.invalidResponse),
                    completion: completion
                )
                return
            }

            do {
                let quote = try GoldResponseParser.parse(data: data)
                self.complete(.success(quote), completion: completion)
            } catch {
                self.complete(.failure(error), completion: completion)
            }
        }.resume()
    }

    private func retry(
        _ request: URLRequest,
        after attempt: Int,
        completion: @escaping (Result<GoldQuote, Error>) -> Void
    ) {
        let delay = retryBaseDelay * pow(2, Double(attempt - 1))
        fputs(
            "AurumBar: 第 \(attempt) 次请求失败，\(delay) 秒后进行网络重试\n",
            stderr
        )
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) {
            self.perform(request, attempt: attempt + 1, completion: completion)
        }
    }

    private func shouldRetry(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        return [
            .timedOut,
            .cannotFindHost,
            .cannotConnectToHost,
            .dnsLookupFailed,
            .networkConnectionLost,
            .notConnectedToInternet,
            .resourceUnavailable,
        ].contains(urlError.code)
    }

    private func shouldRetry(statusCode: Int) -> Bool {
        [500, 502, 503, 504].contains(statusCode)
    }

    private func complete(
        _ result: Result<GoldQuote, Error>,
        completion: @escaping (Result<GoldQuote, Error>) -> Void
    ) {
        DispatchQueue.main.async {
            completion(result)
        }
    }
}
