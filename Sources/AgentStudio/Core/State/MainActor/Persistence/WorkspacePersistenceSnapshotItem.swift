import Foundation

enum WorkspacePersistenceSnapshotParticipantID: CaseIterable, Hashable, Sendable {
    case workspaceIdentity
    case workspaceWindowMemory
    case repositories
    case worktrees
    case watchedPaths
    case unavailableRepositories
    case paneGraphs
    case expandedDrawer
    case tabShells
    case activeTab
    case tabGraphs
    case activeArrangements
    case activePanes
    case activeDrawerChildren
}

enum WorkspacePersistenceSnapshotItemID: Equatable, Hashable, Sendable {
    case workspaceIdentity
    case windowMemory
    case repository(UUID)
    case worktree(UUID)
    case watchedPath(UUID)
    case unavailableRepository(UUID)
    case paneGraph(UUID)
    case expandedDrawer(UUID)
    case tabShell(UUID)
    case activeTab
    case tabGraph(UUID)
    case activeArrangement(tabID: UUID)
    case activePane(arrangementID: UUID)
    case activeDrawerChild(ArrangementDrawerCursorKey)
}

struct WorkspacePersistenceSnapshotWorkspaceIdentity: Equatable, Sendable {
    let workspaceID: UUID
    let workspaceName: String
    let createdAt: Date
}

struct WorkspacePersistenceSnapshotWindowMemory: Equatable, Sendable {
    let sidebarWidth: CGFloat
    let windowFrame: CGRect?
}

struct WorkspacePersistenceSnapshotTabShell: Equatable, Sendable {
    let shell: TabShell
    let sortIndex: Int
}

/// One closed, strictly typed item vocabulary for fixed-revision workspace
/// snapshot pages. An absent owner key is represented by no item, never by an
/// optional payload.
enum WorkspacePersistenceSnapshotItem: Equatable, Sendable {
    case workspaceIdentity(WorkspacePersistenceSnapshotWorkspaceIdentity)
    case windowMemory(WorkspacePersistenceSnapshotWindowMemory)
    case repository(CanonicalRepo)
    case worktree(CanonicalWorktree)
    case watchedPath(WatchedPath)
    case unavailableRepository(UUID)
    case paneGraph(PaneGraphState)
    case expandedDrawer(UUID)
    case tabShell(WorkspacePersistenceSnapshotTabShell)
    case activeTab(UUID)
    case tabGraph(TabGraphState)
    case activeArrangement(tabID: UUID, arrangementID: UUID)
    case activePane(arrangementID: UUID, paneID: UUID)
    case activeDrawerChild(key: ArrangementDrawerCursorKey, childPaneID: UUID)

    var participantID: WorkspacePersistenceSnapshotParticipantID {
        switch self {
        case .workspaceIdentity:
            .workspaceIdentity
        case .windowMemory:
            .workspaceWindowMemory
        case .repository:
            .repositories
        case .worktree:
            .worktrees
        case .watchedPath:
            .watchedPaths
        case .unavailableRepository:
            .unavailableRepositories
        case .paneGraph:
            .paneGraphs
        case .expandedDrawer:
            .expandedDrawer
        case .tabShell:
            .tabShells
        case .activeTab:
            .activeTab
        case .tabGraph:
            .tabGraphs
        case .activeArrangement:
            .activeArrangements
        case .activePane:
            .activePanes
        case .activeDrawerChild:
            .activeDrawerChildren
        }
    }

    var itemID: WorkspacePersistenceSnapshotItemID {
        switch self {
        case .workspaceIdentity:
            .workspaceIdentity
        case .windowMemory:
            .windowMemory
        case .repository(let repository):
            .repository(repository.id)
        case .worktree(let worktree):
            .worktree(worktree.id)
        case .watchedPath(let watchedPath):
            .watchedPath(watchedPath.id)
        case .unavailableRepository(let repositoryID):
            .unavailableRepository(repositoryID)
        case .paneGraph(let paneGraph):
            .paneGraph(paneGraph.id)
        case .expandedDrawer(let drawerID):
            .expandedDrawer(drawerID)
        case .tabShell(let tabShell):
            .tabShell(tabShell.shell.id)
        case .activeTab:
            .activeTab
        case .tabGraph(let tabGraph):
            .tabGraph(tabGraph.tabId)
        case .activeArrangement(let tabID, _):
            .activeArrangement(tabID: tabID)
        case .activePane(let arrangementID, _):
            .activePane(arrangementID: arrangementID)
        case .activeDrawerChild(let key, _):
            .activeDrawerChild(key)
        }
    }
}

extension WorkspacePersistenceSnapshotItem: WorkspaceStateSnapshotIdentifiedItem {
    var snapshotParticipantID: WorkspacePersistenceSnapshotParticipantID {
        participantID
    }

    var snapshotItemID: WorkspacePersistenceSnapshotItemID {
        itemID
    }
}
