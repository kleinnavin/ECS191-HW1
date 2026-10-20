//
//  SmartStockApp.swift
//  SmartStock
//
//  Created by Navin Klein on 10/11/26.
//

import SwiftUI

@main
struct SmartStockApp: App {
    @State private var watchlist = WatchlistStore()
    @State private var portfolio = PortfolioStore()
    @State private var insights = InsightsStore()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(watchlist)
                .environment(portfolio)
                .environment(insights)
                .fontDesign(.rounded)
                .preferredColorScheme(.dark)
        }
    }
}
