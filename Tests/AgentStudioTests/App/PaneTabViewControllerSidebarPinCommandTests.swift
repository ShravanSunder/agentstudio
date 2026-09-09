import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioTestSupport

@MainActor
@Suite(.serialized)
struct PaneTabViewControllerSidebarPinCommandTests {
    init() {
        installTestCoreAtomsIfNeeded()
    }

    @Test("targeted repository pin commands mutate only repository pin state")
    func targetedRepositoryPinCommandsMutateOnlyRepositoryPinState() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let (repo, _) = makeRepoAndWorktree(harness.store, root: harness.tempDir)
        let pane = harness.store.createPane()
        harness.store.appendTab(Tab(paneId: pane.id))

        harness.controller.execute(.pinRepo, target: repo.id, targetType: .repo)

        #expect(harness.store.repositoryTopologyAtom.repo(repo.id)?.isPinned == true)
        #expect(harness.store.paneAtom.pane(pane.id)?.metadata.isPinned == false)

        harness.controller.execute(.unpinRepo, target: repo.id, targetType: .repo)

        #expect(harness.store.repositoryTopologyAtom.repo(repo.id)?.isPinned == false)
        #expect(harness.store.paneAtom.pane(pane.id)?.metadata.isPinned == false)
    }

    @Test("targeted pane pin commands mutate only the selected pane")
    func targetedPanePinCommandsMutateOnlySelectedPane() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let firstPane = harness.store.createPane()
        let secondPane = harness.store.createPane()
        let tab = Tab(paneId: firstPane.id)
        harness.store.appendTab(tab)
        harness.store.insertPane(
            secondPane.id,
            inTab: tab.id,
            at: firstPane.id,
            direction: .horizontal,
            position: .after,
            sizingMode: .halveTarget
        )

        harness.controller.execute(.pinPane, target: secondPane.id, targetType: .pane)

        #expect(harness.store.paneAtom.pane(firstPane.id)?.metadata.isPinned == false)
        #expect(harness.store.paneAtom.pane(secondPane.id)?.metadata.isPinned == true)

        harness.controller.execute(.unpinPane, target: secondPane.id, targetType: .pane)

        #expect(harness.store.paneAtom.pane(secondPane.id)?.metadata.isPinned == false)
    }

    @Test("pin commands reject the wrong target kind")
    func pinCommandsRejectWrongTargetKind() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let (repo, _) = makeRepoAndWorktree(harness.store, root: harness.tempDir)
        let pane = harness.store.createPane()
        harness.store.appendTab(Tab(paneId: pane.id))

        #expect(!harness.controller.canExecute(.pinRepo, target: pane.id, targetType: .pane))
        #expect(!harness.controller.canExecute(.pinPane, target: repo.id, targetType: .repo))
    }
}
