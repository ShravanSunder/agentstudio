import Foundation

struct WorkspacePersistenceInstallationAttemptID: Hashable, Sendable {
    let rawValue: UUID

    fileprivate static func make() -> Self {
        let rawValue = UUIDv7.generate()
        precondition(UUIDv7.isV7(rawValue), "workspace persistence installation attempt must be UUIDv7")
        return Self(rawValue: rawValue)
    }
}

enum WorkspacePersistenceAdapterLifecyclePhase: Equatable, Sendable {
    case preinstall
    case installing(WorkspacePersistenceInstallationAttemptID)
    case installed(WorkspacePersistenceInstallationAttemptID)
    case installationFailed(WorkspacePersistenceInstallationAttemptID)
}

enum WorkspacePersistenceLifecycleRejection: Equatable, Sendable {
    case preinstallAccessUnavailable(phase: WorkspacePersistenceAdapterLifecyclePhase)
    case participantInstallationUnavailable(phase: WorkspacePersistenceAdapterLifecyclePhase)
    case installationAttemptMismatch(
        expectedPhase: WorkspacePersistenceAdapterLifecyclePhase,
        receivedAttemptID: WorkspacePersistenceInstallationAttemptID
    )
}

struct WorkspaceCompositionPreinstallToken: ~Copyable {
    fileprivate init() {}
}

struct WorkspaceTopologyPreinstallToken: ~Copyable {
    fileprivate init() {}
}

enum WorkspacePersistencePreinstallAccessResult<Success> {
    case authorized(Success)
    case rejected(WorkspacePersistenceLifecycleRejection)
}

enum WorkspacePersistenceInstallationStartResult: Equatable, Sendable {
    case started(WorkspacePersistenceInstallationAttemptID)
    case rejected(WorkspacePersistenceLifecycleRejection)
}

enum WorkspacePersistenceInstallationTransitionResult: Equatable, Sendable {
    case completed
    case rejected(WorkspacePersistenceLifecycleRejection)
}

/// Process-generation-scoped persistence participation for canonical workspace state.
///
/// The bundle is constructed once beside the canonical atoms and shared by every
/// pager, persistence coordinator, and prepared applier. Reconstructing an
/// adapter would discard fixed-revision preimage custody, so callers receive the
/// bundle explicitly rather than constructing adapters independently.
@MainActor
final class WorkspacePersistenceAdapterBundle {
    let revisionOwner: WorkspacePersistenceRevisionOwner
    let workspaceIdentity: WorkspaceIdentityPersistenceAdapter
    let workspaceWindowMemory: WorkspaceWindowMemoryPersistenceAdapter
    let repositoryTopology: RepositoryTopologyPersistenceAdapter
    let workspacePaneGraph: WorkspacePaneGraphPersistenceAdapter
    let workspaceDrawerCursor: WorkspaceDrawerCursorPersistenceAdapter
    let workspaceTabShell: WorkspaceTabShellPersistenceAdapter
    let workspaceTabCursor: WorkspaceTabCursorPersistenceAdapter
    let workspaceTabGraph: WorkspaceTabGraphPersistenceAdapter
    let workspaceArrangementCursor: WorkspaceArrangementCursorPersistenceAdapter
    private(set) var compositionLifecyclePhase = WorkspacePersistenceAdapterLifecyclePhase.preinstall
    private(set) var topologyLifecyclePhase = WorkspacePersistenceAdapterLifecyclePhase.preinstall

    init(
        revisionOwner: WorkspacePersistenceRevisionOwner,
        workspaceIdentityAtom: WorkspaceIdentityAtom,
        workspaceWindowMemoryAtom: WorkspaceWindowMemoryAtom,
        repositoryTopologyAtom: RepositoryTopologyAtom,
        workspacePaneGraphAtom: WorkspacePaneGraphAtom,
        workspaceDrawerCursorAtom: WorkspaceDrawerCursorAtom,
        workspaceTabShellAtom: WorkspaceTabShellAtom,
        workspaceTabCursorAtom: WorkspaceTabCursorAtom,
        workspaceTabGraphAtom: WorkspaceTabGraphAtom,
        workspaceArrangementCursorAtom: WorkspaceArrangementCursorAtom
    ) {
        self.revisionOwner = revisionOwner
        workspaceIdentity = WorkspaceIdentityPersistenceAdapter(
            atom: workspaceIdentityAtom,
            revisionOwner: revisionOwner
        )
        workspaceWindowMemory = WorkspaceWindowMemoryPersistenceAdapter(
            atom: workspaceWindowMemoryAtom,
            revisionOwner: revisionOwner
        )
        repositoryTopology = RepositoryTopologyPersistenceAdapter(
            atom: repositoryTopologyAtom,
            revisionOwner: revisionOwner
        )
        workspacePaneGraph = WorkspacePaneGraphPersistenceAdapter(
            atom: workspacePaneGraphAtom,
            revisionOwner: revisionOwner
        )
        workspaceDrawerCursor = WorkspaceDrawerCursorPersistenceAdapter(
            atom: workspaceDrawerCursorAtom,
            revisionOwner: revisionOwner
        )
        workspaceTabShell = WorkspaceTabShellPersistenceAdapter(
            atom: workspaceTabShellAtom,
            revisionOwner: revisionOwner
        )
        workspaceTabCursor = WorkspaceTabCursorPersistenceAdapter(
            atom: workspaceTabCursorAtom,
            revisionOwner: revisionOwner
        )
        workspaceTabGraph = WorkspaceTabGraphPersistenceAdapter(
            atom: workspaceTabGraphAtom,
            revisionOwner: revisionOwner
        )
        workspaceArrangementCursor = WorkspaceArrangementCursorPersistenceAdapter(
            atom: workspaceArrangementCursorAtom,
            revisionOwner: revisionOwner
        )
    }

