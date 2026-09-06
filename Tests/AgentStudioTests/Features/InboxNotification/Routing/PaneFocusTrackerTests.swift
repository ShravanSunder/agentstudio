import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioInboxNotification

@MainActor
@Suite("PaneFocusTracker", .serialized)
struct PaneFocusTrackerTests {
    private func makeWindowKey(_ atom: WindowLifecycleAtom) {
        let id = UUIDv7.generate()
        atom.recordWindowRegistered(id)
        atom.recordWindowBecameKey(id)
    }

    private func makeTab(activePaneId: UUID, paneIds: [UUID]) -> Tab {
        let arrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout.autoTiled(paneIds),
            activePaneId: activePaneId
        )
        return Tab(
            name: "Tab",
            allPaneIds: paneIds,
            arrangements: [arrangement],
            activeArrangementId: arrangement.id
        )
    }

    private func collectAndStop(from tracker: PaneFocusTracker) async -> [UUID] {
        await tracker.waitForPendingDelivery()
        await tracker.stop()
        var collected: [UUID] = []
        for await id in tracker.focusGainedStream { collected.append(id) }
        return collected
    }

    @Test("emits pane ids on attended-pane transitions")
    func emitsOnTransition() async {
        let tabLayout = WorkspaceTabLayoutAtom()
        let windowLifecycle = WindowLifecycleAtom()
        let managementLayer = ManagementLayerAtom()
        let attendedPane = AttendedPaneDerived(
            tabLayout: tabLayout,
            windowLifecycle: windowLifecycle,
            managementLayer: managementLayer
        )
        let tracker = PaneFocusTracker(attendedPane: attendedPane)
        let paneA = UUIDv7.generate()
        let paneB = UUIDv7.generate()
        let tab = makeTab(activePaneId: paneA, paneIds: [paneA, paneB])

        tabLayout.appendTab(tab)
        makeWindowKey(windowLifecycle)
        await tracker.waitForPendingDelivery()
        tabLayout.setActivePane(paneB, inTab: tab.id)
        await tracker.waitForPendingDelivery()

        let collected = await collectAndStop(from: tracker)
        #expect(collected == [paneA, paneB])
        await tracker.stop()
    }

    @Test("traces attended-pane transitions without changing focus-gained stream")
    func tracesAttendedPaneTransitions() async throws {
        let tabLayout = WorkspaceTabLayoutAtom()
        let windowLifecycle = WindowLifecycleAtom()
        let managementLayer = ManagementLayerAtom()
        let attendedPane = AttendedPaneDerived(
            tabLayout: tabLayout,
            windowLifecycle: windowLifecycle,
            managementLayer: managementLayer
        )
        let traceRuntime = AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_BACKEND": "jsonl",
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
        let paneA = UUIDv7.generate()
        let paneB = UUIDv7.generate()
        let tab = makeTab(activePaneId: paneA, paneIds: [paneA, paneB])

        tabLayout.appendTab(tab)
        makeWindowKey(windowLifecycle)
        await tracker.waitForPendingDelivery()
        tabLayout.setActivePane(paneB, inTab: tab.id)
        await tracker.waitForPendingDelivery()

        let collected = await collectAndStop(from: tracker)
        #expect(collected == [paneA, paneB])
        let outputFileURL = try #require(traceRuntime.outputFileURL)
        await tracker.stop()
        await assertEventuallyMain("focus tracker should write attended-pane trace records") {
            guard let contents = try? String(contentsOf: outputFileURL, encoding: .utf8) else {
                return false
            }
            return contents.contains("\"body\":\"app.focus.attendedPaneChanged\"")
                && contents.contains("\"agentstudio.app.focus.attended\":true")
                && contents.contains("\"agentstudio.pane.id\":\"\(paneB.uuidString)\"")
        }

    }

    @Test("does not emit when attended pane remains the same")
    func noEmitOnNoChange() async {
        let tabLayout = WorkspaceTabLayoutAtom()
        let windowLifecycle = WindowLifecycleAtom()
        let managementLayer = ManagementLayerAtom()
        let attendedPane = AttendedPaneDerived(
            tabLayout: tabLayout,
            windowLifecycle: windowLifecycle,
            managementLayer: managementLayer
        )
        let tracker = PaneFocusTracker(attendedPane: attendedPane)
        let paneA = UUIDv7.generate()
        let tab = makeTab(activePaneId: paneA, paneIds: [paneA])

        tabLayout.appendTab(tab)
        makeWindowKey(windowLifecycle)
        await tracker.waitForPendingDelivery()
        tabLayout.setActivePane(paneA, inTab: tab.id)
        await tracker.waitForPendingDelivery()

        let collected = await collectAndStop(from: tracker)
        #expect(collected == [paneA])
        await tracker.stop()
    }

    @Test("stop finishes the owned focus-gained stream")
    func stopFinishesOwnedStream() async {
        let tabLayout = WorkspaceTabLayoutAtom()
        let windowLifecycle = WindowLifecycleAtom()
        let managementLayer = ManagementLayerAtom()
        let attendedPane = AttendedPaneDerived(
            tabLayout: tabLayout,
            windowLifecycle: windowLifecycle,
            managementLayer: managementLayer
        )
        let tracker = PaneFocusTracker(attendedPane: attendedPane)

        await tracker.stop()
        #expect(await collectAndStop(from: tracker).isEmpty)
    }

    @Test("same-turn intermediate gains are not published")
    func publishesOnlySettledGain() async {
        // Arrange
        let tabLayout = WorkspaceTabLayoutAtom()
        let windowLifecycle = WindowLifecycleAtom()
        let managementLayer = ManagementLayerAtom()
        let paneIDs = (0..<3).map { _ in UUIDv7.generate() }
        let tab = makeTab(activePaneId: paneIDs[0], paneIds: paneIDs)
        tabLayout.appendTab(tab)
        makeWindowKey(windowLifecycle)
        let tracker = PaneFocusTracker(
            attendedPane: AttendedPaneDerived(
                tabLayout: tabLayout, windowLifecycle: windowLifecycle, managementLayer: managementLayer
            ))

        // Act
        tabLayout.setActivePane(paneIDs[1], inTab: tab.id)
        tabLayout.setActivePane(paneIDs[2], inTab: tab.id)
        let collected = await collectAndStop(from: tracker)

        // Assert
        #expect(collected == [paneIDs[2]])
    }

    @Test("settled loss and regain publishes a new gain for the same pane")
    func settledNilIntervalAllowsRegain() async {
        // Arrange
        let tabLayout = WorkspaceTabLayoutAtom()
        let windowLifecycle = WindowLifecycleAtom()
        let managementLayer = ManagementLayerAtom()
        let paneID = UUIDv7.generate()
        tabLayout.appendTab(makeTab(activePaneId: paneID, paneIds: [paneID]))
        makeWindowKey(windowLifecycle)
        let tracker = PaneFocusTracker(
            attendedPane: AttendedPaneDerived(
                tabLayout: tabLayout, windowLifecycle: windowLifecycle, managementLayer: managementLayer
            ))

        // Act
        managementLayer.toggle()
        await tracker.waitForPendingDelivery()
        managementLayer.toggle()
        let collected = await collectAndStop(from: tracker)

        // Assert
        #expect(collected == [paneID])
    }

    private func temporaryTraceDirectoryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("agentstudio-pane-focus-tracker-tests", isDirectory: true)
            .appendingPathComponent(UUIDv7.generate().uuidString, isDirectory: true)
    }
}
