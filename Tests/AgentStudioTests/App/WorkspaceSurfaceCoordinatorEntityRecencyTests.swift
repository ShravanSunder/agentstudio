import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioBridge
@testable import AgentStudioCore
@testable import AgentStudioTestSupport

@MainActor
@Suite("WorkspaceSurfaceCoordinator EntityRecency", .serialized)
struct WorkspaceSurfaceCoordinatorEntityRecencyTests {
    init() {
        installTestCoreAtomsIfNeeded()
    }

    @Test("successful worktree open records repository and worktree with one timestamp")
    func successfulWorktreeOpen_recordsCoherentApplicationRecency() throws {
        try withTestCoreAtoms { coreAtoms in
            let store = WorkspaceStore(
                identityAtom: coreAtoms.workspaceIdentity,
                windowMemoryAtom: coreAtoms.workspaceWindowMemory,
                repositoryTopologyAtom: coreAtoms.workspaceRepositoryTopology,
                paneAtom: coreAtoms.workspacePane,
                tabLayoutAtom: coreAtoms.workspaceTabLayout,
                mutationCoordinator: coreAtoms.workspaceMutationCoordinator
            )
            let repo = store.addRepo(at: URL(fileURLWithPath: "/tmp/entity-recency-repo"))
            let worktree = try #require(store.repo(repo.id)?.worktrees.first)
            let coordinator = WorkspaceSurfaceCoordinator(
                store: store,
                viewRegistry: ViewRegistry(),
                runtime: SessionRuntime(store: store),
                windowLifecycleStore: coreAtoms.windowLifecycle,
                bridgePaneAttendance: BridgePaneAttendanceAtom()
            )

            let openedPane = coordinator.openTerminal(for: worktree, in: repo)

            #expect(openedPane != nil)
            let repositoryRecency = try #require(
                coreAtoms.applicationEntityRecency.recentEntities.first {
                    $0.entity == .repository(repositoryStableKey: repo.stableKey)
                }
            )
            let worktreeRecency = try #require(
                coreAtoms.applicationEntityRecency.recentEntities.first {
                    $0.entity == .worktree(worktreeStableKey: worktree.stableKey)
                }
            )
            #expect(repositoryRecency.interaction == .opened)
            #expect(worktreeRecency.interaction == .opened)
            #expect(repositoryRecency.lastInteractedAt == worktreeRecency.lastInteractedAt)
        }
    }

    @Test("rejected unknown worktree action records no application recency")
    func rejectedUnknownWorktreeAction_recordsNothing() {
        withTestCoreAtoms { coreAtoms in
            let store = makeStore(coreAtoms: coreAtoms)
            let coordinator = WorkspaceSurfaceCoordinator(
                store: store,
                viewRegistry: ViewRegistry(),
                runtime: SessionRuntime(store: store),
                windowLifecycleStore: coreAtoms.windowLifecycle,
                bridgePaneAttendance: BridgePaneAttendanceAtom()
            )
            let executor = WorkspaceActionExecutor(coordinator: coordinator, store: store)

            let accepted = executor.execute(.openWorktree(worktreeId: UUID()))

            #expect(!accepted)
            #expect(coreAtoms.applicationEntityRecency.recentEntities.isEmpty)
        }
    }

    @Test("failed split insertion records no application recency")
    func failedSplitInsertion_recordsNothing() throws {
        try withTestCoreAtoms { coreAtoms in
            let store = makeStore(coreAtoms: coreAtoms)
            let repo = store.addRepo(at: URL(fileURLWithPath: "/tmp/entity-recency-split-failure"))
            let worktree = try #require(store.repo(repo.id)?.worktrees.first)
            let targetPane = store.createPane(title: "Target")
            let tab = Tab(paneId: targetPane.id)
            store.appendTab(tab)
            store.setActiveTab(tab.id)
            let arrangementID = try #require(store.tab(tab.id)?.activeArrangementId)
            store.arrangementCursorAtom.replaceCursors(
                activeArrangementIdsByTabId: [tab.id: arrangementID],
                paneCursorsByArrangementId: [
                    arrangementID: ArrangementPaneCursorState(activePaneId: UUID())
                ],
                drawerCursorsByKey: [:]
            )
            let coordinator = WorkspaceSurfaceCoordinator(
                store: store,
                viewRegistry: ViewRegistry(),
                runtime: SessionRuntime(store: store),
                windowLifecycleStore: coreAtoms.windowLifecycle,
                bridgePaneAttendance: BridgePaneAttendanceAtom()
            )
            let executor = WorkspaceActionExecutor(coordinator: coordinator, store: store)

            let accepted = executor.execute(.openWorktreeInPane(worktreeId: worktree.id))

            #expect(accepted)
            #expect(store.panes.count == 1)
            #expect(coreAtoms.applicationEntityRecency.recentEntities.isEmpty)
        }
    }

    private func makeStore(coreAtoms: CoreAtoms) -> WorkspaceStore {
        WorkspaceStore(
            identityAtom: coreAtoms.workspaceIdentity,
            windowMemoryAtom: coreAtoms.workspaceWindowMemory,
            repositoryTopologyAtom: coreAtoms.workspaceRepositoryTopology,
            paneAtom: coreAtoms.workspacePane,
            tabLayoutAtom: coreAtoms.workspaceTabLayout,
            mutationCoordinator: coreAtoms.workspaceMutationCoordinator
        )
    }
}
