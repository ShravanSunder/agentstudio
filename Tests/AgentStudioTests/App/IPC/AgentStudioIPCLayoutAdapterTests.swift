import AgentStudioAppIPC
import AgentStudioProgrammaticControl
import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("AgentStudio IPC layout adapter")
struct AgentStudioIPCLayoutAdapterTests {
    @Test("pane focus fails closed when no workspace window is active")
    func paneFocusFailsClosedWhenNoWorkspaceWindowIsActive() throws {
        let harness = LayoutAdapterHarness(windowSnapshot: .empty)

        do {
            _ = try harness.adapter.focusPane(IPCHandle(kind: .pane, reference: .friendlyOrdinal(1)))
            Issue.record("focusPane unexpectedly succeeded without an active window")
        } catch let error as AppIPCLayoutError {
            #expect(error.reason == .noActiveWindow)
        }
    }

    @Test("pane focus resolves friendly ordinal and delegates to focus control seam")
    func paneFocusResolvesFriendlyOrdinalAndDelegatesToFocusControlSeam() throws {
        let store = makeIPCLayoutWorkspaceStore()
        let firstPane = store.createPane(title: "First")
        let secondPane = store.createPane(title: "Second")
        let tab = makeTab(paneIds: [firstPane.id, secondPane.id], activePaneId: firstPane.id)
        store.appendTab(tab)
        store.setActiveTab(tab.id)
        let focusControl = RecordingPaneFocusAppControl()
        let harness = LayoutAdapterHarness(store: store, focusControl: focusControl)

        let result = try harness.adapter.focusPane(IPCHandle(kind: .pane, reference: .friendlyOrdinal(2)))

        #expect(result == IPCPaneFocusResult(paneId: secondPane.id, focused: true))
        #expect(focusControl.focusedPaneIds == [secondPane.id])
    }

    @Test("pane focus reports target not found for missing pane handle")
    func paneFocusReportsTargetNotFoundForMissingPaneHandle() throws {
        let harness = LayoutAdapterHarness()

        do {
            _ = try harness.adapter.focusPane(IPCHandle(kind: .pane, reference: .canonicalUUID(UUID())))
            Issue.record("focusPane unexpectedly succeeded for a missing pane")
        } catch let error as AppIPCLayoutError {
            #expect(error.reason == .targetNotFound)
        }
    }

    @Test("pane focus rejects non-pane handles")
    func paneFocusRejectsNonPaneHandles() throws {
        let harness = LayoutAdapterHarness()

        do {
            _ = try harness.adapter.focusPane(IPCHandle(kind: .workspace, reference: .friendlyOrdinal(1)))
            Issue.record("focusPane unexpectedly accepted a workspace handle")
        } catch let error as AppIPCLayoutError {
            #expect(error.reason == .validationRejected)
        }
    }

    @Test("concrete pane focus control routes through PaneTabViewController owner chain")
    func concretePaneFocusControlRoutesThroughPaneTabViewControllerOwnerChain() throws {
        try withTestAtomRegistry { _ in
            let harness = makeHarness()
            let firstPane = harness.store.createPane(title: "First")
            let secondPane = harness.store.createPane(title: "Second")
            let tab = makeTab(paneIds: [firstPane.id, secondPane.id], activePaneId: firstPane.id)
            harness.store.appendTab(tab)
            harness.store.setActiveTab(tab.id)
            harness.store.setActivePane(firstPane.id, inTab: tab.id)
            let focusControl = PaneTabViewControllerPaneFocusAppControl(
                paneTabViewController: harness.controller,
                workspaceStore: harness.store
            )

            try focusControl.focusPane(secondPane.id)

            #expect(harness.store.activeTabId == tab.id)
            #expect(harness.store.tab(tab.id)?.activePaneId == secondPane.id)
        }
    }
}

@MainActor
private struct LayoutAdapterHarness {
    let adapter: AgentStudioIPCLayoutAdapter

    init(
        store: WorkspaceStore = makeIPCLayoutWorkspaceStore(),
        windowSnapshot: WorkspaceWindowLifecycleSnapshot = .singleActiveWindow(UUID()),
        focusControl: any PaneFocusAppControlling = RecordingPaneFocusAppControl()
    ) {
        adapter = AgentStudioIPCLayoutAdapter(
            workspaceStore: store,
            windowLifecycleReader: FakeLayoutWorkspaceWindowLifecycleReader(snapshot: windowSnapshot),
            paneFocusControl: focusControl
        )
    }
}

@MainActor
private final class RecordingPaneFocusAppControl: PaneFocusAppControlling, @unchecked Sendable {
    private(set) var focusedPaneIds: [UUID] = []
    var error: PaneFocusAppControlError?

    func focusPane(_ paneId: UUID) throws {
        if let error {
            throw error
        }
        focusedPaneIds.append(paneId)
    }
}

private struct FakeLayoutWorkspaceWindowLifecycleReader: WorkspaceWindowLifecycleReading {
    let snapshotValue: WorkspaceWindowLifecycleSnapshot

    init(snapshot: WorkspaceWindowLifecycleSnapshot) {
        snapshotValue = snapshot
    }

    func snapshot() -> WorkspaceWindowLifecycleSnapshot {
        snapshotValue
    }
}

extension WorkspaceWindowLifecycleSnapshot {
    fileprivate static var empty: Self {
        Self(
            registeredWindowIds: [],
            keyWindowId: nil,
            focusedWindowId: nil,
            preferredWorkspaceWindowId: nil
        )
    }

    fileprivate static func singleActiveWindow(_ windowId: UUID) -> Self {
        Self(
            registeredWindowIds: [windowId],
            keyWindowId: windowId,
            focusedWindowId: windowId,
            preferredWorkspaceWindowId: windowId
        )
    }
}

@MainActor
private func makeIPCLayoutWorkspaceStore() -> WorkspaceStore {
    let tempDir = FileManager.default.temporaryDirectory
        .appending(path: "agentstudio-ipc-layout-adapter-\(UUID().uuidString)")
    return WorkspaceStore(persistor: WorkspacePersistor(workspacesDir: tempDir))
}
