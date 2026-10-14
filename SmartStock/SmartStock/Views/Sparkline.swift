//
//  Sparkline.swift
//  SmartStock
//

import Charts
import SwiftUI

/// Small intraday chart for a watchlist row, with the previous close as a
/// dashed baseline (like the Stocks app).
struct Sparkline: View {
    let history: PriceHistory

    /// Roughly one point per pixel column is plenty at sparkline size;
    /// a 1-minute day has 391 points for a 72-point-wide view.
    private static let maxPoints = 100

    var body: some View {
        let color: Color = history.isUp ? .stockGreen : .stockRed
        let points = thinnedPoints
        let domain = domain

        Chart {
            ForEach(points) { point in
                AreaMark(
                    x: .value("Time", point.date),
                    yStart: .value("Floor", domain.lowerBound),
                    yEnd: .value("Price", point.price)
                )
                .foregroundStyle(
                    LinearGradient(colors: [color.opacity(0.35), color.opacity(0)], startPoint: .top, endPoint: .bottom)
                )
                LineMark(x: .value("Time", point.date), y: .value("Price", point.price))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            if let previousClose = history.previousClose {
                RuleMark(y: .value("Previous Close", previousClose))
                    .foregroundStyle(color.opacity(0.8))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: domain)
        .chartLegend(.hidden)
        .accessibilityHidden(true)
    }

    /// Every Nth point, always keeping the latest.
    private var thinnedPoints: [PricePoint] {
        let points = history.points
        guard points.count > Self.maxPoints else { return points }
        let step = Int((Double(points.count) / Double(Self.maxPoints)).rounded(.up))
        var thinned = stride(from: 0, to: points.count, by: step).map { points[$0] }
        if thinned.last != points.last, let last = points.last { thinned.append(last) }
        return thinned
    }

    /// Fits both the prices and the baseline, with a little headroom.
    private var domain: ClosedRange<Double> {
        var values = history.points.map(\.price)
        if let previousClose = history.previousClose { values.append(previousClose) }
        guard let low = values.min(), let high = values.max(), high > low else {
            let mid = values.first ?? 0
            return (mid - 1)...(mid + 1)
        }
        let pad = (high - low) * 0.08
        return (low - pad)...(high + pad)
    }
}

extension Color {
    static let stockGreen = Color(red: 0.20, green: 0.78, blue: 0.35)
    static let stockRed = Color(red: 1.0, green: 0.27, blue: 0.23)
    /// Indicator colors, chosen to stand apart from the green/red price line.
    static let smaLine = Color.orange
    static let rsiLine = Color(red: 0.75, green: 0.55, blue: 1.0)
}
