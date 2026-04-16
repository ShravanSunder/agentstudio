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
}
