import Foundation

public final class GoldAPIClient {
    public static let endpoint = "https://web.juhe.cn/finance/gold/shgold"

    private let session: URLSession
    private let timeout: TimeInterval

    public init(
        session: URLSession = .shared,
        timeout: TimeInterval = 10
    ) {
        self.session = session
        self.timeout = timeout
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
        request.setValue("AurumBar/0.1.1", forHTTPHeaderField: "User-Agent")

        session.dataTask(with: request) { data, response, error in
            if let error {
                self.complete(
                    .failure(GoldAPIError.network(error.localizedDescription)),
                    completion: completion
                )
                return
            }
            guard
                let httpResponse = response as? HTTPURLResponse,
                (200 ..< 300).contains(httpResponse.statusCode),
                let data
            else {
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

    private func complete(
        _ result: Result<GoldQuote, Error>,
        completion: @escaping (Result<GoldQuote, Error>) -> Void
    ) {
        DispatchQueue.main.async {
            completion(result)
        }
    }
}
