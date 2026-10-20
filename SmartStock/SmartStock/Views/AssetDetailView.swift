//
//  AssetDetailView.swift
//  SmartStock
//

import SwiftUI

/// Sheet with an asset's price history chart, range buttons, and key stats.
struct AssetDetailView: View {
    let asset: Asset

    @Environment(WatchlistStore.self) private var watchlist

    @State private var range: YahooFinanceClient.Range = .oneDay
    @State private var charts: [YahooFinanceClient.Range: YahooFinanceClient.Chart] = [:]
    @State private var errorMessage: String?
    @State private var selectedIndex: Int?
    /// Longer series at each range's interval, used to warm up indicators.
    @State private var lookbacks: [YahooFinanceClient.Range: PriceHistory] = [:]
    /// Ranges whose lookback fetch failed; their indicators use the displayed points.
    @State private var lookbackFailures: Set<YahooFinanceClient.Range> = []

    /// Last computed indicators; the detail view re-renders on every drag
    /// frame, and recomputing them each time was a large share of the work.
    @State private var indicatorCache = IndicatorCache()

    @AppStorage("indicator.sma") private var showSMA = false
    @AppStorage("indicator.rsi") private var showRSI = false

    private var chart: YahooFinanceClient.Chart? { charts[range] }

    /// 52-week range and volume come from chart metadata, which is the same
    /// for every range, so use whichever chart has loaded.
    private var stats: YahooFinanceClient.MarketStats? {
        (charts[.oneDay] ?? charts[range] ?? charts.values.first)?.stats
    }

    /// Average daily volume over 3 months, matching Yahoo's "Avg Vol".
    private var averageVolume: Double? { charts[.threeMonths]?.stats.averageVolume }

