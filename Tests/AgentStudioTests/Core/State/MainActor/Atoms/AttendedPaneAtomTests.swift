import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("AttendedPaneAtom")
struct AttendedPaneAtomTests {
    private func makeWindowKey(_ atom: WindowLifecycleAtom) {
        let id = UUID()
        atom.recordWindowRegistered(id)
        atom.recordWindowBecameKey(id)
    }

    private func makeTabLayout(
        activePaneId: UUID?,
        allPaneIds: [UUID]? = nil
    ) -> (WorkspaceTabLayoutAtom, UUID) {
        let tabLayout = WorkspaceTabLayoutAtom()
        let paneIds = allPaneIds ?? activePaneId.map { [$0] } ?? []
        let layoutPaneId = activePaneId ?? paneIds.first ?? UUID()
        let arrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout.autoTiled(paneIds.isEmpty ? [layoutPaneId] : paneIds)
        )
        let tab = Tab(
            name: "Tab",
            panes: paneIds,
            arrangements: [arrangement],
            activeArrangementId: arrangement.id,
            activePaneId: activePaneId
        )
        tabLayout.appendTab(tab)
        tabLayout.setActiveTab(tab.id)
        return (tabLayout, tab.id)
    }

    @Test("returns active pane when workspace window is key and management is inactive")
    func attendedPaneWhenAllInputsSatisfied() {
        let paneId = UUID()
        let (tabLayout, _) = makeTabLayout(activePaneId: paneId)
        let windowLifecycle = WindowLifecycleAtom()
        let managementLayer = ManagementLayerAtom()
        makeWindowKey(windowLifecycle)

        let atom = AttendedPaneAtom(
            tabLayout: tabLayout,
            windowLifecycle: windowLifecycle,
            managementLayer: managementLayer
        )

        #expect(atom.attendedPaneId == paneId)
        atom.stop()
    }

    @Test("returns nil when workspace window is not key")
    func nilWhenWorkspaceWindowNotKey() {
        let paneId = UUID()
        let (tabLayout, _) = makeTabLayout(activePaneId: paneId)
        let atom = AttendedPaneAtom(
            tabLayout: tabLayout,
            windowLifecycle: WindowLifecycleAtom(),
            managementLayer: ManagementLayerAtom()
        )

        #expect(atom.attendedPaneId == nil)
        atom.stop()
    }

    @Test("returns nil when management layer is active")
    func nilWhenManagementLayerActive() {
        let paneId = UUID()
        let (tabLayout, _) = makeTabLayout(activePaneId: paneId)
        let windowLifecycle = WindowLifecycleAtom()
        let managementLayer = ManagementLayerAtom()
        makeWindowKey(windowLifecycle)
        managementLayer.activate()

        let atom = AttendedPaneAtom(
            tabLayout: tabLayout,
            windowLifecycle: windowLifecycle,
            managementLayer: managementLayer
        )

        #expect(atom.attendedPaneId == nil)
        atom.stop()
    }

    @Test("returns nil when there is no active pane")
    func nilWhenNoActivePane() {
        let (tabLayout, _) = makeTabLayout(activePaneId: nil)
        let windowLifecycle = WindowLifecycleAtom()
        makeWindowKey(windowLifecycle)

        let atom = AttendedPaneAtom(
            tabLayout: tabLayout,
            windowLifecycle: windowLifecycle,
            managementLayer: ManagementLayerAtom()
        )

        #expect(atom.attendedPaneId == nil)
        atom.stop()
    }

    @Test("transition stream emits gained and cleared attended pane ids")
    func transitionStreamEmitsOnInputChanges() async {
        let paneA = UUID()
        let paneB = UUID()
        let (tabLayout, tabId) = makeTabLayout(activePaneId: paneA, allPaneIds: [paneA, paneB])
        let windowLifecycle = WindowLifecycleAtom()
        let managementLayer = ManagementLayerAtom()
        let atom = AttendedPaneAtom(
            tabLayout: tabLayout,
            windowLifecycle: windowLifecycle,
            managementLayer: managementLayer
        )

        var collected: [UUID?] = []
        let collector = Task { @MainActor in
            for await paneId in atom.transitions {
                collected.append(paneId)
                if collected.count >= 3 {
                    break
                }
            }
        }
        await Task.yield()

        makeWindowKey(windowLifecycle)
        await Task.yield()
        tabLayout.setActivePane(paneB, inTab: tabId)
        await Task.yield()
        managementLayer.activate()
        for _ in 0..<50 where collected.count < 3 {
            await Task.yield()
        }

        #expect(collected == [paneA, paneB, nil])
        collector.cancel()
        atom.stop()
    }
}
