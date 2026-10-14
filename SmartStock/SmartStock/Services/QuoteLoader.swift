//
//  QuoteLoader.swift
//  SmartStock
//

import Foundation

/// Fetches an asset's latest quote and intraday history from whichever
/// source has it. Shared by the watchlist and the portfolio.
struct QuoteLoader {
    struct Snapshot {
        var quote: Quote?
        /// Today's intraday prices.
        var history: PriceHistory?
        /// Why the quote is missing, if it is.
        var failure: Error?
    }

    let finnhub: FinnhubClient
    let yahoo: YahooFinanceClient

    /// Yahoo supplies the intraday history (and the quote for indices, which
    /// Finnhub's free tier lacks). Finnhub supplies stock quotes, and each
    /// source backs up the other.
    func load(_ asset: Asset) async -> Snapshot {
        async let chartResult = Result(asyncCatching: { try await yahoo.chart(for: asset.symbol) })
        var snapshot = Snapshot()
        if !asset.isIndex, finnhub.hasAPIKey {
            do { snapshot.quote = try await finnhub.quote(for: asset.symbol) } catch { snapshot.failure = error }
        }

        switch await chartResult {
        case .success(let chart):
            snapshot.history = chart.history
            snapshot.quote = snapshot.quote ?? chart.quote
        case .failure(let error):
            snapshot.failure = snapshot.failure ?? error
        }

        // Last resort for indices: a tracking ETF quoted by Finnhub.
        if snapshot.quote == nil, let proxy = asset.proxySymbol, finnhub.hasAPIKey {
            snapshot.quote = try? await finnhub.quote(for: proxy)
        }
        if snapshot.quote != nil { snapshot.failure = nil }
        return snapshot
    }
}

private extension Result where Failure == Error {
    init(asyncCatching body: () async throws -> Success) async {
        do { self = .success(try await body()) } catch { self = .failure(error) }
    }
}

extension Error {
    var isCancellation: Bool {
        self is CancellationError || (self as? URLError)?.code == .cancelled
    }
}
