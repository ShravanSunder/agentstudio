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

        #expect(idle.backgroundOpacity == AppStyles.General.Fill.subtle)
        #expect(hovered.backgroundOpacity == AppStyles.General.Fill.hover)
        #expect(pressed.backgroundOpacity == AppStyles.General.Fill.pressed)
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

        #expect(active.backgroundOpacity == AppStyles.General.Fill.active)
        #expect(activeHovered.backgroundOpacity == AppStyles.General.Fill.active)
        #expect(activePressed.backgroundOpacity == AppStyles.General.Fill.pressed)
        #expect(active.foregroundIsPrimary)
    }

    @Test
    func popoverAutoOpen_opensWhenRenameTargetsActiveTabArrangement() {
        let arrangementId = UUID()
        let arrangements = [
            ArrangementInfo(id: UUID(), name: "Default", isDefault: true, isActive: true),
            ArrangementInfo(id: arrangementId, name: "Layout 1", isDefault: false, isActive: false),
        ]

        #expect(
            ArrangementPopoverAutoOpen.shouldOpen(
                editingArrangementId: arrangementId,
                activeTabArrangements: arrangements,
                isPresented: false
            )
        )
    }

    @Test
    func popoverAutoOpen_doesNotOpenWhenEditingIdIsNil() {
        let arrangements = [
            ArrangementInfo(id: UUID(), name: "Default", isDefault: true, isActive: true)
        ]

        #expect(
            !ArrangementPopoverAutoOpen.shouldOpen(
                editingArrangementId: nil,
                activeTabArrangements: arrangements,
                isPresented: false
            )
        )
    }

    @Test
    func popoverAutoOpen_doesNotOpenWhenActiveTabIsMissing() {
        #expect(
            !ArrangementPopoverAutoOpen.shouldOpen(
                editingArrangementId: UUID(),
                activeTabArrangements: nil,
                isPresented: false
            )
        )
    }

    @Test
    func popoverAutoOpen_doesNotOpenWhenArrangementBelongsToDifferentTab() {
        let arrangements = [
            ArrangementInfo(id: UUID(), name: "Default", isDefault: true, isActive: true),
            ArrangementInfo(id: UUID(), name: "Layout 1", isDefault: false, isActive: false),
        ]

        #expect(
            !ArrangementPopoverAutoOpen.shouldOpen(
                editingArrangementId: UUID(),
                activeTabArrangements: arrangements,
                isPresented: false
            )
        )
    }

    @Test
    func popoverAutoOpen_doesNotReopenWhenAlreadyPresented() {
        let arrangementId = UUID()
        let arrangements = [
            ArrangementInfo(id: arrangementId, name: "Layout 1", isDefault: false, isActive: false)
        ]

        #expect(
            !ArrangementPopoverAutoOpen.shouldOpen(
                editingArrangementId: arrangementId,
                activeTabArrangements: arrangements,
                isPresented: true
            )
        )
    }

    @Test
    func chipAffordance_hidesPencilForDefaultArrangement() {
        #expect(!ArrangementChipAffordance.showsRenamePencil(isDefault: true))
    }

    @Test
    func chipAffordance_showsPencilForCustomArrangement() {
        #expect(ArrangementChipAffordance.showsRenamePencil(isDefault: false))
    }
}
