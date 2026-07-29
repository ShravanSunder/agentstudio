import Testing

@testable import AgentStudio

@Suite
struct PaneManagementTrailingControlTests {
    @Test("main panes use Move to Tab while drawer panes retain Detach")
    func paneManagementTrailingControlMatchesPaneResidency() {
        #expect(PaneManagementTrailingControl.resolve(isDrawerChild: false) == .movePaneToTab)
        #expect(PaneManagementTrailingControl.resolve(isDrawerChild: true) == .detachDrawerPane)
    }
}
