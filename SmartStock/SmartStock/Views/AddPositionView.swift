//
//  AddPositionView.swift
//  SmartStock
//

import SwiftUI

/// Sheet for adding a position: pick an asset, then enter when it was
/// bought, the price paid, and how much.
struct AddPositionView: View {
    @Environment(WatchlistStore.self) private var watchlist
    @Environment(PortfolioStore.self) private var portfolio
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [SymbolSearchResult] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty {
                    if !watchlistStocks.isEmpty {
                        Section("Your Watchlist") {
                            ForEach(watchlistStocks) { assetLink($0) }
                        }
                    }
                } else {
                    ForEach(results) { assetLink($0.asAsset) }
                }
            }
            .listStyle(.plain)
            .overlay { overlay }
            .navigationTitle("Add Position")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search for a company or symbol"
            )
            .autocorrectionDisabled()
            .textInputAutocapitalization(.characters)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .navigationDestination(for: Asset.self) { asset in
                PositionForm(asset: asset) { position in
                    portfolio.add(position)
                    dismiss()
                }
            }
            .task(id: query) { await search() }
        }
    }

    /// Indices can't be held as positions, so they're left out.
    private var watchlistStocks: [Asset] {
        watchlist.assets.filter { !$0.isIndex }
    }

    private func assetLink(_ asset: Asset) -> some View {
        NavigationLink(value: asset) {
            VStack(alignment: .leading, spacing: 2) {
                Text(asset.title)
                    .font(.headline)
                Text(asset.name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var overlay: some View {
        if query.isEmpty {
            if watchlistStocks.isEmpty {
                ContentUnavailableView("Search Symbols", systemImage: "magnifyingglass", description: Text("Find a stock or fund you own. Market indices can't be added as positions."))
            }
        } else if isLoading && results.isEmpty {
            ProgressView()
        } else if let errorMessage {
            ContentUnavailableView("Search Failed", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
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
            results = found.filter { !$0.asAsset.isIndex }
            errorMessage = nil
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            results = []
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Details form

private struct PositionForm: View {
    let asset: Asset
    let onSave: (Position) -> Void

    @Environment(PortfolioStore.self) private var portfolio

    enum AmountKind: String, CaseIterable, Identifiable {
        case shares = "Shares"
        case dollars = "Dollar Amount"

        var id: String { rawValue }
    }

    /// Result of looking up the closing price on the purchase date.
    enum Lookup: Equatable {
        case idle, loading, failed
        case found(price: Double, date: Date)
    }

    @State private var purchaseDate = Date.now
    @State private var priceText = ""
    /// The last price filled in automatically; once the user types
    /// something else, lookups stop overwriting it.
    @State private var autoFilledPrice = ""
    @State private var lookup: Lookup = .idle
    @State private var kind: AmountKind = .shares
    @State private var amountText = ""

    private var price: Double? { Self.parse(priceText) }
    private var amount: Double? { Self.parse(amountText) }

    private var shares: Double? {
        guard let price, let amount else { return nil }
        return kind == .shares ? amount : amount / price
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 2) {
                    Text(asset.title).font(.title2.bold())
                    Text(asset.name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                DatePicker("Date Purchased", selection: $purchaseDate, in: ...Date.now, displayedComponents: .date)
                LabeledContent {
                    TextField("0.00", text: $priceText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Price per Share")
                        priceSource
                    }
                }
            } footer: {
                Text("Defaults to the closing price on the date purchased (the current price if that's today). Change it if you paid a different price.")
            }

            Section {
                Picker("Enter", selection: $kind) {
                    ForEach(AmountKind.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowSeparator(.hidden)
                LabeledContent(kind == .shares ? "Number of Shares" : "Amount Invested") {
                    TextField(kind == .shares ? "0" : "$0.00", text: $amountText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                }
            } footer: {
                if let shares, let price, shares > 0, price > 0 {
                    Text(kind == .shares
                         ? "Cost basis: \((shares * price).dollars)"
                         : "\(shares.sharesText) at \(price.dollars)")
                }
            }
        }
        .navigationTitle("Position Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Add", action: save)
                    .disabled(!isValid)
            }
        }
        .task(id: Calendar.current.startOfDay(for: purchaseDate)) { await lookUpPrice() }
    }

    /// Whether the price field still holds the looked-up price.
    private var isPriceAutoFilled: Bool { !priceText.isEmpty && priceText == autoFilledPrice }

    /// Caption under "Price per Share" saying where the price came from.
    @ViewBuilder
    private var priceSource: some View {
        Group {
            if case .found(let close, let date) = lookup, !isPriceAutoFilled, !priceText.isEmpty {
                // The user typed their own price; offer the close back.
                HStack(spacing: 6) {
                    tag("Entered by you", systemImage: "pencil")
                        .foregroundStyle(.secondary)
                    Button("Use \(Calendar.current.isDateInToday(date) ? "current" : "close") \(close.dollars)") { fill(close) }
                        .buttonStyle(.borderless)
                }
            } else {
                switch lookup {
                case .idle:
                    EmptyView()
                case .loading:
                    tag("Looking up the close…", systemImage: "clock")
                        .foregroundStyle(.secondary)
                case .failed where priceText.isEmpty:
                    tag("No price found. Enter what you paid.", systemImage: "exclamationmark.circle")
                        .foregroundStyle(.orange)
                case .failed:
                    tag("Entered by you", systemImage: "pencil")
                        .foregroundStyle(.secondary)
                case .found(_, let date):
                    tag(closeName(for: date), systemImage: "calendar")
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .font(.caption)
    }

    /// Icon and text side by side; a Label in a form row's title stacks them.
    private func tag(_ text: String, systemImage: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
            Text(text)
        }
    }

    /// "Close on Oct 3, 2025", noting when a weekend or holiday purchase
    /// date used the next trading day's close.
    private func closeName(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Current price" }
        let day = date.formatted(date: .abbreviated, time: .omitted)
        return calendar.isDate(date, inSameDayAs: purchaseDate)
            ? "Close on \(day)"
            : "Close on \(day) (next trading day)"
    }

    private func fill(_ price: Double) {
        let text = price.formatted(.number.precision(.fractionLength(2)).grouping(.never))
        priceText = text
        autoFilledPrice = text
    }

    private var isValid: Bool {
        guard let price, let shares else { return false }
        return price > 0 && shares > 0
    }

    private func save() {
        guard let price, let shares, isValid else { return }
        onSave(Position(asset: asset, purchaseDate: purchaseDate, purchasePrice: price, shares: shares))
    }

    /// Suggests a purchase price: the current price for today, otherwise the
    /// close on that day (or the next trading day, for weekends and holidays).
    private func lookUpPrice() async {
        lookup = .loading
        let day = Calendar.current.startOfDay(for: purchaseDate)
        do {
            let found: (price: Double, date: Date)?
            if Calendar.current.isDateInToday(day) {
                let current = try await portfolio.yahoo.chart(for: asset.symbol).quote.current
                found = (current, .now)
            } else {
                let end = min(day.addingTimeInterval(6 * 86_400), .now)
                let chart = try await portfolio.yahoo.chart(for: asset.symbol, from: day, to: end, interval: "1d")
                found = chart.history.points.first { $0.date >= day }.map { ($0.price, $0.date) }
            }
            guard let found else {
                lookup = .failed
                return
            }
            lookup = .found(price: found.price, date: found.date)
            if priceText.isEmpty || priceText == autoFilledPrice { fill(found.price) }
        } catch {
            if !error.isCancellation { lookup = .failed }
        }
    }

    private static func parse(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "$", with: "")
        return try? Double(trimmed, format: .number)
    }
}

#Preview("Details") {
    NavigationStack {
        PositionForm(asset: Asset(symbol: "AAPL", title: "AAPL", name: "Apple Inc")) { _ in }
    }
    .environment(PortfolioStore())
    .preferredColorScheme(.dark)
}

#Preview {
    AddPositionView()
        .environment(WatchlistStore())
        .environment(PortfolioStore())
        .preferredColorScheme(.dark)
}
