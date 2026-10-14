//
//  YahooFinanceClient.swift
//  SmartStock
//

import Foundation

enum YahooFinanceError: LocalizedError {
    case http(status: Int)
    case noData(symbol: String, reason: String?)

    var errorDescription: String? {
        switch self {
        case .http(let status) where status == 429:
            "Yahoo Finance rate limit reached. Try again in a minute."
        case .http(let status):
            "Yahoo Finance request failed (\(status))."
        case .noData(let symbol, let reason):
            reason ?? "No chart data available for \(symbol)."
        }
    }
}

/// Client for Yahoo Finance's unofficial chart endpoint. Used for index
/// quotes and price history, which Finnhub's free tier doesn't provide.
/// It needs no API key, but Yahoo may change or rate-limit it without notice.
struct YahooFinanceClient {
    /// Every range Yahoo's chart endpoint serves, shortest first.
    enum Range: String, CaseIterable, Identifiable {
        case oneDay = "1d", fiveDays = "5d", oneMonth = "1mo", threeMonths = "3mo"
        case sixMonths = "6mo", yearToDate = "ytd", oneYear = "1y", twoYears = "2y"
        case fiveYears = "5y", tenYears = "10y", max = "max"

        var id: String { rawValue }

        /// Button title, matching the Stocks app.
        var title: String {
            switch self {
            case .oneDay: "1D"
            case .fiveDays: "1W"
            case .oneMonth: "1M"
            case .threeMonths: "3M"
            case .sixMonths: "6M"
            case .yearToDate: "YTD"
            case .oneYear: "1Y"
            case .twoYears: "2Y"
            case .fiveYears: "5Y"
            case .tenYears: "10Y"
            case .max: "ALL"
            }
        }

        /// Finest interval Yahoo serves for the range, keeping charts to a
        /// few hundred points.
        var interval: String {
            switch self {
            case .oneDay: "1m"
            case .fiveDays: "15m"
            case .oneMonth: "1h"
            case .threeMonths, .sixMonths, .yearToDate, .oneYear: "1d"
            case .twoYears, .fiveYears: "1wk"
            case .tenYears, .max: "1mo"
            }
        }

        var isIntraday: Bool { self == .oneDay || self == .fiveDays || self == .oneMonth }
    }

    struct Chart {
        let quote: Quote
        let history: PriceHistory
        let stats: MarketStats
        /// Yahoo's security type, e.g. "EQUITY", "ETF", "MUTUALFUND" or "CRYPTOCURRENCY".
        let instrumentType: String?
    }

    /// What Yahoo's quoteSummary endpoint says a security is.
    struct Profile {
        /// e.g. "EQUITY", "ETF", "MUTUALFUND".
        let quoteType: String?
        /// Morningstar category for funds, e.g. "Foreign Large Blend" or "Intermediate Government".
        let fundCategory: String?
        /// Headquarters country for stocks, e.g. "United States".
        let country: String?
        let industry: String?
    }

    /// Figures for the detail screen's stats section; `nil` when Yahoo
    /// doesn't provide them.
    struct MarketStats: Hashable {
        let fiftyTwoWeekHigh: Double?
        let fiftyTwoWeekLow: Double?
        /// Today's trading volume.
        let volume: Double?
        /// Mean volume per bar over this chart's range. On a 3-month daily
        /// chart this is the average daily volume Yahoo shows as "Avg Vol".
        let averageVolume: Double?
    }

    private let baseURL = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Converts a Finnhub symbol to Yahoo's format (e.g. "BRK.B" -> "BRK-B").
    static func yahooSymbol(for symbol: String) -> String {
        symbol.hasPrefix("^") ? symbol : symbol.replacingOccurrences(of: ".", with: "-")
    }

    /// - Parameter interval: Bar size; defaults to the range's own interval.
    ///   Pass one explicitly to fetch a longer range at a finer interval.
    func chart(for symbol: String, range: Range = .oneDay, interval: String? = nil) async throws -> Chart {
        try await chart(for: symbol, query: [
            URLQueryItem(name: "range", value: range.rawValue),
            URLQueryItem(name: "interval", value: interval ?? range.interval),
        ], comparesToPreviousDay: range == .oneDay)
    }

