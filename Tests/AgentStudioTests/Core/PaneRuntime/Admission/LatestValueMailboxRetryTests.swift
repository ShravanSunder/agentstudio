import Foundation
import Testing

@testable import AgentStudio

@Suite("Admission LatestValueMailbox retry")
struct AdmissionLatestValueMailboxRetryTests {
    private let generation = AdmissionGeneration(owner: .terminalViewport, value: 41)

    @Test("mixed retry preserves per-value custody and revokes the old lease")
    // swiftlint:disable:next function_body_length
    func mixedRetryPreservesPerValueCustodyAndRevokesOldToken() {
        let releaseRecorder = LatestRetryReleaseRecorder()
        let clock = TestPushClock()
        let mailbox = LatestValueMailbox<Int, LatestRetryPayload>(
            generation: generation,
            declaredKeys: [0, 1, 2],
            limits: LatestValueLimits(
                maximumValuesPerLease: 3,
                maximumAuxiliaryRetainedValues: 6,
                cleanupQuantum: AdmissionCleanupQuantum(
                    maximumEntries: 3,
                    maximumBytes: nil
                )
            ),
            clock: clock
        )
        let producer = mailbox.producerPort
        let consumer = mailbox.consumerPort
        let lifecycle = mailbox.lifecyclePort
        let binding = consumer.bindConsumer().binding

        let originalKeyZero = offer(
            producer: producer,
            key: 0,
            version: 0,
            recorder: releaseRecorder,
            expectedReceipt: .admitted
        )
        let originalKeyOne = offer(
            producer: producer,
            key: 1,
            version: 0,
            recorder: releaseRecorder,
            expectedReceipt: .admitted
        )
        let originalKeyTwo = offer(
            producer: producer,
            key: 2,
            version: 0,
            recorder: releaseRecorder,
            expectedReceipt: .admitted
        )
        guard
            let originalLease = takeProjection(
                consumer: consumer,
                binding: binding,
                expectedIdentities: [
                    0: LatestRetryIdentity(key: 0, version: 0),
                    1: LatestRetryIdentity(key: 1, version: 0),
                    2: LatestRetryIdentity(key: 2, version: 0),
                ]
            )
        else { return }
        #expect(
            originalLease.objectIdentifiersByKey == [
                0: originalKeyZero,
                1: originalKeyOne,
                2: originalKeyTwo,
            ]
        )

        _ = offer(
            producer: producer,
            key: 0,
            version: 1,
            recorder: releaseRecorder,
            expectedReceipt: .admitted
        )
        _ = offer(
            producer: producer,
            key: 0,
            version: 2,
            recorder: releaseRecorder,
            expectedReceipt: .replacedPrevious
        )
        _ = offer(
            producer: producer,
            key: 1,
            version: 1,
            recorder: releaseRecorder,
            expectedReceipt: .admitted
        )

        #expect(lifecycle.diagnostics.pendingValueCount == 2)
        #expect(lifecycle.diagnostics.leasedValueCount == 3)
        #expect(lifecycle.diagnostics.cleanupValueCount == 1)
        #expect(lifecycle.diagnostics.physicalRetainedValueCount == 6)
        #expect(releaseRecorder.releasedIdentities.isEmpty)

