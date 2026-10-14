//
//  SearchView.swift
//  SmartStock
//

import SwiftUI

/// Sheet for finding symbols on Finnhub and adding them to the watchlist.
struct SearchView: View {
    @Environment(WatchlistStore.self) private var watchlist
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [SymbolSearchResult] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List(results) { result in
                SearchResultRow(result: result, isAdded: watchlist.contains(result.symbol)) {
                    watchlist.add(result.asAsset)
                }
            }
            .listStyle(.plain)
            .overlay { overlay }
            .navigationTitle("Add Symbol")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search for a company or symbol"
            )
            .autocorrectionDisabled()
            .textInputAutocapitalization(.characters)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task(id: query) { await search() }
        }
    }

    @ViewBuilder
    private var overlay: some View {
        if isLoading && results.isEmpty {
            ProgressView()
        } else if let errorMessage {
            ContentUnavailableView("Search Failed", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
        } else if query.isEmpty {
            ContentUnavailableView("Search Symbols", systemImage: "magnifyingglass", description: Text("Find stocks, ETFs, and funds to add to your list."))
        } else if results.isEmpty && !isLoading {
            ContentUnavailableView.search(text: query)
        }
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else {
            results = []
            errorMessage = nil
            return
        }
        // Debounce typing; a newer query cancels this task during the sleep.
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }

        isLoading = true
        defer { isLoading = false }
        do {
            let found = try await watchlist.search(text)
            guard !Task.isCancelled else { return }
            results = found
            errorMessage = nil
        } catch {
            guard !Task.isCancelled else { return }
            if let urlError = error as? URLError, urlError.code == .cancelled { return }
            results = []
            errorMessage = error.localizedDescription
        }
    }
}

private struct SearchResultRow: View {
    let result: SymbolSearchResult
    let isAdded: Bool
    let onAdd: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(result.displaySymbol)
                    .font(.headline)
                Text(result.asAsset.name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if isAdded {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityLabel("Added")
            } else {
                Button("Add \(result.displaySymbol)", systemImage: "plus.circle.fill", action: onAdd)
                    .labelStyle(.iconOnly)
                    .font(.title2)
                    .buttonStyle(.borderless)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if !isAdded { onAdd() } }
    }
}
