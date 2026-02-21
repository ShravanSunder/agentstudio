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
        HStack(spacing: 10) {
            // Icon
            if let iconName = item.icon {
                Image(systemName: iconName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(iconColor)
                    .frame(width: 16, height: 16)
            } else {
                Color.clear.frame(width: 16, height: 16)
            }

            // Title with match highlighting
            highlightedTitle
                .lineLimit(1)

            // Subtitle
            if let subtitle = item.subtitle {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary.opacity(isDimmed ? 0.25 : 0.5))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            // Drill-in chevron
            if item.hasChildren {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.3))
            }

            // Shortcut badges
            if let keys = item.shortcutKeys, !keys.isEmpty {
                CommandBarShortcutBadge(keys: keys)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
                .padding(.horizontal, 4)
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
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.primary.opacity(isDimmed ? 0.4 : 0.88))
        } else if let matchResult = CommandBarSearch.fuzzyMatch(pattern: searchQuery, in: title) {
            buildHighlightedText(title, ranges: matchResult.matchedRanges)
        } else {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.primary.opacity(isDimmed ? 0.4 : 0.88))
        }
    }

    private func buildHighlightedText(_ text: String, ranges: [Range<String.Index>]) -> some View {
        var result = AttributedString(text)
        result.font = .system(size: 13, weight: .medium)
        result.foregroundColor = Color.primary.opacity(isDimmed ? 0.4 : 0.58)

        for range in ranges {
            guard let attrRange = Range(range, in: result) else { continue }
            result[attrRange].foregroundColor = Color.primary.opacity(isDimmed ? 0.6 : 0.95)
            result[attrRange].font = .system(size: 13, weight: .bold)
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
