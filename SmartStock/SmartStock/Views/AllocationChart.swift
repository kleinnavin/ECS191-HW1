//
//  AllocationChart.swift
//  SmartStock
//

import Charts
import SwiftUI

/// Donut chart of the portfolio's value by asset category, with a legend
/// listing each category's share. Tap a slice or legend row to highlight it.
struct AllocationChart: View {
    let slices: [(category: AssetCategory, value: Double)]
    /// Positions still waiting for a category; shown as a note.
    var pendingCount = 0

    @State private var selectedAngle: Double?
    @State private var selected: AssetCategory?

    private var total: Double { slices.reduce(0) { $0 + $1.value } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Allocation")
                .font(.title3.bold())

            if slices.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Classifying your assets…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                donut
                    .frame(height: 220)
                legend
                if pendingCount > 0 {
                    Text("\(pendingCount) more \(pendingCount == 1 ? "asset" : "assets") still being classified.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 12)
        .onChange(of: selectedAngle) { oldAngle, newAngle in
            guard let newAngle else { return }
            let category = category(atAngleValue: newAngle)
            // A fresh tap on the highlighted slice clears it; otherwise
            // follow the finger from slice to slice.
            selected = oldAngle == nil && category == selected ? nil : category
        }
        .sensoryFeedback(.selection, trigger: selected)
    }

    private var donut: some View {
        Chart(slices, id: \.category) { slice in
            SectorMark(
                angle: .value("Value", slice.value),
                innerRadius: .ratio(0.62),
                // Thin gap between slices so neighbors stay distinct.
                angularInset: slices.count > 1 ? 1.5 : 0
            )
            .cornerRadius(4)
            .foregroundStyle(slice.category.color)
            .opacity(selected == nil || selected == slice.category ? 1 : 0.3)
        }
        .chartLegend(.hidden)
        .chartAngleSelection(value: $selectedAngle)
        .chartBackground { proxy in
            GeometryReader { geometry in
                if let plotFrame = proxy.plotFrame {
                    let frame = geometry[plotFrame]
                    centerLabel
                        .frame(width: frame.width * 0.55)
                        .position(x: frame.midX, y: frame.midY)
                }
            }
        }
        .accessibilityLabel("Allocation by category")
        .accessibilityValue(slices.map { "\($0.category.title) \(percent($0.value))" }.joined(separator: ", "))
    }

    /// The selected category's share, or the portfolio total.
    private var centerLabel: some View {
        VStack(spacing: 2) {
            if let selected, let slice = slices.first(where: { $0.category == selected }) {
                Text(percent(slice.value))
                    .font(.title2.bold())
                Text(selected.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text(total.formatted(.currency(code: "USD").notation(.compactName)))
                    .font(.title2.bold())
                Text(slices.count == 1 ? "1 category" : "\(slices.count) categories")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .monospacedDigit()
        .lineLimit(2)
        .minimumScaleFactor(0.7)
    }

    private var legend: some View {
        VStack(spacing: 10) {
            ForEach(slices, id: \.category) { slice in
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(slice.category.color)
                        .frame(width: 12, height: 12)
                    Text(slice.category.title)
                    Spacer(minLength: 8)
                    Text(slice.value.dollars)
                        .foregroundStyle(.secondary)
                    Text(percent(slice.value))
                        .fontWeight(.semibold)
                        .frame(minWidth: 56, alignment: .trailing)
                }
                .font(.subheadline)
                .monospacedDigit()
                .opacity(selected == nil || selected == slice.category ? 1 : 0.5)
                .contentShape(Rectangle())
                .onTapGesture {
                    selected = selected == slice.category ? nil : slice.category
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
            }
        }
    }

    private func percent(_ value: Double) -> String {
        guard total > 0 else { return "—" }
        return (value / total).formatted(.percent.precision(.fractionLength(1)))
    }

    /// The slice under a selected angle, given in the chart's value units
    /// (cumulative from the first slice).
    private func category(atAngleValue value: Double) -> AssetCategory? {
        var end = 0.0
        for slice in slices {
            end += slice.value
            if value <= end { return slice.category }
        }
        return slices.last?.category
    }
}

#Preview {
    List {
        AllocationChart(slices: [
            (.usStock, 6_200),
            (.usStockFund, 9_400),
            (.internationalStockFund, 4_100),
            (.governmentBond, 3_200),
            (.realAssets, 800),
        ])
        .listRowBackground(Color.clear)
    }
    .listStyle(.plain)
    .background(Color.black)
    .scrollContentBackground(.hidden)
    .preferredColorScheme(.dark)
}
