import Foundation
import Testing

@testable import AgentStudio

extension AdmissionLatestValueMailboxTests {
    @Test("injected clock can reenter before admission state is locked")
    func injectedClockReentersOutsideAdmissionLock() {
        let clockProbe = LatestValueClockReentryProbe()
        let clock = LatestValueReentrantClock(probe: clockProbe)
        let mailbox = LatestValueMailbox<SampleKey, Int>(
            generation: generation,
            declaredKeys: [.primary],
            limits: makeLatestValueTestLimits(cleanupQuantum: cleanupQuantum),
            clock: clock
        )
        clockProbe.mailbox = mailbox
        let producer = mailbox.producerPort
        let consumer = mailbox.consumerPort
        let lifecycle = mailbox.lifecyclePort
        let binding = consumer.bindConsumer().binding

        _ = producer.offer(generation: generation, key: .primary, value: 1)
        guard
            case .drain = consumer.takeDrain(
                binding: binding,
                generation: generation
            )
        else {
            Issue.record("Expected clock-reentrant custody to drain")
            return
        }
        _ = lifecycle.diagnostics

        #expect(clockProbe.reentryCount == 3)
    }

    @Test("generic key hashing can reenter outside admission state")
    func genericKeyHashingReentersOutsideAdmissionLock() {
        let hashProbe = LatestValueHashReentryProbe()
        let hashKey = LatestValueReentrantKey(identity: 1, probe: hashProbe)
        let hashMailbox = LatestValueMailbox<LatestValueReentrantKey, Int>(
            generation: generation,
            declaredKeys: [hashKey],
            limits: makeLatestValueTestLimits(cleanupQuantum: cleanupQuantum)
        )
        hashProbe.mailbox = hashMailbox
        let hashProducer = hashMailbox.producerPort
        let hashConsumer = hashMailbox.consumerPort
        let hashBinding = hashConsumer.bindConsumer().binding

        _ = hashProducer.offer(generation: generation, key: hashKey, value: 1)
        guard
            case .drain = hashConsumer.takeDrain(
                binding: hashBinding,
                generation: generation
            )
        else {
            Issue.record("Expected reentrant-hash custody to drain")
            return
        }
        #expect(hashProbe.reentryCount > 0)
    }

    @Test("payload release from replacement acknowledgement and invalidation can reenter")
    func payloadReleaseReentersOutsideAdmissionLock() {
        verifyReplacementThenInvalidationReleasePath()
        verifyRetryAcknowledgementThenInvalidationReleasePath()
    }

    private func verifyReplacementThenInvalidationReleasePath() {
        let releaseRecorder = LatestValueReleaseRecorder()
        let releaseMailbox = LatestValueMailbox<SampleKey, LatestValueReentrantRelease>(
            generation: generation,
            declaredKeys: [.primary],
            limits: makeLatestValueTestLimits(cleanupQuantum: cleanupQuantum)
        )
        let weakMailbox = LatestValueWeakMailboxReference(mailbox: releaseMailbox)
        let releaseProducer = releaseMailbox.producerPort
        let releaseLifecycle = releaseMailbox.lifecyclePort
        _ = releaseProducer.offer(
            generation: generation,
            key: .primary,
            value: LatestValueReentrantRelease(
                recorder: releaseRecorder,
                mailboxReference: weakMailbox
            )
        )
        _ = releaseProducer.offer(
            generation: generation,
            key: .primary,
            value: LatestValueReentrantRelease(
                recorder: releaseRecorder,
                mailboxReference: weakMailbox
            )
        )

        #expect(releaseRecorder.releaseCount == 0)
        #expect(releaseLifecycle.invalidate(generation: generation) == .applied)
        #expect(releaseRecorder.releaseCount == 0)
        #expect(
            releaseLifecycle.performCleanup(generation: generation)
                == .performed(
                    AdmissionCleanupTurn(
                        release: .entries(count: 2),
                        wake: .noWake
                    )
                )
        )
        #expect(releaseRecorder.releaseCount == 2)
    }

    private func verifyRetryAcknowledgementThenInvalidationReleasePath() {
        let acknowledgementRecorder = LatestValueReleaseRecorder()
        let acknowledgementMailbox = LatestValueMailbox<
            SampleKey,
            LatestValueReentrantRelease
        >(
            generation: generation,
            declaredKeys: [.primary],
            limits: makeLatestValueTestLimits(cleanupQuantum: cleanupQuantum)
        )
        let weakAcknowledgementMailbox = LatestValueWeakMailboxReference(
            mailbox: acknowledgementMailbox
        )
        let acknowledgementProducer = acknowledgementMailbox.producerPort
        let acknowledgementConsumer = acknowledgementMailbox.consumerPort
        let acknowledgementLifecycle = acknowledgementMailbox.lifecyclePort
        let acknowledgementBinding = acknowledgementConsumer.bindConsumer().binding
        _ = acknowledgementProducer.offer(
            generation: generation,
            key: .primary,
            value: LatestValueReentrantRelease(
                recorder: acknowledgementRecorder,
                mailboxReference: weakAcknowledgementMailbox
            )
        )
        let acknowledgementToken: AdmissionDrainToken? = {
            guard
                case .drain(let drain) = acknowledgementConsumer.takeDrain(
                    binding: acknowledgementBinding,
                    generation: generation
                )
            else {
                Issue.record("Expected acknowledgement release custody to drain")
                return nil
            }
            return drain.token
        }()
        _ = acknowledgementProducer.offer(
            generation: generation,
            key: .primary,
            value: LatestValueReentrantRelease(
                recorder: acknowledgementRecorder,
                mailboxReference: weakAcknowledgementMailbox
            )
        )

        #expect(acknowledgementRecorder.releaseCount == 0)
        if let acknowledgementToken {
            #expect(
                acknowledgementConsumer.acknowledge(
                    acknowledgementToken,
                    disposition: .retry
                ) == .accepted(wake: .scheduleDrain)
            )
        }
        #expect(acknowledgementRecorder.releaseCount == 0)
        #expect(
            acknowledgementConsumer.performCleanup(generation: generation)
                == .performed(
                    AdmissionCleanupTurn(
                        release: .entries(count: 1),
                        wake: .scheduleDrain
                    )
                )
        )
        #expect(acknowledgementRecorder.releaseCount == 1)
        #expect(acknowledgementLifecycle.invalidate(generation: generation) == .applied)
        #expect(acknowledgementRecorder.releaseCount == 1)
        #expect(
            acknowledgementLifecycle.performCleanup(generation: generation)
                == .performed(
                    AdmissionCleanupTurn(
                        release: .entries(count: 1),
                        wake: .noWake
                    )
                )
        )
        #expect(acknowledgementRecorder.releaseCount == 2)
    }
}

