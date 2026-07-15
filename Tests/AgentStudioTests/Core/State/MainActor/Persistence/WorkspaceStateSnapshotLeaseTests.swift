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
        let openResult = openParticipant(
            participant,
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
        let firstOpen = openParticipant(participant, lease: firstLease, orderedBaseKeys: [key])
        let secondOpen = openParticipant(participant, lease: secondLease, orderedBaseKeys: [key])
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
        #expect(openParticipant(participant, lease: lease, orderedBaseKeys: [key]) == .opened(baseMembershipCount: 1))

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
        let firstRead = participant.readBaseValue(
            lease: lease,
            key: key,
            currentValue: .value("latest")
        )
        let secondRead = participant.readBaseValue(
            lease: lease,
            key: key,
            currentValue: .value("newest")
        )
        let retainedBeforeCopy = participant.diagnostics(for: lease)
        let markResult = participant.markBaseValueCopied(
            lease: lease,
            key: key,
            pageID: .make()
        )

        // Assert
        #expect(firstMutation == .retainedFirstBaseValue)
        #expect(secondMutation == .baseValueAlreadyRetained)
        #expect(firstRead == .read(.value("base")))
        #expect(secondRead == .read(.value("base")))
        #expect(
            retainedBeforeCopy
                == .diagnostics(
                    .init(baseMembershipCount: 1, copiedBaseValueCount: 0, retainedBaseValueCount: 1)
                ))
        #expect(markResult == .markedCopied)
        #expect(
            participant.diagnostics(for: lease)
                == .diagnostics(
                    .init(baseMembershipCount: 1, copiedBaseValueCount: 1, retainedBaseValueCount: 0)
                ))
    }

    @Test("removed and re-added base key reads its retained original value")
    func removedAndReaddedBaseKeyReadsItsRetainedOriginalValue() {
        // Arrange
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let lease = WorkspaceStateSnapshotLease.open(
            pagerIdentity: .make(),
            revisionOwner: revisionOwner
        )
        let key = UUIDv7.generate()
        let participant = WorkspaceStateSnapshotKeyedParticipant<UUID, String>()
        #expect(openParticipant(participant, lease: lease, orderedBaseKeys: [key]) == .opened(baseMembershipCount: 1))

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
        let baseRead = participant.readBaseValue(
            lease: lease,
            key: key,
            currentValue: .absent
        )

        // Assert
        #expect(removal == .retainedFirstBaseValue)
        #expect(readdition == .baseValueAlreadyRetained)
        #expect(baseRead == .read(.value("base")))
    }

    @Test("copied base key needs no later retention and only the exact page can replay its mark")
    func copiedBaseKeyNeedsNoLaterRetentionAndOnlyExactPageCanReplayMark() {
        // Arrange
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let lease = WorkspaceStateSnapshotLease.open(
            pagerIdentity: .make(),
            revisionOwner: revisionOwner
        )
        let key = UUIDv7.generate()
        let participant = WorkspaceStateSnapshotKeyedParticipant<UUID, String>()
        #expect(openParticipant(participant, lease: lease, orderedBaseKeys: [key]) == .opened(baseMembershipCount: 1))
        let pageID = WorkspaceStateSnapshotPageID.make()
        let differentPageID = WorkspaceStateSnapshotPageID.make()
        #expect(
            participant.readBaseValue(
                lease: lease,
                key: key,
                currentValue: .value("base")
            ) == .read(.value("base"))
        )
        let firstMark = participant.markBaseValueCopied(lease: lease, key: key, pageID: pageID)
        let replayedMark = participant.markBaseValueCopied(lease: lease, key: key, pageID: pageID)
        let differentPageMark = participant.markBaseValueCopied(
            lease: lease,
            key: key,
            pageID: differentPageID
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
        #expect(UUIDv7.isV7(pageID.rawValue))
        #expect(firstMark == .markedCopied)
        #expect(replayedMark == .alreadyMarkedCopied)
        #expect(differentPageMark == .rejected(.baseValueCopiedByDifferentPage))
        #expect(mutation == .baseValueAlreadyCopied)
        #expect(
            participant.diagnostics(for: lease)
                == .diagnostics(
                    .init(baseMembershipCount: 1, copiedBaseValueCount: 1, retainedBaseValueCount: 0)
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
        #expect(openParticipant(participant, lease: lease, orderedBaseKeys: [key]) == .opened(baseMembershipCount: 1))

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
        #expect(openParticipant(participant, lease: lease, orderedBaseKeys: [key]) == .opened(baseMembershipCount: 1))

        // Act
        let mutation = performMutation(
            with: revisionOwner,
            participant: participant,
            lease: lease,
            key: key,
            currentValue: .absent
        )
        let read = participant.readBaseValue(
            lease: lease,
            key: key,
            currentValue: .absent
        )

        // Assert
        #expect(mutation == .rejected(.baseMembershipValueMissing))
        #expect(read == .rejected(.baseMembershipValueMissing))
        #expect(
            participant.diagnostics(for: lease)
                == .diagnostics(
                    .init(baseMembershipCount: 1, copiedBaseValueCount: 0, retainedBaseValueCount: 0)
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
        #expect(openParticipant(participant, lease: lease, orderedBaseKeys: [key]) == .opened(baseMembershipCount: 1))
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
        let openResult = openParticipant(participant, lease: lease, orderedBaseKeys: sourceKeys)
        sourceKeys.append(secondKey)
        let duplicateOpenResult = openParticipant(
            duplicateParticipant,
            lease: duplicateLease,
            orderedBaseKeys: [firstKey, firstKey]
        )

        // Assert
        #expect(openResult == .opened(baseMembershipCount: 1))
        #expect(participant.membership(for: lease) == .membership([firstKey]))
        #expect(duplicateOpenResult == .rejected(.duplicateBaseMembershipKey))
        #expect(duplicateParticipant.diagnostics(for: duplicateLease) == .rejected(.noActiveLease))
    }

    @Test("membership key-count and raw-byte capacity failures install no lease state")
    func membershipCapacityFailuresInstallNoLeaseState() {
        // Arrange
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let keyCountLease = WorkspaceStateSnapshotLease.open(
            pagerIdentity: .make(),
            revisionOwner: revisionOwner
        )
        let byteCountLease = WorkspaceStateSnapshotLease.open(
            pagerIdentity: .make(),
            revisionOwner: revisionOwner
        )
        let firstKey = UUIDv7.generate()
        let secondKey = UUIDv7.generate()
        let keyCountParticipant = WorkspaceStateSnapshotKeyedParticipant<UUID, String>()
        let byteCountParticipant = WorkspaceStateSnapshotKeyedParticipant<UUID, String>()

        // Act
        let keyCountResult = keyCountParticipant.open(
            lease: keyCountLease,
            orderedBaseKeys: [firstKey, secondKey],
            limits: .init(maximumKeyCount: 1, maximumRawKeyBytes: 100),
            rawByteCountForKey: { _ in 1 }
        )
        let byteCountResult = byteCountParticipant.open(
            lease: byteCountLease,
            orderedBaseKeys: [firstKey],
            limits: .init(maximumKeyCount: 1, maximumRawKeyBytes: 4),
            rawByteCountForKey: { _ in 5 }
        )

        // Assert
        #expect(keyCountResult == .rejected(.baseMembershipKeyCountCapacityExceeded))
        #expect(byteCountResult == .rejected(.baseMembershipRawByteCapacityExceeded))
        #expect(keyCountParticipant.diagnostics(for: keyCountLease) == .rejected(.noActiveLease))
        #expect(byteCountParticipant.diagnostics(for: byteCountLease) == .rejected(.noActiveLease))
    }

    @Test("membership raw-byte overflow installs no lease state")
    func membershipRawByteOverflowInstallsNoLeaseState() {
        // Arrange
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let lease = WorkspaceStateSnapshotLease.open(
            pagerIdentity: .make(),
            revisionOwner: revisionOwner
        )
        let firstKey = UUIDv7.generate()
        let secondKey = UUIDv7.generate()
        let participant = WorkspaceStateSnapshotKeyedParticipant<UUID, String>()

        // Act
        let result = participant.open(
            lease: lease,
            orderedBaseKeys: [firstKey, secondKey],
            limits: .init(maximumKeyCount: 2, maximumRawKeyBytes: .max),
            rawByteCountForKey: { key in key == firstKey ? .max : 1 }
        )

        // Assert
        #expect(result == .rejected(.baseMembershipRawByteCountOverflow))
        #expect(participant.diagnostics(for: lease) == .rejected(.noActiveLease))
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
            openParticipant(
                participant,
                lease: lease,
                orderedBaseKeys: [retainedKey, materializedKey]
            ) == .opened(baseMembershipCount: 2)
        )
        #expect(
            participant.readBaseValue(
                lease: lease,
                key: materializedKey,
                currentValue: .value("materialized")
            ) == .read(.value("materialized"))
        )
        #expect(
            participant.markBaseValueCopied(
                lease: lease,
                key: materializedKey,
                pageID: .make()
            ) == .markedCopied
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
                .baseValueAlreadyCopied,
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
        #expect(openParticipant(participant, lease: lease, orderedBaseKeys: [key]) == .opened(baseMembershipCount: 1))
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

    private func openParticipant<Key: Hashable & Sendable, Value: Sendable>(
        _ participant: WorkspaceStateSnapshotKeyedParticipant<Key, Value>,
        lease: WorkspaceStateSnapshotLease,
        orderedBaseKeys: [Key]
    ) -> WorkspaceStateSnapshotParticipantOpenResult {
        participant.open(
            lease: lease,
            orderedBaseKeys: orderedBaseKeys,
            limits: .init(maximumKeyCount: 100, maximumRawKeyBytes: 10_000),
            rawByteCountForKey: { _ in 1 }
        )
    }
}
