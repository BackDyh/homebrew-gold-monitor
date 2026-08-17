import AurumBarCore
import Foundation

final class QuoteCache {
    private let defaults: UserDefaults
    private let quoteKey = "last-valid-gold-quote"

    init(defaults: UserDefaults? = UserDefaults(suiteName: "com.back.aurumbar")) {
        self.defaults = defaults ?? .standard
    }

    func load() -> GoldQuote? {
        guard let data = defaults.data(forKey: quoteKey) else { return nil }
        return try? JSONDecoder().decode(GoldQuote.self, from: data)
    }

    func save(_ quote: GoldQuote) {
        guard let data = try? JSONEncoder().encode(quote) else { return }
        defaults.set(data, forKey: quoteKey)
    }
}
