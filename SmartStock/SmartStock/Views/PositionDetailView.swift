//
//  PositionDetailView.swift
//  SmartStock
//

import SwiftUI

/// Sheet charting a position's market value from its purchase date to now,
/// with its cost basis as a dashed baseline and the position's key figures.
struct PositionDetailView: View {
    let position: Position

    @Environment(PortfolioStore.self) private var portfolio
    @Environment(\.dismiss) private var dismiss

    /// The position's value at each bar since purchase.
    @State private var values: PriceHistory?
    @State private var errorMessage: String?
    @State private var selectedIndex: Int?
    @State private var isConfirmingDelete = false

    private var quote: Quote? { portfolio.quotes[position.asset.symbol] }

    /// Start of the purchase day; daily bars are stamped at the open.
    private var start: Date { Calendar.current.startOfDay(for: position.purchaseDate) }

    /// Bar interval and the range whose axis labels suit the time held.
    /// Intraday intervals stay within Yahoo's limits (15m: 60 days, 1h: 730).
    private var plan: (interval: String, range: YahooFinanceClient.Range) {
        let days = Date.now.timeIntervalSince(start) / 86_400
        switch days {
        case ..<7: return ("15m", .fiveDays)
        case ..<60: return ("1h", .oneMonth)
        case ..<366: return ("1d", .oneYear)
        case ..<731: return ("1d", .twoYears)
        case ..<1830: return ("1wk", .fiveYears)
        default: return ("1mo", .max)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                Divider()
                valueSummary
                Divider()
                Text("Value Since Purchase")
                    .font(.subheadline.weight(.semibold))
                chartArea
                    .frame(height: 280)
                Divider()
                stats
                Divider()
                Button("Delete Position", systemImage: "trash", role: .destructive) {
                    isConfirmingDelete = true
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Color.appSurface)
        .sheetCloseBar()
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task { await loadValues() }
        .confirmationDialog("Delete this position?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete Position", role: .destructive) {
                portfolio.remove(position)
                dismiss()
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(position.asset.title)
                .font(.largeTitle.bold())
                .lineLimit(1)
                .layoutPriority(1)
            Text(position.asset.name)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    /// Value now (or at the selected point) and the gain over the cost basis.
    private var valueSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if let value = displayedValue {
                    Text(value.dollars)
                        .font(.title2.bold())
                        .monospacedDigit()
                    let gain = value - position.costBasis
                    Text(gainText(gain))
                        .font(.headline)
                        .monospacedDigit()
                        .foregroundStyle(Color.change(gain))
                } else {
                    Text("—").font(.title2.bold())
                }
            }
            Text(summaryCaption)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .transaction(value: selectedIndex) { $0.animation = nil }
    }

    @ViewBuilder
    private var chartArea: some View {
        if let values, values.points.count > 1 {
            PriceChart(
                history: values,
                range: plan.range,
                selectedIndex: $selectedIndex,
                baseline: position.costBasis
            )
            .equatable()
        } else if let errorMessage {
            ContentUnavailableView("Chart Unavailable", systemImage: "chart.xyaxis.line", description: Text(errorMessage))
        } else if values != nil {
            ContentUnavailableView(
                "No Data Yet",
                systemImage: "chart.xyaxis.line",
                description: Text("There's no price history since this purchase yet. Check back after the market trades.")
            )
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var stats: some View {
        let price = quote?.current ?? values?.points.last.map { $0.price / position.shares }
        return StatColumns(
            left: [
                ("Shares", position.shares.formatted(.number.precision(.fractionLength(0...4)))),
                ("Avg Cost", position.purchasePrice.dollars),
                ("Cost Basis", position.costBasis.dollars),
                ("Bought", position.purchaseDate.formatted(date: .numeric, time: .omitted)),
            ],
            right: [
                ("Price", price?.dollars ?? "—"),
                ("Value", price.map { position.marketValue(at: $0).dollars } ?? "—"),
                ("Gain", price.map { position.totalGain(at: $0).signedDollars } ?? "—"),
                ("Day", quote.flatMap { position.dayChange($0) }?.signedDollars ?? "—"),
            ]
        )
    }

    // MARK: - Displayed values

    private var selectedPoint: PricePoint? {
        guard let selectedIndex, let points = values?.points, points.indices.contains(selectedIndex) else { return nil }
        return points[selectedIndex]
    }

    private var displayedValue: Double? {
        selectedPoint?.price
            ?? quote.map { position.marketValue(at: $0.current) }
            ?? values?.points.last?.price
    }

    private func gainText(_ gain: Double) -> String {
        guard position.costBasis > 0 else { return gain.signedDollars }
        return "\(gain.signedDollars) (\((gain / position.costBasis).signedPercent))"
    }

    private var summaryCaption: String {
        if let point = selectedPoint {
            return plan.range.isIntraday
                ? point.date.formatted(date: .abbreviated, time: .shortened)
                : point.date.formatted(date: .abbreviated, time: .omitted)
        }
        return "Since \(position.purchaseDate.formatted(date: .abbreviated, time: .omitted))"
    }

    // MARK: - Loading

    private func loadValues() async {
        guard values == nil else { return }
        do {
            let chart = try await portfolio.yahoo.chart(for: position.asset.symbol, from: start, interval: plan.interval)
            let points = chart.history.points
                .filter { $0.date >= start }
                .map { PricePoint(date: $0.date, price: position.marketValue(at: $0.price)) }
            // The cost basis is the comparison point, so the line is green
            // when the position is up and red when it's down.
            values = PriceHistory(points: points, previousClose: position.costBasis)
            errorMessage = nil
        } catch {
            if !error.isCancellation { errorMessage = error.localizedDescription }
        }
    }
}

#Preview {
    Color.appBackground
        .sheet(isPresented: .constant(true)) {
            PositionDetailView(position: Position(
                asset: Asset(symbol: "AAPL", title: "AAPL", name: "Apple Inc"),
                purchaseDate: .now.addingTimeInterval(-86_400 * 300),
                purchasePrice: 200,
                shares: 10
            ))
            .environment(PortfolioStore())
        }
        .preferredColorScheme(.dark)
}
