import Testing

@testable import AgentStudio

@Suite
struct PaneMoveDestinationPresentationTests {
    @Test("short destination titles remain unchanged")
    func shortDestinationTitlesRemainUnchanged() {
        #expect(
            PaneMoveDestinationPresentation.title(
                tabOrdinal: 2,
                tabTitle: "Composition"
            ) == "Tab 2: Composition"
        )
    }

    @Test("long destination titles are middle-truncated to the menu width budget")
    func longDestinationTitlesAreMiddleTruncated() {
        let title = PaneMoveDestinationPresentation.title(
            tabOrdinal: 2,
            tabTitle:
                "agent-studio.composition | composition | agent-studio.composition"
        )

        #expect(title.count <= PaneMoveDestinationPresentation.maximumCharacterCount)
        #expect(title.hasPrefix("Tab 2: agent-studio"))
        #expect(title.contains("…"))
        #expect(title.hasSuffix("agent-studio.composition"))
    }

    @Test("Move Pane to Tab uses the selected move icon")
    func movePaneToTabUsesSelectedMoveIcon() {
        #expect(
            AppCommand.movePaneToTab.definition.icon
                == .system(.arrowLeftArrowRight)
        )
    }

    @Test("main panes use Move to Tab while drawer panes retain Detach")
    func paneManagementTrailingControlMatchesPaneResidency() {
        #expect(PaneManagementTrailingControl.resolve(isDrawerChild: false) == .movePaneToTab)
        #expect(PaneManagementTrailingControl.resolve(isDrawerChild: true) == .detachDrawerPane)
    }
}
