//
//  Indicators.swift
//  SmartStock
//

import Foundation

/// Technical indicators computed from a series of closing prices. Each
/// result has one entry per input value, `nil` until enough data exists.
enum Indicators {
    /// Simple moving average: the mean of the last `period` closes.
    static func sma(_ closes: [Double], period: Int) -> [Double?] {
        guard period > 0 else { return closes.map { _ in nil } }
        var result = [Double?](repeating: nil, count: closes.count)
        var sum = 0.0
        for (index, close) in closes.enumerated() {
            sum += close
            if index >= period { sum -= closes[index - period] }
            if index >= period - 1 { result[index] = sum / Double(period) }
        }
        return result
    }

    /// Relative Strength Index (0–100) using Wilder's smoothing, the
    /// standard definition. Above 70 is conventionally "overbought" and
    /// below 30 "oversold".
    static func rsi(_ closes: [Double], period: Int = 14) -> [Double?] {
        var result = [Double?](repeating: nil, count: closes.count)
        guard period > 0, closes.count > period else { return result }

        // Seed with the plain average gain/loss over the first `period` changes.
        var averageGain = 0.0
        var averageLoss = 0.0
        for index in 1...period {
            let change = closes[index] - closes[index - 1]
            averageGain += max(change, 0)
            averageLoss += max(-change, 0)
        }
        averageGain /= Double(period)
        averageLoss /= Double(period)
        result[period] = rsiValue(averageGain, averageLoss)

        // Then smooth: each new change gets weight 1/period.
        for index in (period + 1)..<closes.count {
            let change = closes[index] - closes[index - 1]
            averageGain = (averageGain * Double(period - 1) + max(change, 0)) / Double(period)
            averageLoss = (averageLoss * Double(period - 1) + max(-change, 0)) / Double(period)
            result[index] = rsiValue(averageGain, averageLoss)
        }
        return result
    }

    private static func rsiValue(_ averageGain: Double, _ averageLoss: Double) -> Double {
        if averageLoss == 0 { return averageGain == 0 ? 50 : 100 }
        return 100 - 100 / (1 + averageGain / averageLoss)
    }
}

// MARK: - Per-range settings

extension YahooFinanceClient.Range {
    /// RSI's conventional 14 periods, measured in this range's bars.
    var rsiPeriod: Int { 14 }

    /// SMA length scaled to the range: about an hour on 1D, a day on 1W,
    /// the classic 20/50-day averages on daily charts, and so on.
    var smaPeriod: Int {
        switch self {
        case .oneDay: 60            // 60 × 1 min = 1 hour
        case .fiveDays: 26          // 26 × 15 min = 1 trading day
        case .oneMonth: 35          // 35 × 1 hour ≈ 1 trading week
        case .threeMonths: 20       // 20 days ≈ 1 month
        case .sixMonths, .yearToDate, .oneYear: 50   // 50 days
        case .twoYears: 20          // 20 weeks
        case .fiveYears: 40         // 40 weeks ≈ the 200-day average
        case .tenYears, .max: 12    // 12 months
        }
    }

    /// Bar length in words, for labels like "50 daily bars".
    var barName: String {
        switch interval {
        case "1m": "1-min"
        case "5m": "5-min"
        case "15m": "15-min"
        case "1h": "hourly"
        case "1d": "daily"
        case "1wk": "weekly"
        case "1mo": "monthly"
        default: interval
        }
    }

    /// A longer range at the same bar interval, fetched so indicators are
    /// already warmed up at the left edge of the chart. Yahoo limits how far
    /// back fine intervals go, so the lookbacks stay within those limits.
    var indicatorLookback: YahooFinanceClient.Range? {
        switch self {
        case .oneDay: .fiveDays
        case .fiveDays: .oneMonth
        case .oneMonth: .threeMonths
        case .threeMonths: .sixMonths
        case .sixMonths: .oneYear
        case .yearToDate, .oneYear: .twoYears
        case .twoYears: .fiveYears
        case .fiveYears: .tenYears
        case .tenYears: .max
        case .max: nil
        }
    }
}
