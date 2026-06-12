import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("PaneTabViewController terminal geometry")
struct PaneTabViewControllerTerminalGeometryTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    @Test("visible terminal geometry includes expanded non-minimized drawer children")
    func visibleTerminalPaneIdsForActiveTab_includesExpandedDrawerChildren() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let parentPane = harness.store.createPane()
        let tab = Tab(paneId: parentPane.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        harness.store.setActivePane(parentPane.id, inTab: tab.id)

        let firstDrawerPane = try #require(harness.store.addDrawerPane(to: parentPane.id))
        let secondDrawerPane = try #require(harness.store.addDrawerPane(to: parentPane.id))
        #expect(harness.store.minimizeDrawerPane(secondDrawerPane.id, in: parentPane.id) == true)

        #expect(harness.controller.visibleTerminalPaneIdsForActiveTab() == [parentPane.id, firstDrawerPane.id])
    }
}
