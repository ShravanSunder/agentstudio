import SwiftUI

struct SidebarRowShell<Content: View>: View {
    let isSelected: Bool
    let isFlashing: Bool
    let isHovered: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: AppStyles.General.CornerRadius.bar)
                    .fill(backgroundColor)
                    .padding(.horizontal, AppStyles.General.Spacing.tight / 2)
            }
            .contentShape(Rectangle())
            .animation(.easeOut(duration: AppStyles.General.Animation.standard), value: isFlashing)
            .animation(.easeOut(duration: AppStyles.General.Animation.fast), value: isHovered)
            .animation(.easeOut(duration: AppStyles.General.Animation.fast), value: isSelected)
    }

    private var backgroundColor: Color {
        Self.backgroundColor(isSelected: isSelected, isFlashing: isFlashing, isHovered: isHovered)
    }

    static func backgroundColor(
        isSelected: Bool,
        isFlashing: Bool,
        isHovered: Bool
    ) -> Color {
        if isFlashing || isSelected {
            return Color.accentColor.opacity(AppStyles.Shell.Sidebar.rowSelectedOpacity)
        }
        if isHovered {
            return Color.accentColor.opacity(AppStyles.Shell.Sidebar.rowHoverOpacity)
        }
        return .clear
    }
}
