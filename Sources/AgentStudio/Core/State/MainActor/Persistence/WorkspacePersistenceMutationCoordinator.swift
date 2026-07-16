import CoreGraphics
import Foundation

enum WorkspacePersistenceMutationFailure: Equatable, Sendable {
    case arrangementCursorCapture(WorkspaceArrangementCursorPersistenceCaptureError)
    case compositionDomainNotInstalled(phase: WorkspacePersistenceAdapterLifecyclePhase)
    case paneGraphCapture(WorkspacePaneGraphPersistenceCaptureError)
    case paneIdentityMismatch(requestedPaneID: UUID, currentPaneID: UUID)
    case paneMissing(UUID)
    case paneTabApplication(WorkspacePaneTabTransitionApplicationRejection)
    case revisionOwner(WorkspacePersistenceRevisionOwnerError)
    case tabCursorCapture(WorkspaceTabCursorPersistenceCaptureError)
    case tabGraphCapture(WorkspaceTabGraphPersistencePreparationError)
    case tabShellCapture(WorkspaceTabShellPersistencePreparationError)
    case windowMemory(WorkspaceSnapshotPreparationRejection)
}

enum WorkspacePersistenceMutationResult: Equatable, Sendable {
    case changed(revision: WorkspacePersistenceRevision)
    case unchanged(revision: WorkspacePersistenceRevision)
    case rejected(WorkspacePersistenceMutationFailure)
}

enum WorkspacePaneCreationPersistenceCommitResult: Equatable, Sendable {
    case committed(revision: WorkspacePersistenceRevision)
    case rejected(WorkspacePersistenceMutationFailure)
}

/// Persistence-aware mutation boundary for installed canonical workspace state.
///
/// This coordinator owns no canonical values. It reserves fixed-revision
/// preimages in the long-lived adapters and commits the corresponding atom
/// mutation through the shared revision owner.
@MainActor
final class WorkspacePersistenceMutationCoordinator {
    private let revisionOwner: WorkspacePersistenceRevisionOwner
    private let adapters: WorkspacePersistenceAdapterBundle
    private let workspacePaneTabTransitionApplier: WorkspacePaneTabTransitionApplier
    private let workspacePaneGraphAtom: WorkspacePaneGraphAtom
    private let workspacePaneTransitionApplier: WorkspacePaneTransitionApplier
    private let workspaceTabShellAtom: WorkspaceTabShellAtom
    private let workspaceWindowMemoryAtom: WorkspaceWindowMemoryAtom

    init(
        revisionOwner: WorkspacePersistenceRevisionOwner,
        adapters: WorkspacePersistenceAdapterBundle,
        workspacePaneGraphAtom: WorkspacePaneGraphAtom,
        workspaceTabShellAtom: WorkspaceTabShellAtom,
        workspaceTabGraphAtom: WorkspaceTabGraphAtom,
        workspaceArrangementCursorAtom: WorkspaceArrangementCursorAtom,
        workspaceWindowMemoryAtom: WorkspaceWindowMemoryAtom
    ) {
        self.revisionOwner = revisionOwner
        self.adapters = adapters
        self.workspacePaneGraphAtom = workspacePaneGraphAtom
        workspacePaneTransitionApplier = WorkspacePaneTransitionApplier(
            workspacePaneGraphAtom: workspacePaneGraphAtom
        )
        workspacePaneTabTransitionApplier = WorkspacePaneTabTransitionApplier(
            workspacePaneGraphAtom: workspacePaneGraphAtom,
            workspaceTabTransitionApplier: WorkspaceTabTransitionApplier(
                workspaceTabShellAtom: workspaceTabShellAtom,
                workspaceTabGraphAtom: workspaceTabGraphAtom,
                workspaceArrangementCursorAtom: workspaceArrangementCursorAtom
            )
        )
        self.workspaceTabShellAtom = workspaceTabShellAtom
        self.workspaceWindowMemoryAtom = workspaceWindowMemoryAtom
    }

