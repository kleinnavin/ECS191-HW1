//
//  Theme.swift
//  SmartStock
//

import SwiftUI

/// SmartStock's look: deep navy taken from the app icon, a teal accent
/// (the AccentColor asset) and rows shown as rounded cards.
extension Color {
    /// Behind every screen.
    static let appBackground = Color(hex: 0x0B1120)
    /// Cards and sheets, a step lighter than the background.
    static let appSurface = Color(hex: 0x172036)
}

extension View {
    /// Shows a list row on its own rounded card instead of between divider lines.
    func cardRow() -> some View {
        listRowBackground(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.appSurface)
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
        )
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 12, leading: 28, bottom: 12, trailing: 28))
    }

    /// The navy background, for lists and forms that would otherwise be black.
    func appBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(Color.appBackground)
    }
}
