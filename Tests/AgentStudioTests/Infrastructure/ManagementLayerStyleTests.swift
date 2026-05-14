import Testing

@testable import AgentStudio

@Suite
struct ManagementLayerStyleTests {
    @Test
    func backgroundOpacity_rest_returnsControlFill() {
        let result = AppStyles.Shell.ManagementLayer.backgroundOpacity(isHovered: false)
        #expect(result == AppStyles.Shell.ManagementLayer.controlFillOpacity)
    }

    @Test
    func backgroundOpacity_hovered_appliesDelta() {
        let result = AppStyles.Shell.ManagementLayer.backgroundOpacity(isHovered: true)
        let expected =
            AppStyles.Shell.ManagementLayer.controlFillOpacity
            + AppStyles.Shell.ManagementLayer.controlHoverDelta
        #expect(abs(result - expected) < 0.001)
    }

    @Test
    func backgroundOpacity_hovered_isLighterThanRest() {
        let rest = AppStyles.Shell.ManagementLayer.backgroundOpacity(isHovered: false)
        let hovered = AppStyles.Shell.ManagementLayer.backgroundOpacity(isHovered: true)
        #expect(hovered < rest)
    }

    @Test
    func iconOpacity_rest_isMuted() {
        let result = AppStyles.Shell.ManagementLayer.iconOpacity(isHovered: false)
        #expect(result == AppStyles.General.Foreground.muted)
    }

    @Test
    func iconOpacity_hovered_isFullWhite() {
        let result = AppStyles.Shell.ManagementLayer.iconOpacity(isHovered: true)
        #expect(result == 1.0)
    }

    @Test
    func iconOpacity_hovered_isBrighterThanRest() {
        let rest = AppStyles.Shell.ManagementLayer.iconOpacity(isHovered: false)
        let hovered = AppStyles.Shell.ManagementLayer.iconOpacity(isHovered: true)
        #expect(hovered > rest)
    }

    @Test
    func controlFill_isDarkerThanDimmingOverlay() {
        #expect(AppStyles.Shell.ManagementLayer.controlFillOpacity > AppStyles.Shell.ManagementLayer.modeDimmingOpacity)
    }
}
