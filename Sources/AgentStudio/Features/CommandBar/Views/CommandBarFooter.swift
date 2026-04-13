import SwiftUI

// MARK: - CommandBarFooter

/// Two-row keyboard hints footer.
/// Row 1 shows action shortcuts with separate key badges. Row 2 shows
/// navigation hints as dimmer plain text, with dismiss right-aligned.
struct CommandBarFooter: View {
    let hints: [FooterHint]

    private let primaryOpacity: Double = 0.40
    private let secondaryOpacity: Double = 0.25
    private let separatorOpacity: Double = 0.15
    private let rowHeight: CGFloat = 16

    var body: some View {
        let rows = Self.displayRows(for: FooterHintBuilder.layout(for: hints))

        VStack(spacing: 6) {
            HStack(spacing: 0) {
                ForEach(Array(rows.topLeading.enumerated()), id: \.element.id) { index, hint in
                    if index > 0 {
                        Text("·")
                            .font(.system(size: AppStyle.textXs))
                            .foregroundStyle(.primary.opacity(separatorOpacity))
                            .padding(.horizontal, 6)
                    }
                    plainHint(hint)
                }

                Spacer(minLength: 0)

                ForEach(rows.topTrailing) { hint in
                    trailingHint(hint)
                }
            }
            .frame(height: rowHeight)

            HStack(spacing: 14) {
                ForEach(rows.bottom) { hint in
                    badgeHint(hint)
                }
                Spacer(minLength: 0)
            }
            .frame(height: rowHeight)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .padding(.horizontal, 12)
    }

    struct DisplayRows {
        let topLeading: [FooterHint]
        let topTrailing: [FooterHint]
        let bottom: [FooterHint]
    }

    nonisolated static func displayRows(for layout: FooterHintLayout) -> DisplayRows {
        DisplayRows(
            topLeading: layout.secondaryLeadingRow,
            topTrailing: layout.secondaryTrailingRow,
            bottom: layout.primaryRow
        )
    }

    private func badgeHint(_ hint: FooterHint) -> some View {
        HStack(spacing: 4) {
            CommandBarShortcutBadge(
                keys: hint.shortcutKeys,
                style: .row
            )
            Text(hint.label)
                .font(.system(size: AppStyle.textXs))
        }
        .foregroundStyle(.primary.opacity(primaryOpacity))
    }

    private func plainHint(_ hint: FooterHint) -> some View {
        HStack(spacing: 4) {
            Text(hint.shortcutKeys.map(\.symbol).joined())
                .font(.system(size: AppStyle.textXs, weight: .medium, design: .monospaced))
            Text(hint.label)
                .font(.system(size: AppStyle.textXs))
        }
        .foregroundStyle(.primary.opacity(secondaryOpacity))
    }

    @ViewBuilder
    private func trailingHint(_ hint: FooterHint) -> some View {
        if hint.style == .badge {
            HStack(spacing: 4) {
                CommandBarShortcutBadge(
                    keys: hint.shortcutKeys,
                    style: .row
                )
                Text(hint.label)
                    .font(.system(size: AppStyle.textXs))
            }
            .foregroundStyle(.primary.opacity(secondaryOpacity))
        } else {
            plainHint(hint)
        }
    }
}
