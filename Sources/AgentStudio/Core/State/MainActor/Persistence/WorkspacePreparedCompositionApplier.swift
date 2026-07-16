import Foundation

struct WorkspacePreparedCompositionAcceptance: Equatable, Sendable {
    let revision: WorkspacePersistenceRevision
    let repairReport: WorkspaceTabMembershipRepairReport
    let terminalActivationInput: TerminalActivationInput
}

enum WorkspacePreparedCompositionAdapter: Equatable, Sendable {
    case arrangementCursor
    case drawerCursor
    case identity
    case paneGraph
    case tabCursor
    case tabGraph
    case tabShell
    case windowMemory
}

enum WorkspacePreparedCompositionApplyFailure: Equatable, Sendable {
    case adapterRegistration(
        adapter: WorkspacePreparedCompositionAdapter,
        rejection: WorkspaceParticipantRegistrationRejection
    )
    case preparedInputRejected(adapter: WorkspacePreparedCompositionAdapter)
    case lifecycle(WorkspacePersistenceLifecycleRejection)
    case revisionOwnerReentrantTransaction
}

enum WorkspacePreparedCompositionApplyResult: Equatable, Sendable {
    case accepted(WorkspacePreparedCompositionAcceptance)
    case failed(WorkspacePreparedCompositionApplyFailure)
}

/// MainActor install owner for a previously validated workspace composition.
///
/// This owner has no repository/topology capability and performs no fleet
/// validation. Every participating owner is reserved before the revision owner
/// enters commit, then all replacements install once in the same transaction.
@MainActor
final class WorkspacePreparedCompositionApplier {
    private enum TransactionAbort: Error {
        case failed(WorkspacePreparedCompositionApplyFailure)
    }

    private let revisionOwner: WorkspacePersistenceRevisionOwner
    private let adapters: WorkspacePersistenceAdapterBundle

    init(adapters: WorkspacePersistenceAdapterBundle) {
        revisionOwner = adapters.revisionOwner
        self.adapters = adapters
    }

    func apply(
        _ prepared: PreparedWorkspaceComposition
    ) -> WorkspacePreparedCompositionApplyResult {
        do {
            let accessResult = try adapters.withCompositionPreinstallAccess { token in
                try revisionOwner.performSynchronousTransaction {
                    try prepareCompositionCommit(prepared, token: token, for: $0)
                }
            }
            switch accessResult {
            case .authorized(let acceptance):
                return .accepted(acceptance)
            case .rejected(let rejection):
                return .failed(.lifecycle(rejection))
            }
        } catch {
            switch error {
            case let abort as TransactionAbort:
                switch abort {
                case .failed(let failure):
                    return .failed(failure)
                }
            case WorkspacePersistenceRevisionOwnerError.reentrantTransaction:
                return .failed(.revisionOwnerReentrantTransaction)
            default:
                preconditionFailure("prepared composition transaction emitted an unmodeled error")
            }
        }
    }

    private func prepareCompositionCommit(
        _ prepared: PreparedWorkspaceComposition,
        token: borrowing WorkspaceCompositionPreinstallToken,
        for preparation: WorkspacePersistenceTransactionPreparation
    ) throws -> WorkspacePersistencePreparedMutation<WorkspacePreparedCompositionAcceptance> {
        try requireRegisteredParticipant(
            .identity,
            registration: adapters.workspaceIdentity.registerInitialIdentityReplacement(
                token: token,
                workspaceId: prepared.identity.workspaceID,
                workspaceName: prepared.identity.workspaceName,
                createdAt: prepared.identity.createdAt,
                for: preparation
            )
        )
        try requireRegisteredParticipant(
            .windowMemory,
            registration: adapters.workspaceWindowMemory.registerInitialWindowMemoryReplacement(
                token: token,
                sidebarWidth: prepared.windowMemory.sidebarWidth,
                windowFrame: prepared.windowMemory.windowFrame,
                for: preparation
            )
        )
        try requireRegisteredParticipant(
            .paneGraph,
            registration: adapters.workspacePaneGraph.registerInitialReplacement(
                token: token,
                prepared.paneGraph.replacement,
                for: preparation
            )
        )
        try requireRegisteredParticipant(
            .drawerCursor,
            registration: adapters.workspaceDrawerCursor.registerInitialExpandedDrawerReplacement(
                token: token,
                prepared.expandedDrawerID,
                for: preparation
            )
        )
        try requirePreparedInput(.tabShell) {
            try adapters.workspaceTabShell.registerInitialReplacement(
                token: token,
                prepared.tabShells.shells,
                for: preparation
            )
        }
        try requirePreparedInput(.tabGraph) {
            try adapters.workspaceTabGraph.registerInitialReplacement(
                token: token,
                prepared.tabGraph.states,
                for: preparation
            )
        }
        try requireRegisteredParticipant(
            .tabCursor,
            registration: adapters.workspaceTabCursor.registerInitialActiveTabReplacement(
                token: token,
                prepared.activeTabID,
                availableTabIds: prepared.tabShells.shells.map(\.id),
                for: preparation
            )
        )
        try requirePreparedInput(.arrangementCursor) {
            try adapters.workspaceArrangementCursor.registerInitialReplacement(
                token: token,
                activeArrangementIdsByTabId: prepared.arrangementCursors.activeArrangementIDsByTabID,
                paneCursorsByArrangementId: prepared.arrangementCursors.paneCursorsByArrangementID,
                drawerCursorsByKey: prepared.arrangementCursors.drawerCursorsByKey,
                for: preparation
            )
        }
        return preparation.commit {
            WorkspacePreparedCompositionAcceptance(
                revision: preparation.transaction.proposedRevision,
                repairReport: prepared.repairReport,
                terminalActivationInput: prepared.terminalActivationInput
            )
        }
    }

    private func requireRegisteredParticipant(
        _ adapter: WorkspacePreparedCompositionAdapter,
        registration: WorkspaceParticipantRegistration
    ) throws {
        switch registration {
        case .registered:
            break
        case .rejected(let rejection):
            throw TransactionAbort.failed(
                .adapterRegistration(adapter: adapter, rejection: rejection)
            )
        }
    }

    private func requirePreparedInput(
        _ adapter: WorkspacePreparedCompositionAdapter,
        registration: () throws -> Void
    ) throws {
        do {
            try registration()
        } catch {
            throw TransactionAbort.failed(.preparedInputRejected(adapter: adapter))
        }
    }
}
