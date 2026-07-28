import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore

@MainActor
@Suite(.serialized)
struct PaneTabViewControllerTargetedFocusCommandTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    @Test("targeted focusPane is available for an existing main pane")
    func canExecuteFocusPane_targetedMainPane() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let firstPane = harness.store.createPane()
        let secondPane = harness.store.createPane()
        let firstTab = Tab(paneId: firstPane.id)
        let secondTab = Tab(paneId: secondPane.id)
        harness.store.appendTab(firstTab)
        harness.store.appendTab(secondTab)
        harness.store.setActiveTab(firstTab.id)

        #expect(
            harness.controller.canExecute(
                .focusPane,
                target: secondPane.id,
                targetType: .floatingTerminal
            )
        )
    }
}
