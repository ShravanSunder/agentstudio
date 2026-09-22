import AgentStudioAppIPC
import AgentStudioProgrammaticControl
import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioTestSupport

@MainActor
@Suite("AgentStudio IPC layout adapter")
struct AgentStudioIPCLayoutAdapterTests {
    @Test("pane focus fails closed when no workspace window is active")
    func paneFocusFailsClosedWhenNoWorkspaceWindowIsActive() async throws {
        let harness = LayoutAdapterHarness(windowSnapshot: .empty)

        do {
            _ = try await harness.adapter.focusPane(IPCHandle(kind: .pane, reference: .friendlyOrdinal(1)))
            Issue.record("focusPane unexpectedly succeeded without an active window")
        } catch let error as AppIPCLayoutError {
            #expect(error.reason == .noActiveWindow)
        }
    }

    @Test("pane focus resolves friendly ordinal and delegates to focus control seam")
    func paneFocusResolvesFriendlyOrdinalAndDelegatesToFocusControlSeam() async throws {
        let store = makeIPCLayoutWorkspaceStore()
        let firstPane = store.createPane(title: "First")
        let secondPane = store.createPane(title: "Second")
        let tab = makeTab(paneIds: [firstPane.id, secondPane.id], activePaneId: firstPane.id)
        store.appendTab(tab)
        store.setActiveTab(tab.id)
        let focusControl = RecordingPaneFocusAppControl()
        let harness = LayoutAdapterHarness(store: store, focusControl: focusControl)

        let result = try await harness.adapter.focusPane(IPCHandle(kind: .pane, reference: .friendlyOrdinal(2)))

        #expect(result == IPCPaneFocusResult(paneId: secondPane.id, focused: true))
        #expect(focusControl.focusedPaneIds == [secondPane.id])
    }

    @Test("pane focus result waits for the focus owner completion")
    func paneFocusResultWaitsForFocusOwnerCompletion() async throws {
        let store = makeIPCLayoutWorkspaceStore()
        let pane = store.createPane(title: "Target")
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)
        store.setActiveTab(tab.id)
        let focusControl = SuspendingPaneFocusAppControl()
        let harness = LayoutAdapterHarness(store: store, focusControl: focusControl)
        var result: IPCPaneFocusResult?
        let focusTask = Task { @MainActor in
            result = try await harness.adapter.focusPane(
                IPCHandle(kind: .pane, reference: .friendlyOrdinal(1))
            )
        }

        await focusControl.waitUntilStarted()
        #expect(result == nil)
        focusControl.complete()
        try await focusTask.value

