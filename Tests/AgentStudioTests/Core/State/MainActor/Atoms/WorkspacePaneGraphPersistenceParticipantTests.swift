import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("Workspace pane graph persistence participant")
struct WorkspacePaneGraphPersistenceParticipantTests {
    private let membershipLimits = WorkspaceStateSnapshotMembershipLimits(
        maximumKeyCount: 20_000,
        maximumRawKeyBytes: 320_000
    )

    @Test("prepared insert update and remove keep canonical state and participant membership aligned")
    func preparedInsertUpdateAndRemoveStayAligned() throws {
        // Arrange
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let atom = WorkspacePaneGraphAtom()
        let original = makePaneGraphState(title: "Original")
        let insertedAlongsideUpdate = makePaneGraphState(title: "Inserted alongside update")
        let participant = requireParticipant(
            atom.makePersistenceSnapshotParticipant(
                membershipLimits: membershipLimits,
                estimatedByteCount: { _ in 1 }
            ))

        // Act
        try performMutation(.insert(original), atom: atom, revisionOwner: revisionOwner)
        var updated = original
        updated.metadata.title = "Updated"
        try performMutation(
            .init(operations: [.update(updated), .insert(insertedAlongsideUpdate)]),
            atom: atom,
            revisionOwner: revisionOwner
        )
        try performMutation(
            .init(operations: [.remove(original.id), .remove(insertedAlongsideUpdate.id)]),
            atom: atom,
            revisionOwner: revisionOwner
        )
        let lease = WorkspaceStateSnapshotLease.open(
            pagerIdentity: .make(),
            revisionOwner: revisionOwner
        )

        // Assert
        #expect(atom.paneState(original.id) == nil)
        #expect(atom.paneState(insertedAlongsideUpdate.id) == nil)
        #expect(participant.open(lease: lease, limits: membershipLimits) == .opened(baseMembershipCount: 0))
        #expect(participant.slotUpperBound(for: lease) == .upperBound(2))
    }

    @Test("active lease retains the fixed base pane across a prepared update")
    func activeLeaseRetainsFixedBaseAcrossUpdate() throws {
        // Arrange
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let atom = WorkspacePaneGraphAtom()
        let original = makePaneGraphState(title: "Fixed base")
        atom.addPane(original.pane(isDrawerExpanded: false))
        let participant = requireParticipant(
            atom.makePersistenceSnapshotParticipant(
                membershipLimits: membershipLimits,
                estimatedByteCount: { _ in 1 }
            ))
        let lease = WorkspaceStateSnapshotLease.open(
            pagerIdentity: .make(),
            revisionOwner: revisionOwner
        )
        #expect(participant.open(lease: lease, limits: membershipLimits) == .opened(baseMembershipCount: 1))
        var updated = original
        updated.metadata.title = "Current"

        // Act
        try performMutation(.update(updated), atom: atom, revisionOwner: revisionOwner)
        let inspection = participant.inspectBaseSlot(lease: lease, slotCursor: 0)

        // Assert
        #expect(atom.paneState(original.id)?.metadata.title == "Current")
        guard case .item(let projectedItem, let expectedItemID, _, _) = inspection else {
            Issue.record("expected retained pane graph item")
            return
        }
        #expect(expectedItemID == .paneGraph(original.id))
        #expect(projectedItem.item == WorkspacePersistenceSnapshotItem.paneGraph(original))
    }

    @Test("failed later preparation cancels pane bookkeeping and leaves canonical state atomic")
    func failedLaterPreparationIsAtomicAndPermitsRetry() throws {
        // Arrange
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let atom = WorkspacePaneGraphAtom()
        let original = makePaneGraphState(title: "Original")
        atom.addPane(original.pane(isDrawerExpanded: false))
        _ = requireParticipant(
            atom.makePersistenceSnapshotParticipant(
                membershipLimits: membershipLimits,
                estimatedByteCount: { _ in 1 }
            ))
        var updated = original
        updated.metadata.title = "Should not commit"
        let laterParticipant = WorkspaceStateSnapshotKeyedParticipant<UUID, String>()
        #expect(
            laterParticipant.configureMembershipLimits(
                .init(maximumKeyCount: 0, maximumRawKeyBytes: 0)
            ) == .configured
        )
        func failAfterSecondPreparation(
            _ preparation: WorkspacePersistenceTransactionPreparation
        ) throws -> WorkspacePersistencePreparedMutation<Bool> {
            let firstPrepared = try requirePrepared(
                atom.preparePersistenceMutation(
                    .update(updated),
                    for: preparation,
                    revisionOwner: revisionOwner
                )
            )
            _ = firstPrepared
            guard
                case .rejected = laterParticipant.prepare(
                    [
                        .insert(
                            .init(
                                key: UUIDv7.generate(),
                                rawKeyByteCount: 1
                            )
                        )
                    ],
                    for: preparation,
                    revisionOwner: revisionOwner
                )
            else {
                throw PanePreparationTestError.expectedRejection
            }
            throw PanePreparationTestError.expectedRejection
        }

