//
//  InsightsStore.swift
//  SmartStock
//

import Foundation
import Observation

/// The most recent portfolio analysis from Claude, saved across launches.
/// A new analysis is only requested when the user asks for one, so opening
/// Portfolio Insights doesn't spend an API call.
@Observable
final class InsightsStore {
    struct Saved: Codable {
        let analysis: PortfolioAnalysis
        let date: Date
        /// The positions the analysis was based on; see `fingerprint(of:)`.
        let positions: String
    }

    private(set) var saved: Saved? {
        didSet { defaults.set(try? JSONEncoder().encode(saved), forKey: Self.storageKey) }
    }
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    /// Identifies the request in flight, so one that finishes after `clear()`
    /// doesn't bring back insights for positions that were deleted.
    private var requestID: UUID?

    private let advisor: PortfolioAdvisor
    private let defaults: UserDefaults
    private static let storageKey = "insights.latest"

    init(advisor: PortfolioAdvisor = PortfolioAdvisor(), defaults: UserDefaults = .standard) {
        self.advisor = advisor
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey) {
            saved = try? JSONDecoder().decode(Saved.self, from: data)
        }
    }

    /// Whether positions were added, removed or changed since the saved analysis.
    func isOutdated(for portfolio: PortfolioStore) -> Bool {
        saved.map { $0.positions != Self.fingerprint(of: portfolio) } ?? false
    }

    /// Requests a new analysis. It runs outside any view's task so closing
    /// the sheet doesn't throw away a request that's already been paid for.
    func generate(for portfolio: PortfolioStore) {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        let positions = Self.fingerprint(of: portfolio)
        let id = UUID()
        requestID = id
        Task {
            do {
                let analysis = try await advisor.analyze(portfolio)
                guard requestID == id else { return }
                saved = Saved(analysis: analysis, date: .now, positions: positions)
            } catch {
                guard requestID == id else { return }
                errorMessage = error.localizedDescription
            }
            isLoading = false
            requestID = nil
        }
    }

    /// Deletes the saved analysis and abandons any request in flight, e.g.
    /// once every position has been removed.
    func clear() {
        saved = nil
        errorMessage = nil
        isLoading = false
        requestID = nil
    }

    private static func fingerprint(of portfolio: PortfolioStore) -> String {
        portfolio.positions
            .map { "\($0.asset.symbol) \($0.shares) \($0.purchasePrice)" }
            .sorted()
            .joined(separator: ";")
    }
}
