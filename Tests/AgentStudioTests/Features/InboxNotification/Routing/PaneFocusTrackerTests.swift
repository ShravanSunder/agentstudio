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

    private func waitsForStreamCompletion(
        from tracker: PaneFocusTracker,
        maxIterations: Int = 50
    ) async -> Bool {
        var didFinish = false
        let task = Task { @MainActor in
            for await _ in tracker.focusGainedStream {}
            didFinish = true
        }

        for _ in 0..<maxIterations where !didFinish {
            await Task.yield()
        }
        if !didFinish {
            task.cancel()
        }
        return didFinish
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

    @Test("traces attended-pane transitions without changing focus-gained stream")
    func tracesAttendedPaneTransitions() async throws {
        let tabLayout = WorkspaceTabLayoutAtom()
        let windowLifecycle = WindowLifecycleAtom()
        let managementLayer = ManagementLayerAtom()
        let attendedPane = AttendedPaneAtom(
            tabLayout: tabLayout,
            windowLifecycle: windowLifecycle,
            managementLayer: managementLayer
        )
        let traceRuntime = AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_DIR": temporaryTraceDirectoryURL().path,
                "AGENTSTUDIO_TRACE_FLUSH": "immediate",
                "AGENTSTUDIO_TRACE_NAME": "pane-focus-tracker",
                "AGENTSTUDIO_TRACE_TAGS": "app.focus",
            ]),
            processIdentifier: 271,
            sessionID: "pane-focus-session",
            timeUnixNano: { 2002 }
        )
        let tracker = PaneFocusTracker(attendedPane: attendedPane, traceRuntime: traceRuntime)
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
        let outputFileURL = try #require(traceRuntime.outputFileURL)
        await assertEventuallyMain("focus tracker should write attended-pane trace records") {
            guard let contents = try? String(contentsOf: outputFileURL, encoding: .utf8) else {
                return false
            }
            return contents.contains("\"body\":\"app.focus.attendedPaneChanged\"")
                && contents.contains("\"agentstudio.app.focus.attended\":true")
                && contents.contains("\"agentstudio.pane.id\":\"\(paneB.uuidString)\"")
        }

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

    @Test("finishes when attended-pane upstream finishes unexpectedly")
    func finishesWhenUpstreamFinishesUnexpectedly() async {
        let tabLayout = WorkspaceTabLayoutAtom()
        let windowLifecycle = WindowLifecycleAtom()
        let managementLayer = ManagementLayerAtom()
        let attendedPane = AttendedPaneAtom(
            tabLayout: tabLayout,
            windowLifecycle: windowLifecycle,
            managementLayer: managementLayer
        )
        let tracker = PaneFocusTracker(attendedPane: attendedPane)

        attendedPane.stop()
        await Task.yield()

        #expect(await waitsForStreamCompletion(from: tracker))
        tracker.stop()
    }

    private func temporaryTraceDirectoryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("agentstudio-pane-focus-tracker-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
