import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("WorkspaceSurfaceCoordinator EntityRecency", .serialized)
struct WorkspaceSurfaceCoordinatorEntityRecencyTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    @Test("successful worktree open records repository and worktree with one timestamp")
    func successfulWorktreeOpen_recordsCoherentApplicationRecency() throws {
        try withTestAtomRegistry { atoms in
            let store = WorkspaceStore(
                identityAtom: atoms.workspaceIdentity,
                windowMemoryAtom: atoms.workspaceWindowMemory,
                repositoryTopologyAtom: atoms.workspaceRepositoryTopology,
                paneAtom: atoms.workspacePane,
                tabLayoutAtom: atoms.workspaceTabLayout,
                mutationCoordinator: atoms.workspaceMutationCoordinator
            )
            let repo = store.addRepo(at: URL(fileURLWithPath: "/tmp/entity-recency-repo"))
            let worktree = try #require(store.repo(repo.id)?.worktrees.first)
            let coordinator = WorkspaceSurfaceCoordinator(
                store: store,
                viewRegistry: ViewRegistry(),
                runtime: SessionRuntime(store: store),
                windowLifecycleStore: atoms.windowLifecycle
            )

            let openedPane = coordinator.openTerminal(for: worktree, in: repo)

            #expect(openedPane != nil)
            let repositoryRecency = try #require(
                atoms.applicationEntityRecency.recentEntities.first {
                    $0.entity == .repository(repositoryStableKey: repo.stableKey)
                }
            )
            let worktreeRecency = try #require(
                atoms.applicationEntityRecency.recentEntities.first {
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
        withTestAtomRegistry { atoms in
            let store = makeStore(atoms: atoms)
            let coordinator = WorkspaceSurfaceCoordinator(
                store: store,
                viewRegistry: ViewRegistry(),
                runtime: SessionRuntime(store: store),
                windowLifecycleStore: atoms.windowLifecycle
            )
            let executor = WorkspaceActionExecutor(coordinator: coordinator, store: store)

            let accepted = executor.execute(.openWorktree(worktreeId: UUID()))

            #expect(!accepted)
            #expect(atoms.applicationEntityRecency.recentEntities.isEmpty)
        }
    }

    @Test("failed split insertion records no application recency")
    func failedSplitInsertion_recordsNothing() throws {
        try withTestAtomRegistry { atoms in
            let store = makeStore(atoms: atoms)
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
                windowLifecycleStore: atoms.windowLifecycle
            )
            let executor = WorkspaceActionExecutor(coordinator: coordinator, store: store)

            let accepted = executor.execute(.openWorktreeInPane(worktreeId: worktree.id))

            #expect(accepted)
            #expect(store.panes.count == 1)
            #expect(atoms.applicationEntityRecency.recentEntities.isEmpty)
        }
    }

    private func makeStore(atoms: AtomRegistry) -> WorkspaceStore {
        WorkspaceStore(
            identityAtom: atoms.workspaceIdentity,
            windowMemoryAtom: atoms.workspaceWindowMemory,
            repositoryTopologyAtom: atoms.workspaceRepositoryTopology,
            paneAtom: atoms.workspacePane,
            tabLayoutAtom: atoms.workspaceTabLayout,
            mutationCoordinator: atoms.workspaceMutationCoordinator
        )
    }
}
