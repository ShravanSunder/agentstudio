import AgentStudioInfrastructure
import Testing

@testable import AgentStudioSharedComponents

struct PopoverPanelTests {
    @Test
    func inactiveOptionsUseHoverAndPressedFills() {
        let idle = PopoverOptionVisualStyle(
            isSelected: false,
            isHighlighted: false,
            isPressed: false
        )
        let hovered = PopoverOptionVisualStyle(
            isSelected: false,
            isHighlighted: true,
            isPressed: false
        )
        let pressed = PopoverOptionVisualStyle(
            isSelected: false,
            isHighlighted: true,
            isPressed: true
        )

        #expect(idle.backgroundOpacity == AppStyles.General.Fill.subtle)
        #expect(hovered.backgroundOpacity == AppStyles.General.Fill.hover)
        #expect(pressed.backgroundOpacity == AppStyles.General.Fill.pressed)
    }

    @Test
    func selectedOptionsKeepActiveFillUntilPressed() {
        let active = PopoverOptionVisualStyle(
            isSelected: true,
            isHighlighted: false,
            isPressed: false
        )
        let activeHovered = PopoverOptionVisualStyle(
            isSelected: true,
            isHighlighted: true,
            isPressed: false
        )
        let activePressed = PopoverOptionVisualStyle(
            isSelected: true,
            isHighlighted: true,
            isPressed: true
        )

        #expect(active.backgroundOpacity == AppStyles.General.Fill.active)
        #expect(activeHovered.backgroundOpacity == AppStyles.General.Fill.active)
        #expect(activePressed.backgroundOpacity == AppStyles.General.Fill.pressed)
        #expect(active.foregroundIsPrimary)
    }

}
