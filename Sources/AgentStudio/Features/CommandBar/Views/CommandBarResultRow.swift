import SwiftUI

// MARK: - CommandBarResultRow

/// Single result row: icon, title (with ... for drill-in), subtitle, shortcut badges.
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
            if let iconName = item.icon {
                Image(systemName: iconName)
                    .font(.system(size: AppStyles.General.Typography.textBase, weight: .medium))
                    .foregroundStyle(iconColor)
                    .frame(
                        width: AppStyles.CommandBar.Rows.iconSize,
                        height: AppStyles.CommandBar.Rows.iconSize
                    )
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

            // Title with match highlighting
            highlightedTitle
                .lineLimit(1)

            // Subtitle
            if let subtitle = item.subtitle {
                Text(subtitle)
                    .font(.system(size: AppStyles.General.Typography.textSm))
                    .foregroundStyle(.primary.opacity(isDimmed ? 0.25 : 0.5))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            // Drill-in chevron
            if item.hasChildren {
                Image(systemName: "chevron.right")
                    .font(.system(size: AppStyles.General.Typography.textXs, weight: .medium))
                    .foregroundStyle(.primary.opacity(AppStyles.CommandBar.Rows.chevronOpacity))
            }

            // Shortcut badges
            if let keys = item.shortcutKeys, !keys.isEmpty {
                CommandBarShortcutBadge(keys: keys)
            }
        }
        .padding(.horizontal, AppStyles.CommandBar.Rows.horizontalPadding)
        .frame(height: AppStyles.CommandBar.Rows.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: AppStyles.CommandBar.Rows.selectedRowCornerRadius)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
                .padding(.horizontal, AppStyles.CommandBar.Rows.selectedRowHorizontalInset)
        )
        .contentShape(Rectangle())
        .opacity(isDimmed ? 0.5 : 1.0)
    }

    // MARK: - Highlighted Title

    @ViewBuilder
    private var highlightedTitle: some View {
        let title = displayTitle
        if searchQuery.isEmpty {
            Text(title)
                .font(.system(size: AppStyles.General.Typography.textBase, weight: .medium))
                .foregroundStyle(Color.primary.opacity(isDimmed ? 0.4 : 0.88))
        } else if let matchResult = CommandBarSearch.fuzzyMatch(pattern: searchQuery, in: title) {
            buildHighlightedText(title, ranges: matchResult.matchedRanges)
        } else {
            Text(title)
                .font(.system(size: AppStyles.General.Typography.textBase, weight: .medium))
                .foregroundStyle(Color.primary.opacity(isDimmed ? 0.4 : 0.88))
        }
    }

    private func buildHighlightedText(_ text: String, ranges: [Range<String.Index>]) -> some View {
        var result = AttributedString(text)
        result.font = .system(size: AppStyles.General.Typography.textBase, weight: .medium)
        result.foregroundColor = Color.primary.opacity(isDimmed ? 0.4 : 0.58)

        for range in ranges {
            guard let attrRange = Range(range, in: result) else { continue }
            result[attrRange].foregroundColor = Color.primary.opacity(isDimmed ? 0.6 : 0.95)
            result[attrRange].font = .system(size: AppStyles.General.Typography.textBase, weight: .bold)
        }

        return Text(result)
    }

    private var displayTitle: String {
        item.hasChildren ? item.title + "..." : item.title
    }

    private var iconColor: Color {
        if isDimmed { return Color.primary.opacity(0.25) }
        if isSelected { return Color.accentColor }
        return item.iconColor ?? Color.primary.opacity(0.50)
    }
}
