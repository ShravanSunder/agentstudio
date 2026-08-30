import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioCore

@MainActor
@Suite(.serialized)
final class WorkspaceStoreOrphanPoolTests {

    private var store: WorkspaceStore!

    init() {
        store = WorkspaceStore()
    }

    // MARK: - Helpers

    private func createTabWithPane() -> (Tab, Pane) {
        let pane = store.createPane()
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)
        return (tab, pane)
    }

    // MARK: - orphanedPanes query

    @Test

    func test_orphanedPanes_emptyByDefault() {
        _ = createTabWithPane()

        #expect(store.orphanedPanes.isEmpty)
    }

    @Test

    func test_orphanedPanes_excludesBackgroundedPanesRetainedInCanonicalLayouts() {
        let (_, pane1) = createTabWithPane()
        let (_, pane2) = createTabWithPane()

        store.backgroundPane(pane1.id)

        // Background residency defers rendering but retains the canonical tab
        // location, so this pane is not an orphan-pool candidate.
        #expect(store.tabContaining(paneId: pane1.id)?.id != nil)
        #expect(store.orphanedPanes.isEmpty)
        #expect(!(store.orphanedPanes.contains { $0.id == pane2.id }))
    }

    @Test

    func test_orphanedPanes_includesOrphanedResidency() {
        let pane = store.createPane()
        store.setResidency(.orphaned(reason: .worktreeNotFound(path: "/tmp/missing")), for: pane.id)

        #expect(store.orphanedPanes.contains { $0.id == pane.id })
    }

    // MARK: - backgroundPane

    @Test

    func test_backgroundPane_preservesCanonicalLayoutAndExcludesActiveProjection() {
        let pane1 = store.createPane()
        let pane2 = store.createPane()
        let tab = Tab(paneId: pane1.id)
        store.appendTab(tab)
        store.insertPane(
            pane2.id, inTab: tab.id, at: pane1.id,
            direction: .horizontal, position: .after, sizingMode: .halveTarget)

        store.backgroundPane(pane1.id)

        // Canonical layout retains pane1 so its location survives restart.
        let updatedTab = store.tab(tab.id)!
        #expect(updatedTab.panes.contains(pane1.id))
        #expect(updatedTab.panes.contains(pane2.id))

        // The active rendering projection, rather than the canonical graph,
        // excludes the deferred pane.
        let arrangementView = WorkspaceArrangementViewDerived(
            tabLayoutAtom: store.tabLayoutAtom,
            paneAtom: store.paneAtom,
            managementLayerAtom: ManagementLayerAtom()
        )
        #expect(arrangementView.activeVisiblePaneIds(forTab: tab.id) == [pane2.id])

        #expect((store.pane(pane1.id)) != nil)
        #expect(store.pane(pane1.id)!.residency == .backgrounded)
    }

    @Test

    func test_backgroundPane_lastPaneRetainsTabAndCanonicalLocation() {
        let (tab, pane) = createTabWithPane()

        store.backgroundPane(pane.id)

        #expect(store.tab(tab.id)?.panes == [pane.id])
        #expect((store.pane(pane.id)) != nil)
        #expect(store.pane(pane.id)!.residency == .backgrounded)
    }

    @Test

    func test_backgroundPane_preservesCanonicalActivePaneCursor() {
        let pane1 = store.createPane()
        let pane2 = store.createPane()
        let tab = Tab(paneId: pane1.id)
        store.appendTab(tab)
        store.insertPane(
            pane2.id, inTab: tab.id, at: pane1.id,
            direction: .horizontal, position: .after, sizingMode: .halveTarget)
        store.setActivePane(pane1.id, inTab: tab.id)

        store.backgroundPane(pane1.id)

        // The cursor is canonical state; rendering filters the backgrounded
        // pane rather than mutating the saved arrangement.
        #expect(store.tab(tab.id)!.activePaneId == pane1.id)
        let arrangementView = WorkspaceArrangementViewDerived(
            tabLayoutAtom: store.tabLayoutAtom,
            paneAtom: store.paneAtom,
            managementLayerAtom: ManagementLayerAtom()
        )
        #expect(arrangementView.activePaneId(forTab: tab.id) == nil)
        #expect(arrangementView.activeVisiblePaneIds(forTab: tab.id) == [pane2.id])
    }

    @Test

    func test_backgroundPane_marksDirty() async {
        let (_, pane) = createTabWithPane()
        _ = await store.flushAsync()
        store.backgroundPane(pane.id)

        #expect(store.isDirty)
    }

    // MARK: - reactivatePane

    @Test

    func test_reactivatePane_preservesRetainedLocationWithoutDuplicateInsertion() {
        let (tab, pane1) = createTabWithPane()
        let pane2 = store.createPane()
        store.insertPane(
            pane2.id, inTab: tab.id, at: pane1.id,
            direction: .horizontal, position: .after, sizingMode: .halveTarget)

        store.backgroundPane(pane2.id)
        #expect(store.tab(tab.id)?.panes == [pane1.id, pane2.id])
        #expect(store.orphanedPanes.isEmpty)

        store.reactivatePane(
            pane2.id, inTab: tab.id, at: pane1.id,
            direction: .horizontal, position: .after, sizingMode: .halveTarget
        )

        let updatedTab = store.tab(tab.id)!
        #expect(updatedTab.panes == [pane1.id, pane2.id])
        #expect(store.pane(pane2.id)!.residency == .active)
        #expect(store.orphanedPanes.isEmpty)
    }

    @Test

    func test_reactivatePane_nonBackgrounded_noOp() {
        let (tab, pane1) = createTabWithPane()
        let pane2 = store.createPane()
        store.insertPane(
            pane2.id, inTab: tab.id, at: pane1.id,
            direction: .horizontal, position: .after, sizingMode: .halveTarget)

        // pane2 is active, not backgrounded
        store.reactivatePane(
            pane2.id, inTab: tab.id, at: pane1.id,
            direction: .horizontal, position: .after, sizingMode: .halveTarget
        )

        // Should remain as-is (no duplicate insertion)
        #expect(store.pane(pane2.id)!.residency == .active)
    }

    // MARK: - purgeOrphanedPane

    @Test

    func test_purgeOrphanedPane_removesUnretainedOrphanedPaneFromStore() {
        let pane = store.createPane()
        store.setResidency(.orphaned(reason: .worktreeNotFound(path: "/tmp/missing")), for: pane.id)
        #expect((store.pane(pane.id)) != nil)

        store.purgeOrphanedPane(pane.id)

        #expect((store.pane(pane.id)) == nil)
        #expect(store.orphanedPanes.isEmpty)
    }

    @Test

    func test_purgeOrphanedPane_activePane_noOp() {
        let (_, pane) = createTabWithPane()

        store.purgeOrphanedPane(pane.id)

        // Should NOT remove an active pane
        #expect((store.pane(pane.id)) != nil)
    }

    // MARK: - Full lifecycle

    @Test

    func test_fullLifecycle_background_reactivate() {
        let pane1 = store.createPane()
        let pane2 = store.createPane()
        let tab = Tab(paneId: pane1.id)
        store.appendTab(tab)
        store.insertPane(
            pane2.id, inTab: tab.id, at: pane1.id,
            direction: .horizontal, position: .after, sizingMode: .halveTarget)

        // Background pane2 without removing its durable arrangement location.
        store.backgroundPane(pane2.id)
        #expect(store.orphanedPanes.isEmpty)
        #expect(store.tab(tab.id)!.panes == [pane1.id, pane2.id])

        // Reactivate pane2 back into the same tab
        store.reactivatePane(
            pane2.id, inTab: tab.id, at: pane1.id,
            direction: .horizontal, position: .after, sizingMode: .halveTarget
        )
        #expect(store.orphanedPanes.isEmpty)
        #expect(store.tab(tab.id)!.panes == [pane1.id, pane2.id])
        #expect(store.pane(pane2.id)!.residency == .active)
    }

    @Test

    func test_fullLifecycle_orphan_purge() {
        let pane = store.createPane()
        store.setResidency(.orphaned(reason: .worktreeNotFound(path: "/tmp/missing")), for: pane.id)

        #expect(store.orphanedPanes.map(\.id) == [pane.id])
        store.purgeOrphanedPane(pane.id)
        #expect((store.pane(pane.id)) == nil)
    }
}
