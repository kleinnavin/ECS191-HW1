//
//  PositionRow.swift
//  SmartStock
//

import SwiftUI

/// A row in the positions list: shares and cost on the left, market value
/// and total gain on the right, with the gain in dollars, cost basis and
/// today's change below.
struct PositionRow: View {
    let position: Position
    let quote: Quote?
    let error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(position.asset.title)
                        .font(.title3.bold())
                        .lineLimit(1)
                    Text("\(position.shares.sharesText) @ \(position.purchasePrice.dollars)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 6) {
                    if let quote {
                        Text(position.marketValue(at: quote.current).dollars)
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                        ChangeBadge(percent: position.totalGainPercent(at: quote.current) ?? 0)
                    } else if error != nil {
                        Text("—")
                            .font(.title3.weight(.semibold))
                        Image(systemName: "exclamationmark.circle")
                            .foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                    }
                }
            }

            HStack(spacing: 4) {
                Text(gainTitle).foregroundStyle(.secondary)
                gainText
                Spacer(minLength: 8)
                Text("Cost").foregroundStyle(.secondary)
                Text(position.costBasis.dollars).fontWeight(.semibold)
                Spacer(minLength: 8)
                Text("Day").foregroundStyle(.secondary)
                dayChangeText
            }
            .font(.caption)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private var gain: Double? { quote.map { position.totalGain(at: $0.current) } }

    private var gainTitle: String { (gain ?? 0) < 0 ? "Loss" : "Gain" }

    private var gainText: Text {
        guard let gain else { return Text("—") }
        return Text(gain.signedDollars)
            .fontWeight(.semibold)
            .foregroundStyle(Color.change(gain))
    }

    private var dayChangeText: Text {
        guard let quote, let change = position.dayChange(quote) else { return Text("—") }
        return Text(change.signedDollars)
            .fontWeight(.semibold)
            .foregroundStyle(Color.change(change))
    }
}

/// Totals across every position, shown above the list: the portfolio's
/// value, then its total gain or loss and today's change as colored tiles.
struct PortfolioSummary: View {
    let totalValue: Double
    let costBasis: Double
    let dayChange: Double

    private var totalGain: Double { totalValue - costBasis }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Total Value")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(totalValue.dollars)
                    .font(.largeTitle.bold())
                    .monospacedDigit()
            }

            HStack(spacing: 10) {
                ChangeTile(
                    title: totalGain < 0 ? "Total Loss" : "Total Gain",
                    amount: totalGain,
                    base: costBasis,
                    caption: "on \(costBasis.dollars) invested"
                )
                ChangeTile(
                    title: "Today",
                    amount: dayChange,
                    base: totalValue - dayChange,
                    caption: "since last close"
                )
            }
        }
        .padding(.vertical, 8)
    }
}

/// A gain or loss in dollars and percent, tinted green or red, with an
/// arrow so the direction doesn't rely on color alone.
private struct ChangeTile: View {
    let title: String
    let amount: Double
    /// What the change is measured against, for the percent.
    let base: Double
    let caption: String

    var body: some View {
        let color = Color.change(amount)
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                Image(systemName: amount > 0 ? "arrow.up.right" : amount < 0 ? "arrow.down.right" : "minus")
                    .font(.subheadline.weight(.bold))
                Text(amount.signedDollars)
                    .font(.title3.bold())
            }
            .foregroundStyle(color)
            if base > 0 {
                Text((amount / base).signedPercent)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color)
            }
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}

extension Double {
    /// "$1,234.56"
    var dollars: String { formatted(.currency(code: "USD")) }

    /// "+$12.34" or "-$12.34"
    var signedDollars: String { formatted(.currency(code: "USD").sign(strategy: .always())) }

    /// "+1.23%" for 0.0123.
    var signedPercent: String { formatted(.percent.precision(.fractionLength(2)).sign(strategy: .always())) }

    /// "12 shares", "1 share", "6.6667 shares"
    var sharesText: String {
        let number = formatted(.number.precision(.fractionLength(0...4)))
        return self == 1 ? "\(number) share" : "\(number) shares"
    }
}

extension Color {
    /// Green for gains, red for losses, gray for no change.
    static func change(_ value: Double) -> Color {
        if value > 0 { return .stockGreen }
        if value < 0 { return .stockRed }
        return .secondary
    }
}

#Preview {
    let apple = Asset(symbol: "AAPL", title: "AAPL", name: "Apple Inc")
    let quote = Quote(current: 245.12, change: 1.85, percentChange: 0.76, high: 0, low: 0, open: 0, previousClose: 243.27, timestamp: 0)
    List {
        PortfolioSummary(totalValue: 2451.20, costBasis: 1500, dayChange: -18.50)
        PositionRow(
            position: Position(asset: apple, purchaseDate: .now.addingTimeInterval(-86_400 * 400), purchasePrice: 150, shares: 10),
            quote: quote,
            error: nil
        )
    }
    .listStyle(.plain)
    .preferredColorScheme(.dark)
}
