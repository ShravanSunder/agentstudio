import AgentStudioInfrastructure
import SwiftUI

/// Decorative shortcut text supplied by the owning command or local action descriptor.
package struct SidebarShortcutHint: View {
    private let displayText: ShortcutDisplayText

    package init(_ displayText: ShortcutDisplayText) {
        self.displayText = displayText
    }

    package var body: some View {
        Text(displayText.value)
            .lineLimit(1)
            .font(.system(size: AppStyles.Shell.Sidebar.KeyboardHint.fontSize, weight: .medium, design: .monospaced))
            .foregroundStyle(.primary)
            .padding(.horizontal, AppStyles.Shell.Sidebar.KeyboardHint.horizontalPadding)
            .frame(
                minWidth: AppStyles.Shell.Sidebar.KeyboardHint.minimumWidth,
                minHeight: AppStyles.Shell.Sidebar.KeyboardHint.height
            )
            .fixedSize()
            .background(
                RoundedRectangle(cornerRadius: AppStyles.Shell.Sidebar.KeyboardHint.cornerRadius)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppStyles.Shell.Sidebar.KeyboardHint.cornerRadius)
                    .strokeBorder(
                        AppStyles.General.Stroke.controlGroupColor,
                        lineWidth: AppStyles.Shell.Sidebar.KeyboardHint.borderWidth
                    )
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

extension View {
    package func sidebarShortcutHint(_ displayText: ShortcutDisplayText?) -> some View {
        overlay {
            if let displayText {
                SidebarShortcutHint(displayText)
            }
        }
    }
}
