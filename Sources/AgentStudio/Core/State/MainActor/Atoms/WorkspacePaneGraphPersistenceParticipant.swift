import Foundation

enum WorkspacePaneGraphPersistenceOperation: Sendable {
    case insert(PaneGraphState)
    case update(PaneGraphState)
    case remove(UUID)
}

struct WorkspacePaneGraphPersistenceMutation: Sendable {
    let operations: [WorkspacePaneGraphPersistenceOperation]

    init(operations: [WorkspacePaneGraphPersistenceOperation]) {
        precondition(!operations.isEmpty, "pane graph persistence mutation must not be empty")
        self.operations = operations
    }

    static func insert(_ paneState: PaneGraphState) -> Self {
        Self(operations: [.insert(paneState)])
    }

    static func update(_ paneState: PaneGraphState) -> Self {
        Self(operations: [.update(paneState)])
    }

    static func remove(_ paneID: UUID) -> Self {
        Self(operations: [.remove(paneID)])
    }
}

enum WorkspacePaneGraphPersistencePreparationRejection: Equatable, Sendable {
    case paneAlreadyExists(UUID)
    case paneMissing(UUID)
    case participant(WorkspaceSnapshotPreparationRejection)
}

enum WorkspacePaneGraphPersistencePreparationResult {
    case prepared(WorkspacePaneGraphPreparedPersistenceMutation)
    case rejected(WorkspacePaneGraphPersistencePreparationRejection)
}

struct WorkspacePaneGraphParticipantDiagnostics: Equatable, Sendable {
    let currentValueLookupCount: UInt64
    let rawKeyByteCacheLookupCount: UInt64
    let membershipBootstrapPaneCount: UInt64
}

@MainActor
final class WorkspacePaneGraphPreparedPersistenceMutation {
    private enum State {
        case prepared(WorkspacePaneGraphPersistenceMutation)
        case consumed
    }

    fileprivate let transaction: WorkspacePersistenceTransaction
    private let ownerIdentity: ObjectIdentifier
    private var state: State

    fileprivate init(
        mutation: WorkspacePaneGraphPersistenceMutation,
        transaction: WorkspacePersistenceTransaction,
        owner: WorkspacePaneGraphAtom
    ) {
        self.transaction = transaction
        ownerIdentity = ObjectIdentifier(owner)
        state = .prepared(mutation)
    }

    fileprivate func consume(
        owner: WorkspacePaneGraphAtom
    ) -> WorkspacePaneGraphPersistenceMutation {
        precondition(ownerIdentity == ObjectIdentifier(owner), "prepared pane mutation belongs to a different owner")
        guard case .prepared(let mutation) = state else {
            preconditionFailure("prepared pane mutation was consumed more than once")
        }
        state = .consumed
        return mutation
    }
}

extension WorkspacePaneGraphAtom {
    func makePersistenceSnapshotParticipant(
        membershipLimits: WorkspaceStateSnapshotMembershipLimits,
        estimatedByteCount: @escaping @MainActor (PaneGraphState) -> Int
    ) -> SnapshotPagerParticipantConstructionResult<
        WorkspacePersistenceSnapshotParticipantID,
        WorkspacePersistenceSnapshotItem
    > {
        persistenceMembershipBootstrapPaneCount = UInt64(paneStates.count)
        return WorkspaceStateSnapshotPagerParticipant<
            WorkspacePersistenceSnapshotParticipantID,
            WorkspacePersistenceSnapshotItem
        >.typed(
            participantID: .paneGraphs,
            keyedParticipant: paneGraphPersistenceParticipant,
            membershipLimits: membershipLimits,
            orderedBaseKeys: { [self] in Array(paneStates.keys) },
            currentValue: { [self] paneID in
                incrementPersistenceDiagnostic(&persistenceCurrentValueLookupCount)
                return paneStates[paneID].map(WorkspaceStateSnapshotStoredValue.value) ?? .absent
            },
            projection: .init(
                itemIDForKey: { .paneGraph($0) },
                projectItem: { _, paneState in
                    WorkspaceStateSnapshotPagerTypedItem(
                        item: .paneGraph(paneState),
                        estimatedByteCount: estimatedByteCount(paneState)
                    )
                }
            ),
            rawKeyByteCount: { [self] paneID in
                incrementPersistenceDiagnostic(&persistenceRawKeyByteCacheLookupCount)
                guard let rawKeyByteCount = paneRawKeyByteCounts[paneID] else {
                    preconditionFailure("canonical pane key is missing retained raw-key metadata")
                }
                return rawKeyByteCount
            }
        )
    }

