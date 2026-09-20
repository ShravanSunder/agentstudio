import AgentStudioInfrastructure
import SwiftUI

/// Decorative shortcut text supplied by the owning command or local action descriptor.
package struct SidebarShortcutHint: View {
    package enum Style: Equatable {
        case keycap
        case accentGlyph
        case toolbarStamp
    }

    private let displayText: ShortcutDisplayText
    private let style: Style

    package init(_ displayText: ShortcutDisplayText, style: Style = .keycap) {
        self.displayText = displayText
        self.style = style
    }

    package var body: some View {
        Text(displayText.value)
            .lineLimit(1)
            .font(
                .system(
                    size: style == .toolbarStamp
                        ? AppStyles.Shell.Sidebar.KeyboardHint.stampFontSize
                        : AppStyles.Shell.Sidebar.KeyboardHint.fontSize,
                    weight: style == .toolbarStamp
                        ? AppStyles.Shell.Sidebar.KeyboardHint.stampFontWeight
                        : .medium,
                    design: .monospaced
                )
            )
            .foregroundStyle(style == .accentGlyph ? Color.accentColor : Color.primary)
            .padding(.horizontal, AppStyles.Shell.Sidebar.KeyboardHint.horizontalPadding)
            .frame(
                minWidth: AppStyles.Shell.Sidebar.KeyboardHint.minimumWidth,
                minHeight: AppStyles.Shell.Sidebar.KeyboardHint.height
            )
            .fixedSize()
            .background(
                RoundedRectangle(cornerRadius: AppStyles.Shell.Sidebar.KeyboardHint.cornerRadius)
                    .fill(style == .accentGlyph ? Color.clear : Color(nsColor: .controlBackgroundColor))
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppStyles.Shell.Sidebar.KeyboardHint.cornerRadius)
                    .strokeBorder(
                        style == .accentGlyph ? Color.clear : AppStyles.General.Stroke.controlGroupColor,
                        lineWidth: style == .accentGlyph ? 0 : AppStyles.Shell.Sidebar.KeyboardHint.borderWidth
                    )
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

extension View {
    package func sidebarShortcutHint(
        _ displayText: ShortcutDisplayText?,
        style: SidebarShortcutHint.Style = .keycap
    ) -> some View {
        overlay {
            if let displayText {
                SidebarShortcutHint(displayText, style: style)
            }
        }
    }
}
