import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioInfrastructure

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

    @Test("targeted focusPane selects the exact non-current pane")
    func executeFocusPaneSelectsExactNonCurrentPane() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let firstPane = harness.store.createPane()
        let destinationActivePane = harness.store.createPane()
        let targetPane = harness.store.createPane()
        let firstTab = Tab(paneId: firstPane.id)
        let secondTab = Tab(paneId: destinationActivePane.id)
        harness.store.appendTab(firstTab)
        harness.store.appendTab(secondTab)
        harness.store.insertPane(
            targetPane.id,
            inTab: secondTab.id,
            at: destinationActivePane.id,
            direction: .horizontal,
            position: .after,
            sizingMode: .halveTarget
        )
        harness.store.setActivePane(destinationActivePane.id, inTab: secondTab.id)
        harness.store.setActiveTab(firstTab.id)

        #expect(harness.store.tab(secondTab.id)?.activePaneId == destinationActivePane.id)

        harness.controller.execute(.focusPane, target: targetPane.id, targetType: .pane)

        #expect(harness.store.activeTabId == secondTab.id)
        #expect(harness.store.tab(secondTab.id)?.activePaneId == targetPane.id)
    }

    @Test("targeted focusPane rejects a stale pane without changing selection")
    func executeFocusPaneRejectsStalePaneWithoutFallback() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let pane = harness.store.createPane()
        let tab = Tab(paneId: pane.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        let stalePaneId = UUIDv7.generate()
        let tabCountBeforeFocus = harness.store.tabs.count
        let paneCountBeforeFocus = harness.store.paneAtom.panes.count

        #expect(!harness.controller.canExecute(.focusPane, target: stalePaneId, targetType: .pane))
        harness.controller.execute(.focusPane, target: stalePaneId, targetType: .pane)

        #expect(harness.store.activeTabId == tab.id)
        #expect(harness.store.tab(tab.id)?.activePaneId == pane.id)
        #expect(harness.store.tabs.count == tabCountBeforeFocus)
        #expect(harness.store.paneAtom.panes.count == paneCountBeforeFocus)
    }
}
