import SwiftUI

// MARK: - CommandBarFooter

/// Dynamic keyboard hints footer for the selected item.
struct CommandBarFooter: View {
    let hints: [FooterHint]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(hints) { hint in
                if hint.isDivider {
                    divider
                } else {
                    footerHint(hint.key, hint.label)
                }
            }
        }
        .frame(height: 32)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
    }

    private func footerHint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            CommandBarShortcutBadge(
                keys: ShortcutKey.from(chord: key),
                style: .footerCompact
            )
            Text(label)
                .font(.system(size: AppStyle.textXs))
        }
        .foregroundStyle(.primary.opacity(0.3))
    }

    private var divider: some View {
        Rectangle()
            .fill(.primary.opacity(0.1))
            .frame(width: 1, height: 14)
    }
}
