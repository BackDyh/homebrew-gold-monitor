import AurumBarCore
import Foundation

public protocol GoldQuoteFetching: Sendable {
    func fetch(apiKey: String) async throws -> GoldQuote
}

extension GoldAPIClient: GoldQuoteFetching {}

@MainActor
public final class QuoteRefreshCoordinator {
    public enum Event {
        case started
        case succeeded(GoldQuote)
        case failed(Error)
    }

    public var onEvent: ((Event) -> Void)?

    private let fetcher: GoldQuoteFetching
    private var apiKey: String
    private var generation: UInt = 0
    private var requestTask: Task<Void, Never>?

    public init(apiKey: String, fetcher: GoldQuoteFetching) {
        self.apiKey = apiKey
        self.fetcher = fetcher
    }

    public var isRefreshing: Bool {
        requestTask != nil
    }

    public func refresh() {
        guard !apiKey.isEmpty, requestTask == nil else { return }
        startRequest()
    }

    public func replaceAPIKey(_ key: String) {
        generation &+= 1
        apiKey = key
        requestTask?.cancel()
        requestTask = nil
        startRequest()
    }

    public func cancel() {
        generation &+= 1
        requestTask?.cancel()
        requestTask = nil
    }

    private func startRequest() {
        guard !apiKey.isEmpty else { return }

        let requestGeneration = generation
        let requestKey = apiKey
        requestTask = Task { [weak self, fetcher] in
            guard !Task.isCancelled else { return }

            let result: Result<GoldQuote, Error>
            do {
                result = .success(try await fetcher.fetch(apiKey: requestKey))
            } catch is CancellationError {
                guard let self,
                      !Task.isCancelled,
                      self.generation == requestGeneration
                else {
                    return
                }
                self.requestTask = nil
                return
            } catch {
                result = .failure(error)
            }

            guard let self,
                  !Task.isCancelled,
                  self.generation == requestGeneration
            else {
                return
            }

            self.requestTask = nil
            switch result {
            case let .success(quote):
                self.onEvent?(.succeeded(quote))
            case let .failure(error):
                self.onEvent?(.failed(error))
            }
        }
        onEvent?(.started)
    }
}