        // Act
        #expect(throws: PanePreparationTestError.self) {
            _ = try revisionOwner.performSynchronousTransaction(failAfterSecondPreparation)
        }
        try revisionOwner.performSynchronousTransaction { preparation in
            let prepared = try requirePrepared(
                atom.preparePersistenceMutation(
                    .update(updated),
                    for: preparation,
                    revisionOwner: revisionOwner
                )
            )
            return preparation.commit {
                atom.applyPreparedPersistenceMutation(
                    prepared,
                    revisionOwner: revisionOwner
                )
            }
        }

        // Assert
        #expect(atom.paneState(original.id)?.metadata.title == "Should not commit")
        #expect(revisionOwner.committedRevision.rawValue == 1)
        #expect(
            atom.persistencePreparationDiagnostics()
                == WorkspaceSnapshotPreparationDiagnostics(
                    status: .available,
                    appliedReservationCount: 1,
                    cancelledReservationCount: 1
                )
        )
    }

    @Test("last-key current read performs one keyed lookup without raw-key recomputation")
    func lastKeyCurrentReadIsBounded() {
        // Arrange
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let atom = WorkspacePaneGraphAtom()
        let paneCount = 10_000
        for index in 0..<paneCount {
            let pane = makePaneGraphState(title: "Pane \(index)")
            atom.addPane(pane.pane(isDrawerExpanded: false))
        }
        let participant = requireParticipant(
            atom.makePersistenceSnapshotParticipant(
                membershipLimits: membershipLimits,
                estimatedByteCount: { _ in 1 }
            ))
        let lease = WorkspaceStateSnapshotLease.open(
            pagerIdentity: .make(),
            revisionOwner: revisionOwner
        )
        #expect(
            participant.open(lease: lease, limits: membershipLimits)
                == .opened(baseMembershipCount: paneCount)
        )
        let beforeRead = atom.persistenceParticipantDiagnostics()
        guard case .upperBound(let slotUpperBound) = participant.slotUpperBound(for: lease) else {
            Issue.record("expected pane participant slot upper bound")
            return
        }

        // Act
        let inspection = participant.inspectBaseSlot(
            lease: lease,
            slotCursor: slotUpperBound - 1
        )
        let afterRead = atom.persistenceParticipantDiagnostics()

        // Assert
        guard case .item(let projectedItem, _, _, _) = inspection,
            case .paneGraph(let inspectedPane) = projectedItem.item
        else {
            Issue.record("expected final pane participant item")
            return
        }
        #expect(atom.paneState(inspectedPane.id) != nil)
        #expect(afterRead.currentValueLookupCount - beforeRead.currentValueLookupCount == 1)
        #expect(afterRead.rawKeyByteCacheLookupCount == beforeRead.rawKeyByteCacheLookupCount)
        #expect(afterRead.membershipBootstrapPaneCount == UInt64(paneCount))
    }

    private func performMutation(
        _ mutation: WorkspacePaneGraphPersistenceMutation,
        atom: WorkspacePaneGraphAtom,
        revisionOwner: WorkspacePersistenceRevisionOwner
    ) throws {
        try revisionOwner.performSynchronousTransaction { preparation in
            let prepared = try requirePrepared(
                atom.preparePersistenceMutation(
                    mutation,
                    for: preparation,
                    revisionOwner: revisionOwner
                )
            )
            return preparation.commit {
                atom.applyPreparedPersistenceMutation(
                    prepared,
                    revisionOwner: revisionOwner
                )
            }
        }
    }

    private func requirePrepared(
        _ result: WorkspacePaneGraphPersistencePreparationResult
    ) throws -> WorkspacePaneGraphPreparedPersistenceMutation {
        guard case .prepared(let prepared) = result else {
            throw PanePreparationTestError.expectedPreparedMutation
        }
        return prepared
    }

    private func requireParticipant(
        _ result: SnapshotPagerParticipantConstructionResult<
            WorkspacePersistenceSnapshotParticipantID,
            WorkspacePersistenceSnapshotItem
        >
    ) -> WorkspaceStateSnapshotPagerParticipant<
        WorkspacePersistenceSnapshotParticipantID,
        WorkspacePersistenceSnapshotItem
    > {
        guard case .constructed(let participant) = result else {
            Issue.record("expected pane graph participant construction")
            preconditionFailure("expected pane graph participant construction")
        }
        return participant
    }

    private func makePaneGraphState(title: String) -> PaneGraphState {
        PaneGraphState(
            pane: Pane(
                content: .terminal(TerminalState(provider: .zmx, lifetime: .persistent)),
                metadata: PaneMetadata(title: title)
            )
        )
    }
}

private enum PanePreparationTestError: Error {
    case expectedPreparedMutation
    case expectedRejection
}
