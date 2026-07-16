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

enum WorkspacePaneGraphReplacementPreparationError: Error, Equatable {
    case ownerRegistration(WorkspaceParticipantRegistrationRejection)
    case snapshotParticipant(WorkspaceSnapshotPreparationRejection)
}

enum WorkspacePaneGraphPersistencePreparationResult {
    case prepared(WorkspacePaneGraphPreparedPersistenceMutation)
    case rejected(WorkspacePaneGraphPersistencePreparationRejection)
}

struct WorkspacePaneGraphParticipantDiagnostics: Equatable, Sendable {
    let currentValueLookupCount: UInt64
    let persistenceCapturePaneLookupCount: UInt64
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
        owner: WorkspacePaneGraphPersistenceAdapter
    ) {
        self.transaction = transaction
        ownerIdentity = ObjectIdentifier(owner)
        state = .prepared(mutation)
    }

    fileprivate func consume(
        owner: WorkspacePaneGraphPersistenceAdapter
    ) -> WorkspacePaneGraphPersistenceMutation {
        precondition(ownerIdentity == ObjectIdentifier(owner), "prepared pane mutation belongs to a different owner")
        guard case .prepared(let mutation) = state else {
            preconditionFailure("prepared pane mutation was consumed more than once")
        }
        state = .consumed
        return mutation
    }
}

@MainActor
final class WorkspacePaneGraphPersistenceAdapter {
    private enum ProjectedPaneState {
        case present(PaneGraphState)
        case absent
    }

    nonisolated static let rawKeyByteCount: UInt64 = 16

    private let atom: WorkspacePaneGraphAtom
    private let revisionOwner: WorkspacePersistenceRevisionOwner
    private let snapshotParticipant = WorkspaceStateSnapshotKeyedParticipant<UUID, PaneGraphState>()
    private let diagnostics = WorkspacePaneGraphParticipantDiagnosticCounter()

    init(atom: WorkspacePaneGraphAtom, revisionOwner: WorkspacePersistenceRevisionOwner) {
        self.atom = atom
        self.revisionOwner = revisionOwner
    }

