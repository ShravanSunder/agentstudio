import SwiftUI

// MARK: - CommandBarShortcutBadge

/// Renders keyboard shortcut as individual key badges: [⌘] [W]
/// Linear-style: small rounded rectangles with SF Mono characters.
struct CommandBarShortcutBadge: View {
    let keys: [ShortcutKey]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(keys) { key in
                Text(key.symbol)
                    .font(.system(size: AppStyle.textXs, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary.opacity(0.35))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.primary.opacity(0.06))
                    )
            }
        }
    }
}
