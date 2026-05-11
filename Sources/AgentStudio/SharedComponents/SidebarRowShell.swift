import SwiftUI

struct SidebarRowShell<Content: View>: View {
    let isSelected: Bool
    let isFlashing: Bool
    let isHovering: Bool
    let content: Content

    init(
        isSelected: Bool = false,
        isFlashing: Bool = false,
        isHovering: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.isSelected = isSelected
        self.isFlashing = isFlashing
        self.isHovering = isHovering
        self.content = content()
    }

    var body: some View {
        content
            .padding(.vertical, AppStyles.Shell.Sidebar.rowVerticalInset)
            .padding(.horizontal, AppStyles.Shell.Sidebar.rowHorizontalInset)
            .background(rowBackground)
            .contentShape(Rectangle())
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: AppStyles.Shell.Sidebar.rowCornerRadius)
            .fill(rowFill)
    }

    private var rowFill: Color {
        if isFlashing {
            return Color.accentColor.opacity(AppStyles.General.Fill.selected)
        }
        if isSelected {
            return Color.accentColor.opacity(AppStyles.General.Fill.active)
        }
        if isHovering {
            return Color.accentColor.opacity(AppStyles.Shell.Sidebar.rowHoverOpacity)
        }
        return Color.clear
    }
}