    func commitPaneCreation(
        _ transition: WorkspacePaneCreationTransition
    ) -> WorkspacePaneCreationPersistenceCommitResult {
        guard case .installed = adapters.compositionLifecyclePhase else {
            return .rejected(
                .compositionDomainNotInstalled(phase: adapters.compositionLifecyclePhase)
            )
        }
        let preparedApplication: WorkspacePreparedPaneTabTransitionApplication
        switch workspacePaneTabTransitionApplier.preflight(
            paneState: transition.paneState,
            tabTransition: transition.tabTransition
        ) {
        case .ready(let preparation):
            preparedApplication = preparation
        case .rejected(let rejection):
            return .rejected(.paneTabApplication(rejection))
        }

        do {
            let committedRevision = try revisionOwner.performSynchronousTransaction { preparation in
                try capturePaneCreationPreimages(
                    transition,
                    for: preparation
                )
                return preparation.commit { [workspacePaneTabTransitionApplier] in
                    workspacePaneTabTransitionApplier.apply(preparedApplication)
                    return preparation.transaction.proposedRevision
                }
            }
            return .committed(revision: committedRevision)
        } catch let error as WorkspacePaneGraphPersistenceCaptureError {
            return .rejected(.paneGraphCapture(error))
        } catch let error as WorkspaceTabShellPersistencePreparationError {
            return .rejected(.tabShellCapture(error))
        } catch let error as WorkspaceTabCursorPersistenceCaptureError {
            return .rejected(.tabCursorCapture(error))
        } catch let error as WorkspaceTabGraphPersistencePreparationError {
            return .rejected(.tabGraphCapture(error))
        } catch let error as WorkspaceArrangementCursorPersistenceCaptureError {
            return .rejected(.arrangementCursorCapture(error))
        } catch let error as WorkspacePersistenceRevisionOwnerError {
            return .rejected(.revisionOwner(error))
        } catch {
            preconditionFailure("pane-creation persistence mutation emitted an unmodeled error")
        }
    }

    func updatePaneTitle(
        _ request: WorkspacePaneTitleUpdateRequest
    ) -> WorkspacePersistenceMutationResult {
        guard case .installed = adapters.compositionLifecyclePhase else {
            return .rejected(
                .compositionDomainNotInstalled(phase: adapters.compositionLifecyclePhase)
            )
        }

        switch WorkspacePaneTitleTransitionPlanner.plan(
            request,
            currentPaneState: workspacePaneGraphAtom.paneState(request.paneID)
        ) {
        case .changed(let transition):
            return performPaneTransition(transition)
        case .unchanged:
            return .unchanged(revision: revisionOwner.committedRevision)
        case .rejected(.paneMissing(let paneID)):
            return .rejected(.paneMissing(paneID))
        case .rejected(.paneIdentityMismatch(let requestedPaneID, let currentPaneID)):
            return .rejected(
                .paneIdentityMismatch(
                    requestedPaneID: requestedPaneID,
                    currentPaneID: currentPaneID
                )
            )
        }
    }

    func setSidebarWidth(_ sidebarWidth: CGFloat) -> WorkspacePersistenceMutationResult {
        guard case .installed = adapters.compositionLifecyclePhase else {
            return .rejected(
                .compositionDomainNotInstalled(phase: adapters.compositionLifecyclePhase)
            )
        }
        guard workspaceWindowMemoryAtom.sidebarWidth != sidebarWidth else {
            return .unchanged(revision: revisionOwner.committedRevision)
        }
        return performWindowMemoryMutation { [workspaceWindowMemoryAtom] in
            workspaceWindowMemoryAtom.setSidebarWidth(sidebarWidth)
        }
    }

    func setWindowFrame(_ windowFrame: CGRect) -> WorkspacePersistenceMutationResult {
        guard case .installed = adapters.compositionLifecyclePhase else {
            return .rejected(
                .compositionDomainNotInstalled(phase: adapters.compositionLifecyclePhase)
            )
        }
        guard workspaceWindowMemoryAtom.windowFrame != windowFrame else {
            return .unchanged(revision: revisionOwner.committedRevision)
        }
        return performWindowMemoryMutation { [workspaceWindowMemoryAtom] in
            workspaceWindowMemoryAtom.setWindowFrame(windowFrame)
        }
    }

