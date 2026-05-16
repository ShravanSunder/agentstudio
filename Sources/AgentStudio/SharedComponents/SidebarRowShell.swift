import SwiftUI

struct SidebarRowShell<Content: View>: View {
    let isSelected: Bool
    let isFlashing: Bool
    let isHovering: Bool
    let content: Content

    static var chromePolicy: SidebarRowChromePolicy {
        .sidebarRowShell
    }

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
            .padding(.vertical, Self.contentVerticalInset)
            .padding(.horizontal, Self.contentHorizontalInset)
            .background(rowBackground)
            .contentShape(Rectangle())
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: Self.rowCornerRadius)
            .fill(rowFill)
    }

    private var rowFill: Color {
        Self.backgroundColor(
            isSelected: isSelected,
            isFlashing: isFlashing,
            isHovering: isHovering
        )
    }

    static func backgroundColor(
        isSelected: Bool,
        isFlashing: Bool,
        isHovering: Bool
    ) -> Color {
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

    static var contentVerticalInset: CGFloat {
        AppStyles.Shell.Sidebar.rowVerticalInset
    }

    static var contentHorizontalInset: CGFloat {
        AppStyles.Shell.Sidebar.rowHorizontalInset
    }

    static var rowCornerRadius: CGFloat {
        AppStyles.Shell.Sidebar.rowCornerRadius
    }
}
