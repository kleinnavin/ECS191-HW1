//
//  RSIChart.swift
//  SmartStock
//

import Charts
import SwiftUI

/// Relative Strength Index panel drawn under the price chart, sharing its
/// x positions so points line up vertically. Equatable on its data, like
/// `PriceChart`, so dragging only redraws the marker. Use with `.equatable()`.
struct RSIChart: View, Equatable {
    /// RSI aligned with the price chart's points.
    let values: [Double?]
    let range: YahooFinanceClient.Range
    @Binding var selectedIndex: Int?

    static func == (lhs: RSIChart, rhs: RSIChart) -> Bool {
        lhs.range == rhs.range && lhs.values == rhs.values
    }

    var body: some View {
        Chart {
            // Conventional overbought / oversold bands.
            RectangleMark(yStart: .value("Low", 30), yEnd: .value("High", 70))
                .foregroundStyle(Color.rsiLine.opacity(0.08))
            ForEach([30, 70], id: \.self) { level in
                RuleMark(y: .value("Level", level))
                    .foregroundStyle(Color.secondary.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }

            ForEach(values.indices, id: \.self) { index in
                if let value = values[index] {
                    LineMark(x: .value("Index", index), y: .value("RSI", value))
                        .foregroundStyle(Color.rsiLine)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
            }
        }
        .chartXScale(domain: PriceChart.xDomain(count: values.count, range: range))
        .chartYScale(domain: 0...100)
        .chartXSelection(value: $selectedIndex)
        .chartXAxis(.hidden)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                ChartSelectionMarker(
                    proxy: proxy,
                    plotSize: geometry.size,
                    prices: nil,
                    color: .rsiLine,
                    selectedIndex: $selectedIndex
                )
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: [30, 70]) { value in
                AxisValueLabel {
                    if let level = value.as(Int.self) {
                        Text("\(level)")
                            .frame(width: PriceChart.yAxisLabelWidth, alignment: .leading)
                    }
                }
            }
        }
        .accessibilityLabel("Relative strength index")
    }
}
