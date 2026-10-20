//
//  PortfolioAdvisor.swift
//  SmartStock
//

import Foundation

/// Claude's review of the user's portfolio.
struct PortfolioAnalysis: Codable {
    struct Recommendation: Codable, Identifiable {
        enum Priority: String, Codable { case high, medium, low }

        let title: String
        let detail: String
        let priority: Priority

        var id: String { title }
    }

    enum Rating: String, Codable { case poor, fair, good, excellent }

    let summary: String
    let diversification: Rating
    let strengths: [String]
    let risks: [String]
    let recommendations: [Recommendation]
}

enum InsightsError: LocalizedError {
    case notConfigured
    case server(status: Int, message: String?)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "Portfolio Insights isn't set up. Add INSIGHTS_API_HOST to Config/Secrets.xcconfig and rebuild."
        case .server(_, let message?):
            message
        case .server(let status, nil):
            "Portfolio Insights request failed (\(status))."
        case .badResponse:
            "Portfolio Insights returned a response the app couldn't read."
        }
    }
}

/// Asks Claude to review the positions in a `PortfolioStore` and suggest
/// improvements. Requests go through the SmartStock Insights Worker
/// (insights-worker/ in the repo), which holds the Anthropic API key and the
/// prompt, so neither ships in the app.
struct PortfolioAdvisor {
    private let endpoint: URL?
    private let session: URLSession

    init(endpoint: URL? = PortfolioAdvisor.bundledEndpoint, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.session = session
    }

    /// The Worker's `/analyze` URL, from the host injected into Info.plist
    /// from Secrets.xcconfig at build time.
    static var bundledEndpoint: URL? {
        guard let host = Bundle.main.object(forInfoDictionaryKey: "InsightsAPIHost") as? String else { return nil }
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        // An unset build setting expands to "", and the template ships a placeholder.
        guard !trimmed.isEmpty, !trimmed.hasPrefix("$("), trimmed != "your-worker.your-subdomain.workers.dev"
        else { return nil }
        // Local `wrangler dev` serves plain HTTP; deployed Workers use HTTPS.
        let scheme = trimmed.hasPrefix("localhost") || trimmed.hasPrefix("127.0.0.1") ? "http" : "https"
        return URL(string: "\(scheme)://\(trimmed)/analyze")
    }

    func analyze(_ portfolio: PortfolioStore) async throws -> PortfolioAnalysis {
        guard let endpoint else { throw InsightsError.notConfigured }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        // Thinking can take a while; the default 60-second timeout is too short.
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONEncoder().encode(["holdings": Self.holdings(in: portfolio)])

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let message = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
            throw InsightsError.server(status: http.statusCode, message: message)
        }
        guard let analysis = try? JSONDecoder().decode(PortfolioAnalysis.self, from: data) else {
            throw InsightsError.badResponse
        }
        return analysis
    }

    /// One holding in the request body; the Worker turns these into the prompt.
    private struct Holding: Encodable {
        let symbol: String
        let name: String
        let type: String?
        let category: String?
        var shares = 0.0
        var value = 0.0
        var cost = 0.0
    }

    /// The portfolio's holdings, combining lots of the same asset.
    private static func holdings(in portfolio: PortfolioStore) -> [Holding] {
        var holdings: [String: Holding] = [:]
        var order: [String] = []
        for position in portfolio.positions {
            let asset = position.asset
            if holdings[asset.symbol] == nil {
                holdings[asset.symbol] = Holding(
                    symbol: asset.symbol,
                    name: asset.name,
                    type: asset.securityType,
                    category: portfolio.categories[asset.symbol]?.title
                )
                order.append(asset.symbol)
            }
            // Unquoted positions count at cost, as in the allocation chart.
            let price = portfolio.quotes[asset.symbol]?.current ?? position.purchasePrice
            holdings[asset.symbol]!.shares += position.shares
            holdings[asset.symbol]!.cost += position.costBasis
            holdings[asset.symbol]!.value += position.marketValue(at: price)
        }
        return order.compactMap { holdings[$0] }
    }
}
