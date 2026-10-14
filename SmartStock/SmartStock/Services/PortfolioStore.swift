//
//  PortfolioStore.swift
//  SmartStock
//

import Foundation
import Observation
import SwiftUI

/// The user's positions and the latest quotes for the assets in them.
@Observable
final class PortfolioStore {
    private(set) var positions: [Position] {
        didSet { save() }
    }
    private(set) var quotes: [String: Quote] = [:]
    private(set) var errors: [String: String] = [:]
    /// Asset category by symbol. Confirmed ones are saved; guesses are
    /// kept for this launch only so they're retried next time.
    private(set) var categories: [String: AssetCategory] = [:]
    private var confirmedCategories: [String: AssetCategory] {
        didSet { defaults.set(try? JSONEncoder().encode(confirmedCategories), forKey: Self.categoriesKey) }
    }
    /// Symbols classified (or being classified) this launch.
    private var classifying: Set<String> = []

    let finnhub: FinnhubClient
    let yahoo: YahooFinanceClient

    private static let storageKey = "portfolio.positions"
    // v2: categories split individual stocks from funds.
    private static let categoriesKey = "portfolio.categories.v2"
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
           let saved = try? JSONDecoder().decode([Position].self, from: data) {
            positions = saved
        } else {
            positions = []
        }
        if let data = defaults.data(forKey: Self.categoriesKey),
           let saved = try? JSONDecoder().decode([String: AssetCategory].self, from: data) {
            confirmedCategories = saved
        } else {
            confirmedCategories = [:]
        }
        categories = confirmedCategories
    }

    func add(_ position: Position) {
        positions.append(position)
        Task { await refresh(position.asset) }
        Task { await classify(position.asset) }
    }

    func remove(atOffsets offsets: IndexSet) {
        let removed = offsets.map { positions[$0].asset.symbol }
        positions.remove(atOffsets: offsets)
        for symbol in removed where !positions.contains(where: { $0.asset.symbol == symbol }) {
            quotes[symbol] = nil
            errors[symbol] = nil
        }
    }

    func remove(_ position: Position) {
        guard let index = positions.firstIndex(where: { $0.id == position.id }) else { return }
        remove(atOffsets: [index])
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        positions.move(fromOffsets: source, toOffset: destination)
    }

    // MARK: - Totals

    /// Value of every position that has a quote.
    var totalValue: Double {
        positions.reduce(0) { total, position in
            total + (quotes[position.asset.symbol].map { position.marketValue(at: $0.current) } ?? 0)
        }
    }

    /// Cost of the positions counted in `totalValue`, so the gain compares like with like.
    var quotedCostBasis: Double {
        positions.reduce(0) { total, position in
            total + (quotes[position.asset.symbol] == nil ? 0 : position.costBasis)
        }
    }

    var totalDayChange: Double {
        positions.reduce(0) { total, position in
            total + (quotes[position.asset.symbol].flatMap { position.dayChange($0) } ?? 0)
        }
    }

    /// Portfolio value per category, in `AssetCategory` order. Positions
    /// without a quote yet count at their cost basis; ones not yet
    /// classified are left out until they are.
    var allocation: [(category: AssetCategory, value: Double)] {
        var totals: [AssetCategory: Double] = [:]
        for position in positions {
            guard let category = categories[position.asset.symbol] else { continue }
            let value = quotes[position.asset.symbol].map { position.marketValue(at: $0.current) } ?? position.costBasis
            totals[category, default: 0] += value
        }
        return AssetCategory.allCases.compactMap { category in
            totals[category].flatMap { $0 > 0 ? (category, $0) : nil }
        }
    }

    // MARK: - Loading

    func refreshAll() async {
        // Several lots of the same asset share one quote.
        var seen = Set<String>()
        let assets = positions.map(\.asset).filter { seen.insert($0.symbol).inserted }
        await withTaskGroup(of: Void.self) { group in
            for asset in assets {
                group.addTask { await self.refresh(asset) }
                group.addTask { await self.classify(asset) }
            }
        }
    }

    private func classify(_ asset: Asset) async {
        guard categories[asset.symbol] == nil, !classifying.contains(asset.symbol) else { return }
        classifying.insert(asset.symbol)
        let result = await AssetClassifier(finnhub: finnhub, yahoo: yahoo).classify(asset)
        categories[asset.symbol] = result.category
        if result.isConfirmed { confirmedCategories[asset.symbol] = result.category }
    }

    func refresh(_ asset: Asset) async {
        let snapshot = await QuoteLoader(finnhub: finnhub, yahoo: yahoo).load(asset)
        if let quote = snapshot.quote {
            quotes[asset.symbol] = quote
            errors[asset.symbol] = nil
        } else if let failure = snapshot.failure, !failure.isCancellation {
            errors[asset.symbol] = failure.localizedDescription
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(positions) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}
