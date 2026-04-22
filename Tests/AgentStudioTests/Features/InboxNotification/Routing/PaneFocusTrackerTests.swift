import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("PaneFocusTracker")
struct PaneFocusTrackerTests {
    private func makeWindowKey(_ atom: WindowLifecycleAtom) {
        let id = UUID()
        atom.recordWindowRegistered(id)
        atom.recordWindowBecameKey(id)
    }

    private func makeTab(activePaneId: UUID, paneIds: [UUID]) -> Tab {
        let arrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: activePaneId),
            visiblePaneIds: Set(paneIds)
        )
        return Tab(
            name: "Tab",
            panes: paneIds,
            arrangements: [arrangement],
            activeArrangementId: arrangement.id,
            activePaneId: activePaneId
        )
    }

    private func collect(
        from tracker: PaneFocusTracker,
        expected: Int,
        maxIterations: Int = 50
    ) async -> [UUID] {
        var collected: [UUID] = []
        let task = Task { @MainActor in
            for await id in tracker.focusGainedStream {
                collected.append(id)
                if collected.count >= expected {
                    break
                }
            }
        }

        for _ in 0..<maxIterations where collected.count < expected {
            await Task.yield()
        }
        task.cancel()
        return collected
    }

    @Test("emits pane ids on attended-pane transitions")
    func emitsOnTransition() async {
        let tabLayout = WorkspaceTabLayoutAtom()
        let windowLifecycle = WindowLifecycleAtom()
        let managementLayer = ManagementLayerAtom()
        let attendedPane = AttendedPaneAtom(
            tabLayout: tabLayout,
            windowLifecycle: windowLifecycle,
            managementLayer: managementLayer
        )
        let tracker = PaneFocusTracker(attendedPane: attendedPane)
        let paneA = UUID()
        let paneB = UUID()
        let tab = makeTab(activePaneId: paneA, paneIds: [paneA, paneB])

        tabLayout.appendTab(tab)
        makeWindowKey(windowLifecycle)
        await Task.yield()
        tabLayout.setActivePane(paneB, inTab: tab.id)
        await Task.yield()

        let collected = await collect(from: tracker, expected: 2)
        #expect(collected == [paneA, paneB])
        tracker.stop()
        attendedPane.stop()
    }

    @Test("does not emit when attended pane remains the same")
    func noEmitOnNoChange() async {
        let tabLayout = WorkspaceTabLayoutAtom()
        let windowLifecycle = WindowLifecycleAtom()
        let managementLayer = ManagementLayerAtom()
        let attendedPane = AttendedPaneAtom(
            tabLayout: tabLayout,
            windowLifecycle: windowLifecycle,
            managementLayer: managementLayer
        )
        let tracker = PaneFocusTracker(attendedPane: attendedPane)
        let paneA = UUID()
        let tab = makeTab(activePaneId: paneA, paneIds: [paneA])

        tabLayout.appendTab(tab)
        makeWindowKey(windowLifecycle)
        await Task.yield()
        tabLayout.setActivePane(paneA, inTab: tab.id)
        await Task.yield()

        let collected = await collect(from: tracker, expected: 2, maxIterations: 10)
        #expect(collected == [paneA])
        tracker.stop()
        attendedPane.stop()
    }
}
