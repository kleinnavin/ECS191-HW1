//
//  SheetCloseBar.swift
//  SmartStock
//

import SwiftUI

/// Round glass close button pinned to the top left of a detail sheet.
struct SheetCloseBar: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                // Size and shape the label itself, not the button: a frame
                // outside the button enlarges the circle but leaves only the
                // small icon tappable, so taps near the edge did nothing.
                Image(systemName: "xmark")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityLabel("Close")
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 4)
    }
}

extension View {
    /// Pins a `SheetCloseBar` to the top of a scrolling sheet. As a safe
    /// area bar it gets a scroll edge effect, so content scrolled under it
    /// is blurred out instead of running behind the close button.
    func sheetCloseBar() -> some View {
        safeAreaBar(edge: .top, spacing: 0) { SheetCloseBar() }
            .scrollEdgeEffectStyle(.soft, for: .top)
    }
}