    func makeSnapshotParticipant(
        membershipLimits: WorkspaceStateSnapshotMembershipLimits,
        estimatedByteCount: @escaping @MainActor (PaneGraphState) -> Int
    ) -> SnapshotPagerParticipantConstructionResult<
        WorkspacePersistenceSnapshotParticipantID,
        WorkspacePersistenceSnapshotItem
    > {
        diagnostics.recordMembershipBootstrap(paneCount: atom.paneStates.count)
        return WorkspaceStateSnapshotPagerParticipant<
            WorkspacePersistenceSnapshotParticipantID,
            WorkspacePersistenceSnapshotItem
        >.typed(
            participantID: .paneGraphs,
            keyedParticipant: snapshotParticipant,
            membershipLimits: membershipLimits,
            orderedBaseKeys: { [atom] in Array(atom.paneStates.keys) },
            currentValue: { [atom, diagnostics] paneID in
                diagnostics.recordCurrentValueLookup()
                return atom.paneState(paneID).map(WorkspaceStateSnapshotStoredValue.value) ?? .absent
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
            rawKeyByteCount: { [diagnostics] _ in
                diagnostics.recordRawKeyByteLookup()
                return Self.rawKeyByteCount
            }
        )
    }

    func registerInitialReplacement(
        token _: borrowing WorkspaceCompositionPreinstallToken,
        _ replacement: WorkspacePaneGraphReplacement,
        for preparation: WorkspacePersistenceTransactionPreparation
    ) -> WorkspaceParticipantRegistration {
        registerPreparedReplacement(
            replacement,
            for: preparation
        )
    }

    func prepareReplacement(
        _ replacement: WorkspacePaneGraphReplacement,
        for preparation: WorkspacePersistenceTransactionPreparation
    ) throws {
        let currentPaneStates = atom.paneStates
        let replacementMutations = Self.makeReplacementMutations(
            current: currentPaneStates,
            replacement: replacement.paneStates
        )
        if !replacementMutations.isEmpty {
            switch snapshotParticipant.prepare(
                replacementMutations,
                for: preparation,
                revisionOwner: revisionOwner
            ) {
            case .prepared:
                break
            case .rejected(let rejection):
                throw WorkspacePaneGraphReplacementPreparationError.snapshotParticipant(rejection)
            }
        }
        switch registerPreparedReplacement(
            replacement,
            for: preparation
        ) {
        case .registered:
            break
        case .rejected(let rejection):
            throw WorkspacePaneGraphReplacementPreparationError.ownerRegistration(rejection)
        }
    }

    private func registerPreparedReplacement(
        _ replacement: WorkspacePaneGraphReplacement,
        for preparation: WorkspacePersistenceTransactionPreparation
    ) -> WorkspaceParticipantRegistration {
        revisionOwner.registerPreparedParticipantMutation(
            participant: self,
            preparation: preparation,
            apply: { [atom, revisionOwner = self.revisionOwner] in
                precondition(
                    revisionOwner.validateActiveCommit(preparation.transaction) == .active,
                    "pane graph replacement requires its exact active transaction"
                )
                atom.replacePaneStates(replacement)
            },
            cancel: {}
        )
    }

    private static func makeReplacementMutations(
        current: [UUID: PaneGraphState],
        replacement: [UUID: PaneGraphState]
    ) -> [WorkspaceStateSnapshotParticipantMutation<UUID, PaneGraphState>] {
        var mutations: [WorkspaceStateSnapshotParticipantMutation<UUID, PaneGraphState>] = []
        mutations.reserveCapacity(current.count + replacement.count)
        for (paneID, currentPaneState) in current where replacement[paneID] == nil {
            mutations.append(.remove(.init(key: paneID, currentValue: .value(currentPaneState))))
        }
        for (paneID, replacementPaneState) in replacement {
            guard let currentPaneState = current[paneID] else {
                mutations.append(.insert(.init(key: paneID, rawKeyByteCount: rawKeyByteCount)))
                continue
            }
            guard currentPaneState != replacementPaneState else { continue }
            mutations.append(.replaceValue(key: paneID, currentValue: .value(currentPaneState)))
        }
        return mutations
    }

    func prepareMutation(
        _ mutation: WorkspacePaneGraphPersistenceMutation,
        for preparation: WorkspacePersistenceTransactionPreparation
    ) -> WorkspacePaneGraphPersistencePreparationResult {
        var projectedPaneStateByID: [UUID: ProjectedPaneState] = [:]
        var participantMutations: [WorkspaceStateSnapshotParticipantMutation<UUID, PaneGraphState>] = []
        participantMutations.reserveCapacity(mutation.operations.count)
        for operation in mutation.operations {
            switch prepareParticipantMutation(operation, overlay: &projectedPaneStateByID) {
            case .prepared(let participantMutation):
                participantMutations.append(participantMutation)
            case .rejected(let rejection):
                return .rejected(rejection)
            }
        }

        switch snapshotParticipant.prepare(
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

    func capturePersistencePreimages(
        _ capture: WorkspacePaneGraphPersistenceCapture,
        for preparation: WorkspacePersistenceTransactionPreparation
    ) throws {
        guard !capture.operations.isEmpty else {
            throw WorkspacePaneGraphPersistenceCaptureError.emptyCapture
        }
        var capturedPaneIDs = Set<UUID>()
        capturedPaneIDs.reserveCapacity(capture.operations.count)
        var participantMutations: [WorkspaceStateSnapshotParticipantMutation<UUID, PaneGraphState>] = []
        participantMutations.reserveCapacity(capture.operations.count)

        for operation in capture.operations {
            let paneID: UUID
            switch operation {
            case .insertion(let id), .valueChange(let id), .removal(let id):
                paneID = id
            }
            guard capturedPaneIDs.insert(paneID).inserted else {
                throw WorkspacePaneGraphPersistenceCaptureError.duplicateOrConflictingPaneID(paneID)
            }
            diagnostics.recordPersistenceCapturePaneLookup()
            switch operation {
            case .insertion:
                guard atom.paneState(paneID) == nil else {
                    throw WorkspacePaneGraphPersistenceCaptureError.insertedPaneAlreadyExists(paneID)
                }
                participantMutations.append(.insert(.init(key: paneID, rawKeyByteCount: Self.rawKeyByteCount)))
            case .valueChange:
                guard let currentPaneState = atom.paneState(paneID) else {
                    throw WorkspacePaneGraphPersistenceCaptureError.existingPaneMissing(paneID)
                }
                participantMutations.append(.replaceValue(key: paneID, currentValue: .value(currentPaneState)))
            case .removal:
                guard let currentPaneState = atom.paneState(paneID) else {
                    throw WorkspacePaneGraphPersistenceCaptureError.existingPaneMissing(paneID)
                }
                participantMutations.append(.remove(.init(key: paneID, currentValue: .value(currentPaneState))))
            }
        }

        switch snapshotParticipant.prepare(
            participantMutations,
            for: preparation,
            revisionOwner: revisionOwner
        ) {
        case .prepared:
            break
        case .rejected(let rejection):
            throw WorkspacePaneGraphPersistenceCaptureError.snapshotPreparation(rejection)
        }
    }

    func applyPreparedMutation(
        _ preparedMutation: WorkspacePaneGraphPreparedPersistenceMutation
    ) {
        precondition(
            revisionOwner.validateActiveCommit(preparedMutation.transaction) == .active,
            "prepared pane mutation requires its exact active outer transaction"
        )
        let mutation = preparedMutation.consume(owner: self)
        for operation in mutation.operations {
            switch operation {
            case .insert(let paneState):
                precondition(atom.paneState(paneState.id) == nil, "prepared pane insertion canonical key changed")
                atom.setCanonicalPaneState(paneState)
            case .update(let paneState):
                precondition(atom.paneState(paneState.id) != nil, "prepared pane update canonical key disappeared")
                atom.setCanonicalPaneState(paneState)
            case .remove(let paneID):
                precondition(atom.paneState(paneID) != nil, "prepared pane removal canonical key disappeared")
                atom.removeCanonicalPaneState(for: paneID)
            }
        }
    }

    func preparationDiagnostics() -> WorkspaceSnapshotPreparationDiagnostics {
        snapshotParticipant.preparationDiagnostics()
    }

    func participantDiagnostics() -> WorkspacePaneGraphParticipantDiagnostics {
        diagnostics.snapshot()
    }

    private func prepareParticipantMutation(
        _ operation: WorkspacePaneGraphPersistenceOperation,
        overlay: inout [UUID: ProjectedPaneState]
    ) -> PreparedParticipantMutationResult {
        switch operation {
        case .insert(let paneState):
            guard projectedPaneState(for: paneState.id, overlay: overlay) == nil else {
                return .rejected(.paneAlreadyExists(paneState.id))
            }
            overlay[paneState.id] = .present(paneState)
            return .prepared(
                .insert(
                    WorkspaceStateSnapshotMembershipInsertion(
                        key: paneState.id,
                        rawKeyByteCount: Self.rawKeyByteCount
                    )
                )
            )
        case .update(let paneState):
            guard let currentPaneState = projectedPaneState(for: paneState.id, overlay: overlay) else {
                return .rejected(.paneMissing(paneState.id))
            }
            overlay[paneState.id] = .present(paneState)
            return .prepared(
                .replaceValue(
                    key: paneState.id,
                    currentValue: .value(currentPaneState)
                )
            )
        case .remove(let paneID):
            guard let currentPaneState = projectedPaneState(for: paneID, overlay: overlay) else {
                return .rejected(.paneMissing(paneID))
            }
            overlay[paneID] = .absent
            return .prepared(
                .remove(
                    WorkspaceStateSnapshotMembershipRemoval(
                        key: paneID,
                        currentValue: .value(currentPaneState)
                    )
                )
            )
        }
    }

    private func projectedPaneState(
        for paneID: UUID,
        overlay: [UUID: ProjectedPaneState]
    ) -> PaneGraphState? {
        guard let projectedState = overlay[paneID] else { return atom.paneState(paneID) }
        switch projectedState {
        case .present(let paneState): return paneState
        case .absent: return nil
        }
    }

    private enum PreparedParticipantMutationResult {
        case prepared(WorkspaceStateSnapshotParticipantMutation<UUID, PaneGraphState>)
        case rejected(WorkspacePaneGraphPersistencePreparationRejection)
    }
}

@MainActor
private final class WorkspacePaneGraphParticipantDiagnosticCounter {
    private var currentValueLookupCount: UInt64 = 0
    private var persistenceCapturePaneLookupCount: UInt64 = 0
    private var rawKeyByteCacheLookupCount: UInt64 = 0
    private var membershipBootstrapPaneCount: UInt64 = 0

    func recordCurrentValueLookup() {
        increment(&currentValueLookupCount)
    }

    func recordRawKeyByteLookup() {
        increment(&rawKeyByteCacheLookupCount)
    }

    func recordPersistenceCapturePaneLookup() {
        increment(&persistenceCapturePaneLookupCount)
    }

    func recordMembershipBootstrap(paneCount: Int) {
        membershipBootstrapPaneCount = UInt64(paneCount)
    }

    func snapshot() -> WorkspacePaneGraphParticipantDiagnostics {
        WorkspacePaneGraphParticipantDiagnostics(
            currentValueLookupCount: currentValueLookupCount,
            persistenceCapturePaneLookupCount: persistenceCapturePaneLookupCount,
            rawKeyByteCacheLookupCount: rawKeyByteCacheLookupCount,
            membershipBootstrapPaneCount: membershipBootstrapPaneCount
        )
    }

    private func increment(_ count: inout UInt64) {
        let increment = count.addingReportingOverflow(1)
        precondition(!increment.overflow, "pane graph persistence diagnostic count exhausted")
        count = increment.partialValue
    }
}