private final class LatestValueClockReentryProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedReentryCount = 0

    weak var mailbox: LatestValueMailbox<AdmissionLatestValueMailboxTests.SampleKey, Int>?

    var reentryCount: Int {
        lock.withLock { recordedReentryCount }
    }

    func reenterMailbox() {
        guard let mailbox else { return }
        _ = mailbox.lifecyclePort.authoritySnapshot
        lock.withLock {
            recordedReentryCount += 1
        }
    }
}

private struct LatestValueReentrantClock: Clock {
    typealias Duration = Swift.Duration
    typealias Instant = ContinuousClock.Instant

    let probe: LatestValueClockReentryProbe

    var now: Instant {
        probe.reenterMailbox()
        return ContinuousClock.now
    }

    var minimumResolution: Duration {
        ContinuousClock().minimumResolution
    }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        try await ContinuousClock().sleep(until: deadline, tolerance: tolerance)
    }
}

private final class LatestValueHashReentryProbe: @unchecked Sendable {
    weak var mailbox: LatestValueMailbox<LatestValueReentrantKey, Int>?
    var reentryCount = 0
}

private struct LatestValueReentrantKey: Hashable, Sendable {
    let identity: Int
    let probe: LatestValueHashReentryProbe

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.identity == rhs.identity
    }

    func hash(into hasher: inout Hasher) {
        if let mailbox = probe.mailbox {
            _ = mailbox.lifecyclePort.diagnostics
            probe.reentryCount += 1
        }
        hasher.combine(identity)
    }
}

private final class LatestValueReleaseRecorder: @unchecked Sendable {
    var releaseCount = 0
}

private final class LatestValueWeakMailboxReference: @unchecked Sendable {
    weak var mailbox:
        LatestValueMailbox<
            AdmissionLatestValueMailboxTests.SampleKey,
            LatestValueReentrantRelease
        >?

    init(
        mailbox: LatestValueMailbox<
            AdmissionLatestValueMailboxTests.SampleKey,
            LatestValueReentrantRelease
        >
    ) {
        self.mailbox = mailbox
    }
}

private final class LatestValueReentrantRelease: @unchecked Sendable {
    private let recorder: LatestValueReleaseRecorder
    private let mailboxReference: LatestValueWeakMailboxReference

    init(
        recorder: LatestValueReleaseRecorder,
        mailboxReference: LatestValueWeakMailboxReference
    ) {
        self.recorder = recorder
        self.mailboxReference = mailboxReference
    }

    deinit {
        if let mailbox = mailboxReference.mailbox {
            _ = mailbox.lifecyclePort.diagnostics
        }
        recorder.releaseCount += 1
    }
}
