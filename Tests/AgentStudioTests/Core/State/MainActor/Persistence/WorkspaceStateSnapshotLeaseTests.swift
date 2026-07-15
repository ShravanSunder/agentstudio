import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct WorkspaceStateSnapshotLeaseTests {
    @Test(
        "lease opening performs constant membership work",
        arguments: [10, 100, 300]
    )
    func leaseOpeningPerformsConstantMembershipWork(keyCount: Int) {
        // Arrange
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let lease = WorkspaceStateSnapshotLease.open(
            pagerIdentity: .make(),
            revisionOwner: revisionOwner
        )
        let participant = WorkspaceStateSnapshotKeyedParticipant<UUID, String>()
        for _ in 0..<keyCount {
            #expect(
                participant.registerInitialKey(
                    UUIDv7.generate(),
                    rawKeyByteCount: 16,
                    limits: .init(maximumKeyCount: 300, maximumRawKeyBytes: 4800)
                ) == .registered
            )
        }
        let diagnosticsBeforeOpen = participant.workDiagnostics()

        // Act
        let openResult = participant.open(
            lease: lease,
            limits: .init(maximumKeyCount: 300, maximumRawKeyBytes: 4800)
        )

        // Assert
        #expect(openResult == .opened(baseMembershipCount: keyCount))
        #expect(
            participant.workDiagnostics()
                == .init(
                    leaseOpenCount: diagnosticsBeforeOpen.leaseOpenCount + 1,
                    leaseOpenSlotInspectionCount: 0,
                    leaseOpenRawKeyByteComputationCount: 0
                )
        )
    }

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
        #expect(participant.baseSlotUpperBound(for: lease) == .success(2))
        #expect(postBaseMutation == .postBaseKeyExcluded)
        #expect(participant.baseSlotUpperBound(for: lease) == .success(2))
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
        let foreignMembership = participant.baseSlotUpperBound(for: secondLease)

        // Assert
        #expect(firstOpen == .opened(baseMembershipCount: 1))
        #expect(secondOpen == .rejected(.activeLeaseExists))
        #expect(foreignMembership == .failure(.foreignLease))
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
        let firstRead = requireInspectedItem(
            participant.inspectBaseSlot(lease: lease, slotCursor: 0) { _ in .value("latest") }
        )
        let secondRead = requireInspectedItem(
            participant.inspectBaseSlot(lease: lease, slotCursor: 0) { _ in .value("newest") }
        )
        let retainedBeforeCopy = participant.diagnostics(for: lease)
        let markResult = participant.markBaseValueCopied(
            lease: lease,
            copyToken: firstRead.copyToken,
            pageID: .make()
        )

        // Assert
        #expect(firstMutation == .retainedFirstBaseValue)
        #expect(secondMutation == .baseValueAlreadyRetained)
        #expect(firstRead.value == "base")
        #expect(secondRead.value == "base")
        #expect(
            retainedBeforeCopy
                == .diagnostics(
                    diagnostics(
                        baseMembershipCount: 1,
                        copiedBaseValueCount: 0,
                        retainedBaseValueCount: 1,
                        physicalSlotCount: 1,
                        reusableSlotCount: 0
                    )
                ))
        #expect(markResult == .markedCopied)
        #expect(
            participant.diagnostics(for: lease)
                == .diagnostics(
                    diagnostics(
                        baseMembershipCount: 1,
                        copiedBaseValueCount: 1,
                        retainedBaseValueCount: 0,
                        physicalSlotCount: 1,
                        reusableSlotCount: 0
                    )
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
        let baseRead = requireInspectedItem(
            participant.inspectBaseSlot(lease: lease, slotCursor: 0) { _ in .absent }
        )

        // Assert
        #expect(removal == .retainedFirstBaseValue)
        #expect(readdition == .baseValueAlreadyRetained)
        #expect(baseRead.value == "base")
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
        let inspected = requireInspectedItem(
            participant.inspectBaseSlot(lease: lease, slotCursor: 0) { _ in .value("base") }
        )
        let firstMark = participant.markBaseValueCopied(lease: lease, copyToken: inspected.copyToken, pageID: pageID)
        let replayedMark = participant.markBaseValueCopied(lease: lease, copyToken: inspected.copyToken, pageID: pageID)
        let differentPageMark = participant.markBaseValueCopied(
            lease: lease,
            copyToken: inspected.copyToken,
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
                    diagnostics(
                        baseMembershipCount: 1,
                        copiedBaseValueCount: 1,
                        retainedBaseValueCount: 0,
                        physicalSlotCount: 1,
                        reusableSlotCount: 0
                    )
                ))
    }

    @Test("base copy tokens cannot cross participant boundaries")
    func baseCopyTokensCannotCrossParticipantBoundaries() {
        // Arrange
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let lease = WorkspaceStateSnapshotLease.open(
            pagerIdentity: .make(),
            revisionOwner: revisionOwner
        )
        let sourceKey = UUIDv7.generate()
        let targetKey = UUIDv7.generate()
        let sourceParticipant = WorkspaceStateSnapshotKeyedParticipant<UUID, String>()
        let targetParticipant = WorkspaceStateSnapshotKeyedParticipant<UUID, String>()
        #expect(
            openParticipant(sourceParticipant, lease: lease, orderedBaseKeys: [sourceKey])
                == .opened(baseMembershipCount: 1)
        )
        #expect(
            openParticipant(targetParticipant, lease: lease, orderedBaseKeys: [targetKey])
                == .opened(baseMembershipCount: 1)
        )
        let sourceInspection = requireInspectedItem(
            sourceParticipant.inspectBaseSlot(lease: lease, slotCursor: 0) { _ in
                .value("source")
            }
        )
        let targetInspection = requireInspectedItem(
            targetParticipant.inspectBaseSlot(lease: lease, slotCursor: 0) { _ in
                .value("target")
            }
        )
        let targetDiagnosticsBeforeRelay = targetParticipant.diagnostics(for: lease)
        let relayedPageID = WorkspaceStateSnapshotPageID.make()
        let legitimatePageID = WorkspaceStateSnapshotPageID.make()

        // Act
        let relayedMark = targetParticipant.markBaseValueCopied(
            lease: lease,
            copyToken: sourceInspection.copyToken,
            pageID: relayedPageID
        )
        let targetDiagnosticsAfterRelay = targetParticipant.diagnostics(for: lease)
        let legitimateMark = targetParticipant.markBaseValueCopied(
            lease: lease,
            copyToken: targetInspection.copyToken,
            pageID: legitimatePageID
        )

        // Assert
        #expect(relayedMark == .rejected(.staleBaseCopyToken))
        #expect(targetDiagnosticsAfterRelay == targetDiagnosticsBeforeRelay)
        #expect(legitimateMark == .markedCopied)
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
        let read = participant.inspectBaseSlot(lease: lease, slotCursor: 0) { _ in .absent }

        // Assert
        #expect(mutation == .rejected(.baseMembershipValueMissing))
        #expect(isRejectedInspection(read, rejection: .baseMembershipValueMissing))
        #expect(
            participant.diagnostics(for: lease)
                == .diagnostics(
                    diagnostics(
                        baseMembershipCount: 1,
                        copiedBaseValueCount: 0,
                        retainedBaseValueCount: 0,
                        physicalSlotCount: 1,
                        reusableSlotCount: 0
                    )
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
                key: key,
                currentValue: .value("base"),
                transaction: preparation.transaction,
                revisionOwner: revisionOwner
            )
            return preparation.commit {
                participant.recordWillChange(
                    key: key,
                    currentValue: .value("base"),
                    transaction: preparation.transaction,
                    revisionOwner: revisionOwner
                )
            }
        }
        let replayResult = participant.recordWillChange(
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
        #expect(participant.baseSlotUpperBound(for: lease) == .success(1))
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
        let bootstrapLimits = WorkspaceStateSnapshotMembershipLimits(
            maximumKeyCount: 2,
            maximumRawKeyBytes: 100
        )
        #expect(
            keyCountParticipant.registerInitialKey(firstKey, rawKeyByteCount: 1, limits: bootstrapLimits) == .registered
        )
        #expect(
            keyCountParticipant.registerInitialKey(secondKey, rawKeyByteCount: 1, limits: bootstrapLimits)
                == .registered)
        #expect(
            byteCountParticipant.registerInitialKey(firstKey, rawKeyByteCount: 5, limits: bootstrapLimits)
                == .registered)
        let keyCountResult = keyCountParticipant.open(
            lease: keyCountLease,
            limits: .init(maximumKeyCount: 1, maximumRawKeyBytes: 100)
        )
        let byteCountResult = byteCountParticipant.open(
            lease: byteCountLease,
            limits: .init(maximumKeyCount: 1, maximumRawKeyBytes: 4)
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
        let limits = WorkspaceStateSnapshotMembershipLimits(
            maximumKeyCount: 2,
            maximumRawKeyBytes: .max
        )
        #expect(participant.registerInitialKey(firstKey, rawKeyByteCount: .max, limits: limits) == .registered)
        let result = participant.registerInitialKey(secondKey, rawKeyByteCount: 1, limits: limits)

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
        let materializedInspection = requireInspectedItem(
            participant.inspectBaseSlot(lease: lease, slotCursor: 1) { _ in .value("materialized") }
        )
        #expect(
            participant.markBaseValueCopied(
                lease: lease,
                copyToken: materializedInspection.copyToken,
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
                    key: retainedKey,
                    currentValue: evaluatedValue("base"),
                    transaction: preparation.transaction,
                    revisionOwner: revisionOwner
                )
                let repeatedRetention = participant.recordWillChange(
                    key: retainedKey,
                    currentValue: evaluatedValue("later"),
                    transaction: preparation.transaction,
                    revisionOwner: revisionOwner
                )
                let materializedMutation = participant.recordWillChange(
                    key: materializedKey,
                    currentValue: evaluatedValue("materialized-later"),
                    transaction: preparation.transaction,
                    revisionOwner: revisionOwner
                )
                let postBaseMutation = participant.recordWillChange(
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
        let cleanupResult = participant.drainCleanup(maximumValues: 1)
        let closedDiagnostics = participant.diagnostics(for: lease)

        // Assert
        #expect(
            closeResult
                == .closed(
                    .init(releasedMembershipCount: 1, releasedBaseValueCount: 1)
                ))
        #expect(closedDiagnostics == .rejected(.noActiveLease))
        #expect(cleanupResult == .drained(releasedValueCount: 1, remainingValueCount: 0))
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

    private func performMembershipMutation<Result>(
        with revisionOwner: WorkspacePersistenceRevisionOwner,
        _ mutation: @escaping (WorkspacePersistenceTransaction) -> Result
    ) throws -> Result {
        try revisionOwner.performSynchronousTransaction { preparation in
            preparation.commit {
                mutation(preparation.transaction)
            }
        }
    }

    private func openParticipant<Key: Hashable & Sendable, Value: Sendable>(
        _ participant: WorkspaceStateSnapshotKeyedParticipant<Key, Value>,
        lease: WorkspaceStateSnapshotLease,
        orderedBaseKeys: [Key]
    ) -> WorkspaceStateSnapshotParticipantOpenResult {
        let limits = WorkspaceStateSnapshotMembershipLimits(
            maximumKeyCount: 100,
            maximumRawKeyBytes: 10_000
        )
        for key in orderedBaseKeys {
            switch participant.registerInitialKey(key, rawKeyByteCount: 1, limits: limits) {
            case .registered:
                break
            case .rejected(.duplicateCurrentKey):
                return .rejected(.duplicateBaseMembershipKey)
            case .rejected(let rejection):
                return .rejected(rejection)
            }
        }
        return participant.open(lease: lease, limits: limits)
    }

    private struct InspectedSnapshotItem<Key: Sendable, Value: Sendable> {
        let key: Key
        let value: Value
        let copyToken: WorkspaceStateSnapshotBaseCopyToken
    }

    private func requireInspectedItem<Key: Sendable, Value: Sendable>(
        _ inspection: WorkspaceStateSnapshotBaseSlotInspection<Key, Value>
    ) -> InspectedSnapshotItem<Key, Value> {
        guard case .item(let key, let value, let copyToken, _) = inspection else {
            Issue.record("expected inspected base item")
            preconditionFailure("expected inspected base item")
        }
        return InspectedSnapshotItem(key: key, value: value, copyToken: copyToken)
    }

    private func isRejectedInspection<Key: Sendable, Value: Sendable>(
        _ inspection: WorkspaceStateSnapshotBaseSlotInspection<Key, Value>,
        rejection: WorkspaceStateSnapshotParticipantRejection
    ) -> Bool {
        guard case .rejected(let actualRejection) = inspection else { return false }
        return actualRejection == rejection
    }

    private func isExhaustedInspection<Key: Sendable, Value: Sendable>(
        _ inspection: WorkspaceStateSnapshotBaseSlotInspection<Key, Value>
    ) -> Bool {
        guard case .exhausted = inspection else { return false }
        return true
    }

    private func isItemInspection<Key: Sendable, Value: Sendable>(
        _ inspection: WorkspaceStateSnapshotBaseSlotInspection<Key, Value>
    ) -> Bool {
        guard case .item = inspection else { return false }
        return true
    }

    private func diagnostics(
        baseMembershipCount: Int,
        copiedBaseValueCount: Int,
        retainedBaseValueCount: Int,
        physicalSlotCount: Int,
        reusableSlotCount: Int
    ) -> WorkspaceStateSnapshotParticipantDiagnostics {
        WorkspaceStateSnapshotParticipantDiagnostics(
            baseMembershipCount: baseMembershipCount,
            copiedBaseValueCount: copiedBaseValueCount,
            retainedBaseValueCount: retainedBaseValueCount,
            physicalSlotCount: physicalSlotCount,
            reusableSlotCount: reusableSlotCount,
            cleanupRetainedValueCount: 0
        )
    }
}