    /// Bars between two dates, e.g. from a purchase date to now. Yahoo
    /// limits intraday intervals to recent dates (15m: 60 days, 1h: 730 days).
    func chart(for symbol: String, from start: Date, to end: Date = .now, interval: String) async throws -> Chart {
        try await chart(for: symbol, query: [
            URLQueryItem(name: "period1", value: String(Int(start.timeIntervalSince1970))),
            URLQueryItem(name: "period2", value: String(Int(end.timeIntervalSince1970))),
            URLQueryItem(name: "interval", value: interval),
        ], comparesToPreviousDay: false)
    }

    private func chart(for symbol: String, query: [URLQueryItem], comparesToPreviousDay: Bool) async throws -> Chart {
        let yahooSymbol = Self.yahooSymbol(for: symbol)
        var components = URLComponents(url: baseURL.appending(path: yahooSymbol), resolvingAgainstBaseURL: false)!
        components.queryItems = query

        let (data, response) = try await session.data(from: components.url!)
        let decoded = try? JSONDecoder().decode(ChartResponse.self, from: data)

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            if let error = decoded?.chart.error {
                throw YahooFinanceError.noData(symbol: symbol, reason: error.description)
            }
            throw YahooFinanceError.http(status: http.statusCode)
        }
        guard let result = decoded?.chart.result?.first, let price = result.meta.regularMarketPrice else {
            throw YahooFinanceError.noData(symbol: symbol, reason: decoded?.chart.error?.description)
        }

        let meta = result.meta
        let bars = result.indicators.quote.first
        let closes = bars?.close ?? []
        let points = zip(result.timestamp ?? [], closes).compactMap { time, close in
            close.map { PricePoint(date: Date(timeIntervalSince1970: time), price: $0) }
        }

        // For a one-day chart the comparison point is yesterday's close;
        // for longer ranges it's the close before the range started.
        let previousClose = comparesToPreviousDay
            ? (meta.previousClose ?? meta.chartPreviousClose)
            : meta.chartPreviousClose
        let change = previousClose.map { price - $0 }

        var quote = Quote(
            current: price,
            change: change,
            percentChange: zip2(change, previousClose).map { $0 / $1 * 100 },
            high: meta.regularMarketDayHigh ?? 0,
            low: meta.regularMarketDayLow ?? 0,
            open: bars?.open?.lazy.compactMap { $0 }.first ?? 0,
            previousClose: previousClose ?? 0,
            timestamp: meta.regularMarketTime ?? 0
        )
        quote.sourceSymbol = symbol

        let volumes = (bars?.volume ?? []).compactMap { $0 }.filter { $0 > 0 }
        let stats = MarketStats(
            fiftyTwoWeekHigh: meta.fiftyTwoWeekHigh,
            fiftyTwoWeekLow: meta.fiftyTwoWeekLow,
            volume: meta.regularMarketVolume.flatMap { $0 > 0 ? $0 : nil },
            averageVolume: volumes.isEmpty ? nil : volumes.reduce(0, +) / Double(volumes.count)
        )

