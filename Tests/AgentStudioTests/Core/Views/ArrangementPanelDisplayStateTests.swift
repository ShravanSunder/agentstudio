import Foundation
import Testing

@testable import AgentStudio

struct ArrangementPanelDisplayStateTests {
    @Test
    func singleVisiblePane_stillShowsArrangementControls() {
        let state = ArrangementPanelDisplayState(
            visiblePanes: [
                PaneVisibilityInfo(id: UUID(), title: "Terminal", isMinimized: false)
            ],
            arrangements: [
                ArrangementInfo(id: UUID(), name: "Default", isDefault: true, isActive: true)
            ],
            allowsMinimizedBarToggle: true
        )

        #expect(state.showsSaveArrangementButton)
        #expect(state.showsPaneVisibilitySection)
        #expect(state.showsMinimizedBarToggle)
    }

    @Test
    func noVisiblePanes_hidesPaneSpecificSections() {
        let state = ArrangementPanelDisplayState(
            visiblePanes: [],
            arrangements: [
                ArrangementInfo(id: UUID(), name: "Default", isDefault: true, isActive: true)
            ],
            allowsMinimizedBarToggle: true
        )

        #expect(!state.showsSaveArrangementButton)
        #expect(!state.showsPaneVisibilitySection)
        #expect(!state.showsMinimizedBarToggle)
    }

    @Test
    func toggleFlag_canHideMinimizedBarToggleWithoutHidingPaneVisibility() {
        let state = ArrangementPanelDisplayState(
            visiblePanes: [
                PaneVisibilityInfo(id: UUID(), title: "Terminal", isMinimized: false)
            ],
            arrangements: [
                ArrangementInfo(id: UUID(), name: "Default", isDefault: true, isActive: true)
            ],
            allowsMinimizedBarToggle: false
        )

        #expect(state.showsSaveArrangementButton)
        #expect(state.showsPaneVisibilitySection)
        #expect(!state.showsMinimizedBarToggle)
    }

    @Test
    func chipVisualStyle_inactiveChip_usesHoverAndPressedFills() {
        let idle = ArrangementChipVisualStyle(
            isActive: false,
            isHovered: false,
            isPressed: false
        )
        let hovered = ArrangementChipVisualStyle(
            isActive: false,
            isHovered: true,
            isPressed: false
        )
        let pressed = ArrangementChipVisualStyle(
            isActive: false,
            isHovered: true,
            isPressed: true
        )

        #expect(idle.backgroundOpacity == AppStyle.fillSubtle)
        #expect(hovered.backgroundOpacity == AppStyle.fillHover)
        #expect(pressed.backgroundOpacity == AppStyle.fillPressed)
    }

    @Test
    func chipVisualStyle_activeChip_keepsActiveFillUntilPressed() {
        let active = ArrangementChipVisualStyle(
            isActive: true,
            isHovered: false,
            isPressed: false
        )
        let activeHovered = ArrangementChipVisualStyle(
            isActive: true,
            isHovered: true,
            isPressed: false
        )
        let activePressed = ArrangementChipVisualStyle(
            isActive: true,
            isHovered: true,
            isPressed: true
        )

        #expect(active.backgroundOpacity == AppStyle.fillActive)
        #expect(activeHovered.backgroundOpacity == AppStyle.fillActive)
        #expect(activePressed.backgroundOpacity == AppStyle.fillPressed)
        #expect(active.foregroundIsPrimary)
    }
}
