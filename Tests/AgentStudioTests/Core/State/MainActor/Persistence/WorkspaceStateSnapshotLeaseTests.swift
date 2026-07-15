import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct WorkspaceStateSnapshotLeaseTests {
    @Test("lease identity is UUIDv7 and membership remains fixed")
    func leaseIdentityIsUUIDv7AndMembershipRemainsFixed() {
        // Arrange
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let lease = WorkspaceStateSnapshotLease.open(
            pagerIdentity: .make(),
            revisionOwner: revisionOwner
        )
        let firstKey = UUIDv7.generate()
        let secondKey = UUIDv7.generate()
        let postBaseKey = UUIDv7.generate()
        let participant = WorkspaceStateSnapshotKeyedParticipant<UUID, String>()

        // Act
        let openResult = participant.open(
            lease: lease,
            orderedBaseKeys: [firstKey, secondKey]
        )
        let postBaseMutation = performMutation(
            with: revisionOwner,
            participant: participant,
            lease: lease,
            key: postBaseKey,
            currentValue: .absent
        )

        // Assert
        #expect(UUIDv7.isV7(lease.leaseID.rawValue))
        #expect(UUIDv7.isV7(lease.pagerIdentity.rawValue))
        #expect(openResult == .opened(baseMembershipCount: 2))
        #expect(participant.membership(for: lease) == .membership([firstKey, secondKey]))
        #expect(postBaseMutation == .postBaseKeyExcluded)
        #expect(participant.membership(for: lease) == .membership([firstKey, secondKey]))
    }

    @Test("only one lease can be active and foreign handles are rejected")
    func onlyOneLeaseCanBeActiveAndForeignHandlesAreRejected() {
        // Arrange
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let firstLease = WorkspaceStateSnapshotLease.open(
            pagerIdentity: .make(),
            revisionOwner: revisionOwner
        )
        let secondLease = WorkspaceStateSnapshotLease.open(
            pagerIdentity: .make(),
            revisionOwner: revisionOwner
        )
        let key = UUIDv7.generate()
        let participant = WorkspaceStateSnapshotKeyedParticipant<UUID, String>()

        // Act
        let firstOpen = participant.open(lease: firstLease, orderedBaseKeys: [key])
        let secondOpen = participant.open(lease: secondLease, orderedBaseKeys: [key])
        let foreignMembership = participant.membership(for: secondLease)

        // Assert
        #expect(firstOpen == .opened(baseMembershipCount: 1))
        #expect(secondOpen == .rejected(.activeLeaseExists))
        #expect(foreignMembership == .rejected(.foreignLease))
    }

    @Test("first pre-change value is retained once across repeated changes")
    func firstPreChangeValueIsRetainedOnceAcrossRepeatedChanges() {
        // Arrange
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let lease = WorkspaceStateSnapshotLease.open(
            pagerIdentity: .make(),
            revisionOwner: revisionOwner
        )
        let key = UUIDv7.generate()
        let participant = WorkspaceStateSnapshotKeyedParticipant<UUID, String>()
        #expect(participant.open(lease: lease, orderedBaseKeys: [key]) == .opened(baseMembershipCount: 1))

        // Act
        let firstMutation = performMutation(
            with: revisionOwner,
            participant: participant,
            lease: lease,
            key: key,
            currentValue: .value("base")
        )
        let secondMutation = performMutation(
            with: revisionOwner,
            participant: participant,
            lease: lease,
            key: key,
            currentValue: .value("intermediate")
        )
        let materialization = participant.materializeBaseValue(
            lease: lease,
            key: key,
            currentValue: .value("latest")
        )

        // Assert
        #expect(firstMutation == .retainedFirstBaseValue)
        #expect(secondMutation == .baseValueAlreadyRetained)
        #expect(materialization == .materialized(.value("base")))
        #expect(
            participant.diagnostics(for: lease)
                == .diagnostics(
                    .init(baseMembershipCount: 1, materializedCount: 1, retainedBaseValueCount: 0)
                ))
    }

    @Test("removed and re-added base key materializes its original value")
    func removedAndReaddedBaseKeyMaterializesItsOriginalValue() {
        // Arrange
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let lease = WorkspaceStateSnapshotLease.open(
            pagerIdentity: .make(),
            revisionOwner: revisionOwner
        )
        let key = UUIDv7.generate()
        let participant = WorkspaceStateSnapshotKeyedParticipant<UUID, String>()
        #expect(participant.open(lease: lease, orderedBaseKeys: [key]) == .opened(baseMembershipCount: 1))

        // Act
        let removal = performMutation(
            with: revisionOwner,
            participant: participant,
            lease: lease,
            key: key,
            currentValue: .value("base")
        )
        let readdition = performMutation(
            with: revisionOwner,
            participant: participant,
            lease: lease,
            key: key,
            currentValue: .absent
        )
        let materialization = participant.materializeBaseValue(
            lease: lease,
            key: key,
            currentValue: .value("readded")
        )

        // Assert
        #expect(removal == .retainedFirstBaseValue)
        #expect(readdition == .baseValueAlreadyRetained)
        #expect(materialization == .materialized(.value("base")))
    }

    @Test("materialized base key needs no later retention")
    func materializedBaseKeyNeedsNoLaterRetention() {
        // Arrange
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let lease = WorkspaceStateSnapshotLease.open(
            pagerIdentity: .make(),
            revisionOwner: revisionOwner
        )
        let key = UUIDv7.generate()
        let participant = WorkspaceStateSnapshotKeyedParticipant<UUID, String>()
        #expect(participant.open(lease: lease, orderedBaseKeys: [key]) == .opened(baseMembershipCount: 1))
        #expect(
            participant.materializeBaseValue(
                lease: lease,
                key: key,
                currentValue: .value("base")
            ) == .materialized(.value("base"))
        )

        // Act
        let mutation = performMutation(
            with: revisionOwner,
            participant: participant,
            lease: lease,
            key: key,
            currentValue: .value("base")
        )

        // Assert
        #expect(mutation == .baseValueAlreadyMaterialized)
        #expect(
            participant.diagnostics(for: lease)
                == .diagnostics(
                    .init(baseMembershipCount: 1, materializedCount: 1, retainedBaseValueCount: 0)
                ))
    }

    @Test("foreign and stale transactions are rejected")
    func foreignAndStaleTransactionsAreRejected() throws {
        // Arrange
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let foreignRevisionOwner = WorkspacePersistenceRevisionOwner()
        var baseTransaction: WorkspacePersistenceTransaction?
        try revisionOwner.performSynchronousTransaction { preparation in
            baseTransaction = preparation.transaction
            return preparation.commit {}
        }
        let lease = WorkspaceStateSnapshotLease.open(
            pagerIdentity: .make(),
            revisionOwner: revisionOwner
        )
        let key = UUIDv7.generate()
        let participant = WorkspaceStateSnapshotKeyedParticipant<UUID, String>()
        #expect(participant.open(lease: lease, orderedBaseKeys: [key]) == .opened(baseMembershipCount: 1))

        // Act
        let staleTransactionResult = participant.recordWillChange(
            lease: lease,
            key: key,
            currentValue: .value("base"),
            transaction: try #require(baseTransaction),
            revisionOwner: revisionOwner
        )
        let foreignTransactionResult = performMutation(
            with: foreignRevisionOwner,
            participant: participant,
            lease: lease,
            key: key,
            currentValue: .value("base")
        )

        // Assert
        #expect(staleTransactionResult == .rejected(.transactionNotActive))
        #expect(foreignTransactionResult == .rejected(.foreignProcessGeneration))
    }

    @Test("base membership cannot retain an absent first value")
    func baseMembershipCannotRetainAnAbsentFirstValue() {
        // Arrange
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let lease = WorkspaceStateSnapshotLease.open(
            pagerIdentity: .make(),
            revisionOwner: revisionOwner
        )
        let key = UUIDv7.generate()
        let participant = WorkspaceStateSnapshotKeyedParticipant<UUID, String>()
        #expect(participant.open(lease: lease, orderedBaseKeys: [key]) == .opened(baseMembershipCount: 1))

        // Act
        let mutation = performMutation(
            with: revisionOwner,
            participant: participant,
            lease: lease,
            key: key,
            currentValue: .absent
        )

        // Assert
        #expect(mutation == .rejected(.baseMembershipValueMissing))
        #expect(
            participant.diagnostics(for: lease)
                == .diagnostics(
                    .init(baseMembershipCount: 1, materializedCount: 0, retainedBaseValueCount: 0)
                ))
    }

    @Test("transaction is accepted only inside its exact commit body")
    func transactionIsAcceptedOnlyInsideItsExactCommitBody() throws {
        // Arrange
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let lease = WorkspaceStateSnapshotLease.open(
            pagerIdentity: .make(),
            revisionOwner: revisionOwner
        )
        let key = UUIDv7.generate()
        let participant = WorkspaceStateSnapshotKeyedParticipant<UUID, String>()
        #expect(participant.open(lease: lease, orderedBaseKeys: [key]) == .opened(baseMembershipCount: 1))
        var capturedTransaction: WorkspacePersistenceTransaction?
        var preparationResult: WorkspaceStateSnapshotMutationResult?

        // Act
        let commitResult = try revisionOwner.performSynchronousTransaction { preparation in
            capturedTransaction = preparation.transaction
            preparationResult = participant.recordWillChange(
                lease: lease,
                key: key,
                currentValue: .value("base"),
                transaction: preparation.transaction,
                revisionOwner: revisionOwner
            )
            return preparation.commit {
                participant.recordWillChange(
                    lease: lease,
                    key: key,
                    currentValue: .value("base"),
                    transaction: preparation.transaction,
                    revisionOwner: revisionOwner
                )
            }
        }
        let replayResult = participant.recordWillChange(
            lease: lease,
            key: key,
            currentValue: .value("later"),
            transaction: try #require(capturedTransaction),
            revisionOwner: revisionOwner
        )

        // Assert
        #expect(preparationResult == .rejected(.transactionNotActive))
        #expect(commitResult == .retainedFirstBaseValue)
        #expect(replayResult == .rejected(.transactionNotActive))
    }

    @Test("membership copy is independent and duplicate keys are rejected")
    func membershipCopyIsIndependentAndDuplicateKeysAreRejected() {
        // Arrange
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let lease = WorkspaceStateSnapshotLease.open(
            pagerIdentity: .make(),
            revisionOwner: revisionOwner
        )
        let duplicateLease = WorkspaceStateSnapshotLease.open(
            pagerIdentity: .make(),
            revisionOwner: revisionOwner
        )
        let firstKey = UUIDv7.generate()
        let secondKey = UUIDv7.generate()
        var sourceKeys = [firstKey]
        let participant = WorkspaceStateSnapshotKeyedParticipant<UUID, String>()
        let duplicateParticipant = WorkspaceStateSnapshotKeyedParticipant<UUID, String>()

        // Act
        let openResult = participant.open(lease: lease, orderedBaseKeys: sourceKeys)
        sourceKeys.append(secondKey)
        let duplicateOpenResult = duplicateParticipant.open(
            lease: duplicateLease,
            orderedBaseKeys: [firstKey, firstKey]
        )

        // Assert
        #expect(openResult == .opened(baseMembershipCount: 1))
        #expect(participant.membership(for: lease) == .membership([firstKey]))
        #expect(duplicateOpenResult == .rejected(.duplicateBaseMembershipKey))
        #expect(duplicateParticipant.diagnostics(for: duplicateLease) == .rejected(.noActiveLease))
    }

    @Test("current value is evaluated only when first base retention needs it")
    func currentValueIsEvaluatedOnlyWhenFirstBaseRetentionNeedsIt() throws {
        // Arrange
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let lease = WorkspaceStateSnapshotLease.open(
            pagerIdentity: .make(),
            revisionOwner: revisionOwner
        )
        let retainedKey = UUIDv7.generate()
        let materializedKey = UUIDv7.generate()
        let postBaseKey = UUIDv7.generate()
        let participant = WorkspaceStateSnapshotKeyedParticipant<UUID, String>()
        #expect(
            participant.open(
                lease: lease,
                orderedBaseKeys: [retainedKey, materializedKey]
            ) == .opened(baseMembershipCount: 2)
        )
        #expect(
            participant.materializeBaseValue(
                lease: lease,
                key: materializedKey,
                currentValue: .value("materialized")
            ) == .materialized(.value("materialized"))
        )
        var evaluationCount = 0

        func evaluatedValue(_ value: String) -> WorkspaceStateSnapshotStoredValue<String> {
            evaluationCount += 1
            return .value(value)
        }

        // Act
        let results = try revisionOwner.performSynchronousTransaction { preparation in
            preparation.commit {
                let firstRetention = participant.recordWillChange(
                    lease: lease,
                    key: retainedKey,
                    currentValue: evaluatedValue("base"),
                    transaction: preparation.transaction,
                    revisionOwner: revisionOwner
                )
                let repeatedRetention = participant.recordWillChange(
                    lease: lease,
                    key: retainedKey,
                    currentValue: evaluatedValue("later"),
                    transaction: preparation.transaction,
                    revisionOwner: revisionOwner
                )
                let materializedMutation = participant.recordWillChange(
                    lease: lease,
                    key: materializedKey,
                    currentValue: evaluatedValue("materialized-later"),
                    transaction: preparation.transaction,
                    revisionOwner: revisionOwner
                )
                let postBaseMutation = participant.recordWillChange(
                    lease: lease,
                    key: postBaseKey,
                    currentValue: evaluatedValue("post-base"),
                    transaction: preparation.transaction,
                    revisionOwner: revisionOwner
                )
                return [firstRetention, repeatedRetention, materializedMutation, postBaseMutation]
            }
        }

        // Assert
        #expect(
            results == [
                .retainedFirstBaseValue,
                .baseValueAlreadyRetained,
                .baseValueAlreadyMaterialized,
                .postBaseKeyExcluded,
            ]
        )
        #expect(evaluationCount == 1)
    }

    @Test("closing releases all membership and retained values")
    func closingReleasesAllMembershipAndRetainedValues() {
        // Arrange
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let lease = WorkspaceStateSnapshotLease.open(
            pagerIdentity: .make(),
            revisionOwner: revisionOwner
        )
        let key = UUIDv7.generate()
        let participant = WorkspaceStateSnapshotKeyedParticipant<UUID, String>()
        #expect(participant.open(lease: lease, orderedBaseKeys: [key]) == .opened(baseMembershipCount: 1))
        #expect(
            performMutation(
                with: revisionOwner,
                participant: participant,
                lease: lease,
                key: key,
                currentValue: .value("base")
            ) == .retainedFirstBaseValue
        )

        // Act
        let closeResult = participant.close(lease: lease)
        let closedDiagnostics = participant.diagnostics(for: lease)

        // Assert
        #expect(
            closeResult
                == .closed(
                    .init(releasedMembershipCount: 1, releasedBaseValueCount: 1)
                ))
        #expect(closedDiagnostics == .rejected(.noActiveLease))
    }

    private func performMutation<Key: Hashable & Sendable, Value: Sendable>(
        with revisionOwner: WorkspacePersistenceRevisionOwner,
        participant: WorkspaceStateSnapshotKeyedParticipant<Key, Value>,
        lease: WorkspaceStateSnapshotLease,
        key: Key,
        currentValue: WorkspaceStateSnapshotStoredValue<Value>
    ) -> WorkspaceStateSnapshotMutationResult {
        do {
            return try revisionOwner.performSynchronousTransaction { preparation in
                preparation.commit {
                    participant.recordWillChange(
                        lease: lease,
                        key: key,
                        currentValue: currentValue,
                        transaction: preparation.transaction,
                        revisionOwner: revisionOwner
                    )
                }
            }
        } catch {
            Issue.record("unexpected transaction failure: \(error)")
            return .rejected(.noActiveLease)
        }
    }
}
