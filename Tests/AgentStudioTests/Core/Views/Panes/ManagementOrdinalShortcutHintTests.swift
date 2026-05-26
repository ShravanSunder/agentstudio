import Testing

@testable import AgentStudio

struct ManagementOrdinalShortcutHintTests {
    @Test("pane overlay ordinal keeps management-control chrome")
    func paneOverlayOrdinalKeepsManagementControlChrome() {
        let style = ManagementOrdinalShortcutHintStyle.resolve(variant: .paneOverlay)

        #expect(style.foreground == .white(opacity: AppStyles.Shell.ManagementLayer.iconOpacity(isHovered: false)))
        #expect(
            style.background == .black(opacity: AppStyles.Shell.ManagementLayer.backgroundOpacity(isHovered: false)))
    }

    @Test("collapsed bar ordinal uses minimized-bar chrome")
    func collapsedBarOrdinalUsesMinimizedBarChrome() {
        let style = ManagementOrdinalShortcutHintStyle.resolve(variant: .collapsedBar)

        #expect(
            style.foreground
                == .secondary(opacity: AppStyles.Shell.ManagementLayer.collapsedBarOrdinalForegroundOpacity))
        #expect(style.background == .white(opacity: AppStyles.General.Fill.muted))
    }
}
