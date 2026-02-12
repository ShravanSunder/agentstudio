import SwiftUI

// MARK: - CommandBarFooter

/// Keyboard hints footer: "↵ Open  ↑↓ Navigate  esc Dismiss"
struct CommandBarFooter: View {
    let isNested: Bool
    let selectedHasChildren: Bool

    var body: some View {
        HStack(spacing: 16) {
            footerHint("↵", isNested ? "Select" : "Open")
            if selectedHasChildren && !isNested {
                footerHint("→", "Drill in")
            }
            footerHint("↑↓", "Navigate")
            if isNested {
                footerHint("⌫", "Back")
            }
            footerHint("esc", "Dismiss")
        }
        .frame(height: 32)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
    }

    private func footerHint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
            Text(label)
                .font(.system(size: 11))
        }
        .foregroundStyle(.primary.opacity(0.3))
    }
}
