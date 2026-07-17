import Foundation

/// The exact canonical atom owners participating in workspace persistence.
///
/// This value validates composition identity. It neither constructs atoms nor
/// owns persistence behavior.
@MainActor
struct WorkspacePersistenceAtomOwners {
    let workspaceIdentity: WorkspaceIdentityAtom
    let workspaceWindowMemory: WorkspaceWindowMemoryAtom
    let repositoryTopology: RepositoryTopologyAtom
    let workspacePaneGraph: WorkspacePaneGraphAtom
    let workspaceDrawerCursor: WorkspaceDrawerCursorAtom
    let workspaceTabShell: WorkspaceTabShellAtom
    let workspaceTabCursor: WorkspaceTabCursorAtom
    let workspaceTabGraph: WorkspaceTabGraphAtom
    let workspaceArrangementCursor: WorkspaceArrangementCursorAtom

    init(atomRegistry: AtomRegistry) {
        self.init(
            workspaceIdentity: atomRegistry.workspaceIdentity,
            workspaceWindowMemory: atomRegistry.workspaceWindowMemory,
            repositoryTopology: atomRegistry.workspaceRepositoryTopology,
            workspacePaneGraph: atomRegistry.workspacePaneGraph,
            workspaceDrawerCursor: atomRegistry.workspaceDrawerCursor,
            workspaceTabShell: atomRegistry.workspaceTabShell,
            workspaceTabCursor: atomRegistry.workspaceTabCursor,
            workspaceTabGraph: atomRegistry.workspaceTabGraph,
            workspaceArrangementCursor: atomRegistry.workspaceArrangementCursor
        )
    }

    init(
        workspaceIdentity: WorkspaceIdentityAtom,
        workspaceWindowMemory: WorkspaceWindowMemoryAtom,
        repositoryTopology: RepositoryTopologyAtom,
        workspacePaneGraph: WorkspacePaneGraphAtom,
        workspaceDrawerCursor: WorkspaceDrawerCursorAtom,
        workspaceTabShell: WorkspaceTabShellAtom,
        workspaceTabCursor: WorkspaceTabCursorAtom,
        workspaceTabGraph: WorkspaceTabGraphAtom,
        workspaceArrangementCursor: WorkspaceArrangementCursorAtom
    ) {
        self.workspaceIdentity = workspaceIdentity
        self.workspaceWindowMemory = workspaceWindowMemory
        self.repositoryTopology = repositoryTopology
        self.workspacePaneGraph = workspacePaneGraph
        self.workspaceDrawerCursor = workspaceDrawerCursor
        self.workspaceTabShell = workspaceTabShell
        self.workspaceTabCursor = workspaceTabCursor
        self.workspaceTabGraph = workspaceTabGraph
        self.workspaceArrangementCursor = workspaceArrangementCursor
    }
}

enum WorkspacePersistenceSnapshotPagerState: Equatable, Sendable {
    case unavailableAwaitingDomainParticipantInstallation
}

/// Production composition boundary for workspace persistence participation.
///
/// Construction is intentionally inert: both domains remain preinstall and no
/// participant inventory or pager exists until the later writer-cutover owns
/// those lifecycle transitions.
@MainActor
final class WorkspacePersistenceRuntime {
    let revisionOwner: WorkspacePersistenceRevisionOwner
    let atomOwners: WorkspacePersistenceAtomOwners
    let adapters: WorkspacePersistenceAdapterBundle
    let snapshotParticipantFactory: WorkspacePersistenceSnapshotParticipantFactory
    let preparedCompositionApplier: WorkspacePreparedCompositionApplier
    let preparedTopologyApplier: WorkspacePreparedTopologyApplier
    let mutationCoordinator: WorkspacePersistenceMutationCoordinator
    let paneCreationGateway: WorkspacePaneCreationGateway
    let snapshotPagerState = WorkspacePersistenceSnapshotPagerState
        .unavailableAwaitingDomainParticipantInstallation

    convenience init(atomRegistry: AtomRegistry) {
        self.init(
            revisionOwner: WorkspacePersistenceRevisionOwner(),
            atomOwners: WorkspacePersistenceAtomOwners(atomRegistry: atomRegistry)
        )
    }