        let contractedBeforeRetry = lifecycle.diagnostics.admission.contracted
        let retryAcknowledgement = consumer.acknowledge(
            originalLease.token,
            disposition: .retry
        )
        #expect(retryAcknowledgement == .accepted(wake: .scheduleDrain))
        #expect(lifecycle.diagnostics.pendingValueCount == 3)
        #expect(lifecycle.diagnostics.leasedValueCount == 0)
        #expect(lifecycle.diagnostics.cleanupValueCount == 3)
        #expect(lifecycle.diagnostics.physicalRetainedValueCount == 6)
        #expect(
            lifecycle.diagnostics.admission.contracted
                == contractedBeforeRetry + 2
        )
        #expect(releaseRecorder.releasedIdentities.isEmpty)

        let diagnosticsBeforeDuplicateAcknowledgement = lifecycle.diagnostics
        #expect(
            consumer.acknowledge(originalLease.token, disposition: .retry)
                == .invalidToken
        )
        #expect(lifecycle.diagnostics == diagnosticsBeforeDuplicateAcknowledgement)

        let replacementForRetriedKey = offer(
            producer: producer,
            key: 2,
            version: 1,
            recorder: releaseRecorder,
            expectedReceipt: .replacedPrevious
        )
        #expect(replacementForRetriedKey != originalKeyTwo)
        #expect(lifecycle.diagnostics.pendingValueCount == 3)
        #expect(lifecycle.diagnostics.leasedValueCount == 0)
        #expect(lifecycle.diagnostics.cleanupValueCount == 4)
        #expect(lifecycle.diagnostics.physicalRetainedValueCount == 7)
        #expect(releaseRecorder.releasedIdentities.isEmpty)
        #expect(isRetryCleanupRequired(consumer.takeDrain(binding: binding, generation: generation)))

        #expect(
            consumer.performCleanup(generation: generation)
                == .performed(
                    AdmissionCleanupTurn(
                        releasedEntryCount: 3,
                        releasedByteCount: nil,
                        wake: .scheduleDrain
                    )
                )
        )
        #expect(
            releaseRecorder.releasedIdentities == [
                LatestRetryIdentity(key: 0, version: 1),
                LatestRetryIdentity(key: 0, version: 0),
                LatestRetryIdentity(key: 1, version: 0),
            ]
        )
        #expect(
            consumer.performCleanup(generation: generation)
                == .performed(
                    AdmissionCleanupTurn(
                        releasedEntryCount: 1,
                        releasedByteCount: nil,
                        wake: .scheduleDrain
                    )
                )
        )
        #expect(
            releaseRecorder.releasedIdentities == [
                LatestRetryIdentity(key: 0, version: 1),
                LatestRetryIdentity(key: 0, version: 0),
                LatestRetryIdentity(key: 1, version: 0),
                LatestRetryIdentity(key: 2, version: 0),
            ]
        )

        guard
            let finalLease = takeProjection(
                consumer: consumer,
                binding: binding,
                expectedIdentities: [
                    0: LatestRetryIdentity(key: 0, version: 2),
                    1: LatestRetryIdentity(key: 1, version: 1),
                    2: LatestRetryIdentity(key: 2, version: 1),
                ]
            )
        else { return }
        #expect(finalLease.objectIdentifiersByKey[2] == replacementForRetriedKey)
        #expect(lifecycle.diagnostics.pendingValueCount == 0)
        #expect(lifecycle.diagnostics.leasedValueCount == 3)
        #expect(lifecycle.diagnostics.cleanupValueCount == 0)
        #expect(lifecycle.diagnostics.physicalRetainedValueCount == 3)
    }

    private func offer(
        producer: LatestValueProducerPort<Int, LatestRetryPayload>,
        key: Int,
        version: Int,
        recorder: LatestRetryReleaseRecorder,
        expectedReceipt: AdmissionReceipt
    ) -> ObjectIdentifier {
        let payload = LatestRetryPayload(
            identity: LatestRetryIdentity(key: key, version: version),
            recorder: recorder
        )
        let objectIdentifier = ObjectIdentifier(payload)
        let result = producer.offer(
            generation: generation,
            key: key,
            value: payload
        )
        #expect(result.receipt == expectedReceipt)
        return objectIdentifier
    }

    private func takeProjection(
        consumer: LatestValueConsumerPort<Int, LatestRetryPayload>,
        binding: AdmissionConsumerBinding,
        expectedIdentities: [Int: LatestRetryIdentity]
    ) -> LatestRetryDrainProjection? {
        guard
            case .drain(let drain) = consumer.takeDrain(
                binding: binding,
                generation: generation
            )
        else {
            Issue.record("Expected latest-value retry drain")
            return nil
        }
        let identitiesByKey = drain.valuesByKey.mapValues(\.identity)
        #expect(identitiesByKey == expectedIdentities)
        return LatestRetryDrainProjection(
            token: drain.token,
            objectIdentifiersByKey: drain.valuesByKey.mapValues(ObjectIdentifier.init)
        )
    }
}

private struct LatestRetryIdentity: Sendable, Equatable {
    let key: Int
    let version: Int
}

private struct LatestRetryDrainProjection: Sendable {
    let token: AdmissionDrainToken
    let objectIdentifiersByKey: [Int: ObjectIdentifier]
}

private final class LatestRetryPayload: @unchecked Sendable {
    let identity: LatestRetryIdentity
    private let recorder: LatestRetryReleaseRecorder

    init(identity: LatestRetryIdentity, recorder: LatestRetryReleaseRecorder) {
        self.identity = identity
        self.recorder = recorder
    }

    deinit {
        recorder.record(identity)
    }
}

private final class LatestRetryReleaseRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedReleasedIdentities: [LatestRetryIdentity] = []

    var releasedIdentities: [LatestRetryIdentity] {
        lock.withLock { recordedReleasedIdentities }
    }

    func record(_ identity: LatestRetryIdentity) {
        lock.withLock {
            recordedReleasedIdentities.append(identity)
        }
    }
}

private func isRetryCleanupRequired<Key, Value>(
    _ result: LatestValueDrainResult<Key, Value>
) -> Bool where Key: Hashable & Sendable, Value: Sendable {
    if case .cleanupRequired = result { return true }
    return false
}
