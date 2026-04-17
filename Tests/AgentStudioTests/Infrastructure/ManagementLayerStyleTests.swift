import Testing

@testable import AgentStudio

@Suite
struct ManagementLayerStyleTests {
    @Test
    func backgroundOpacity_rest_returnsControlFill() {
        let result = AppStyle.managementLayerBackgroundOpacity(isHovered: false)
        #expect(result == AppStyle.managementLayerControlFill)
    }

    @Test
    func backgroundOpacity_hovered_appliesDelta() {
        let result = AppStyle.managementLayerBackgroundOpacity(isHovered: true)
        let expected = AppStyle.managementLayerControlFill + AppStyle.managementLayerControlHoverDelta
        #expect(abs(result - expected) < 0.001)
    }

    @Test
    func backgroundOpacity_hovered_isLighterThanRest() {
        let rest = AppStyle.managementLayerBackgroundOpacity(isHovered: false)
        let hovered = AppStyle.managementLayerBackgroundOpacity(isHovered: true)
        #expect(hovered < rest)
    }

    @Test
    func iconOpacity_rest_isMuted() {
        let result = AppStyle.managementLayerIconOpacity(isHovered: false)
        #expect(result == AppStyle.foregroundMuted)
    }

    @Test
    func iconOpacity_hovered_isFullWhite() {
        let result = AppStyle.managementLayerIconOpacity(isHovered: true)
        #expect(result == 1.0)
    }

    @Test
    func iconOpacity_hovered_isBrighterThanRest() {
        let rest = AppStyle.managementLayerIconOpacity(isHovered: false)
        let hovered = AppStyle.managementLayerIconOpacity(isHovered: true)
        #expect(hovered > rest)
    }

    @Test
    func controlFill_isDarkerThanDimmingOverlay() {
        #expect(AppStyle.managementLayerControlFill > AppStyle.managementLayerDimming)
    }
}
