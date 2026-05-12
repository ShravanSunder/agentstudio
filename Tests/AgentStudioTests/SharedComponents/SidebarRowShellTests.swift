import SwiftUI
import Testing

@testable import AgentStudio

@Suite("SidebarRowShell")
struct SidebarRowShellTests {
    @Test("row shell builds with selected hover and flashing states")
    @MainActor
    func rowShellBuildsWithAllVisualStates() {
        let normal = SidebarRowShell(isSelected: false, isFlashing: false, isHovered: false) {
            Text("Normal")
        }
        let selected = SidebarRowShell(isSelected: true, isFlashing: false, isHovered: false) {
            Text("Selected")
        }
        let flashing = SidebarRowShell(isSelected: false, isFlashing: true, isHovered: false) {
            Text("Flashing")
        }

        #expect(String(describing: type(of: normal)).contains("SidebarRowShell"))
        #expect(String(describing: type(of: selected)).contains("SidebarRowShell"))
        #expect(String(describing: type(of: flashing)).contains("SidebarRowShell"))
    }

    @Test("selected and flashing fill use sidebar selected token")
    @MainActor
    func selectedAndFlashingFillUseSidebarSelectedToken() {
        let selectedFill = SidebarRowShell<Text>.backgroundColor(
            isSelected: true,
            isFlashing: false,
            isHovered: false
        )
        let flashingFill = SidebarRowShell<Text>.backgroundColor(
            isSelected: false,
            isFlashing: true,
            isHovered: false
        )

        #expect(selectedFill == Color.accentColor.opacity(AppStyles.Shell.Sidebar.rowSelectedOpacity))
        #expect(flashingFill == Color.accentColor.opacity(AppStyles.Shell.Sidebar.rowSelectedOpacity))
    }

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
