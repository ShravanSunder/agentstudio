import AgentStudioInfrastructure
import SwiftUI

package struct ChromeToolbarButtonLabel: View {
    let symbolName: String
    var selectedSymbolName: String?
    var isSelected = false
    var isHovered = false
    var badgeText: String?
    var buttonSize = AppStyles.Shell.Chrome.ToolbarButton.size
    var showsBackground = true

    package init(
        symbolName: String,
        selectedSymbolName: String? = nil,
        isSelected: Bool = false,
        isHovered: Bool = false,
        badgeText: String? = nil,
        buttonSize: CGFloat = AppStyles.Shell.Chrome.ToolbarButton.size,
        showsBackground: Bool = true
    ) {
        self.symbolName = symbolName
        self.selectedSymbolName = selectedSymbolName
        self.isSelected = isSelected
        self.isHovered = isHovered
        self.badgeText = badgeText
        self.buttonSize = buttonSize
        self.showsBackground = showsBackground
    }

    private var resolvedSymbolName: String {
        if isSelected, let selectedSymbolName {
            return selectedSymbolName
        }
        return symbolName
    }

    private var foregroundStyle: Color {
        if showsBackground {
            return ChromeToolbarControlPalette.foregroundColor(isSelected: isSelected, isHovered: isHovered)
        }
        if isSelected {
            return AppStyles.General.Accent.primaryColor
        }
        return isHovered ? .primary : .secondary
    }

    package var body: some View {
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

package struct ChromeToolbarCapsuleBackground: View {
    var isSelected = false
    var isHovered = false
    var isPressed = false

    package init(
        isSelected: Bool = false,
        isHovered: Bool = false,
        isPressed: Bool = false
    ) {
        self.isSelected = isSelected
        self.isHovered = isHovered
        self.isPressed = isPressed
    }

    package var body: some View {
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

package enum ChromeToolbarControlPalette {
    package static func foregroundColor(isSelected: Bool, isHovered: Bool) -> Color {
        if isSelected {
            return AppStyles.General.Accent.primaryColor
        }
        if isHovered {
            return AppStyles.Shell.Chrome.ToolbarButton.hoverIconForegroundColor
        }
        return AppStyles.Shell.Chrome.ToolbarButton.iconForegroundColor
    }

    package static func fillColor(isSelected: Bool, isHovered: Bool, isPressed: Bool = false) -> Color {
        if isSelected {
            return AppStyles.General.Accent.primaryColor.opacity(
                AppStyles.Shell.Chrome.ToolbarButton.selectedFillOpacity)
        }
        if isPressed {
            return AppStyles.Shell.Chrome.ToolbarButton.pressedFillColor
        }
        if isHovered {
            return AppStyles.Shell.Chrome.ToolbarButton.hoverFillColor
        }
        return AppStyles.Shell.Chrome.ToolbarButton.baseFillColor
    }

    package static func strokeColor(isSelected: Bool, isHovered: Bool, isPressed: Bool = false) -> Color {
        if isSelected {
            return AppStyles.General.Accent.primaryColor.opacity(
                AppStyles.Shell.Chrome.ToolbarButton.selectedStrokeOpacity)
        }
        if isPressed {
            return AppStyles.Shell.Chrome.ToolbarButton.pressedStrokeColor
                .opacity(AppStyles.Shell.Chrome.ToolbarButton.pressedStrokeOpacity)
        }
        if isHovered {
            return AppStyles.Shell.Chrome.ToolbarButton.hoverStrokeColor
                .opacity(AppStyles.Shell.Chrome.ToolbarButton.hoverStrokeOpacity)
        }
        return Color.white.opacity(AppStyles.Shell.Chrome.ToolbarButton.baseStrokeOpacity)
    }
}
