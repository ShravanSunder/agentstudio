import Foundation
import Testing

@testable import AgentStudio

@Suite("Admission BoundedGatherMailbox metadata custody")
struct AdmissionBoundedGatherMailboxMetadataCustodyTests {
    private let generation = AdmissionGeneration(owner: .filesystemObservation, value: 84)

    @Test(
        "recovery-only invalidation charges metadata until bounded cleanup",
        arguments: [1, 100, 10_000]
    )
    func recoveryOnlyInvalidationChargesMetadataUntilBoundedCleanup(slotCount: Int) {
        // Arrange
        let cleanupEntryQuantum = 17
        let probe = GatherHashProbe()
        let keys = (0..<slotCount).map {
            GatherHashProbeKey(identifier: $0, probe: probe)
        }
        let clock = TestPushClock()
        let mailbox = BoundedGatherMailbox<GatherHashProbeKey, Int>(
            generation: generation,
            declaredKeys: Set(keys),
            limits: GatherMailboxLimits(
                maximumDeclaredKeys: slotCount,
                maximumRetainedContributions: 0,
                maximumRetainedItems: 0,
                maximumRetainedBytes: 0,
                maximumRetainedContributionsPerKey: 0,
                maximumRetainedItemsPerKey: 0,
                maximumRetainedBytesPerKey: 0,
                maximumContributionsPerLease: 1,
                maximumItemsPerLease: 1,
                maximumBytesPerLease: 1,
                cleanupQuantum: .entriesAndBytes(
                    maximumEntries: cleanupEntryQuantum,
                    maximumBytes: cleanupEntryQuantum
                )
            ),
            clock: clock
        )
        for key in keys {
            let result = mailbox.producerPort.offer(
                generation: generation,
                contribution: GatherContribution(
                    key: key,
                    payload: key.identifier,
                    footprint: GatherFootprint(itemCount: 1, byteCount: 1),
                    recoverySignal: .ordinary
                )
            )
            _ = requireContractedRecoveryRevision(requireGenericAdmission(result))
        }
        #expect(mailbox.lifecyclePort.diagnostics.retainedContributionCount == 0)
        #expect(mailbox.lifecyclePort.diagnostics.recoverySlotCount == slotCount)
        clock.advance(by: .seconds(5))
        probe.reset()

        // Act
        let invalidation = mailbox.lifecyclePort.invalidate(generation: generation)
        let afterInvalidation = mailbox.lifecyclePort.diagnostics
        var totalReleasedEntries = 0
        while mailbox.lifecyclePort.diagnostics.cleanupMetadataEntryCount > 0 {
            let before = mailbox.lifecyclePort.diagnostics.cleanupMetadataEntryCount
            guard case .performed(let turn) = mailbox.lifecyclePort.performCleanup(generation: generation)
            else {
                Issue.record("Expected recovery-only metadata cleanup to make bounded progress")
                break
            }
            let after = mailbox.lifecyclePort.diagnostics.cleanupMetadataEntryCount
            let release = requireEntryAndByteRelease(turn)
            #expect(release.entries > 0)
            #expect(release.entries <= cleanupEntryQuantum)
            #expect(release.bytes == 0)
            #expect(before - after == release.entries)
            let expectedWake: AdmissionWakeDirective =
                after > 0 ? .scheduleDrain : .noWake
            #expect(turn.wake == expectedWake)
            totalReleasedEntries += release.entries
        }
        let afterCleanup = mailbox.lifecyclePort.diagnostics

        // Assert
        #expect(invalidation == .applied)
        #expect(afterInvalidation.retainedContributionCount == 0)
        #expect(afterInvalidation.pendingContributionCount == 0)
        #expect(afterInvalidation.leasedContributionCount == 0)
        #expect(afterInvalidation.recoverySlotCount == 0)
        #expect(afterInvalidation.cleanupContributionCount == 0)
        #expect(afterInvalidation.cleanupByteCount == 0)
        #expect(afterInvalidation.cleanupMetadataEntryCount == slotCount)
        #expect(
            afterInvalidation.oldestCleanupAge
                == AdmissionAgeMeasurement.exact(Duration.seconds(5)))
        #expect(afterInvalidation.isQuiescent == false)
        #expect(totalReleasedEntries == slotCount)
        #expect(afterCleanup.cleanupMetadataEntryCount == 0)
        #expect(afterCleanup.oldestCleanupAge == nil)
        #expect(afterCleanup.isQuiescent)
        #expect(mailbox.lifecyclePort.performCleanup(generation: generation) == .empty)
        #expect(probe.operationCount == 0)
    }

    @Test(
        "mixed invalidation releases payload and metadata within one shared quantum",
        arguments: [1, 100, 10_000]
    )
    func mixedInvalidationReleasesPayloadAndMetadataWithinOneSharedQuantum(slotCount: Int) {
        // Arrange
        let cleanupEntryQuantum = 17
        let probe = GatherHashProbe()
        let keys = (0..<slotCount).map {
            GatherHashProbeKey(identifier: $0, probe: probe)
        }
        let recorder = GatherMetadataReleaseRecorder()
        let mailbox = BoundedGatherMailbox<GatherHashProbeKey, GatherMetadataPayload>(
            generation: generation,
            declaredKeys: Set(keys),
            limits: metadataLimits(
                slotCount: slotCount,
                cleanupEntryQuantum: cleanupEntryQuantum
            )
        )
        var weakPayloads: [WeakGatherMetadataPayload] = []
        weakPayloads.reserveCapacity(slotCount)
        for key in keys {
            var payload: GatherMetadataPayload? = GatherMetadataPayload(
                identity: GatherMetadataIdentity(key: key.identifier, version: 1),
                recorder: recorder
            )
            weakPayloads.append(WeakGatherMetadataPayload(payload!))
            let result = mailbox.producerPort.offer(
                generation: generation,
                contribution: GatherContribution(
                    key: key,
                    payload: payload!,
                    footprint: GatherFootprint(itemCount: 1, byteCount: 1),
                    recoverySignal: .authoritativeRecoveryRequired
                )
            )
            _ = requireRetainedRecoveryRevision(requireGenericAdmission(result))
            payload = nil
        }
        let beforeInvalidation = mailbox.lifecyclePort.diagnostics
        probe.reset()

        // Act
        let invalidation = mailbox.lifecyclePort.invalidate(generation: generation)
        let afterInvalidation = mailbox.lifecyclePort.diagnostics
        let releasesAfterInvalidation = recorder.identities
        var totalReleasedEntries = 0
        var totalReleasedBytes = 0
        while true {
            let before = mailbox.lifecyclePort.diagnostics
            let totalBefore = before.cleanupContributionCount + before.cleanupMetadataEntryCount
            guard totalBefore > 0 else { break }
            let releasedBefore = recorder.identities.count
            let weakNilBefore = weakPayloads.lazy.filter { $0.payload == nil }.count
            guard case .performed(let turn) = mailbox.lifecyclePort.performCleanup(generation: generation)
            else {
                Issue.record("Expected mixed cleanup to make bounded progress")
                break
            }
            let after = mailbox.lifecyclePort.diagnostics
            let totalAfter = after.cleanupContributionCount + after.cleanupMetadataEntryCount
            let releasedAfter = recorder.identities.count
            let weakNilAfter = weakPayloads.lazy.filter { $0.payload == nil }.count
            let release = requireEntryAndByteRelease(turn)
            #expect(release.entries > 0)
            #expect(release.entries <= cleanupEntryQuantum)
            #expect(totalBefore - totalAfter == release.entries)
            #expect(releasedAfter - releasedBefore == release.bytes)
            #expect(weakNilAfter - weakNilBefore == release.bytes)
            #expect(release.bytes <= cleanupEntryQuantum)
            totalReleasedEntries += release.entries
            totalReleasedBytes += release.bytes
        }
        let afterCleanup = mailbox.lifecyclePort.diagnostics

        // Assert
        #expect(invalidation == .applied)
        #expect(beforeInvalidation.retainedContributionCount == slotCount)
        #expect(beforeInvalidation.recoverySlotCount == slotCount)
        #expect(afterInvalidation.cleanupContributionCount == slotCount)
        #expect(afterInvalidation.cleanupMetadataEntryCount == slotCount)
        #expect(afterInvalidation.cleanupByteCount == slotCount)
        #expect(afterInvalidation.physicalRetainedContributionCount == slotCount)
        #expect(releasesAfterInvalidation.isEmpty)
        #expect(afterInvalidation.isQuiescent == false)
        #expect(totalReleasedEntries == slotCount * 2)
        #expect(totalReleasedBytes == slotCount)
        #expect(Set(recorder.identities).count == slotCount)
        #expect(weakPayloads.allSatisfy { $0.payload == nil })
        #expect(afterCleanup.cleanupContributionCount == 0)
        #expect(afterCleanup.cleanupMetadataEntryCount == 0)
        #expect(afterCleanup.isQuiescent)
        #expect(probe.operationCount == 0)
    }

    @Test("mixed cleanup remains charged during destructor and owns exclusive authority")
    func mixedCleanupRemainsChargedDuringDestructorAndOwnsExclusiveAuthority() {
        // Arrange
        let probe = GatherHashProbe()
        let key = GatherHashProbeKey(identifier: 0, probe: probe)
        let recorder = GatherMetadataReleaseRecorder()
        let gate = GatherMetadataCleanupGate()
        let mailboxReference = GatherMetadataMailboxReference(generation: generation)
        let resultBox = GatherMetadataCleanupResultBox()
        let mailbox = BoundedGatherMailbox<GatherHashProbeKey, GatherMetadataPayload>(
            generation: generation,
            declaredKeys: [key],
            limits: metadataLimits(slotCount: 1, cleanupEntryQuantum: 2)
        )
        mailboxReference.mailbox = mailbox
        let consumer = mailbox.consumerPort
        let binding = consumer.bindConsumer().binding
        var payload: GatherMetadataPayload? = GatherMetadataPayload(
            identity: GatherMetadataIdentity(key: 0, version: 1),
            recorder: recorder,
            mailboxReference: mailboxReference,
            cleanupGate: gate
        )
        _ = mailbox.producerPort.offer(
            generation: generation,
            contribution: GatherContribution(
                key: key,
                payload: payload!,
                footprint: GatherFootprint(itemCount: 1, byteCount: 1),
                recoverySignal: .authoritativeRecoveryRequired
            )
        )
        let weakPayload = WeakGatherMetadataPayload(payload!)
        payload = nil
        _ = mailbox.lifecyclePort.invalidate(generation: generation)

        // Act
        DispatchQueue(label: "gather-metadata-cleanup-test").async {
            resultBox.store(mailbox.lifecyclePort.performCleanup(generation: self.generation))
            gate.cleanupCompleted.signal()
        }
        guard gate.destructorEntered.wait(timeout: .now() + 5) == .success else {
            Issue.record("Timed out waiting for cleanup destructor barrier")
            gate.releaseDestructor.signal()
            return
        }
        let whileDestroying = mailbox.lifecyclePort.diagnostics
        let concurrentCleanup = mailbox.lifecyclePort.performCleanup(generation: generation)
        let takeDuringCleanup = consumer.takeDrain(binding: binding, generation: generation)
        gate.releaseDestructor.signal()
        guard gate.cleanupCompleted.wait(timeout: .now() + 5) == .success else {
            Issue.record("Timed out waiting for cleanup finalization")
            return
        }
        let afterCleanup = mailbox.lifecyclePort.diagnostics

        // Assert
        #expect(whileDestroying.cleanupContributionCount == 1)
        #expect(whileDestroying.cleanupMetadataEntryCount == 1)
        #expect(whileDestroying.cleanupByteCount == 1)
        #expect(whileDestroying.physicalRetainedContributionCount == 1)
        #expect(whileDestroying.outstandingCleanupTurnCount == 1)
        #expect(whileDestroying.isQuiescent == false)
        #expect(recorder.reentrantResult == .alreadyCleaning)
        #expect(concurrentCleanup == .alreadyCleaning)
        guard case .closed = takeDuringCleanup else {
            Issue.record("Expected invalidated delivery to stay terminal during cleanup")
            return
        }
        #expect(
            resultBox.result
                == .performed(
                    AdmissionCleanupTurn(
                        release: .entriesAndBytes(count: 2, bytes: 1),
                        wake: .noWake
                    )))
        #expect(recorder.identities == [GatherMetadataIdentity(key: 0, version: 1)])
        #expect(weakPayload.payload == nil)
        #expect(afterCleanup.cleanupContributionCount == 0)
        #expect(afterCleanup.cleanupMetadataEntryCount == 0)
        #expect(afterCleanup.outstandingCleanupTurnCount == 0)
        #expect(afterCleanup.isQuiescent)
    }

    private func metadataLimits(
        slotCount: Int,
        cleanupEntryQuantum: Int
    ) -> GatherMailboxLimits {
        GatherMailboxLimits(
            maximumDeclaredKeys: slotCount,
            maximumRetainedContributions: slotCount,
            maximumRetainedItems: slotCount,
            maximumRetainedBytes: slotCount,
            maximumRetainedContributionsPerKey: 1,
            maximumRetainedItemsPerKey: 1,
            maximumRetainedBytesPerKey: 1,
            maximumContributionsPerLease: 1,
            maximumItemsPerLease: 1,
            maximumBytesPerLease: 1,
            cleanupQuantum: .entriesAndBytes(
                maximumEntries: cleanupEntryQuantum,
                maximumBytes: cleanupEntryQuantum
            )
        )
    }
}