        return Chart(
            quote: quote,
            history: PriceHistory(points: points, previousClose: previousClose),
            stats: stats,
            instrumentType: meta.instrumentType
        )
    }

    // MARK: - Search

    /// Mutual funds matching `text`. Finnhub's free search leaves them out,
    /// so this fills the gap.
    func searchMutualFunds(_ text: String) async throws -> [SymbolSearchResult] {
        var components = URLComponents(string: "https://query2.finance.yahoo.com/v1/finance/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "quotesCount", value: "10"),
            URLQueryItem(name: "newsCount", value: "0"),
        ]
        let (data, response) = try await session.data(from: components.url!)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw YahooFinanceError.http(status: http.statusCode)
        }
        return try JSONDecoder().decode(SearchResponse.self, from: data).quotes.compactMap { quote in
            // U.S. funds only; foreign listings carry a suffix such as ".L".
            guard quote.quoteType == "MUTUALFUND", let symbol = quote.symbol, !symbol.contains(".") else { return nil }
            return SymbolSearchResult(
                description: quote.longname ?? quote.shortname ?? symbol,
                displaySymbol: symbol,
                symbol: symbol,
                type: "Mutual Fund"
            )
        }
    }

    // MARK: - Profile

    /// quoteSummary needs a session cookie plus a matching "crumb" token,
    /// fetched once and shared by every client.
    private static var crumb: String?

    func profile(for symbol: String) async throws -> Profile {
        do {
            return try await profile(for: symbol, crumb: try await crumb())
        } catch YahooFinanceError.http(let status) where status == 401 || status == 403 {
            // The cookie or crumb expired; get a fresh pair and try once more.
            Self.crumb = nil
            return try await profile(for: symbol, crumb: try await crumb())
        }
    }

    private func profile(for symbol: String, crumb: String) async throws -> Profile {
        let url = URL(string: "https://query2.finance.yahoo.com/v10/finance/quoteSummary")!
            .appending(path: Self.yahooSymbol(for: symbol))
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "modules", value: "quoteType,fundProfile,assetProfile"),
            URLQueryItem(name: "crumb", value: crumb),
        ]
        let (data, response) = try await session.data(from: components.url!)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw YahooFinanceError.http(status: http.statusCode)
        }
        guard let result = try JSONDecoder().decode(SummaryResponse.self, from: data).quoteSummary.result?.first else {
            throw YahooFinanceError.noData(symbol: symbol, reason: nil)
        }
        return Profile(
            quoteType: result.quoteType?.quoteType,
            fundCategory: result.fundProfile?.categoryName,
            country: result.assetProfile?.country,
            industry: result.assetProfile?.industry
        )
    }

    private func crumb() async throws -> String {
        if let crumb = Self.crumb { return crumb }
        // This request only sets the session cookie; its response (often a 404) doesn't matter.
        _ = try? await session.data(from: URL(string: "https://fc.yahoo.com")!)
        let (data, response) = try await session.data(from: URL(string: "https://query2.finance.yahoo.com/v1/test/getcrumb")!)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw YahooFinanceError.http(status: http.statusCode)
        }
        let crumb = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        // A crumb is a short token; anything else is an error page.
        guard !crumb.isEmpty, crumb.count <= 32, !crumb.contains(" ") else {
            throw YahooFinanceError.noData(symbol: "", reason: "Yahoo Finance didn't provide a session token.")
        }
        Self.crumb = crumb
        return crumb
    }
}

private func zip2<A, B>(_ a: A?, _ b: B?) -> (A, B)? {
    guard let a, let b else { return nil }
    return (a, b)
}

// MARK: - Response

private struct ChartResponse: Decodable {
    let chart: Body

    struct Body: Decodable {
        let result: [Result]?
        let error: APIError?
    }

    struct APIError: Decodable {
        let code: String
        let description: String
    }

    struct Result: Decodable {
        let meta: Meta
        let timestamp: [TimeInterval]?
        let indicators: Indicators
    }

    struct Meta: Decodable {
        let regularMarketPrice: Double?
        let previousClose: Double?
        let chartPreviousClose: Double?
        let regularMarketDayHigh: Double?
        let regularMarketDayLow: Double?
        let regularMarketTime: TimeInterval?
        let regularMarketVolume: Double?
        let fiftyTwoWeekHigh: Double?
        let fiftyTwoWeekLow: Double?
        let instrumentType: String?
    }

    struct Indicators: Decodable {
        let quote: [Bars]
    }

    struct Bars: Decodable {
        let open: [Double?]?
        let close: [Double?]?
        let volume: [Double?]?
    }
}

private struct SummaryResponse: Decodable {
    let quoteSummary: Body

    struct Body: Decodable {
        let result: [Result]?
    }

    struct Result: Decodable {
        let quoteType: QuoteType?
        let fundProfile: FundProfile?
        let assetProfile: AssetProfile?
    }

    struct QuoteType: Decodable {
        let quoteType: String?
    }

    struct FundProfile: Decodable {
        let categoryName: String?
    }

    struct AssetProfile: Decodable {
        let country: String?
        let industry: String?
    }
}

private struct SearchResponse: Decodable {
    let quotes: [Quote]

    struct Quote: Decodable {
        let symbol: String?
        let shortname: String?
        let longname: String?
        let quoteType: String?
    }
}
