import SwiftUI

struct ChromeToolbarButtonLabel: View {
    let symbolName: String
    var selectedSymbolName: String?
    var isSelected = false
    var isHovered = false
    var badgeText: String?

    private var resolvedSymbolName: String {
        if isSelected, let selectedSymbolName {
            return selectedSymbolName
        }
        return symbolName
    }

    private var foregroundStyle: Color {
        if isSelected {
            return Color.accentColor
        }
        return isHovered ? .primary : .secondary
    }

    private var fillOpacity: CGFloat {
        if isSelected {
            return AppStyles.Shell.Chrome.ToolbarButton.selectedFillOpacity
        }
        if isHovered {
            return AppStyles.Shell.Chrome.ToolbarButton.hoverFillOpacity
        }
        return AppStyles.Shell.Chrome.ToolbarButton.baseFillOpacity
    }

    var body: some View {
        Image(systemName: resolvedSymbolName)
            .font(.system(size: AppStyles.Shell.Chrome.ToolbarButton.iconSize, weight: .medium))
            .foregroundStyle(foregroundStyle)
            .frame(width: AppStyles.General.Button.toolbar, height: AppStyles.General.Button.toolbar)
            .background(
                Circle()
                    .fill(
                        isSelected
                            ? Color.accentColor.opacity(fillOpacity)
                            : Color.white.opacity(fillOpacity)
                    )
            )
            .overlay(alignment: .topTrailing) {
                if let badgeText {
                    UnreadCountBadge(text: badgeText)
                        .offset(
                            x: AppStyles.Shell.Chrome.ToolbarButton.badgeOffsetX,
                            y: AppStyles.Shell.Chrome.ToolbarButton.badgeOffsetY
                        )
                }
            }
            .contentShape(Circle())
    }
}
