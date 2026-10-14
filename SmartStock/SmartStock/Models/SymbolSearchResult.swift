//
//  SymbolSearchResult.swift
//  SmartStock
//

import Foundation

/// Response from Finnhub's `/search` endpoint.
struct SymbolSearchResponse: Decodable {
    let count: Int
    let result: [SymbolSearchResult]
}

/// Response from Finnhub's `/stock/profile2` endpoint.
struct CompanyProfile: Decodable {
    /// Two-letter country code of the company's headquarters, e.g. "US" or "TW".
    let country: String?
    /// Finnhub's industry classification, e.g. "Technology" or "Real Estate".
    let finnhubIndustry: String?
}

struct SymbolSearchResult: Decodable, Identifiable, Hashable {
    let description: String
    let displaySymbol: String
    let symbol: String
    let type: String

    var id: String { symbol }

    var asAsset: Asset {
        Asset(symbol: symbol, title: displaySymbol, name: description.capitalizedIfShouting, securityType: type)
    }
}

private extension String {
    /// Finnhub returns names in all caps ("APPLE INC"); soften them to "Apple Inc".
    var capitalizedIfShouting: String {
        self == uppercased() ? capitalized : self
    }
}
