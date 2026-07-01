import SwiftUI

struct ChromeToolbarButtonLabel: View {
    let symbolName: String
    var selectedSymbolName: String?
    var isSelected = false
    var isHovered = false
    var badgeText: String?
    var buttonSize = AppStyles.Shell.Chrome.ToolbarButton.size
    var showsBackground = true

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

    var body: some View {
        Image(systemName: resolvedSymbolName)
            .font(.system(size: AppStyles.Shell.Chrome.ToolbarButton.iconSize, weight: .medium))
            .foregroundStyle(foregroundStyle)
            .frame(width: buttonSize, height: buttonSize)
            .background(
                Group {
                    if showsBackground {
                        ChromeToolbarCircleBackground(
                            isSelected: isSelected,
                            isHovered: isHovered
                        )
                    }
                }
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
            .contentShape(Rectangle())
    }
}

struct ChromeToolbarCircleBackground: View {
    var isSelected = false
    var isHovered = false
    var isPressed = false

    var body: some View {
        Circle()
            .fill(
                ChromeToolbarControlPalette.fillColor(
                    isSelected: isSelected,
                    isHovered: isHovered,
                    isPressed: isPressed
                )
            )
            .overlay(
                Circle()
                    .stroke(
                        ChromeToolbarControlPalette.strokeColor(
                            isSelected: isSelected,
                            isHovered: isHovered,
                            isPressed: isPressed
                        ),
                        lineWidth: 1
                    )
            )
    }
}

struct ChromeToolbarCapsuleBackground: View {
    var isSelected = false
    var isHovered = false
    var isPressed = false

    var body: some View {
        Capsule()
            .fill(
                ChromeToolbarControlPalette.fillColor(
                    isSelected: isSelected,
                    isHovered: isHovered,
                    isPressed: isPressed
                )
            )
            .overlay(
                Capsule()
                    .stroke(
                        ChromeToolbarControlPalette.strokeColor(
                            isSelected: isSelected,
                            isHovered: isHovered,
                            isPressed: isPressed
                        ),
                        lineWidth: 1
                    )
            )
    }
}

enum ChromeToolbarControlPalette {
    static func fillColor(isSelected: Bool, isHovered: Bool, isPressed: Bool = false) -> Color {
        if isSelected {
            return Color.accentColor.opacity(AppStyles.Shell.Chrome.ToolbarButton.selectedFillOpacity)
        }
        if isPressed {
            return Color.white.opacity(AppStyles.Shell.Chrome.ToolbarButton.pressedFillOpacity)
        }
        if isHovered {
            return Color.white.opacity(AppStyles.Shell.Chrome.ToolbarButton.hoverFillOpacity)
        }
        return Color.white.opacity(AppStyles.Shell.Chrome.ToolbarButton.baseFillOpacity)
    }

    static func strokeColor(isSelected: Bool, isHovered: Bool, isPressed: Bool = false) -> Color {
        if isSelected {
            return Color.accentColor.opacity(AppStyles.Shell.Chrome.ToolbarButton.selectedStrokeOpacity)
        }
        if isHovered || isPressed {
            return Color.white.opacity(AppStyles.Shell.Chrome.ToolbarButton.hoverStrokeOpacity)
        }
        return Color.white.opacity(AppStyles.Shell.Chrome.ToolbarButton.baseStrokeOpacity)
    }
}
