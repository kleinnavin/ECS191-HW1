//
//  HomeView.swift
//  SmartStock
//

import SwiftUI

struct HomeView: View {
    @Environment(WatchlistStore.self) private var watchlist
    @Environment(PortfolioStore.self) private var portfolio
    /// Whether My Positions is pushed; remembered across launches.
    @AppStorage("home.showingPositions") private var isShowingPositions = false
    @State private var editMode: EditMode = .inactive
    @State private var isSearching = false
    @State private var selectedAsset: Asset?

    var body: some View {
        NavigationStack {
            List {
                if let error = watchlist.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.yellow)
                        .listRowBackground(Color.clear)
                }

                ForEach(watchlist.assets) { asset in
                    Button {
                        selectedAsset = asset
                    } label: {
                        AssetRow(
                            asset: asset,
                            quote: watchlist.quotes[asset.symbol],
                            history: watchlist.histories[asset.symbol],
                            error: watchlist.errors[asset.symbol]
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .listRowSeparatorTint(Color(white: 0.25))
                }
                .onDelete(perform: watchlist.remove(atOffsets:))
                .onMove(perform: watchlist.move(fromOffsets:toOffset:))
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .safeAreaInset(edge: .bottom) {
                // Pinned so it's visible however long the watchlist is; the
                // list scrolls behind it and its last row stays reachable.
                if !editMode.isEditing {
                    PortfolioCard(
                        positionCount: portfolio.positions.count,
                        totalValue: portfolio.quotes.isEmpty ? nil : portfolio.totalValue,
                        dayChange: portfolio.totalDayChange
                    ) {
                        isShowingPositions = true
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 4)
                    // Fade the list out behind the card and down to the screen edge.
                    .background {
                        LinearGradient(
                            stops: [.init(color: .black.opacity(0), location: 0), .init(color: .black, location: 0.35)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .ignoresSafeArea(edges: .bottom)
                    }
                    .task {
                        // The watchlist doesn't refresh positions, so load their
                        // quotes once for the card's summary.
                        if portfolio.quotes.isEmpty { await portfolio.refreshAll() }
                    }
                }
            }
            .environment(\.editMode, $editMode)
            .navigationTitle("Stocks")
            .navigationSubtitle(Date.now.formatted(.dateTime.month(.wide).day()))
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Search", systemImage: "magnifyingglass") {
                        isSearching = true
                    }
                    editMenu
                }
            }
            .refreshable { await watchlist.refreshAll() }
            .task {
                // Refresh now and then once a minute while the view is visible.
                while !Task.isCancelled {
                    await watchlist.refreshAll()
                    try? await Task.sleep(for: .seconds(60))
                }
            }
            .navigationDestination(isPresented: $isShowingPositions) {
                PositionsView()
            }
            .onChange(of: isShowingPositions) { editMode = .inactive }
            .sheet(isPresented: $isSearching) {
                SearchView()
            }
            .sheet(item: $selectedAsset) { asset in
                AssetDetailView(asset: asset)
            }
        }
    }

    /// "Edit" opens a menu to edit the watchlist or open My Positions;
    /// while editing it becomes "Done".
    @ViewBuilder
    private var editMenu: some View {
        if editMode.isEditing {
            Button("Done") {
                withAnimation { editMode = .inactive }
            }
            .fontWeight(.semibold)
        } else {
            Menu("Edit") {
                Button("Edit Watchlist", systemImage: "pencil") {
                    withAnimation { editMode = .active }
                }
                Divider()
                Button {
                    isShowingPositions = true
                } label: {
                    Label("My Positions", systemImage: "briefcase")
                    Text("Your holdings, gains and allocation")
                }
            }
        }
    }
}

#Preview {
    HomeView()
        .environment(WatchlistStore())
        .environment(PortfolioStore())
        .preferredColorScheme(.dark)
}
