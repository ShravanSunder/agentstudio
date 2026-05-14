import SwiftUI

// MARK: - CommandBarFooter

/// Two-row keyboard hints footer.
/// Row 1 shows action shortcuts with separate key badges. Row 2 shows
/// navigation hints as dimmer plain text, with dismiss right-aligned.
struct CommandBarFooter: View {
    let hints: [FooterHint]

    var body: some View {
        let rows = Self.displayRows(for: FooterHintBuilder.layout(for: hints))

        VStack(spacing: AppStyles.CommandBar.Footer.rowSpacing) {
            HStack(spacing: 0) {
                ForEach(Array(rows.topLeading.enumerated()), id: \.element.id) { index, hint in
                    if index > 0 {
                        Text("·")
                            .font(.system(size: AppStyles.General.Typography.textXs))
                            .foregroundStyle(.primary.opacity(AppStyles.CommandBar.Footer.separatorOpacity))
                            .padding(.horizontal, AppStyles.CommandBar.Footer.separatorHorizontalPadding)
                    }
                    plainHint(hint)
                }

                Spacer(minLength: 0)

                ForEach(rows.topTrailing) { hint in
                    trailingHint(hint)
                }
            }
            .frame(height: AppStyles.CommandBar.Footer.rowHeight)

            HStack(spacing: AppStyles.CommandBar.Footer.bottomRowSpacing) {
                ForEach(rows.bottom) { hint in
                    badgeHint(hint)
                }
                Spacer(minLength: 0)
            }
            .frame(height: AppStyles.CommandBar.Footer.rowHeight)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, AppStyles.CommandBar.Footer.topPadding)
        .padding(.bottom, AppStyles.CommandBar.Footer.bottomPadding)
        .padding(.horizontal, AppStyles.CommandBar.Footer.horizontalPadding)
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
        HStack(spacing: AppStyles.CommandBar.Footer.hintSpacing) {
            CommandBarShortcutBadge(
                keys: hint.shortcutKeys,
                style: .row
            )
            Text(hint.label)
                .font(.system(size: AppStyles.General.Typography.textXs))
        }
        .foregroundStyle(.primary.opacity(AppStyles.CommandBar.Footer.primaryOpacity))
    }

    private func plainHint(_ hint: FooterHint) -> some View {
        HStack(spacing: AppStyles.CommandBar.Footer.hintSpacing) {
            Text(hint.shortcutKeys.map(\.symbol).joined())
                .font(.system(size: AppStyles.General.Typography.textXs, weight: .medium, design: .monospaced))
            Text(hint.label)
                .font(.system(size: AppStyles.General.Typography.textXs))
        }
        .foregroundStyle(.primary.opacity(AppStyles.CommandBar.Footer.secondaryOpacity))
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
                    .font(.system(size: AppStyles.General.Typography.textXs))
            }
            .foregroundStyle(.primary.opacity(AppStyles.CommandBar.Footer.secondaryOpacity))
        } else {
            plainHint(hint)
        }
    }
}
