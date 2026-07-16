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

    @Test("pane split resolves requested pane instead of active pane")
    func paneSplitResolvesRequestedPaneInsteadOfActivePane() throws {
        let store = makeIPCLayoutWorkspaceStore()
        let activePane = store.createPane(title: "Active")
        let requestedPane = store.createPane(title: "Requested")
        let tab = makeTab(paneIds: [activePane.id, requestedPane.id], activePaneId: activePane.id)
        store.appendTab(tab)
        store.setActiveTab(tab.id)
        let workspaceActionExecutor = RecordingIPCLayoutActionExecutor()
        let harness = LayoutAdapterHarness(store: store, workspaceActionExecutor: workspaceActionExecutor)

        let result = try harness.adapter.splitPane(
            IPCPaneSplitParams(handle: "pane:2", direction: .right, correlationId: nil)
        )

        #expect(result.targetPaneId == requestedPane.id)
        #expect(workspaceActionExecutor.actions.count == 1)
        guard case .insertPaneRequest(let request) = workspaceActionExecutor.actions.first else {
            Issue.record("pane split did not delegate an insertPaneRequest")
            return
        }
        #expect(request.targetTabId == tab.id)
        #expect(request.targetPaneId == requestedPane.id)
        #expect(request.direction == .right)
        #expect(request.source == .newTerminal)
    }

    @Test("pane close delegates explicit pane action")
    func paneCloseDelegatesExplicitPaneAction() throws {
        let store = makeIPCLayoutWorkspaceStore()
        let firstPane = store.createPane(title: "First")
        let secondPane = store.createPane(title: "Second")
        let tab = makeTab(paneIds: [firstPane.id, secondPane.id], activePaneId: firstPane.id)
        store.appendTab(tab)
        store.setActiveTab(tab.id)
        let workspaceActionExecutor = RecordingIPCLayoutActionExecutor()
        let harness = LayoutAdapterHarness(store: store, workspaceActionExecutor: workspaceActionExecutor)

        let result = try harness.adapter.closePane(IPCPaneCloseParams(handle: "pane:2", correlationId: nil))

        #expect(result.paneId == secondPane.id)
        #expect(workspaceActionExecutor.actions == [.closePane(tabId: tab.id, paneId: secondPane.id)])
    }

    @Test("drawer methods delegate through layout action seam")
    func drawerMethodsDelegateThroughLayoutActionSeam() throws {
        let store = makeIPCLayoutWorkspaceStore()
        let parentPane = store.createPane(title: "Parent")
        let tab = makeTab(paneIds: [parentPane.id], activePaneId: parentPane.id)
        store.appendTab(tab)
        store.setActiveTab(tab.id)
        let workspaceActionExecutor = RecordingIPCLayoutActionExecutor()
        let harness = LayoutAdapterHarness(store: store, workspaceActionExecutor: workspaceActionExecutor)

        let addResult = try harness.adapter.addDrawerPane(
            IPCDrawerAddPaneParams(parentPaneHandle: "pane:1", correlationId: nil)
        )
        let toggleResult = try harness.adapter.toggleDrawer(
            IPCDrawerToggleParams(parentPaneHandle: "pane:1", correlationId: nil)
        )

        #expect(addResult.parentPaneId == parentPane.id)
        #expect(toggleResult.parentPaneId == parentPane.id)
        #expect(
            workspaceActionExecutor.actions == [
                .addDrawerPane(parentPaneId: parentPane.id),
                .toggleDrawer(paneId: parentPane.id),
            ])
    }

    @Test("drawer methods reject drawer child handles as parents")
    func drawerMethodsRejectDrawerChildHandlesAsParents() throws {
        let store = makeIPCLayoutWorkspaceStore()
        let parentPane = store.createPane(title: "Parent")
        let drawerPane = store.paneAtom.addDrawerPane(
            to: parentPane.id,
            parentFallbackCWD: nil,
            zmxSessionID: .generateUUIDv7()
        )
        let tab = makeTab(paneIds: [parentPane.id], activePaneId: parentPane.id)
        store.appendTab(tab)
        store.setActiveTab(tab.id)
        let workspaceActionExecutor = RecordingIPCLayoutActionExecutor()
        let harness = LayoutAdapterHarness(store: store, workspaceActionExecutor: workspaceActionExecutor)

        do {
            _ = try harness.adapter.addDrawerPane(
                IPCDrawerAddPaneParams(parentPaneHandle: "pane:2", correlationId: nil)
            )
            Issue.record("drawer.addPane unexpectedly accepted a drawer child as parent")
        } catch let error as AppIPCLayoutError {
            #expect(error.reason == .validationRejected)
        }

        do {
            _ = try harness.adapter.toggleDrawer(
                IPCDrawerToggleParams(parentPaneHandle: "pane:2", correlationId: nil)
            )
            Issue.record("drawer.toggle unexpectedly accepted a drawer child as parent")
        } catch let error as AppIPCLayoutError {
            #expect(error.reason == .validationRejected)
        }

        #expect(drawerPane?.isDrawerChild == true)
        #expect(workspaceActionExecutor.actions.isEmpty)
    }

    @Test("layout methods report validation rejection from action owner")
    func layoutMethodsReportValidationRejectionFromActionOwner() throws {
        let store = makeIPCLayoutWorkspaceStore()
        let parentPane = store.createPane(title: "Parent")
        let tab = makeTab(paneIds: [parentPane.id], activePaneId: parentPane.id)
        store.appendTab(tab)
        store.setActiveTab(tab.id)
        let workspaceActionExecutor = RecordingIPCLayoutActionExecutor(accepted: false)
        let harness = LayoutAdapterHarness(store: store, workspaceActionExecutor: workspaceActionExecutor)

        do {
            _ = try harness.adapter.splitPane(
                IPCPaneSplitParams(handle: "pane:1", direction: .right, correlationId: nil)
            )
            Issue.record("pane.split unexpectedly reported success after owner rejection")
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

    @Test("concrete layout actions register hosts before exposing created panes")
    func concreteLayoutActionsRegisterHostsBeforeExposingCreatedPanes() throws {
        try withTestAtomRegistry { _ in
            let harness = makeHarness()
            let parentPane = harness.store.createPane(title: "Parent")
            let tab = makeTab(paneIds: [parentPane.id], activePaneId: parentPane.id)
            harness.store.appendTab(tab)
            harness.store.setActiveTab(tab.id)
            harness.store.setActivePane(parentPane.id, inTab: tab.id)
            let adapter = AgentStudioIPCLayoutAdapter(
                workspaceStore: harness.store,
                windowLifecycleReader: FakeLayoutWorkspaceWindowLifecycleReader(snapshot: .singleActiveWindow(UUID())),
                paneFocusControl: RecordingPaneFocusAppControl(),
                workspaceActionExecutor: harness.executor
            )

            let panesBeforeSplit = Set(harness.store.paneAtom.panes.keys)
            _ = try adapter.splitPane(
                IPCPaneSplitParams(handle: "pane:1", direction: .right, correlationId: nil)
            )
            let splitPaneIds = Set(harness.store.paneAtom.panes.keys).subtracting(panesBeforeSplit)
            let splitPaneId = try #require(splitPaneIds.first)

            #expect(harness.viewRegistry.view(for: splitPaneId) != nil)

            let panesBeforeDrawerAdd = Set(harness.store.paneAtom.panes.keys)
            _ = try adapter.addDrawerPane(
                IPCDrawerAddPaneParams(parentPaneHandle: "pane:1", correlationId: nil)
            )
            let drawerPaneIds = Set(harness.store.paneAtom.panes.keys).subtracting(panesBeforeDrawerAdd)
            let drawerPaneId = try #require(drawerPaneIds.first)

            #expect(harness.store.paneAtom.pane(drawerPaneId)?.isDrawerChild == true)
            #expect(harness.viewRegistry.view(for: drawerPaneId) != nil)
        }
    }
}

@MainActor
private struct LayoutAdapterHarness {
    let adapter: AgentStudioIPCLayoutAdapter

    init(
        store: WorkspaceStore = makeIPCLayoutWorkspaceStore(),
        windowSnapshot: WorkspaceWindowLifecycleSnapshot = .singleActiveWindow(UUID()),
        focusControl: any PaneFocusAppControlling = RecordingPaneFocusAppControl(),
        workspaceActionExecutor: any AgentStudioIPCLayoutActionExecuting = RecordingIPCLayoutActionExecutor()
    ) {
        adapter = AgentStudioIPCLayoutAdapter(
            workspaceStore: store,
            windowLifecycleReader: FakeLayoutWorkspaceWindowLifecycleReader(snapshot: windowSnapshot),
            paneFocusControl: focusControl,
            workspaceActionExecutor: workspaceActionExecutor
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

@MainActor
private final class RecordingIPCLayoutActionExecutor: AgentStudioIPCLayoutActionExecuting, @unchecked Sendable {
    private let accepted: Bool
    private(set) var actions: [WorkspaceActionCommand] = []

    init(accepted: Bool = true) {
        self.accepted = accepted
    }

    func execute(_ action: WorkspaceActionCommand) -> Bool {
        actions.append(action)
        return accepted
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
    return WorkspaceStore(
        workspacePersistenceRevisionOwner: WorkspacePersistenceRevisionOwner())
}
