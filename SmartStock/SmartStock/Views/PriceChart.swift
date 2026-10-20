//
//  PriceChart.swift
//  SmartStock
//

import Charts
import SwiftUI

/// Full-size price history chart. Points are plotted by index rather than
/// by date so overnight and weekend gaps don't stretch the line, as in the
/// Stocks app. Drag across the chart to inspect a point.
///
/// Equatable on its data so dragging (which only changes the selection)
/// doesn't rebuild hundreds of marks each frame; the selection marker is a
/// separate overlay view that redraws on its own. Use with `.equatable()`.
struct PriceChart: View, Equatable {
    let history: PriceHistory
    let range: YahooFinanceClient.Range
    @Binding var selectedIndex: Int?
    /// Simple moving average aligned with `history.points`; empty to hide it.
    var sma: [Double?] = []
    /// Value drawn as a dashed line, such as a position's cost basis.
    /// Defaults to the previous close on 1D and none otherwise.
    var baseline: Double? = nil

    /// A full regular session at 1-minute intervals: 9:30 through the
    /// 4:00 closing bar (6.5 hours).
    private static let barsPerTradingDay = 391

    /// Fixed y-axis label width, shared with `RSIChart` so both plots line up.
    static let yAxisLabelWidth: CGFloat = 46

    static func == (lhs: PriceChart, rhs: PriceChart) -> Bool {
        lhs.range == rhs.range && lhs.history == rhs.history && lhs.sma == rhs.sma && lhs.baseline == rhs.baseline
    }

    var body: some View {
        // Computed once per render rather than once per mark.
        let color: Color = isUp ? .stockGreen : .stockRed
        let points = history.points
        let yDomain = yDomain
        let xTicks = xTicks
        let gradient = LinearGradient(colors: [color.opacity(0.35), color.opacity(0)], startPoint: .top, endPoint: .bottom)

        Chart {
            ForEach(points.indices, id: \.self) { index in
                AreaMark(
                    x: .value("Index", index),
                    yStart: .value("Floor", yDomain.lowerBound),
                    yEnd: .value("Price", points[index].price)
                )
                .foregroundStyle(gradient)
                LineMark(
                    x: .value("Index", index),
                    y: .value("Price", points[index].price),
                    series: .value("Series", "Price")
                )
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: 2))
            }

            ForEach(sma.indices, id: \.self) { index in
                if let average = sma[index] {
                    LineMark(
                        x: .value("Index", index),
                        y: .value("SMA", average),
                        series: .value("Series", "SMA")
                    )
                    .foregroundStyle(Color.smaLine)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
            }

            if let baselineValue {
                RuleMark(y: .value("Baseline", baselineValue))
                    .foregroundStyle(Color.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: yDomain)
        .chartXSelection(value: $selectedIndex)
        .chartXAxis {
            AxisMarks(values: xTicks) { _ in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.12))
            }
        }
        .chartOverlay(alignment: .topLeading) { proxy in
            GeometryReader { geometry in
                if let plotFrame = proxy.plotFrame {
                    let plot = geometry[plotFrame]
                    // Charts' own x labels sit right of their gridlines and the
                    // newest one gets dropped near the edge, so draw them centered.
                    ForEach(xTicks, id: \.self) { index in
                        if let x = proxy.position(forX: index), points.indices.contains(index) {
                            let label = xLabel(for: points[index].date)
                            // Rough half-width of a caption2 label, so edge labels
                            // shift only as far as needed to stay inside the plot.
                            let halfWidth = CGFloat(label.count) * 3.5
                            Text(label)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize()
                                .position(
                                    x: min(max(plot.minX + x, plot.minX + halfWidth), plot.maxX - halfWidth),
                                    y: plot.maxY + 12
                                )
                        }
                    }
                }
                ChartSelectionMarker(
                    proxy: proxy,
                    plotSize: geometry.size,
                    prices: points.map(\.price),
                    color: color,
                    selectedIndex: $selectedIndex
                )
            }
        }
        .padding(.bottom, 22)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.12))
                AxisValueLabel {
                    if let price = value.as(Double.self) {
                        // Decide decimals from the chart's scale, not each label,
                        // so a 0 tick on a large-valued chart isn't "0.00".
                        Text(price, format: .number.precision(.fractionLength(yDomain.upperBound >= 1000 ? 0 : 2)))
                            .frame(width: Self.yAxisLabelWidth, alignment: .leading)
                    }
                }
            }
        }
        .accessibilityLabel("Price history")
    }

    private var isUp: Bool {
        guard let last = history.points.last?.price,
              let start = history.previousClose ?? history.points.first?.price else { return true }
        return last >= start
    }

    private var baselineValue: Double? {
        baseline ?? (range == .oneDay ? history.previousClose : nil)
    }

    private var xDomain: ClosedRange<Int> { Self.xDomain(count: history.points.count, range: range) }

    /// 1D reserves room for the whole session so a partial day fills from the left.
    static func xDomain(count: Int, range: YahooFinanceClient.Range) -> ClosedRange<Int> {
        let last = max(count - 1, 1)
        return 0...(range == .oneDay ? max(last, barsPerTradingDay - 1) : last)
    }

    private var yDomain: ClosedRange<Double> {
        var values = history.points.map(\.price) + sma.compactMap { $0 }
        if let baselineValue { values.append(baselineValue) }
        guard let low = values.min(), let high = values.max(), high > low else {
            let mid = values.first ?? 0
            return (mid - 1)...(mid + 1)
        }
        let pad = (high - low) * 0.08
        return (low - pad)...(high + pad)
    }

    // MARK: - X axis

    /// Calendar boundary that gets a tick (e.g. each hour on 1D, each month on 1Y).
    private var tickComponent: Calendar.Component {
        switch range {
        case .oneDay: .hour
        case .fiveDays: .day
        case .oneMonth: .weekOfYear
        case .threeMonths, .sixMonths, .yearToDate, .oneYear, .twoYears: .month
        case .fiveYears, .tenYears, .max: .year
        }
    }

    /// Indices where the tick component changes, thinned to round values
    /// (every 5 years, every 3 months, ...) so ticks stay evenly spaced
    /// and the last one lands near the end of the data.
    private var xTicks: [Int] {
        let calendar = Calendar.current
        let points = history.points
        let maxTicks = 7

        // (index, component value) at each boundary, e.g. (412, 2025).
        var boundaries: [(index: Int, value: Int)] = []
        for index in points.indices.dropFirst() {
            let value = calendar.component(tickComponent, from: points[index].date)
            if value != calendar.component(tickComponent, from: points[index - 1].date) {
                boundaries.append((index, value))
            }
        }
        guard boundaries.count > maxTicks else { return boundaries.map(\.index) }

        // Months count from January so a step of 3 gives Jan/Apr/Jul/Oct.
        let offset = tickComponent == .month ? 1 : 0
        let roundSteps: [Int] = switch tickComponent {
        case .year: [2, 5, 10, 20, 25, 50]
        case .month: [2, 3, 4, 6, 12]
        default: []
        }
        for step in roundSteps {
            let ticks = boundaries.filter { ($0.value - offset) % step == 0 }.map(\.index)
            if ticks.count <= maxTicks { return ticks }
        }

        // No round step fits (hours, days, weeks): take every Nth boundary,
        // counting back from the last so the newest one is always labeled.
        let step = Int((Double(boundaries.count) / Double(maxTicks)).rounded(.up))
        return stride(from: boundaries.count - 1, through: 0, by: -step).map { boundaries[$0].index }.reversed()
    }

    private func xLabel(for date: Date) -> String {
        switch range {
        case .oneDay: date.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)))
        case .fiveDays: date.formatted(.dateTime.weekday(.abbreviated))
        case .oneMonth: date.formatted(.dateTime.month(.abbreviated).day())
        case .threeMonths, .sixMonths, .yearToDate, .oneYear: date.formatted(.dateTime.month(.abbreviated))
        case .twoYears: date.formatted(.dateTime.month(.abbreviated).year(.twoDigits))
        case .fiveYears, .tenYears, .max: date.formatted(.dateTime.year())
        }
    }
}