        #expect(focusControl.focusedPaneIDs == [pane.id])
        #expect(result == IPCPaneFocusResult(paneId: pane.id, focused: true))
    }

    @Test("pane focus reports target not found for missing pane handle")
    func paneFocusReportsTargetNotFoundForMissingPaneHandle() async throws {
        let harness = LayoutAdapterHarness()

        do {
            _ = try await harness.adapter.focusPane(IPCHandle(kind: .pane, reference: .canonicalUUID(UUID())))
            Issue.record("focusPane unexpectedly succeeded for a missing pane")
        } catch let error as AppIPCLayoutError {
            #expect(error.reason == .targetNotFound)
        }
    }

    @Test("pane focus rejects non-pane handles")
    func paneFocusRejectsNonPaneHandles() async throws {
        let harness = LayoutAdapterHarness()

        do {
            _ = try await harness.adapter.focusPane(IPCHandle(kind: .workspace, reference: .friendlyOrdinal(1)))
            Issue.record("focusPane unexpectedly accepted a workspace handle")
        } catch let error as AppIPCLayoutError {
            #expect(error.reason == .validationRejected)
        }
    }

    @Test("pane split resolves requested pane instead of active pane")
    func paneSplitResolvesRequestedPaneInsteadOfActivePane() async throws {
        let store = makeIPCLayoutWorkspaceStore()
        let activePane = store.createPane(title: "Active")
        let requestedPane = store.createPane(title: "Requested")
        let tab = makeTab(paneIds: [activePane.id, requestedPane.id], activePaneId: activePane.id)
        store.appendTab(tab)
        store.setActiveTab(tab.id)
        let workspaceActionExecutor = RecordingIPCLayoutActionExecutor()
        let harness = LayoutAdapterHarness(store: store, workspaceActionExecutor: workspaceActionExecutor)

        let result = try await harness.adapter.splitPane(
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
    func paneCloseDelegatesExplicitPaneAction() async throws {
        let store = makeIPCLayoutWorkspaceStore()
        let firstPane = store.createPane(title: "First")
        let secondPane = store.createPane(title: "Second")
        let tab = makeTab(paneIds: [firstPane.id, secondPane.id], activePaneId: firstPane.id)
        store.appendTab(tab)
        store.setActiveTab(tab.id)
        let workspaceActionExecutor = RecordingIPCLayoutActionExecutor()
        let harness = LayoutAdapterHarness(store: store, workspaceActionExecutor: workspaceActionExecutor)

        let result = try await harness.adapter.closePane(IPCPaneCloseParams(handle: "pane:2", correlationId: nil))

        #expect(result.paneId == secondPane.id)
        #expect(workspaceActionExecutor.actions == [.closePane(tabId: tab.id, paneId: secondPane.id)])
    }

    @Test("drawer methods delegate through layout action seam")
    func drawerMethodsDelegateThroughLayoutActionSeam() async throws {
        let store = makeIPCLayoutWorkspaceStore()
        let parentPane = store.createPane(title: "Parent")
        let tab = makeTab(paneIds: [parentPane.id], activePaneId: parentPane.id)
        store.appendTab(tab)
        store.setActiveTab(tab.id)
        let workspaceActionExecutor = RecordingIPCLayoutActionExecutor()
        let harness = LayoutAdapterHarness(store: store, workspaceActionExecutor: workspaceActionExecutor)

        let addResult = try await harness.adapter.addDrawerPane(
            IPCDrawerAddPaneParams(parentPaneHandle: "pane:1", correlationId: nil)
        )
        let toggleResult = try await harness.adapter.toggleDrawer(
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
    func drawerMethodsRejectDrawerChildHandlesAsParents() async throws {
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
            _ = try await harness.adapter.addDrawerPane(
                IPCDrawerAddPaneParams(parentPaneHandle: "pane:2", correlationId: nil)
            )
            Issue.record("drawer.addPane unexpectedly accepted a drawer child as parent")
        } catch let error as AppIPCLayoutError {
            #expect(error.reason == .validationRejected)
        }

        do {
            _ = try await harness.adapter.toggleDrawer(
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
    func layoutMethodsReportValidationRejectionFromActionOwner() async throws {
        let store = makeIPCLayoutWorkspaceStore()
        let parentPane = store.createPane(title: "Parent")
        let tab = makeTab(paneIds: [parentPane.id], activePaneId: parentPane.id)
        store.appendTab(tab)
        store.setActiveTab(tab.id)
        let workspaceActionExecutor = RecordingIPCLayoutActionExecutor(accepted: false)
        let harness = LayoutAdapterHarness(store: store, workspaceActionExecutor: workspaceActionExecutor)

        do {
            _ = try await harness.adapter.splitPane(
                IPCPaneSplitParams(handle: "pane:1", direction: .right, correlationId: nil)
            )
            Issue.record("pane.split unexpectedly reported success after owner rejection")
        } catch let error as AppIPCLayoutError {
            #expect(error.reason == .validationRejected)
        }
    }

    @Test("concrete pane focus control routes through PaneTabViewController owner chain")
    func concretePaneFocusControlRoutesThroughPaneTabViewControllerOwnerChain() async throws {
        try await withAsyncTestCoreAtoms { _ in
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

            let focusWindow = makePaneTabViewControllerCommandWindow(for: harness.controller)
            focusWindow.isReleasedWhenClosed = false
            defer { focusWindow.close() }
            try attachPaneHost(paneId: secondPane.id, in: harness, to: focusWindow)

            try await focusControl.focusPane(secondPane.id)

            #expect(harness.store.activeTabId == tab.id)
            #expect(harness.store.tab(tab.id)?.activePaneId == secondPane.id)
        }
    }

    @Test("concrete pane focus control rejects completion when no native host can focus")
    func concretePaneFocusControlRejectsMissingNativeHost() async throws {
        try await withAsyncTestCoreAtoms { _ in
            let harness = makeHarness()
            let pane = harness.store.createPane(title: "Target")
            let tab = Tab(paneId: pane.id)
            harness.store.appendTab(tab)
            harness.store.setActiveTab(tab.id)
            let focusControl = PaneTabViewControllerPaneFocusAppControl(
                paneTabViewController: harness.controller,
                workspaceStore: harness.store
            )

            do {
                try await focusControl.focusPane(pane.id)
                Issue.record("focusPane unexpectedly succeeded without a native pane host")
            } catch let error as PaneFocusAppControlError {
                #expect(error == .validationRejected)
            }
        }
    }

    @Test("concrete pane focus control maps rejected admission to validation rejection")
    func concretePaneFocusControlRejectsClosedAdmission() async throws {
        try await withAsyncTestCoreAtoms { _ in
            let harness = makeHarness()
            let firstPane = harness.store.createPane(title: "First")
            let secondPane = harness.store.createPane(title: "Second")
            let tab = makeTab(paneIds: [firstPane.id, secondPane.id], activePaneId: firstPane.id)
            harness.store.appendTab(tab)
            harness.store.setActiveTab(tab.id)
            let focusWindow = makePaneTabViewControllerCommandWindow(for: harness.controller)
            focusWindow.isReleasedWhenClosed = false
            defer { focusWindow.close() }
            try attachPaneHost(paneId: secondPane.id, in: harness, to: focusWindow)
            let focusControl = PaneTabViewControllerPaneFocusAppControl(
                paneTabViewController: harness.controller,
                workspaceStore: harness.store
            )
            await harness.executor.stopAcceptingCommandsAndDrain()

            do {
                try await focusControl.focusPane(secondPane.id)
                Issue.record("focusPane unexpectedly succeeded after admission closed")
            } catch let error as PaneFocusAppControlError {
                #expect(error == .validationRejected)
            }
            #expect(harness.store.tab(tab.id)?.activePaneId == firstPane.id)
        }
    }

    @Test("concrete layout actions register hosts before exposing created panes")
    func concreteLayoutActionsRegisterHostsBeforeExposingCreatedPanes() async throws {
        try await withAsyncTestCoreAtoms { _ in
            let harness = makeHarness()
            let (repo, worktree) = makeRepoAndWorktree(harness.store, root: harness.tempDir)
            let parentPane = harness.store.createPane(
                launchDirectory: worktree.path,
                title: "Parent",
                facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path)
            )
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

            let panesBeforeSplit = harness.store.paneAtom.graphAtom.paneIDs
            _ = try await adapter.splitPane(
                IPCPaneSplitParams(handle: "pane:1", direction: .right, correlationId: nil)
            )
            let splitPaneIds = harness.store.paneAtom.graphAtom.paneIDs.subtracting(panesBeforeSplit)
            let splitPaneId = try #require(splitPaneIds.first)

            #expect(harness.viewRegistry.view(for: splitPaneId) != nil)
            let splitFacets = try #require(
                harness.store.paneAtom.graphAtom.paneState(splitPaneId)?.durableContextFacets
            )
            #expect(splitFacets.repoId == repo.id)
            #expect(splitFacets.worktreeId == worktree.id)
            #expect(splitFacets.cwd?.standardizedFileURL.path == worktree.path.standardizedFileURL.path)

            let panesBeforeDrawerAdd = harness.store.paneAtom.graphAtom.paneIDs
            _ = try await adapter.addDrawerPane(
                IPCDrawerAddPaneParams(parentPaneHandle: "pane:1", correlationId: nil)
            )
            let drawerPaneIds = harness.store.paneAtom.graphAtom.paneIDs.subtracting(panesBeforeDrawerAdd)
            let drawerPaneId = try #require(drawerPaneIds.first)

            #expect(harness.store.paneAtom.pane(drawerPaneId)?.isDrawerChild == true)
            #expect(harness.viewRegistry.view(for: drawerPaneId) != nil)
            let drawerFacets = try #require(
                harness.store.paneAtom.graphAtom.paneState(drawerPaneId)?.durableContextFacets
            )
            #expect(drawerFacets.repoId == repo.id)
            #expect(drawerFacets.worktreeId == worktree.id)
            #expect(drawerFacets.cwd?.standardizedFileURL.path == worktree.path.standardizedFileURL.path)
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

    func focusPane(_ paneId: UUID) async throws {
        if let error {
            throw error
        }
        focusedPaneIds.append(paneId)
    }
}

@MainActor
private final class SuspendingPaneFocusAppControl: PaneFocusAppControlling, @unchecked Sendable {
    private(set) var focusedPaneIDs: [UUID] = []
    private let startedStream: AsyncStream<Void>
    private let startedContinuation: AsyncStream<Void>.Continuation
    private var completionContinuation: CheckedContinuation<Void, Never>?

    init() {
        (startedStream, startedContinuation) = AsyncStream.makeStream(of: Void.self)
    }

    func focusPane(_ paneId: UUID) async throws {
        focusedPaneIDs.append(paneId)
        startedContinuation.yield()
        await withCheckedContinuation { continuation in
            completionContinuation = continuation
        }
    }

    func waitUntilStarted() async {
        for await _ in startedStream {
            return
        }
    }

    func complete() {
        completionContinuation?.resume()
        completionContinuation = nil
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
    return WorkspaceStore()
}
