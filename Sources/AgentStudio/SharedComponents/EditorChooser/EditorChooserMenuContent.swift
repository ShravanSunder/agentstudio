import AppKit
import SwiftUI

struct EditorChooserMenuStyle: Equatable {
    var menuWidth: CGFloat
    var outerPadding: CGFloat
    var rowSpacing: CGFloat
    var rowContentSpacing: CGFloat
    var rowHorizontalPadding: CGFloat
    var rowVerticalPadding: CGFloat
    var rowCornerRadius: CGFloat
    var appIconSize: CGFloat
    var badgeSize: CGFloat
    var badgeCornerRadius: CGFloat
    var bookmarkHitSize: CGFloat

    static let standard = Self(
        menuWidth: AppStyles.Components.EditorChooser.menuWidth,
        outerPadding: AppStyles.Components.EditorChooser.outerPadding,
        rowSpacing: AppStyles.Components.EditorChooser.rowSpacing,
        rowContentSpacing: AppStyles.Components.EditorChooser.rowContentSpacing,
        rowHorizontalPadding: AppStyles.Components.EditorChooser.rowHorizontalPadding,
        rowVerticalPadding: AppStyles.Components.EditorChooser.rowVerticalPadding,
        rowCornerRadius: AppStyles.Components.EditorChooser.rowCornerRadius,
        appIconSize: AppStyles.Components.EditorChooser.appIconSize,
        badgeSize: AppStyles.Components.EditorChooser.badgeSize,
        badgeCornerRadius: AppStyles.Components.EditorChooser.badgeCornerRadius,
        bookmarkHitSize: AppStyles.Components.EditorChooser.bookmarkHitSize
    )
}

struct EditorChooserMenuContent: View {
    struct DisplayItem: Identifiable {
        let id: EditorTargetId
        let title: String
        let appIcon: NSImage?
        let shortcutNumber: Int
        let isBookmarked: Bool
    }

    let items: [EditorChoiceItem]
    let bookmarkedEditorId: EditorTargetId?
    let selectedEditorId: EditorTargetId?
    let directLaunchHintText: String?
    let directLaunchShortcutText: String?
    let style: EditorChooserMenuStyle
    let onSelect: (EditorTargetId) -> Void
    let onToggleBookmark: (EditorTargetId) -> Void

    @State private var hoveredRowId: EditorTargetId?

    nonisolated static func makeDisplayItems(
        items: [EditorChoiceItem],
        bookmarkedEditorId: EditorTargetId?
    ) -> [DisplayItem] {
        items.map { item in
            DisplayItem(
                id: item.id,
                title: item.title,
                appIcon: item.appIcon,
                shortcutNumber: item.shortcutNumber,
                isBookmarked: item.id == bookmarkedEditorId
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: style.rowSpacing) {
            if let directLaunchHintText, let directLaunchShortcutText, !directLaunchShortcutText.isEmpty {
                headerHint(shortcut: directLaunchShortcutText, text: directLaunchHintText)
            }
            ForEach(Self.makeDisplayItems(items: items, bookmarkedEditorId: bookmarkedEditorId)) { item in
                row(item)
            }
        }
        .padding(style.outerPadding)
        .frame(width: style.menuWidth)
    }

    private func headerHint(shortcut: String, text: String) -> some View {
        HStack(alignment: .center, spacing: AppStyles.Components.EditorChooser.headerContentSpacing) {
            Text(shortcut)
                .font(.system(size: AppStyles.General.Typography.textXs, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, AppStyles.Components.EditorChooser.shortcutHintHorizontalPadding)
                .padding(.vertical, AppStyles.Components.EditorChooser.shortcutHintVerticalPadding)
                .background(
                    RoundedRectangle(cornerRadius: style.badgeCornerRadius)
                        .fill(Color.primary.opacity(AppStyles.Components.EditorChooser.badgeFillOpacity))
                )

            Text(text)
                .font(.system(size: AppStyles.General.Typography.textXs, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, style.rowHorizontalPadding)
        .padding(.bottom, AppStyles.Components.EditorChooser.headerBottomPadding)
    }

    @ViewBuilder
    private func iconView(for icon: NSImage?) -> some View {
        if let icon {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: style.appIconSize, height: style.appIconSize)
        } else {
            Image(systemName: "app")
                .font(.system(size: AppStyles.Components.EditorChooser.fallbackIconFontSize, weight: .medium))
                .frame(width: style.appIconSize, height: style.appIconSize)
        }
    }

    private func row(_ item: DisplayItem) -> some View {
        HStack(spacing: style.rowContentSpacing) {
            Button {
                onSelect(item.id)
            } label: {
                HStack(spacing: style.rowContentSpacing) {
                    Text("\(item.shortcutNumber)")
                        .font(
                            .system(
                                size: AppStyles.Components.EditorChooser.badgeFontSize,
                                weight: .semibold
                            )
                        )
                        .foregroundStyle(.secondary)
                        .frame(width: style.badgeSize, height: style.badgeSize)
                        .background(
                            RoundedRectangle(cornerRadius: style.badgeCornerRadius)
                                .fill(Color.primary.opacity(AppStyles.Components.EditorChooser.badgeFillOpacity))
                        )

                    iconView(for: item.appIcon)

                    Text(item.title)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, style.rowHorizontalPadding)
                .padding(.vertical, style.rowVerticalPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                onToggleBookmark(item.id)
            } label: {
                Image(systemName: item.isBookmarked ? "bookmark.fill" : "bookmark")
                    .foregroundStyle(item.isBookmarked ? Color.accentColor : Color.secondary)
                    .frame(width: style.bookmarkHitSize, height: style.bookmarkHitSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, style.rowHorizontalPadding)
        }
        .background(
            RoundedRectangle(cornerRadius: style.rowCornerRadius)
                .fill(
                    selectedEditorId == item.id
                        ? Color.accentColor.opacity(AppStyles.Components.EditorChooser.selectedRowFillOpacity)
                        : (hoveredRowId == item.id
                            ? Color.primary.opacity(AppStyles.General.Fill.hover)
                            : Color.clear)
                )
        )
        .onHover { hovering in
            hoveredRowId = hovering ? item.id : nil
        }
    }
}