    func preparePersistenceMutation(
        _ mutation: WorkspacePaneGraphPersistenceMutation,
        for preparation: WorkspacePersistenceTransactionPreparation,
        revisionOwner: WorkspacePersistenceRevisionOwner
    ) -> WorkspacePaneGraphPersistencePreparationResult {
        var projectedPaneStateByID: [UUID: ProjectedPaneState] = [:]
        var participantMutations: [WorkspaceStateSnapshotParticipantMutation<UUID, PaneGraphState>] = []
        participantMutations.reserveCapacity(mutation.operations.count)
        for operation in mutation.operations {
            switch operation {
            case .insert(let paneState):
                guard projectedPaneState(for: paneState.id, overlay: projectedPaneStateByID) == nil else {
                    return .rejected(.paneAlreadyExists(paneState.id))
                }
                participantMutations.append(
                    .insert(
                        WorkspaceStateSnapshotMembershipInsertion(
                            key: paneState.id,
                            rawKeyByteCount: Self.persistenceRawKeyByteCount
                        )
                    )
                )
                projectedPaneStateByID[paneState.id] = .present(paneState)
            case .update(let paneState):
                guard let currentPaneState = projectedPaneState(for: paneState.id, overlay: projectedPaneStateByID)
                else {
                    return .rejected(.paneMissing(paneState.id))
                }
                participantMutations.append(
                    .replaceValue(
                        key: paneState.id,
                        currentValue: .value(currentPaneState)
                    )
                )
                projectedPaneStateByID[paneState.id] = .present(paneState)
            case .remove(let paneID):
                guard let currentPaneState = projectedPaneState(for: paneID, overlay: projectedPaneStateByID) else {
                    return .rejected(.paneMissing(paneID))
                }
                participantMutations.append(
                    .remove(
                        WorkspaceStateSnapshotMembershipRemoval(
                            key: paneID,
                            currentValue: .value(currentPaneState)
                        )
                    )
                )
                projectedPaneStateByID[paneID] = .absent
            }
        }

        switch paneGraphPersistenceParticipant.prepare(
            participantMutations,
            for: preparation,
            revisionOwner: revisionOwner
        ) {
        case .prepared:
            return .prepared(
                WorkspacePaneGraphPreparedPersistenceMutation(
                    mutation: mutation,
                    transaction: preparation.transaction,
                    owner: self
                )
            )
        case .rejected(let rejection):
            return .rejected(.participant(rejection))
        }
    }

    func applyPreparedPersistenceMutation(
        _ preparedMutation: WorkspacePaneGraphPreparedPersistenceMutation,
        revisionOwner: WorkspacePersistenceRevisionOwner
    ) {
        precondition(
            revisionOwner.validateActiveCommit(preparedMutation.transaction) == .active,
            "prepared pane mutation requires its exact active outer transaction"
        )
        let mutation = preparedMutation.consume(owner: self)
        for operation in mutation.operations {
            switch operation {
            case .insert(let paneState):
                precondition(paneStates[paneState.id] == nil, "prepared pane insertion canonical key changed")
                setCanonicalPaneState(paneState)
            case .update(let paneState):
                precondition(paneStates[paneState.id] != nil, "prepared pane update canonical key disappeared")
                setCanonicalPaneState(paneState)
            case .remove(let paneID):
                precondition(paneStates[paneID] != nil, "prepared pane removal canonical key disappeared")
                removeCanonicalPaneState(for: paneID)
            }
        }
    }

    func persistencePreparationDiagnostics() -> WorkspaceSnapshotPreparationDiagnostics {
        paneGraphPersistenceParticipant.preparationDiagnostics()
    }

    func persistenceParticipantDiagnostics() -> WorkspacePaneGraphParticipantDiagnostics {
        WorkspacePaneGraphParticipantDiagnostics(
            currentValueLookupCount: persistenceCurrentValueLookupCount,
            rawKeyByteCacheLookupCount: persistenceRawKeyByteCacheLookupCount,
            membershipBootstrapPaneCount: persistenceMembershipBootstrapPaneCount
        )
    }

    private enum ProjectedPaneState {
        case present(PaneGraphState)
        case absent
    }

    private func projectedPaneState(
        for paneID: UUID,
        overlay: [UUID: ProjectedPaneState]
    ) -> PaneGraphState? {
        guard let projectedState = overlay[paneID] else { return paneStates[paneID] }
        switch projectedState {
        case .present(let paneState): return paneState
        case .absent: return nil
        }
    }
}
