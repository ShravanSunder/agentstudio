import SwiftUI
import Testing

@testable import AgentStudio

@Suite("SidebarRowShell")
struct SidebarRowShellTests {
    @Test("hover fill matches RepoExplorer accent hover policy")
    @MainActor
    func hoverFillMatchesRepoExplorerAccentHoverPolicy() {
        let hoverFill = SidebarRowShell<Text>.backgroundColor(
            isSelected: false,
            isFlashing: false,
            isHovered: true
        )

        #expect(hoverFill == Color.accentColor.opacity(AppStyles.Shell.Sidebar.rowHoverOpacity))
    }
}
