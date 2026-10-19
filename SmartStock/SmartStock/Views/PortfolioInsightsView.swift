//
//  PortfolioInsightsView.swift
//  SmartStock
//

import SwiftUI

/// Sheet showing Claude's most recent review of the user's positions. It
/// opens on the saved analysis; a new one is only requested when the user
/// taps Generate, to save API calls.
struct PortfolioInsightsView: View {
    @Environment(PortfolioStore.self) private var portfolio
    @Environment(InsightsStore.self) private var insights

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                Divider()
                content
                Text("AI-generated suggestions for educational purposes only, not financial advice. Claude can make mistakes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(Color.black)
        .sheetCloseBar()
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Portfolio Insights", systemImage: "sparkles")
                .font(.title2.weight(.bold))
            if let date = insights.saved?.date {
                Text("Generated \(date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Recommendations from Claude")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if insights.isLoading {
            VStack(spacing: 12) {
                ProgressView()
                Text("Analyzing your ^[\(portfolio.positions.count) position](inflect: true)…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 240)
        } else if let saved = insights.saved {
            if let errorMessage = insights.errorMessage {
                notice(errorMessage, systemImage: "exclamationmark.triangle.fill")
            } else if insights.isOutdated(for: portfolio) {
                notice("Your positions have changed since these insights were generated.", systemImage: "info.circle.fill")
            }
            results(saved.analysis)
            generateButton("Generate New Insights")
                .padding(.top, 4)
        } else {
            ContentUnavailableView {
                Label(insights.errorMessage == nil ? "No Insights Yet" : "Couldn't Analyze",
                      systemImage: insights.errorMessage == nil ? "sparkles" : "exclamationmark.triangle")
            } description: {
                Text(insights.errorMessage ?? "Claude can review your positions and suggest ways to improve your portfolio.")
            } actions: {
                generateButton(insights.errorMessage == nil ? "Generate Insights" : "Try Again")
            }
        }
    }

    private func generateButton(_ title: String) -> some View {
        Button(title, systemImage: "sparkles") {
            insights.generate(for: portfolio)
        }
        .buttonStyle(.borderedProminent)
        .frame(maxWidth: .infinity)
    }

    private func notice(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.footnote)
            .foregroundStyle(.yellow)
    }

    private func results(_ analysis: PortfolioAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Diversification")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(analysis.diversification.rawValue.capitalized)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(color(for: analysis.diversification).opacity(0.2), in: .capsule)
                    .foregroundStyle(color(for: analysis.diversification))
            }

            Text(analysis.summary)
                .font(.body)

            if !analysis.recommendations.isEmpty {
                section("Recommendations") {
                    ForEach(analysis.recommendations) { recommendation in
                        RecommendationCard(recommendation: recommendation)
                    }
                }
            }

            if !analysis.strengths.isEmpty {
                section("Strengths") {
                    bullets(analysis.strengths, symbol: "checkmark.circle.fill", color: .green)
                }
            }

            if !analysis.risks.isEmpty {
                section("Risks") {
                    bullets(analysis.risks, symbol: "exclamationmark.circle.fill", color: .orange)
                }
            }
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content()
        }
    }

    private func bullets(_ items: [String], symbol: String, color: Color) -> some View {
        ForEach(items, id: \.self) { item in
            Label {
                Text(item)
                    .font(.subheadline)
            } icon: {
                Image(systemName: symbol)
                    .foregroundStyle(color)
            }
        }
    }

    private func color(for rating: PortfolioAnalysis.Rating) -> Color {
        switch rating {
        case .poor: .red
        case .fair: .orange
        case .good: .green
        case .excellent: .mint
        }
    }
}

private struct RecommendationCard: View {
    let recommendation: PortfolioAnalysis.Recommendation

    private var priorityColor: Color {
        switch recommendation.priority {
        case .high: .red
        case .medium: .orange
        case .low: .blue
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(recommendation.title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(recommendation.priority.rawValue.capitalized)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(priorityColor)
            }
            Text(recommendation.detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(white: 0.11), in: .rect(cornerRadius: 14))
    }
}
