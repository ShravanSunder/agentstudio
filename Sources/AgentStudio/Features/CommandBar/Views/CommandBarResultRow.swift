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
        rowContent
            .padding(.horizontal, AppStyles.CommandBar.Rows.horizontalPadding)
            .frame(height: rowHeight)
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
    private var rowContent: some View {
        if item.secondaryLine == nil {
            compactRowContent
        } else {
            expandedRowContent
        }
    }

    private var compactRowContent: some View {
        HStack(spacing: AppStyles.CommandBar.Rows.iconSpacing) {
            leadingIcon
            openStateIndicator
            highlightedTitle
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)

            Spacer(minLength: AppStyles.CommandBar.Rows.trailingMetadataSpacing)

            trailingAccessories
        }
    }

    private var expandedRowContent: some View {
        HStack(alignment: .top, spacing: AppStyles.CommandBar.Rows.iconSpacing) {
            leadingIcon
            openStateIndicator

            VStack(alignment: .leading, spacing: AppStyles.CommandBar.Rows.secondaryLineSpacing) {
                HStack(spacing: 0) {
                    highlightedTitle
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(1)

                    Spacer(minLength: AppStyles.CommandBar.Rows.trailingMetadataSpacing)

                    trailingAccessories
                }

                secondaryLineView
            }
            .padding(.top, 1)
        }
    }

    @ViewBuilder
    private var leadingIcon: some View {
        if let icon = item.icon {
            iconView(icon)
        } else {
            Color.clear.frame(
                width: AppStyles.CommandBar.Rows.iconSize,
                height: AppStyles.CommandBar.Rows.iconSize
            )
        }
    }

    @ViewBuilder
    private var openStateIndicator: some View {
        if let openState = item.worktreeOpenState, openState != .notOpen {
            Circle()
                .fill(Color.green.opacity(isDimmed ? 0.3 : 0.7))
                .frame(
                    width: AppStyles.CommandBar.Rows.worktreeOpenIndicatorSize,
                    height: AppStyles.CommandBar.Rows.worktreeOpenIndicatorSize
                )
        }
    }

    @ViewBuilder
    private var secondaryLineView: some View {
        if let secondaryLine = item.secondaryLine {
            HStack(spacing: 5) {
                if let icon = secondaryLine.icon {
                    secondaryLineIcon(icon)
                }

                Text(secondaryLine.text)
                    .font(.system(size: AppStyles.General.Typography.textXs, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(secondaryLineOpacity))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .layoutPriority(1)
        }
    }

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

    private var secondaryLineOpacity: Double {
        if isDimmed { return AppStyles.CommandBar.Rows.dimmedTrailingMetadataOpacity }
        if isSelected { return AppStyles.CommandBar.Rows.selectedSecondaryLineOpacity }
        return AppStyles.CommandBar.Rows.secondaryLineOpacity
    }

    private var rowHeight: CGFloat {
        item.secondaryLine == nil
            ? AppStyles.CommandBar.Rows.rowHeight
            : AppStyles.CommandBar.Rows.rowHeightWithSecondaryLine
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

    @ViewBuilder
    private func secondaryLineIcon(_ icon: CommandIcon) -> some View {
        switch icon {
        case .system(let systemSymbol):
            Image(systemName: systemSymbol.rawValue)
                .font(.system(size: AppStyles.CommandBar.Rows.secondaryLineIconSize, weight: .medium))
                .foregroundStyle(Color.primary.opacity(secondaryLineOpacity))
                .frame(
                    width: AppStyles.CommandBar.Rows.iconSize,
                    height: AppStyles.CommandBar.Rows.secondaryLineIconSize
                )
        case .octicon(let octiconSymbol):
            OcticonImage(name: octiconSymbol.rawValue, size: AppStyles.CommandBar.Rows.secondaryLineIconSize)
                .foregroundStyle(Color.primary.opacity(secondaryLineOpacity))
                .frame(
                    width: AppStyles.CommandBar.Rows.iconSize,
                    height: AppStyles.CommandBar.Rows.secondaryLineIconSize
                )
        }
    }
}