    private func performWindowMemoryMutation(
        _ mutate: @escaping @MainActor () -> Void
    ) -> WorkspacePersistenceMutationResult {
        do {
            let committedRevision = try revisionOwner.performSynchronousTransaction { preparation in
                try adapters.workspaceWindowMemory.capturePersistencePreimage(
                    .currentWindowMemory,
                    for: preparation
                )
                return preparation.commit {
                    mutate()
                    return preparation.transaction.proposedRevision
                }
            }
            return .changed(revision: committedRevision)
        } catch let error as WorkspaceWindowMemorySnapshotPreparationError {
            return .rejected(.windowMemory(error.rejection))
        } catch let error as WorkspacePersistenceRevisionOwnerError {
            return .rejected(.revisionOwner(error))
        } catch {
            preconditionFailure("window-memory persistence mutation emitted an unmodeled error")
        }
    }

    private func capturePaneCreationPreimages(
        _ transition: WorkspacePaneCreationTransition,
        for preparation: WorkspacePersistenceTransactionPreparation
    ) throws {
        let tabID = transition.tab.id
        try adapters.workspacePaneGraph.capturePersistencePreimages(
            WorkspacePaneGraphPersistenceCapture(
                operations: [.insertion(transition.paneState.id)]
            ),
            for: preparation
        )
        try adapters.workspaceTabShell.capturePersistencePreimages(
            WorkspaceTabShellPersistenceCapture(
                operations: [.insertion(tabID)]
            ),
            for: preparation
        )
        try adapters.workspaceTabCursor.capturePersistencePreimage(
            workspaceTabShellAtom.activeTabId == nil ? .insertion : .valueChange,
            for: preparation
        )
        try adapters.workspaceTabGraph.capturePersistencePreimages(
            WorkspaceTabGraphPersistenceCapture(
                operations: [.insertion(tabID)]
            ),
            for: preparation
        )

        let activeArrangementCaptures = transition.tabTransition.activeArrangement.persistenceCaptures
        let activePaneCaptures = transition.tabTransition.activePanes.map(\.persistenceCapture)
        let activeDrawerCaptures = transition.tabTransition.activeDrawerChildren.map(\.persistenceCapture)
        try adapters.workspaceArrangementCursor.capturePersistencePreimages(
            WorkspaceArrangementCursorPersistenceCapture(
                activeArrangements: activeArrangementCaptures,
                activePanes: activePaneCaptures,
                activeDrawerChildren: activeDrawerCaptures
            ),
            for: preparation
        )
    }

    private func performPaneTransition(
        _ transition: WorkspacePaneGraphTransition
    ) -> WorkspacePersistenceMutationResult {
        do {
            let committedRevision = try revisionOwner.performSynchronousTransaction { preparation in
                try adapters.workspacePaneGraph.capturePersistencePreimages(
                    WorkspacePaneGraphPersistenceCapture(
                        operations: transition.replacements.map { .valueChange($0.paneID) }
                    ),
                    for: preparation
                )
                return preparation.commit { [workspacePaneTransitionApplier] in
                    workspacePaneTransitionApplier.apply(transition)
                    return preparation.transaction.proposedRevision
                }
            }
            return .changed(revision: committedRevision)
        } catch let error as WorkspacePaneGraphPersistenceCaptureError {
            return .rejected(.paneGraphCapture(error))
        } catch let error as WorkspacePersistenceRevisionOwnerError {
            return .rejected(.revisionOwner(error))
        } catch {
            preconditionFailure("pane persistence mutation emitted an unmodeled error")
        }
    }
}

extension WorkspaceActiveArrangementTransition {
    fileprivate var persistenceCaptures: [WorkspaceActiveArrangementPersistenceCapture] {
        switch self {
        case .insert(let tabID, _):
            [.insertion(tabID: tabID)]
        }
    }
}

extension WorkspaceActivePaneTransition {
    fileprivate var persistenceCapture: WorkspaceActivePanePersistenceCapture {
        switch self {
        case .insert(let arrangementID, _):
            .insertion(arrangementID: arrangementID)
        }
    }
}

extension WorkspaceActiveDrawerChildTransition {
    fileprivate var persistenceCapture: WorkspaceActiveDrawerChildPersistenceCapture {
        switch self {
        case .insert(let key, _):
            .insertion(key)
        }
    }
}