/// Vertical line (and optional dot) at the selected point, drawn over a
/// chart. It's the only part that redraws while the user drags.
struct ChartSelectionMarker: View {
    let proxy: ChartProxy
    let plotSize: CGSize
    /// Values to place the dot at; nil draws just the line.
    let prices: [Double]?
    let color: Color
    @Binding var selectedIndex: Int?

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let plotFrame = proxy.plotFrame, let index = selectedIndex,
               let x = proxy.position(forX: index) {
                GeometryReader { geometry in
                    let plot = geometry[plotFrame]
                    Rectangle()
                        .fill(Color.primary.opacity(0.6))
                        .frame(width: 1, height: plot.height)
                        .position(x: plot.minX + x, y: plot.midY)
                    if let prices, prices.indices.contains(index),
                       let y = proxy.position(forY: prices[index]) {
                        Circle()
                            .fill(color)
                            .frame(width: 10, height: 10)
                            .position(x: plot.minX + x, y: plot.minY + y)
                    }
                }
            }
        }
        .frame(width: plotSize.width, height: plotSize.height, alignment: .topLeading)
        .allowsHitTesting(false)
        .sensoryFeedback(.selection, trigger: selectedIndex)
    }
}

#Preview("ALL, monthly since 1992") {
    let calendar = Calendar.current
    let start = calendar.date(from: DateComponents(year: 1992, month: 1, day: 31))!
    let points = (0..<418).map { month in
        let date = calendar.date(byAdding: .month, value: month, to: start)!
        let trend = 3_150 * pow(1.0068, Double(month))
        return PricePoint(date: date, price: trend * (1 + 0.04 * sin(Double(month) / 7)))
    }
    PriceChart(
        history: PriceHistory(points: points, previousClose: 3_152),
        range: .max,
        selectedIndex: .constant(nil)
    )
    .frame(height: 280)
    .padding(20)
    .background(Color.appSurface)
    .preferredColorScheme(.dark)
}

#Preview("1D, 1-minute bars") {
    let open = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 6, minute: 30))!
    let points = (0..<391).map { bar -> PricePoint in
        let minute = Double(bar)
        let trend: Double = 51_260 + minute * 1.2
        let swing: Double = 60 * sin(minute / 25)
        let noise: Double = 8 * sin(minute * 1.3)
        return PricePoint(date: open.addingTimeInterval(minute * 60), price: trend + swing + noise)
    }
    PriceChart(
        history: PriceHistory(points: points, previousClose: 51_231.6),
        range: .oneDay,
        selectedIndex: .constant(nil)
    )
    .frame(height: 280)
    .padding(20)
    .background(Color.appSurface)
    .preferredColorScheme(.dark)
}

#Preview("1Y, daily bars") {
    let start = Calendar.current.date(from: DateComponents(year: 2025, month: 10, day: 10))!
    let points = (0..<251).map { day in
        PricePoint(
            date: start.addingTimeInterval(Double(day) * 86_400 * 365 / 251),
            price: 46_400 + Double(day) * 21 + 900 * sin(Double(day) / 17)
        )
    }
    PriceChart(
        history: PriceHistory(points: points, previousClose: 46_358),
        range: .oneYear,
        selectedIndex: .constant(nil)
    )
    .frame(height: 280)
    .padding(20)
    .background(Color.appSurface)
    .preferredColorScheme(.dark)
}