    func withCompositionPreinstallAccess<Success>(
        _ body: (borrowing WorkspaceCompositionPreinstallToken) throws -> Success
    ) rethrows -> WorkspacePersistencePreinstallAccessResult<Success> {
        guard case .preinstall = compositionLifecyclePhase else {
            return .rejected(.preinstallAccessUnavailable(phase: compositionLifecyclePhase))
        }
        return .authorized(try body(WorkspaceCompositionPreinstallToken()))
    }

    func withTopologyPreinstallAccess<Success>(
        _ body: (borrowing WorkspaceTopologyPreinstallToken) throws -> Success
    ) rethrows -> WorkspacePersistencePreinstallAccessResult<Success> {
        guard case .preinstall = topologyLifecyclePhase else {
            return .rejected(.preinstallAccessUnavailable(phase: topologyLifecyclePhase))
        }
        return .authorized(try body(WorkspaceTopologyPreinstallToken()))
    }

    func beginCompositionParticipantInstallation() -> WorkspacePersistenceInstallationStartResult {
        beginInstallation(phase: &compositionLifecyclePhase)
    }

    func completeCompositionParticipantInstallation(
        _ attemptID: WorkspacePersistenceInstallationAttemptID
    ) -> WorkspacePersistenceInstallationTransitionResult {
        completeInstallation(attemptID, phase: &compositionLifecyclePhase)
    }

    func failCompositionParticipantInstallation(
        _ attemptID: WorkspacePersistenceInstallationAttemptID
    ) -> WorkspacePersistenceInstallationTransitionResult {
        failInstallation(attemptID, phase: &compositionLifecyclePhase)
    }

    func beginTopologyParticipantInstallation() -> WorkspacePersistenceInstallationStartResult {
        beginInstallation(phase: &topologyLifecyclePhase)
    }

    func completeTopologyParticipantInstallation(
        _ attemptID: WorkspacePersistenceInstallationAttemptID
    ) -> WorkspacePersistenceInstallationTransitionResult {
        completeInstallation(attemptID, phase: &topologyLifecyclePhase)
    }

    func failTopologyParticipantInstallation(
        _ attemptID: WorkspacePersistenceInstallationAttemptID
    ) -> WorkspacePersistenceInstallationTransitionResult {
        failInstallation(attemptID, phase: &topologyLifecyclePhase)
    }

    private func beginInstallation(
        phase: inout WorkspacePersistenceAdapterLifecyclePhase
    ) -> WorkspacePersistenceInstallationStartResult {
        guard case .preinstall = phase else {
            return .rejected(.participantInstallationUnavailable(phase: phase))
        }
        let attemptID = WorkspacePersistenceInstallationAttemptID.make()
        phase = .installing(attemptID)
        return .started(attemptID)
    }

    private func completeInstallation(
        _ attemptID: WorkspacePersistenceInstallationAttemptID,
        phase: inout WorkspacePersistenceAdapterLifecyclePhase
    ) -> WorkspacePersistenceInstallationTransitionResult {
        guard phase == .installing(attemptID) else {
            return .rejected(
                .installationAttemptMismatch(
                    expectedPhase: phase,
                    receivedAttemptID: attemptID
                )
            )
        }
        phase = .installed(attemptID)
        return .completed
    }

    private func failInstallation(
        _ attemptID: WorkspacePersistenceInstallationAttemptID,
        phase: inout WorkspacePersistenceAdapterLifecyclePhase
    ) -> WorkspacePersistenceInstallationTransitionResult {
        guard phase == .installing(attemptID) else {
            return .rejected(
                .installationAttemptMismatch(
                    expectedPhase: phase,
                    receivedAttemptID: attemptID
                )
            )
        }
        phase = .installationFailed(attemptID)
        return .completed
    }
}
