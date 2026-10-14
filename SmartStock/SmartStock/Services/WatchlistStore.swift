//
//  WatchlistStore.swift
//  SmartStock
//

import Foundation
import Observation
import SwiftUI

/// The user's list of assets and their latest quotes.
@Observable
final class WatchlistStore {
    private(set) var assets: [Asset] {
        didSet { save() }
    }
    private(set) var quotes: [String: Quote] = [:]
    /// Today's intraday prices, for the row sparklines.
    private(set) var histories: [String: PriceHistory] = [:]
    private(set) var errors: [String: String] = [:]
    private(set) var lastError: String?

    let finnhub: FinnhubClient
    let yahoo: YahooFinanceClient

    private static let storageKey = "watchlist.assets"
    private let defaults: UserDefaults

    init(
        finnhub: FinnhubClient = FinnhubClient(),
        yahoo: YahooFinanceClient = YahooFinanceClient(),
        defaults: UserDefaults = .standard
    ) {
        self.finnhub = finnhub
        self.yahoo = yahoo
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode([Asset].self, from: data) {
            assets = saved
        } else {
            assets = Asset.defaults
        }
    }

    func contains(_ symbol: String) -> Bool {
        assets.contains { $0.symbol == symbol }
    }

    func add(_ asset: Asset) {
        guard !contains(asset.symbol) else { return }
        assets.append(asset)
        Task { await refresh(asset) }
    }

    func remove(atOffsets offsets: IndexSet) {
        for index in offsets {
            quotes[assets[index].symbol] = nil
            histories[assets[index].symbol] = nil
            errors[assets[index].symbol] = nil
        }
        assets.remove(atOffsets: offsets)
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        assets.move(fromOffsets: source, toOffset: destination)
    }

    /// Symbols matching `text`: Finnhub's results plus mutual funds from
    /// Yahoo, which Finnhub's free plan doesn't cover. Yahoo is a bonus, so
    /// its failures are ignored; Finnhub's are reported.
    func search(_ text: String) async throws -> [SymbolSearchResult] {
        async let funds = try? yahoo.searchMutualFunds(text)
        let results = try await finnhub.search(text)
        let found = Set(results.map(\.symbol))
        return results + (await funds ?? []).filter { !found.contains($0.symbol) }
    }

    func refreshAll() async {
        lastError = finnhub.hasAPIKey ? nil : FinnhubError.missingAPIKey.errorDescription
        await withTaskGroup(of: Void.self) { group in
            for asset in assets {
                group.addTask { await self.refresh(asset) }
            }
        }
    }

    func refresh(_ asset: Asset) async {
        let snapshot = await QuoteLoader(finnhub: finnhub, yahoo: yahoo).load(asset)
        if let history = snapshot.history {
            histories[asset.symbol] = history
        }
        if let quote = snapshot.quote {
            quotes[asset.symbol] = quote
            errors[asset.symbol] = nil
        } else if let failure = snapshot.failure, !failure.isCancellation {
            errors[asset.symbol] = failure.localizedDescription
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(assets) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}
