//
//  AssetRow.swift
//  SmartStock
//

import SwiftUI

struct AssetRow: View {
    let asset: Asset
    let quote: Quote?
    let history: PriceHistory?
    let error: String?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(asset.title)
                    .font(.title3.bold())
                    .lineLimit(1)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let history, history.points.count > 1 {
                Sparkline(history: history)
                    .frame(width: 72, height: 34)
            }

            VStack(alignment: .trailing, spacing: 6) {
                if let quote {
                    Text(quote.current, format: .number.precision(.fractionLength(2)))
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                    ChangeBadge(percent: quote.percentChange ?? 0)
                } else if error != nil {
                    Text("—")
                        .font(.title3.weight(.semibold))
                    Image(systemName: "exclamationmark.circle")
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
            }
            // Fixed width keeps the sparklines lined up across rows.
            .frame(width: 112, alignment: .trailing)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    /// Notes when a quote came from a tracking ETF rather than the index itself.
    private var subtitle: String {
        if let quote, quote.sourceSymbol != asset.symbol, !quote.sourceSymbol.isEmpty {
            // Lead with the proxy so it survives truncation of long names.
            return "via \(quote.sourceSymbol) · \(asset.name)"
        }
        return asset.name
    }
}

/// The green/red pill showing the day's percent change.
struct ChangeBadge: View {
    let percent: Double

    var body: some View {
        Text(percent / 100, format: .percent.precision(.fractionLength(2)).sign(strategy: .always()))
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .frame(minWidth: 72, alignment: .trailing)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color, in: RoundedRectangle(cornerRadius: 6))
    }

    private var color: Color {
        if percent > 0 { return .stockGreen }
        if percent < 0 { return .stockRed }
        return Color(white: 0.4)
    }
}

#Preview {
    List {
        AssetRow(
            asset: Asset.defaults[0],
            quote: Quote(current: 51654.95, change: 424.1, percentChange: 0.83, high: 0, low: 0, open: 0, previousClose: 51230.85, timestamp: 0),
            history: .preview(from: 51230.85, to: 51654.95),
            error: nil
        )
        AssetRow(
            asset: Asset(symbol: "ON", title: "ON", name: "ON Semiconductor Corporation"),
            quote: Quote(current: 77.53, change: -1.88, percentChange: -2.37, high: 0, low: 0, open: 0, previousClose: 79.41, timestamp: 0),
            history: .preview(from: 79.41, to: 77.53),
            error: nil
        )
    }
    .listStyle(.plain)
    .preferredColorScheme(.dark)
}

private extension PriceHistory {
    static func preview(from start: Double, to end: Double) -> PriceHistory {
        let now = Date.now
        let points = (0..<60).map { i in
            let t = Double(i) / 59
            let wobble = sin(Double(i) * 0.7) * abs(end - start) * 0.15
            return PricePoint(date: now.addingTimeInterval(Double(i) * 300), price: start + (end - start) * t + wobble)
        }
        return PriceHistory(points: points, previousClose: start)
    }
}
