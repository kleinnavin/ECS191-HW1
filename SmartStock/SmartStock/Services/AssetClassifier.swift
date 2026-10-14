//
//  AssetClassifier.swift
//  SmartStock
//

import Foundation

/// Works out an asset's category from both data sources. Neither has a
/// ready-made asset class on the free tier, so it combines:
/// 1. Finnhub's company profile, which exists only for single stocks and
///    gives the headquarters country (U.S. vs. international).
/// 2. Yahoo's quoteSummary, which gives funds their Morningstar category
///    ("Foreign Large Blend", "Long Government", ...).
/// 3. If both fail, the security type (from Finnhub's search, or Yahoo's
///    chart) plus keywords in the fund's name.
struct AssetClassifier {
    struct Result {
        let category: AssetCategory
        /// From a profile rather than a guess, so it's safe to keep for good.
        let isConfirmed: Bool
    }

    let finnhub: FinnhubClient
    let yahoo: YahooFinanceClient

    func classify(_ asset: Asset) async -> Result {
        if asset.isIndividualStock != false, finnhub.hasAPIKey,
           let profile = try? await finnhub.profile(for: asset.symbol), let country = profile.country {
            return Result(category: .stock(country: country), isConfirmed: true)
        }

        if let profile = try? await yahoo.profile(for: asset.symbol) {
            if profile.quoteType == "EQUITY", let country = profile.country {
                return Result(category: .stock(country: country), isConfirmed: true)
            }
            if let fundCategory = profile.fundCategory, !fundCategory.isEmpty {
                // Categories without a region or bond term ("Large Blend",
                // "Technology") are U.S. stock funds.
                return Result(category: .fund(matching: fundCategory) ?? .usStockFund, isConfirmed: true)
            }
        }

        // Guess from the security type and the fund's name.
        let isStock: Bool?
        if let known = asset.isIndividualStock {
            isStock = known
        } else {
            switch try? await yahoo.chart(for: asset.symbol).instrumentType {
            case "EQUITY": isStock = true
            case "ETF", "MUTUALFUND": isStock = false
            default: isStock = nil
            }
        }
        let guess: AssetCategory = switch isStock {
        // A company's name says little about where it's based ("Global
        // Payments" is a U.S. company); ADRs are foreign by definition.
        case true: asset.securityType == "ADR" ? .internationalStock : .usStock
        case false: .fund(matching: asset.name) ?? .usStockFund
        case nil: .fund(matching: asset.name) ?? .other
        }
        return Result(category: guess, isConfirmed: false)
    }
}
