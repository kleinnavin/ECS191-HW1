//
//  PositionsView.swift
//  SmartStock
//

import SwiftUI

/// The user's positions with a portfolio summary and allocation chart.
/// Pushed from the watchlist, so the back button returns to it.
struct PositionsView: View {
    @Environment(PortfolioStore.self) private var portfolio
    @Environment(InsightsStore.self) private var insights
    @State private var editMode: EditMode = .inactive
    @State private var isAddingPosition = false
    @State private var isShowingInsights = false
    @State private var selectedPosition: Position?

    var body: some View {
        List {
            if !portfolio.positions.isEmpty {
                PortfolioSummary(
                    totalValue: portfolio.totalValue,
                    costBasis: portfolio.quotedCostBasis,
                    dayChange: portfolio.totalDayChange
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            ForEach(portfolio.positions) { position in
                Button {
                    selectedPosition = position
                } label: {
                    PositionRow(
                        position: position,
                        quote: portfolio.quotes[position.asset.symbol],
                        error: portfolio.errors[position.asset.symbol]
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .cardRow()
            }
            .onDelete(perform: portfolio.remove(atOffsets:))
            .onMove(perform: portfolio.move(fromOffsets:toOffset:))

            if !portfolio.positions.isEmpty {
                AllocationChart(
                    slices: portfolio.allocation,
                    pendingCount: Set(portfolio.positions.map(\.asset.symbol))
                        .filter { portfolio.categories[$0] == nil }.count
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                Text("Tap \(Image(systemName: "sparkles")) for Portfolio Insights: Claude reviews your positions and suggests ways to improve your portfolio.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.appBackground)
        .overlay {
            if portfolio.positions.isEmpty {
                ContentUnavailableView {
                    Label("No Positions", systemImage: "briefcase")
                } description: {
                    Text("Add shares you own to track their value since you bought them.")
                } actions: {
                    Button("Add Position") { isAddingPosition = true }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .environment(\.editMode, $editMode)
        .navigationTitle("My Positions")
        .navigationSubtitle(Date.now.formatted(.dateTime.month(.wide).day()))
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Portfolio Insights", systemImage: "sparkles") {
                    isShowingInsights = true
                }
                .disabled(portfolio.positions.isEmpty || editMode.isEditing)
                Button("Add Position", systemImage: "plus") {
                    isAddingPosition = true
                }
                Button(editMode.isEditing ? "Done" : "Edit") {
                    withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                }
                .fontWeight(editMode.isEditing ? .semibold : .regular)
                .disabled(portfolio.positions.isEmpty && !editMode.isEditing)
            }
        }
        .refreshable { await portfolio.refreshAll() }
        .task {
            // Refresh now and then once a minute while the view is visible.
            while !Task.isCancelled {
                await portfolio.refreshAll()
                try? await Task.sleep(for: .seconds(60))
            }
        }
        .onChange(of: portfolio.positions.isEmpty, initial: true) { _, isEmpty in
            if isEmpty {
                editMode = .inactive
                insights.clear()
            }
        }
        .sheet(isPresented: $isAddingPosition) {
            AddPositionView()
        }
        .sheet(item: $selectedPosition) { position in
            PositionDetailView(position: position)
        }
        .sheet(isPresented: $isShowingInsights) {
            PortfolioInsightsView()
        }
    }
}

#Preview {
    NavigationStack {
        PositionsView()
    }
    .environment(WatchlistStore())
    .environment(PortfolioStore())
    .environment(InsightsStore())
    .preferredColorScheme(.dark)
}
