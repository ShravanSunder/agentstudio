import SwiftUI

// MARK: - CommandBarResultRow

/// Single result row: icon, title, trailing metadata, drill-in affordance, shortcut badges.
/// Supports fuzzy match highlighting and dimming for unavailable commands.
struct CommandBarResultRow: View {
    let item: CommandBarItem
    let isSelected: Bool
    let searchQuery: String
    let isDimmed: Bool

    init(item: CommandBarItem, isSelected: Bool, searchQuery: String = "", isDimmed: Bool = false) {
        self.item = item
        self.isSelected = isSelected
        self.searchQuery = searchQuery
        self.isDimmed = isDimmed
    }

    var body: some View {
        HStack(spacing: AppStyles.CommandBar.Rows.iconSpacing) {
            // Icon
            if let icon = item.icon {
                iconView(icon)
            } else {
                Color.clear.frame(
                    width: AppStyles.CommandBar.Rows.iconSize,
                    height: AppStyles.CommandBar.Rows.iconSize
                )
            }

            if let openState = item.worktreeOpenState, openState != .notOpen {
                Circle()
                    .fill(Color.green.opacity(isDimmed ? 0.3 : 0.7))
                    .frame(
                        width: AppStyles.CommandBar.Rows.worktreeOpenIndicatorSize,
                        height: AppStyles.CommandBar.Rows.worktreeOpenIndicatorSize
                    )
            }

            highlightedTitle
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)

            Spacer(minLength: AppStyles.CommandBar.Rows.trailingMetadataSpacing)

            trailingAccessories
        }
        .padding(.horizontal, AppStyles.CommandBar.Rows.horizontalPadding)
        .frame(height: AppStyles.CommandBar.Rows.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: AppStyles.CommandBar.Rows.selectedRowCornerRadius)
                .fill(isSelected ? Color.accentColor.opacity(AppStyles.General.Fill.selected) : Color.clear)
                .padding(.horizontal, AppStyles.CommandBar.Rows.selectedRowHorizontalInset)
        )
        .contentShape(Rectangle())
        .opacity(isDimmed ? 0.5 : 1.0)
    }

    // MARK: - Highlighted Title

    @ViewBuilder
    private var trailingAccessories: some View {
        HStack(spacing: AppStyles.CommandBar.Rows.shortcutSpacing) {
            if let subtitle = item.subtitle {
                Text(subtitle)
                    .font(.system(size: AppStyles.General.Typography.textSm))
                    .foregroundStyle(
                        .primary.opacity(
                            isDimmed
                                ? AppStyles.CommandBar.Rows.dimmedTrailingMetadataOpacity
                                : AppStyles.CommandBar.Rows.trailingMetadataOpacity
                        )
                    )
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: AppStyles.CommandBar.Rows.trailingMetadataMaxWidth, alignment: .trailing)
            }

            if item.hasChildren {
                Image(systemName: "chevron.right")
                    .font(.system(size: AppStyles.General.Typography.textXs, weight: .medium))
                    .foregroundStyle(.primary.opacity(AppStyles.CommandBar.Rows.chevronOpacity))
            }

            if let keys = item.shortcutKeys, !keys.isEmpty {
                CommandBarShortcutBadge(keys: keys)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .layoutPriority(2)
    }

    @ViewBuilder
    private var highlightedTitle: some View {
        let title = displayTitle
        if searchQuery.isEmpty {
            Text(title)
                .font(
                    .system(
                        size: AppStyles.General.Typography.textBase,
                        weight: isSelected ? .semibold : .medium
                    )
                )
                .foregroundStyle(Color.primary.opacity(titleOpacity))
        } else if let matchResult = CommandBarSearch.fuzzyMatch(pattern: searchQuery, in: title) {
            buildHighlightedText(title, ranges: matchResult.matchedRanges)
        } else {
            Text(title)
                .font(
                    .system(
                        size: AppStyles.General.Typography.textBase,
                        weight: isSelected ? .semibold : .medium
                    )
                )
                .foregroundStyle(Color.primary.opacity(titleOpacity))
        }
    }

    private func buildHighlightedText(_ text: String, ranges: [Range<String.Index>]) -> some View {
        var result = AttributedString(text)
        result.font = .system(
            size: AppStyles.General.Typography.textBase,
            weight: isSelected ? .semibold : .medium
        )
        result.foregroundColor = Color.primary.opacity(
            isDimmed
                ? AppStyles.CommandBar.Rows.dimmedRowTitleOpacity
                : AppStyles.CommandBar.Rows.fuzzyUnmatchedTitleOpacity
        )

        for range in ranges {
            guard let attrRange = Range(range, in: result) else { continue }
            result[attrRange].foregroundColor = Color.primary.opacity(
                isDimmed
                    ? AppStyles.CommandBar.Rows.trailingMetadataOpacity
                    : AppStyles.CommandBar.Rows.selectedRowTitleOpacity
            )
            result[attrRange].font = .system(size: AppStyles.General.Typography.textBase, weight: .bold)
        }

        return Text(result)
    }

    private var displayTitle: String {
        item.title
    }

    private var titleOpacity: Double {
        if isDimmed { return AppStyles.CommandBar.Rows.dimmedRowTitleOpacity }
        if isSelected { return AppStyles.CommandBar.Rows.selectedRowTitleOpacity }
        return AppStyles.CommandBar.Rows.rowTitleOpacity
    }

    private var iconColor: Color {
        if isDimmed { return Color.primary.opacity(0.25) }
        if isSelected { return Color.accentColor }
        return item.iconColor ?? Color.primary.opacity(0.50)
    }

    @ViewBuilder
    private func iconView(_ icon: CommandIcon) -> some View {
        switch icon {
        case .system(let systemSymbol):
            Image(systemName: systemSymbol.rawValue)
                .font(.system(size: AppStyles.General.Typography.textBase, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(
                    width: AppStyles.CommandBar.Rows.iconSize,
                    height: AppStyles.CommandBar.Rows.iconSize
                )
        case .octicon(let octiconSymbol):
            OcticonImage(name: octiconSymbol.rawValue, size: AppStyles.CommandBar.Rows.iconSize)
                .foregroundStyle(iconColor)
                .frame(
                    width: AppStyles.CommandBar.Rows.iconSize,
                    height: AppStyles.CommandBar.Rows.iconSize
                )
        }
    }
}
