//
//  FinnhubClient.swift
//  SmartStock
//

import Foundation

enum FinnhubError: LocalizedError {
    case missingAPIKey
    case http(status: Int)
    case noData(symbol: String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "No Finnhub API key found. Add it to Config/Secrets.xcconfig and rebuild."
        case .http(let status) where status == 401:
            "Finnhub rejected the API key (401)."
        case .http(let status) where status == 429:
            "Finnhub rate limit reached. Try again in a minute."
        case .http(let status):
            "Finnhub request failed (\(status))."
        case .noData(let symbol):
            "No quote available for \(symbol)."
        }
    }
}

/// Thin wrapper around the Finnhub REST API.
struct FinnhubClient {
    private let baseURL = URL(string: "https://finnhub.io/api/v1")!
    private let apiKey: String?
    private let session: URLSession

    init(apiKey: String? = FinnhubClient.bundledAPIKey, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    /// The key injected into Info.plist from Secrets.xcconfig at build time.
    static var bundledAPIKey: String? {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "FinnhubAPIKey") as? String else { return nil }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        // An unset build setting expands to "", and the template ships a placeholder.
        guard !trimmed.isEmpty, !trimmed.hasPrefix("$("), trimmed != "your_finnhub_api_key_here" else { return nil }
        return trimmed
    }

    var hasAPIKey: Bool { apiKey != nil }

    func quote(for symbol: String) async throws -> Quote {
        var quote: Quote = try await get("quote", query: ["symbol": symbol])
        guard !quote.isEmpty else { throw FinnhubError.noData(symbol: symbol) }
        quote.sourceSymbol = symbol
        return quote
    }

    /// Quotes `asset.symbol`, falling back to `asset.proxySymbol` if the
    /// primary symbol isn't available (e.g. indices on the free plan).
    func quote(for asset: Asset) async throws -> Quote {
        do {
            return try await quote(for: asset.symbol)
        } catch {
            guard let proxy = asset.proxySymbol else { throw error }
            if case FinnhubError.http(let status) = error, status == 429 { throw error }
            return try await quote(for: proxy)
        }
    }

    /// Company profile (free tier). Finnhub returns `{}` for ETFs and funds,
    /// so this is `nil` for anything that isn't a single company's stock.
    func profile(for symbol: String) async throws -> CompanyProfile? {
        let profile: CompanyProfile = try await get("stock/profile2", query: ["symbol": symbol])
        return profile.country?.isEmpty == false ? profile : nil
    }

    func search(_ text: String) async throws -> [SymbolSearchResult] {
        let response: SymbolSearchResponse = try await get("search", query: ["q": text, "exchange": "US"])
        return response.result
    }

    private func get<T: Decodable>(_ path: String, query: [String: String]) async throws -> T {
        guard let apiKey else { throw FinnhubError.missingAPIKey }

        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }

        var request = URLRequest(url: components.url!)
        // Send the key as a header rather than a query parameter so it
        // doesn't end up in URL logs.
        request.setValue(apiKey, forHTTPHeaderField: "X-Finnhub-Token")

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw FinnhubError.http(status: http.statusCode)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