    /// The live watchlist quote, or the one-day chart's quote if the
    /// watchlist hasn't loaded it.
    private var quote: Quote? { watchlist.quotes[asset.symbol] ?? charts[.oneDay]?.quote }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                Divider()
                priceSummary
                Divider()
                RangePicker(selection: $range)
                let indicators = indicatorValues
                if showSMA || showRSI {
                    IndicatorLegend(
                        range: range,
                        sma: showSMA ? indicators.sma : nil,
                        rsi: showRSI ? indicators.rsi : nil,
                        selectedIndex: selectedIndex
                    )
                }
                chartArea(sma: indicators.sma)
                    .frame(height: 280)
                if showRSI, chart != nil {
                    RSIChart(values: indicators.rsi, range: range, selectedIndex: $selectedIndex)
                        .equatable()
                        .frame(height: 90)
                }
                Divider()
                StatsGrid(quote: quote, stats: stats, averageVolume: averageVolume)
                Divider()
                IndicatorToggles(range: range, showSMA: $showSMA, showRSI: $showRSI)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Color.appSurface)
        .sheetCloseBar()
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .transaction(value: showSMA) { $0.animation = nil }
        .transaction(value: showRSI) { $0.animation = nil }
        .task(id: range) { await load(range) }
        .task { await loadAverageVolume() }
        .task(id: "\(range.rawValue)-\(showSMA || showRSI)") {
            if showSMA || showRSI { await loadLookback(range) }
        }
        .onChange(of: range) { selectedIndex = nil }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(asset.title)
                .font(.largeTitle.bold())
                .lineLimit(1)
                .layoutPriority(1)
            Text(asset.name)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var priceSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if let price = displayedPrice {
                    Text(price, format: .number.precision(.fractionLength(2)))
                        .font(.title2.bold())
                        .monospacedDigit()
                } else {
                    Text("—").font(.title2.bold())
                }
                if let percent = displayedPercentChange {
                    Text(percent / 100, format: .percent.precision(.fractionLength(2)).sign(strategy: .always()))
                        .font(.headline)
                        .monospacedDigit()
                        .foregroundStyle(percent >= 0 ? Color.stockGreen : Color.stockRed)
                    if selectedIndex == nil, range != .oneDay {
                        Text(rangeCaption)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Text(timestampCaption)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        // Update instantly while scrubbing, even if the chart's selection
        // gesture delivers its changes inside an animation.
        .transaction(value: selectedIndex) { $0.animation = nil }
    }

    @ViewBuilder
    private func chartArea(sma: [Double?]) -> some View {
        if let chart, chart.history.points.count > 1 {
            PriceChart(history: chart.history, range: range, selectedIndex: $selectedIndex, sma: sma)
                .equatable()
        } else if let errorMessage, chart == nil {
            ContentUnavailableView("Chart Unavailable", systemImage: "chart.xyaxis.line", description: Text(errorMessage))
        } else if chart != nil {
            ContentUnavailableView("No Data", systemImage: "chart.xyaxis.line", description: Text("No price history for this range."))
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Displayed values

    private var selectedPoint: PricePoint? {
        guard let selectedIndex, let points = chart?.history.points, points.indices.contains(selectedIndex) else { return nil }
        return points[selectedIndex]
    }

    private var displayedPrice: Double? {
        selectedPoint?.price ?? quote?.current ?? chart?.history.points.last?.price
    }

    /// Change from the start of the range (or yesterday's close for 1D) to
    /// the selected point, or to now when nothing is selected.
    private var displayedPercentChange: Double? {
        if selectedPoint == nil, range == .oneDay, let percent = quote?.percentChange { return percent }
        guard let history = chart?.history, let end = displayedPrice,
              let start = history.previousClose ?? history.points.first?.price, start != 0 else { return nil }
        return (end - start) / start * 100
    }

    private var rangeCaption: String {
        switch range {
        case .oneDay: "Today"
        case .fiveDays: "Past Week"
        case .oneMonth: "Past Month"
        case .threeMonths: "Past 3 Months"
        case .sixMonths: "Past 6 Months"
        case .yearToDate: "Year to Date"
        case .oneYear: "Past Year"
        case .twoYears: "Past 2 Years"
        case .fiveYears: "Past 5 Years"
        case .tenYears: "Past 10 Years"
        case .max: "All Time"
        }
    }

    private var timestampCaption: String {
        if let point = selectedPoint {
            return range.isIntraday
                ? point.date.formatted(date: .abbreviated, time: .shortened)
                : point.date.formatted(date: .abbreviated, time: .omitted)
        }
        guard let time = quote?.timestamp, time > 0 else { return asset.symbol }
        let date = Date(timeIntervalSince1970: time)
        // A quote older than ~15 minutes means the market is closed. Its
        // timestamp can lag the actual close, so don't show it then.
        if Date.now.timeIntervalSince(date) > 15 * 60 { return "At Close" }
        return "As of \(date.formatted(date: .omitted, time: .shortened))"
    }

    // MARK: - Indicators

    /// SMA and RSI aligned with the displayed points (empty when off).
    /// They're computed over the longer lookback series when it has loaded,
    /// so the first displayed points already have values.
    private var indicatorValues: (sma: [Double?], rsi: [Double?]) {
        guard let points = chart?.history.points, showSMA || showRSI else { return ([], []) }
        let key = IndicatorCache.Key(
            range: range, showSMA: showSMA, showRSI: showRSI,
            points: points.count, lastDate: points.last?.date,
            lookback: lookbacks[range]?.points.count, lookbackFailed: lookbackFailures.contains(range)
        )
        if let cached = indicatorCache.values(for: key) { return cached }
        let values = computeIndicators(points: points)
        indicatorCache.store(values, for: key)
        return values
    }

    private func computeIndicators(points: [PricePoint]) -> (sma: [Double?], rsi: [Double?]) {
        // Wait for the lookback rather than drawing a partial line that then
        // jumps to full width (and rescales the chart) when it arrives.
        let awaitingLookback = range.indicatorLookback != nil
            && lookbacks[range] == nil && !lookbackFailures.contains(range)
        if awaitingLookback {
            let none = [Double?](repeating: nil, count: points.count)
            return (showSMA ? none : [], showRSI ? none : [])
        }
        let source = lookbacks[range]?.points ?? points
        let closes = source.map(\.price)
        let smaAll = showSMA ? Indicators.sma(closes, period: range.smaPeriod) : []
        let rsiAll = showRSI ? Indicators.rsi(closes, period: range.rsiPeriod) : []

        // Bars at the same interval share timestamps, so match on date.
        var sourceIndex: [Date: Int] = [:]
        for (index, point) in source.enumerated() { sourceIndex[point.date] = index }
        let matched = points.map { sourceIndex[$0.date] }
        return (
            showSMA ? matched.map { $0.flatMap { smaAll[$0] } } : [],
            showRSI ? matched.map { $0.flatMap { rsiAll[$0] } } : []
        )
    }

    // MARK: - Loading

    private func load(_ range: YahooFinanceClient.Range) async {
        guard charts[range] == nil else { return }
        errorMessage = nil
        do {
            charts[range] = try await watchlist.yahoo.chart(for: asset.symbol, range: range)
        } catch is CancellationError {
        } catch let error as URLError where error.code == .cancelled {
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Loads the 3-month daily chart (the same one the 3M button shows) for
    /// average volume, without reporting errors over the visible chart.
    private func loadAverageVolume() async {
        guard charts[.threeMonths] == nil else { return }
        if let chart = try? await watchlist.yahoo.chart(for: asset.symbol, range: .threeMonths) {
            charts[.threeMonths] = charts[.threeMonths] ?? chart
        }
    }

    /// Without a lookback, indicators fall back to the displayed points and
    /// just start a little way into the chart.
    private func loadLookback(_ range: YahooFinanceClient.Range) async {
        guard lookbacks[range] == nil, let longer = range.indicatorLookback else { return }
        do {
            lookbacks[range] = try await watchlist.yahoo.chart(for: asset.symbol, range: longer, interval: range.interval).history
        } catch is CancellationError {
        } catch let error as URLError where error.code == .cancelled {
        } catch {
            lookbackFailures.insert(range)
        }
    }
}

// MARK: - Range picker

private struct RangePicker: View {
    @Binding var selection: YahooFinanceClient.Range

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(YahooFinanceClient.Range.allCases) { range in
                        Button(range.title) { selection = range }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(selection == range ? .primary : .secondary)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .background {
                                if selection == range {
                                    Capsule().fill(Color(white: 0.24))
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(selection == range ? .isSelected : [])
                            .id(range)
                    }
                }
            }
            .scrollIndicators(.hidden)
            // Run the row to the screen edges so the clipped last button
            // hints that more ranges are a scroll away.
            .contentMargins(.horizontal, 20, for: .scrollContent)
            .padding(.horizontal, -20)
            .onChange(of: selection) {
                withAnimation(.snappy) { proxy.scrollTo(selection, anchor: .center) }
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// Holds the most recent indicator result. A plain class so writing to it
/// during rendering doesn't trigger another render.
private final class IndicatorCache {
    struct Key: Hashable {
        let range: YahooFinanceClient.Range
        let showSMA: Bool
        let showRSI: Bool
        let points: Int
        let lastDate: Date?
        let lookback: Int?
        let lookbackFailed: Bool
    }

    private var key: Key?
    private var cached: (sma: [Double?], rsi: [Double?]) = ([], [])

    func values(for key: Key) -> (sma: [Double?], rsi: [Double?])? {
        key == self.key ? cached : nil
    }

    func store(_ values: (sma: [Double?], rsi: [Double?]), for key: Key) {
        self.key = key
        cached = values
    }
}

// MARK: - Indicator controls

/// Current indicator values (at the selected point, or the latest).
private struct IndicatorLegend: View {
    let range: YahooFinanceClient.Range
    let sma: [Double?]?
    let rsi: [Double?]?
    let selectedIndex: Int?

    var body: some View {
        HStack(spacing: 16) {
            if let sma {
                item("SMA \(range.smaPeriod)", value(in: sma), color: .smaLine, decimals: 2)
            }
            if let rsi {
                item("RSI \(range.rsiPeriod)", value(in: rsi), color: .rsiLine, decimals: 1)
            }
            Spacer()
        }
        .font(.caption)
        .transaction(value: selectedIndex) { $0.animation = nil }
    }

    private func value(in values: [Double?]) -> Double? {
        if let selectedIndex, values.indices.contains(selectedIndex) { return values[selectedIndex] }
        return values.last { $0 != nil } ?? nil
    }

    private func item(_ title: String, _ value: Double?, color: Color, decimals: Int) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title).foregroundStyle(.secondary)
            Group {
                if let value {
                    Text(value, format: .number.precision(.fractionLength(decimals)))
                } else {
                    Text("—")
                }
            }
            .fontWeight(.semibold)
            .monospacedDigit()
        }
    }
}

/// Check boxes that turn the chart indicators on and off.
private struct IndicatorToggles: View {
    let range: YahooFinanceClient.Range
    @Binding var showSMA: Bool
    @Binding var showRSI: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Indicators")
                .font(.subheadline.weight(.semibold))
            CheckboxRow(
                title: "Simple Moving Average",
                detail: "\(range.smaPeriod) \(range.barName) bars",
                tint: .smaLine,
                isOn: $showSMA
            )
            CheckboxRow(
                title: "Relative Strength Index",
                detail: "\(range.rsiPeriod) \(range.barName) bars",
                tint: .rsiLine,
                isOn: $showRSI
            )
        }
    }
}

/// A square check box, filled in the indicator's line color when on.
/// Built from a tap gesture rather than a Button or Toggle, whose built-in
/// press and value animations made the rows slide and cross-fade.
private struct CheckboxRow: View {
    let title: String
    let detail: String
    let tint: Color
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isOn ? "checkmark.square.fill" : "square")
                .font(.title3)
                .foregroundStyle(isOn ? tint : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { isOn.toggle() }
        }
        .sensoryFeedback(.selection, trigger: isOn)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

// MARK: - Stats

private struct StatsGrid: View {
    let quote: Quote?
    let stats: YahooFinanceClient.MarketStats?
    let averageVolume: Double?

    var body: some View {
        StatColumns(
            left: [
                ("Open", price(quote?.open)),
                ("High", price(quote?.high)),
                ("Low", price(quote?.low)),
            ],
            right: [
                ("52W H", price(stats?.fiftyTwoWeekHigh)),
                ("52W L", price(stats?.fiftyTwoWeekLow)),
                ("Vol", volume(stats?.volume)),
                ("Avg Vol", volume(averageVolume)),
            ]
        )
    }

    /// "—" marks a figure that's unavailable, as in the Stocks app.
    private func price(_ value: Double?) -> String {
        guard let value, value > 0 else { return "—" }
        return value.formatted(.number.precision(.fractionLength(2)))
    }

    /// Compact volume such as "339.5M".
    private func volume(_ value: Double?) -> String {
        guard let value, value > 0 else { return "—" }
        return value.formatted(.number.notation(.compactName).precision(.fractionLength(1)))
    }
}

/// Two label/value columns split by one continuous rule, like the Stocks
/// app, spanning the full content width.
struct StatColumns: View {
    let left: [(label: String, value: String)]
    let right: [(label: String, value: String)]

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            column(left)
            Rectangle()
                .fill(Color.white.opacity(0.15))
                .frame(width: 1)
            column(right)
        }
        .fixedSize(horizontal: false, vertical: true)
        .font(.subheadline)
    }

    private func column(_ rows: [(label: String, value: String)]) -> some View {
        VStack(spacing: 10) {
            ForEach(rows, id: \.label) { row in
                HStack {
                    Text(row.label)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(row.value)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

#Preview {
    Color.appBackground
        .sheet(isPresented: .constant(true)) {
            AssetDetailView(asset: Asset.defaults[0])
                .environment(WatchlistStore())
        }
        .preferredColorScheme(.dark)
}
