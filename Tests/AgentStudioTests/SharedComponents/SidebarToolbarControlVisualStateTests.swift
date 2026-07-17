import Testing

@testable import AgentStudio

@Suite("Sidebar toolbar control visual state")
struct SidebarToolbarControlVisualStateTests {
    @Test("interaction state precedence is disabled pressed open active hovered idle")
    func interactionStatePrecedence() {
        #expect(resolve(isEnabled: false, isHovered: true, isPressed: true, isActive: true, isOpen: true) == .disabled)
        #expect(resolve(isHovered: true, isPressed: true, isActive: true, isOpen: true) == .pressed)
        #expect(resolve(isHovered: true, isActive: true, isOpen: true) == .open)
        #expect(resolve(isHovered: true, isActive: true) == .active)
        #expect(resolve(isHovered: true) == .hovered)
        #expect(resolve() == .idle)
    }

    @Test("visible interaction states paint stronger fills than idle")
    func visibleInteractionStatesPaintFills() {
        #expect(SidebarToolbarControlVisualState.idle.fillOpacity == 0)
        #expect(SidebarToolbarControlVisualState.hovered.fillOpacity > 0)
        #expect(
            SidebarToolbarControlVisualState.pressed.fillOpacity
                > SidebarToolbarControlVisualState.hovered.fillOpacity
        )
        #expect(
            SidebarToolbarControlVisualState.open.fillOpacity
                >= SidebarToolbarControlVisualState.pressed.fillOpacity
        )
    }

    private func resolve(
        isEnabled: Bool = true,
        isHovered: Bool = false,
        isPressed: Bool = false,
        isActive: Bool = false,
        isOpen: Bool = false
    ) -> SidebarToolbarControlVisualState {
        SidebarToolbarControlVisualState.resolve(
            isEnabled: isEnabled,
            isHovered: isHovered,
            isPressed: isPressed,
            isActive: isActive,
            isOpen: isOpen
        )
    }
}