    init(
        revisionOwner: WorkspacePersistenceRevisionOwner,
        atomOwners: WorkspacePersistenceAtomOwners
    ) {
        self.revisionOwner = revisionOwner
        self.atomOwners = atomOwners

        let adapters = WorkspacePersistenceAdapterBundle(
            revisionOwner: revisionOwner,
            workspaceIdentityAtom: atomOwners.workspaceIdentity,
            workspaceWindowMemoryAtom: atomOwners.workspaceWindowMemory,
            repositoryTopologyAtom: atomOwners.repositoryTopology,
            workspacePaneGraphAtom: atomOwners.workspacePaneGraph,
            workspaceDrawerCursorAtom: atomOwners.workspaceDrawerCursor,
            workspaceTabShellAtom: atomOwners.workspaceTabShell,
            workspaceTabCursorAtom: atomOwners.workspaceTabCursor,
            workspaceTabGraphAtom: atomOwners.workspaceTabGraph,
            workspaceArrangementCursorAtom: atomOwners.workspaceArrangementCursor
        )
        self.adapters = adapters
        snapshotParticipantFactory = WorkspacePersistenceSnapshotParticipantFactory(adapters: adapters)
        preparedCompositionApplier = WorkspacePreparedCompositionApplier(adapters: adapters)
        preparedTopologyApplier = WorkspacePreparedTopologyApplier(adapters: adapters)
        let mutationCoordinator = WorkspacePersistenceMutationCoordinator(
            revisionOwner: revisionOwner,
            adapters: adapters,
            workspacePaneGraphAtom: atomOwners.workspacePaneGraph,
            workspaceDrawerCursorAtom: atomOwners.workspaceDrawerCursor,
            workspaceTabShellAtom: atomOwners.workspaceTabShell,
            workspaceTabCursorAtom: atomOwners.workspaceTabCursor,
            workspaceTabGraphAtom: atomOwners.workspaceTabGraph,
            workspaceArrangementCursorAtom: atomOwners.workspaceArrangementCursor,
            workspaceWindowMemoryAtom: atomOwners.workspaceWindowMemory
        )
        self.mutationCoordinator = mutationCoordinator
        paneCreationGateway = WorkspacePaneCreationGateway(
            contextBuilder: WorkspacePaneCreationContextBuilder(
                workspacePaneGraphAtom: atomOwners.workspacePaneGraph,
                workspaceTabShellAtom: atomOwners.workspaceTabShell,
                workspaceTabGraphAtom: atomOwners.workspaceTabGraph,
                workspaceArrangementCursorAtom: atomOwners.workspaceArrangementCursor
            ),
            persistenceMutationCoordinator: mutationCoordinator
        )
    }

    func requireExactAtomOwners(_ received: WorkspacePersistenceAtomOwners) {
        precondition(
            atomOwners.workspaceIdentity === received.workspaceIdentity,
            "WorkspaceStore must share the runtime workspace-identity owner"
        )
        precondition(
            atomOwners.workspaceWindowMemory === received.workspaceWindowMemory,
            "WorkspaceStore must share the runtime window-memory owner"
        )
        precondition(
            atomOwners.repositoryTopology === received.repositoryTopology,
            "WorkspaceStore must share the runtime repository-topology owner"
        )
        precondition(
            atomOwners.workspacePaneGraph === received.workspacePaneGraph,
            "WorkspaceStore must share the runtime pane-graph owner"
        )
        precondition(
            atomOwners.workspaceDrawerCursor === received.workspaceDrawerCursor,
            "WorkspaceStore must share the runtime drawer-cursor owner"
        )
        precondition(
            atomOwners.workspaceTabShell === received.workspaceTabShell,
            "WorkspaceStore must share the runtime tab-shell owner"
        )
        precondition(
            atomOwners.workspaceTabCursor === received.workspaceTabCursor,
            "WorkspaceStore must share the runtime tab-cursor owner"
        )
        precondition(
            atomOwners.workspaceTabGraph === received.workspaceTabGraph,
            "WorkspaceStore must share the runtime tab-graph owner"
        )
        precondition(
            atomOwners.workspaceArrangementCursor === received.workspaceArrangementCursor,
            "WorkspaceStore must share the runtime arrangement-cursor owner"
        )
    }
}
