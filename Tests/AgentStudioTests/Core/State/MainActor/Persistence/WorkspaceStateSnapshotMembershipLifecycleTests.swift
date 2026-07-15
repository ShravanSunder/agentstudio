import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct WorkspaceStateSnapshotMembershipLifecycleTests {
    @Test("failed removal retention preserves current membership")
    func failedRemovalRetentionPreservesCurrentMembership() throws {
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
        let removal = try revisionOwner.performSynchronousTransaction { preparation in
            preparation.commit {
                participant.recordRemoved(
                    key: key,
                    currentValue: .absent,
                    transaction: preparation.transaction,
                    revisionOwner: revisionOwner
                )
            }
        }
        let inspection = requireInspectedItem(
            participant.inspectBaseSlot(lease: lease, slotCursor: 0) { _ in .value("base") }
        )

        // Assert
        #expect(removal == .rejected(.baseMembershipValueMissing))
        #expect(inspection.key == key)
        #expect(inspection.value == "base")
        #expect(
            try performMembershipMutation(with: revisionOwner) { transaction in
                participant.recordInserted(
                    key: key,
                    rawKeyByteCount: 1,
                    transaction: transaction,
                    revisionOwner: revisionOwner
                )
            } == .rejected(.duplicateCurrentKey)
        )
    }

    @Test("remove and reinsert emits only the original base incarnation")
    func removeAndReinsertEmitsOnlyOriginalBaseIncarnation() throws {
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
        let removal = try performMembershipMutation(with: revisionOwner) { transaction in
            participant.recordRemoved(
                key: key,
                currentValue: .value("base"),
                transaction: transaction,
                revisionOwner: revisionOwner
            )
        }
        let insertion = try performMembershipMutation(with: revisionOwner) { transaction in
            participant.recordInserted(
                key: key,
                rawKeyByteCount: 1,
                transaction: transaction,
                revisionOwner: revisionOwner
            )
        }
        let baseItem = requireInspectedItem(
            participant.inspectBaseSlot(lease: lease, slotCursor: 0) { _ in .value("reinserted") }
        )
        let afterBase = participant.inspectBaseSlot(lease: lease, slotCursor: 1) { _ in .value("reinserted") }

        // Assert
        #expect(removal == .removed)
        #expect(insertion == .inserted)
        #expect(baseItem.key == key)
        #expect(baseItem.value == "base")
        #expect(isExhaustedInspection(afterBase))
    }

    @Test("post-base insertion never enters fixed membership")
    func postBaseInsertionNeverEntersFixedMembership() throws {
        // Arrange
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let lease = WorkspaceStateSnapshotLease.open(
            pagerIdentity: .make(),
            revisionOwner: revisionOwner
        )
        let participant = WorkspaceStateSnapshotKeyedParticipant<UUID, String>()
        #expect(openParticipant(participant, lease: lease, orderedBaseKeys: []) == .opened(baseMembershipCount: 0))

        // Act
        let insertion = try performMembershipMutation(with: revisionOwner) { transaction in
            participant.recordInserted(
                key: UUIDv7.generate(),
                rawKeyByteCount: 1,
                transaction: transaction,
                revisionOwner: revisionOwner
            )
        }
        let inspection = participant.inspectBaseSlot(lease: lease, slotCursor: 0) { _ in .value("post-base") }

        // Assert
        #expect(insertion == .inserted)
        #expect(isExhaustedInspection(inspection))
    }

    @Test("post-base churn reuses one physical slot")
    func postBaseChurnReusesOnePhysicalSlot() throws {
        // Arrange
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let lease = WorkspaceStateSnapshotLease.open(
            pagerIdentity: .make(),
            revisionOwner: revisionOwner
        )
        let participant = WorkspaceStateSnapshotKeyedParticipant<UUID, String>()
        #expect(openParticipant(participant, lease: lease, orderedBaseKeys: []) == .opened(baseMembershipCount: 0))
        let key = UUIDv7.generate()

        // Act
        for _ in 0..<1000 {
            #expect(
                try performMembershipMutation(with: revisionOwner) { transaction in
                    participant.recordInserted(
                        key: key,
                        rawKeyByteCount: 1,
                        transaction: transaction,
                        revisionOwner: revisionOwner
                    )
                } == .inserted
            )
            #expect(
                try performMembershipMutation(with: revisionOwner) { transaction in
                    participant.recordRemoved(
                        key: key,
                        currentValue: .value("post-base"),
                        transaction: transaction,
                        revisionOwner: revisionOwner
                    )
                } == .removed
            )
        }

        // Assert
        #expect(
            participant.diagnostics(for: lease)
                == .diagnostics(
                    diagnostics(
                        baseMembershipCount: 0,
                        copiedBaseValueCount: 0,
                        retainedBaseValueCount: 0,
                        physicalSlotCount: 1,
                        reusableSlotCount: 1
                    )
                )
        )
    }

    @Test("retired copied token cannot mark a reused slot")
    func retiredCopiedTokenCannotMarkReusedSlot() throws {
        // Arrange
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let lease = WorkspaceStateSnapshotLease.open(
            pagerIdentity: .make(),
            revisionOwner: revisionOwner
        )
        let baseKey = UUIDv7.generate()
        let replacementKey = UUIDv7.generate()
        let participant = WorkspaceStateSnapshotKeyedParticipant<UUID, String>()
        #expect(
            openParticipant(participant, lease: lease, orderedBaseKeys: [baseKey]) == .opened(baseMembershipCount: 1)
        )
        let baseItem = requireInspectedItem(
            participant.inspectBaseSlot(lease: lease, slotCursor: 0) { _ in .value("base") }
        )
        #expect(
            participant.markBaseValueCopied(
                lease: lease,
                copyToken: baseItem.copyToken,
                pageID: .make()
            ) == .markedCopied
        )

        // Act
        #expect(
            try performMembershipMutation(with: revisionOwner) { transaction in
                participant.recordRemoved(
                    key: baseKey,
                    currentValue: .value("base"),
                    transaction: transaction,
                    revisionOwner: revisionOwner
                )
            } == .removed
        )
        #expect(
            try performMembershipMutation(with: revisionOwner) { transaction in
                participant.recordInserted(
                    key: replacementKey,
                    rawKeyByteCount: 1,
                    transaction: transaction,
                    revisionOwner: revisionOwner
                )
            } == .inserted
        )
        let staleMark = participant.markBaseValueCopied(
            lease: lease,
            copyToken: baseItem.copyToken,
            pageID: .make()
        )

        // Assert
        #expect(staleMark == .rejected(.staleBaseCopyToken))
    }

    @Test("copy token from a closed lease cannot mark the same slot in a successor")
    func copyTokenFromClosedLeaseCannotMarkSameSlotInSuccessor() {
        // Arrange
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let firstLease = WorkspaceStateSnapshotLease.open(
            pagerIdentity: .make(),
            revisionOwner: revisionOwner
        )
        let key = UUIDv7.generate()
        let participant = WorkspaceStateSnapshotKeyedParticipant<UUID, String>()
        #expect(
            openParticipant(participant, lease: firstLease, orderedBaseKeys: [key]) == .opened(baseMembershipCount: 1)
        )
        let firstLeaseItem = requireInspectedItem(
            participant.inspectBaseSlot(lease: firstLease, slotCursor: 0) { _ in .value("base") }
        )
        #expect(
            participant.close(lease: firstLease)
                == .closed(.init(releasedMembershipCount: 1, releasedBaseValueCount: 0))
        )
        let secondLease = WorkspaceStateSnapshotLease.open(
            pagerIdentity: .make(),
            revisionOwner: revisionOwner
        )
        #expect(
            participant.open(
                lease: secondLease,
                limits: .init(maximumKeyCount: 100, maximumRawKeyBytes: 10_000)
            ) == .opened(baseMembershipCount: 1)
        )

        // Act
        let staleMark = participant.markBaseValueCopied(
            lease: secondLease,
            copyToken: firstLeaseItem.copyToken,
            pageID: .make()
        )

        // Assert
        #expect(staleMark == .rejected(.staleBaseCopyToken))
        #expect(
            isItemInspection(
                participant.inspectBaseSlot(lease: secondLease, slotCursor: 0) { _ in .value("base") }
            )
        )
    }

    @Test("insertions enforce configured membership capacities")
    func insertionsEnforceConfiguredMembershipCapacities() throws {
        // Arrange
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let lease = WorkspaceStateSnapshotLease.open(
            pagerIdentity: .make(),
            revisionOwner: revisionOwner
        )
        let participant = WorkspaceStateSnapshotKeyedParticipant<UUID, String>()
        let limits = WorkspaceStateSnapshotMembershipLimits(maximumKeyCount: 1, maximumRawKeyBytes: 1)
        #expect(participant.open(lease: lease, limits: limits) == .opened(baseMembershipCount: 0))

        // Act
        let oversized = try performMembershipMutation(with: revisionOwner) { transaction in
            participant.recordInserted(
                key: UUIDv7.generate(),
                rawKeyByteCount: 2,
                transaction: transaction,
                revisionOwner: revisionOwner
            )
        }
        let inserted = try performMembershipMutation(with: revisionOwner) { transaction in
            participant.recordInserted(
                key: UUIDv7.generate(),
                rawKeyByteCount: 1,
                transaction: transaction,
                revisionOwner: revisionOwner
            )
        }
        let overCount = try performMembershipMutation(with: revisionOwner) { transaction in
            participant.recordInserted(
                key: UUIDv7.generate(),
                rawKeyByteCount: 0,
                transaction: transaction,
                revisionOwner: revisionOwner
            )
        }

        // Assert
        #expect(oversized == .rejected(.baseMembershipRawByteCapacityExceeded))
        #expect(inserted == .inserted)
        #expect(overCount == .rejected(.baseMembershipKeyCountCapacityExceeded))
    }

    @Test("cleanup releases retained values in bounded turns", arguments: [10, 100, 300])
    func cleanupReleasesRetainedValuesInBoundedTurns(keyCount: Int) throws {
        // Arrange
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let lease = WorkspaceStateSnapshotLease.open(
            pagerIdentity: .make(),
            revisionOwner: revisionOwner
        )
        let keys = (0..<keyCount).map { _ in UUIDv7.generate() }
        let participant = WorkspaceStateSnapshotKeyedParticipant<UUID, String>()
        let limits = WorkspaceStateSnapshotMembershipLimits(
            maximumKeyCount: 300,
            maximumRawKeyBytes: 4800
        )
        for key in keys {
            #expect(
                participant.registerInitialKey(key, rawKeyByteCount: 16, limits: limits) == .registered
            )
        }
        #expect(participant.open(lease: lease, limits: limits) == .opened(baseMembershipCount: keyCount))
        try revisionOwner.performSynchronousTransaction { preparation in
            preparation.commit {
                for key in keys {
                    #expect(
                        participant.recordWillChange(
                            key: key,
                            currentValue: .value("base"),
                            transaction: preparation.transaction,
                            revisionOwner: revisionOwner
                        ) == .retainedFirstBaseValue
                    )
                }
            }
        }

        // Act
        #expect(
            participant.close(lease: lease)
                == .closed(
                    .init(
                        releasedMembershipCount: keyCount,
                        releasedBaseValueCount: keyCount
                    )
                )
        )
        let successorLease = WorkspaceStateSnapshotLease.open(
            pagerIdentity: .make(),
            revisionOwner: revisionOwner
        )
        #expect(participant.open(lease: successorLease, limits: limits) == .rejected(.cleanupPending))
        var remainingValueCount = keyCount
        while remainingValueCount > 0 {
            guard
                case .drained(let releasedValueCount, let nextRemainingValueCount) =
                    participant.drainCleanup(maximumValues: 7)
            else {
                Issue.record("expected bounded cleanup progress")
                break
            }
            #expect(releasedValueCount > 0)
            #expect(releasedValueCount <= 7)
            #expect(nextRemainingValueCount == remainingValueCount - releasedValueCount)
            remainingValueCount = nextRemainingValueCount
        }

        // Assert
        #expect(participant.drainCleanup(maximumValues: 7) == .complete)
        #expect(participant.open(lease: successorLease, limits: limits) == .opened(baseMembershipCount: keyCount))
    }

    @Test("idle cleanup is complete for every budget")
    func idleCleanupIsCompleteForEveryBudget() {
        // Arrange
        let participant = WorkspaceStateSnapshotKeyedParticipant<UUID, String>()

        // Act
        let zeroBudgetResult = participant.drainCleanup(maximumValues: 0)
        let positiveBudgetResult = participant.drainCleanup(maximumValues: 1)

        // Assert
        #expect(zeroBudgetResult == .complete)
        #expect(positiveBudgetResult == .complete)
    }

    @Test("unread base replacement remains within two times physical membership", arguments: [10, 100, 300])
    func unreadBaseReplacementRemainsWithinTwoTimesPhysicalMembership(keyCount: Int) throws {
        // Arrange
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let lease = WorkspaceStateSnapshotLease.open(
            pagerIdentity: .make(),
            revisionOwner: revisionOwner
        )
        let baseKeys = (0..<keyCount).map { _ in UUIDv7.generate() }
        let replacementKeys = (0..<keyCount).map { _ in UUIDv7.generate() }
        let participant = WorkspaceStateSnapshotKeyedParticipant<UUID, String>()
        let limits = WorkspaceStateSnapshotMembershipLimits(
            maximumKeyCount: UInt64(keyCount),
            maximumRawKeyBytes: UInt64(keyCount * 16)
        )
        for key in baseKeys {
            #expect(
                participant.registerInitialKey(
                    key,
                    rawKeyByteCount: 16,
                    limits: limits
                ) == .registered
            )
        }
        #expect(
            participant.open(lease: lease, limits: limits)
                == .opened(baseMembershipCount: keyCount)
        )

        // Act
        try revisionOwner.performSynchronousTransaction { preparation in
            preparation.commit {
                for key in baseKeys {
                    #expect(
                        participant.recordRemoved(
                            key: key,
                            currentValue: .value("base"),
                            transaction: preparation.transaction,
                            revisionOwner: revisionOwner
                        ) == .removed
                    )
                }
                for key in replacementKeys {
                    #expect(
                        participant.recordInserted(
                            key: key,
                            rawKeyByteCount: 16,
                            transaction: preparation.transaction,
                            revisionOwner: revisionOwner
                        ) == .inserted
                    )
                }
            }
        }
        let activeDiagnostics = participant.diagnostics(for: lease)
        let closeResult = participant.close(lease: lease)
        var cleanupTurnCount = 0
        while participant.drainCleanup(maximumValues: 17) != .complete {
            cleanupTurnCount += 1
        }
        let successorLease = WorkspaceStateSnapshotLease.open(
            pagerIdentity: .make(),
            revisionOwner: revisionOwner
        )
        let successorOpen = participant.open(lease: successorLease, limits: limits)
        let successorDiagnostics = participant.diagnostics(for: successorLease)

        // Assert
        #expect(
            activeDiagnostics
                == .diagnostics(
                    diagnostics(
                        baseMembershipCount: keyCount,
                        copiedBaseValueCount: 0,
                        retainedBaseValueCount: keyCount,
                        physicalSlotCount: keyCount * 2,
                        reusableSlotCount: 0
                    )
                )
        )
        #expect(
            closeResult
                == .closed(
                    .init(
                        releasedMembershipCount: keyCount,
                        releasedBaseValueCount: keyCount
                    )
                )
        )
        #expect(cleanupTurnCount <= (keyCount + 16) / 17)
        #expect(successorOpen == .opened(baseMembershipCount: keyCount))
        #expect(
            successorDiagnostics
                == .diagnostics(
                    diagnostics(
                        baseMembershipCount: keyCount,
                        copiedBaseValueCount: 0,
                        retainedBaseValueCount: 0,
                        physicalSlotCount: keyCount * 2,
                        reusableSlotCount: keyCount
                    )
                )
        )
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
