//
//  PortfolioCard.swift
//  SmartStock
//

import SwiftUI

/// Card pinned to the bottom of the watchlist that introduces My Positions
/// (or, once there are positions, sums them up) and opens it when tapped.
/// Kept to two lines so it covers as little of the list as possible.
struct PortfolioCard: View {
    let positionCount: Int
    /// Total market value, or `nil` until quotes have loaded.
    let totalValue: Double?
    let dayChange: Double
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Image(systemName: "briefcase.fill")
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                    Text("My Positions")
                        .font(.headline)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                if positionCount == 0 {
                    Text("Track shares you own: gains, cost basis and allocation.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else {
                    summary
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Opaque so rows scrolling underneath don't show through the text.
            .background {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.appSurface)
                    .strokeBorder(Color.white.opacity(0.08))
                    .shadow(color: .black.opacity(0.6), radius: 12, y: 4)
            }
            .contentShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows your positions")
    }

    private var summary: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if let totalValue {
                Text(totalValue.dollars)
                    .font(.headline)
                    .monospacedDigit()
                Text("\(dayChange.signedDollars) today")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.change(dayChange))
            }
            Spacer(minLength: 0)
            Text(positionCount == 1 ? "1 position" : "\(positionCount) positions")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        PortfolioCard(positionCount: 0, totalValue: nil, dayChange: 0) {}
        PortfolioCard(positionCount: 4, totalValue: 27_648.59, dayChange: 182.40) {}
    }
    .padding()
    .frame(maxHeight: .infinity)
    .background(Color.appBackground)
    .preferredColorScheme(.dark)
}
