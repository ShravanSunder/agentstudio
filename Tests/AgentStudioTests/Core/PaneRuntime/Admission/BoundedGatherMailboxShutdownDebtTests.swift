import Foundation
import Testing
import os

@testable import AgentStudio

@Suite("Admission BoundedGatherMailbox shutdown debt")
struct BoundedGatherMailboxShutdownDebtTests {
    private let generation = AdmissionGeneration(owner: .filesystemObservation, value: 419)

    @Test("empty mailbox reports a quiescent shutdown debt snapshot")
    func emptyMailboxReportsQuiescentShutdownDebt() throws {
        // Arrange
        let mailbox = makeMailbox(declaredKeys: [.alpha, .beta])

        // Act
        let snapshot = mailbox.lifecyclePort.shutdownDebtSnapshot
        let debtByKey = try shutdownDebtByKey(snapshot)

        // Assert
        #expect(snapshot.isQuiescent)
        #expect(snapshot.activeLease == .vacant)
        #expect(snapshot.queuedCleanup == .vacant)
        #expect(snapshot.inFlightCleanup == .vacant)
        #expect(debtByKey.count == 2)
        for key in [GatherTestKey.alpha, .beta] {
            let debt = try #require(debtByKey[key])
            #expect(debt.queuedContributionCount == 0)
            #expect(debt.queuedItemCount == 0)
            #expect(debt.queuedByteCount == 0)
            #expect(debt.retryDisposition == .vacant)
            #expect(debt.recoveryDisposition == .vacant)
            #expect(debt.queuedCleanupContributionCount == 0)
            #expect(debt.queuedCleanupItemCount == 0)
            #expect(debt.queuedCleanupByteCount == 0)
        }
    }

    @Test("shutdown debt reports queued custody independently for every declared key")
    func shutdownDebtReportsPerKeyQueuedCustody() throws {
        // Arrange
        let mailbox = makeMailbox(declaredKeys: [.alpha, .beta])
        let producer = mailbox.producerPort

        // Act
        _ = producer.offer(
            generation: generation,
            contribution: contribution(key: .alpha, label: "alpha", items: 2, bytes: 7)
        )
        _ = producer.offer(
            generation: generation,
            contribution: contribution(key: .beta, label: "beta", items: 3, bytes: 11)
        )
        let snapshot = mailbox.lifecyclePort.shutdownDebtSnapshot
        let debtByKey = try shutdownDebtByKey(snapshot)

        // Assert
        let alphaDebt = try #require(debtByKey[.alpha])
        let betaDebt = try #require(debtByKey[.beta])
        #expect(alphaDebt.queuedContributionCount == 1)
        #expect(alphaDebt.queuedItemCount == 2)
        #expect(alphaDebt.queuedByteCount == 7)
        #expect(betaDebt.queuedContributionCount == 1)
        #expect(betaDebt.queuedItemCount == 3)
        #expect(betaDebt.queuedByteCount == 11)
        #expect(alphaDebt.retryDisposition == .vacant)
        #expect(betaDebt.retryDisposition == .vacant)
        #expect(alphaDebt.recoveryDisposition == .vacant)
        #expect(betaDebt.recoveryDisposition == .vacant)
        #expect(snapshot.activeLease == .vacant)
        #expect(snapshot.isQuiescent == false)
    }

    @Test("active lease debt distinguishes presented and awaiting replacement presentation")
    func activeLeaseDebtDistinguishesPresentationState() {
        // Arrange
        let mailbox = makeMailbox(declaredKeys: [.alpha])
        let producer = mailbox.producerPort
        let consumer = mailbox.consumerPort
        let initialBinding = consumer.bindConsumer().binding
        _ = producer.offer(
            generation: generation,
            contribution: contribution(key: .alpha, label: "leased", items: 1, bytes: 4)
        )

        // Act
        let initialLease = requireLease(
            consumer.takeDrain(binding: initialBinding, generation: generation)
        )
        let presentedSnapshot = mailbox.lifecyclePort.shutdownDebtSnapshot
        let replacementBinding = consumer.bindConsumer().binding
        let awaitingSnapshot = mailbox.lifecyclePort.shutdownDebtSnapshot
        let replacementLease = requireLease(
            consumer.takeDrain(binding: replacementBinding, generation: generation)
        )
        let representedSnapshot = mailbox.lifecyclePort.shutdownDebtSnapshot

        // Assert
        #expect(
            presentedSnapshot.activeLease
                == .presented(key: .alpha, token: initialLease.token)
        )
        #expect(replacementLease.token != initialLease.token)
        #expect(
            awaitingSnapshot.activeLease
                == .awaitingPresentation(key: .alpha, token: replacementLease.token)
        )
        #expect(
            representedSnapshot.activeLease
                == .presented(key: .alpha, token: replacementLease.token)
        )
        #expect(representedSnapshot.isQuiescent == false)
    }

    @Test("retry acknowledgement remains explicit until transferred acknowledgement")
    func retryAcknowledgementRemainsExplicitUntilTransferred() throws {
        // Arrange
        let mailbox = makeMailbox(declaredKeys: [.alpha])
        let producer = mailbox.producerPort
        let consumer = mailbox.consumerPort
        let binding = consumer.bindConsumer().binding
        _ = producer.offer(
            generation: generation,
            contribution: contribution(key: .alpha, label: "retry", items: 2, bytes: 5)
        )
        let initialLease = requireLease(
            consumer.takeDrain(binding: binding, generation: generation)
        )

        // Act
        let retryAcknowledgement = consumer.acknowledge(
            token: initialLease.token,
            disposition: .retry
        )
        let retrySnapshot = mailbox.lifecyclePort.shutdownDebtSnapshot
        let retryDebt = try #require(try shutdownDebtByKey(retrySnapshot)[.alpha])
        let retriedLease = requireLease(
            consumer.takeDrain(binding: binding, generation: generation)
        )
        let transferredAcknowledgement = consumer.acknowledge(
            token: retriedLease.token,
            disposition: .transferred
        )
        let completedSnapshot = mailbox.lifecyclePort.shutdownDebtSnapshot
        let completedDebt = try #require(try shutdownDebtByKey(completedSnapshot)[.alpha])

        // Assert
        #expect(retryAcknowledgement == .accepted(wake: .scheduleDrain))
        #expect(retryDebt.retryDisposition == .retained)
        #expect(retryDebt.queuedContributionCount == 0)
        #expect(retryDebt.queuedItemCount == 0)
        #expect(retryDebt.queuedByteCount == 0)
        #expect(retrySnapshot.activeLease == .vacant)
        #expect(retrySnapshot.isQuiescent == false)
        #expect(transferredAcknowledgement == .accepted(wake: .noWake))
        #expect(completedDebt.retryDisposition == .vacant)
        #expect(completedSnapshot.isQuiescent)
    }

    @Test("capacity contraction reports recovery and key-scoped queued cleanup until both retire")
    func contractionReportsRecoveryAndKeyScopedQueuedCleanup() throws {
        // Arrange
        let mailbox = BoundedGatherMailbox<GatherTestKey, GatherTestPayload>(
            generation: generation,
            declaredKeys: [.alpha],
            limits: singleContributionLimits
        )
        let producer = mailbox.producerPort
        let consumer = mailbox.consumerPort
        let binding = consumer.bindConsumer().binding
        _ = producer.offer(
            generation: generation,
            contribution: contribution(key: .alpha, label: "retired", items: 1, bytes: 1)
        )

        // Act
        let contraction = requireAdmission(
            producer.offer(
                generation: generation,
                contribution: contribution(key: .alpha, label: "overflow", items: 1, bytes: 1)
            ))
        let recoveryRevision = requireContractedRecoveryRevision(contraction)
        let contractedSnapshot = mailbox.lifecyclePort.shutdownDebtSnapshot
        let contractedDebt = try #require(try shutdownDebtByKey(contractedSnapshot)[.alpha])
        let cleanupResult = mailbox.lifecyclePort.performCleanup(generation: generation)
        let recoveryLease = requireLease(
            consumer.takeDrain(binding: binding, generation: generation)
        )
        let recoveryAcknowledgement = consumer.acknowledge(
            token: recoveryLease.token,
            disposition: .transferred
        )
        let completedSnapshot = mailbox.lifecyclePort.shutdownDebtSnapshot

        // Assert
        #expect(contractedDebt.recoveryDisposition == .retained(recoveryRevision))
        #expect(contractedDebt.queuedCleanupContributionCount == 1)
        #expect(contractedDebt.queuedCleanupItemCount == 1)
        #expect(contractedDebt.queuedCleanupByteCount == 1)
        #expect(
            contractedSnapshot.queuedCleanup
                == .retained(
                    GatherShutdownCleanupCounts(
                        contributionCount: 1,
                        itemCount: 1,
                        byteCount: 1,
                        metadataEntryCount: 0
                    ))
        )
        #expect(contractedSnapshot.isQuiescent == false)
        #expect(
            cleanupResult
                == .performed(
                    AdmissionCleanupTurn(
                        release: .entriesAndBytes(count: 1, bytes: 1),
                        wake: .noWake
                    ))
        )
        #expect(requireRecoveryRevision(recoveryLease) == recoveryRevision)
        #expect(recoveryAcknowledgement == .accepted(wake: .noWake))
        #expect(completedSnapshot.isQuiescent)
    }

    @Test("in-flight key cleanup retains stable authority and conservative custody charge")
    func inFlightKeyCleanupRetainsStableAuthority() throws {
        // Arrange
        let cleanupGate = ShutdownDebtCleanupGate()
        let cleanupResult = ShutdownDebtCleanupResultBox()
        let mailbox = BoundedGatherMailbox<GatherTestKey, ShutdownDebtPayload>(
            generation: generation,
            declaredKeys: [.alpha],
            limits: singleContributionLimits
        )
        _ = offerBlockingPayload(
            through: mailbox.producerPort,
            generation: generation,
            cleanupGate: cleanupGate
        )
        _ = mailbox.producerPort.offer(
            generation: generation,
            contribution: GatherContribution(
                key: .alpha,
                payload: ShutdownDebtPayload(),
                footprint: GatherFootprint(itemCount: 1, byteCount: 1),
                recoverySignal: .ordinary
            )
        )

        // Act
        DispatchQueue(label: "gather-shutdown-debt-key-cleanup").async {
            cleanupResult.store(
                mailbox.lifecyclePort.performCleanup(generation: self.generation)
            )
            cleanupGate.cleanupCompleted.signal()
        }
        guard cleanupGate.destructorEntered.wait(timeout: .now() + 5) == .success else {
            cleanupGate.releaseDestructor.signal()
            Issue.record("Timed out waiting for key-scoped cleanup destructor")
            return
        }
        let firstSnapshot = mailbox.lifecyclePort.shutdownDebtSnapshot
        let secondSnapshot = mailbox.lifecyclePort.shutdownDebtSnapshot
        let concurrentCleanup = mailbox.lifecyclePort.performCleanup(generation: generation)
        cleanupGate.releaseDestructor.signal()
        guard cleanupGate.cleanupCompleted.wait(timeout: .now() + 5) == .success else {
            Issue.record("Timed out waiting for key-scoped cleanup completion")
            return
        }
        let completedSnapshot = mailbox.lifecyclePort.shutdownDebtSnapshot

        // Assert
        let firstDebt = try requireInFlightCleanup(firstSnapshot)
        let secondDebt = try requireInFlightCleanup(secondSnapshot)
        let alphaDebt = try #require(try shutdownDebtByKey(firstSnapshot)[.alpha])
        #expect(firstDebt.authority == secondDebt.authority)
        #expect(firstDebt.scope == .key(.alpha))
        #expect(firstDebt.contributionCount == 1)
        #expect(firstDebt.itemCount == 1)
        #expect(firstDebt.byteCount == 1)
        #expect(firstDebt.metadataEntryCount == 0)
        #expect(firstDebt.hasQueuedRemainder == false)
        #expect(alphaDebt.queuedCleanupContributionCount == 0)
        #expect(alphaDebt.queuedCleanupItemCount == 0)
        #expect(alphaDebt.queuedCleanupByteCount == 0)
        #expect(firstSnapshot.queuedCleanup == .vacant)
        #expect(firstSnapshot.isQuiescent == false)
        #expect(concurrentCleanup == .alreadyCleaning)
        #expect(
            cleanupResult.result
                == .performed(
                    AdmissionCleanupTurn(
                        release: .entriesAndBytes(count: 1, bytes: 1),
                        wake: .noWake
                    ))
        )
        #expect(completedSnapshot.inFlightCleanup == .vacant)
    }

    @Test("invalidated in-flight cleanup exposes unscoped authority and queued metadata")
    func invalidatedInFlightCleanupExposesUnscopedAuthorityAndMetadata() throws {
        // Arrange
        let cleanupGate = ShutdownDebtCleanupGate()
        let cleanupResult = ShutdownDebtCleanupResultBox()
        let mailbox = BoundedGatherMailbox<GatherTestKey, ShutdownDebtPayload>(
            generation: generation,
            declaredKeys: [.alpha],
            limits: singleContributionLimits
        )
        _ = offerBlockingPayload(
            through: mailbox.producerPort,
            generation: generation,
            cleanupGate: cleanupGate
        )
        _ = mailbox.lifecyclePort.invalidate(generation: generation)
        let queuedBeforeCleanup = mailbox.lifecyclePort.shutdownDebtSnapshot

        // Act
        DispatchQueue(label: "gather-shutdown-debt-unscoped-cleanup").async {
            cleanupResult.store(
                mailbox.lifecyclePort.performCleanup(generation: self.generation)
            )
            cleanupGate.cleanupCompleted.signal()
        }
        guard cleanupGate.destructorEntered.wait(timeout: .now() + 5) == .success else {
            cleanupGate.releaseDestructor.signal()
            Issue.record("Timed out waiting for unscoped cleanup destructor")
            return
        }
        let inFlightSnapshot = mailbox.lifecyclePort.shutdownDebtSnapshot
        cleanupGate.releaseDestructor.signal()
        guard cleanupGate.cleanupCompleted.wait(timeout: .now() + 5) == .success else {
            Issue.record("Timed out waiting for unscoped cleanup completion")
            return
        }
        let afterContributionCleanup = mailbox.lifecyclePort.shutdownDebtSnapshot
        let metadataCleanup = mailbox.lifecyclePort.performCleanup(generation: generation)
        let completedSnapshot = mailbox.lifecyclePort.shutdownDebtSnapshot

        // Assert
        let queuedBeforeCleanupCounts = try requireQueuedCleanup(queuedBeforeCleanup)
        let inFlightDebt = try requireInFlightCleanup(inFlightSnapshot)
        let queuedDuringInFlight = try requireQueuedCleanup(inFlightSnapshot)
        #expect(queuedBeforeCleanup.inFlightCleanup == .vacant)
        #expect(queuedBeforeCleanupCounts.contributionCount == 1)
        #expect(queuedBeforeCleanupCounts.itemCount == 1)
        #expect(queuedBeforeCleanupCounts.byteCount == 1)
        #expect(queuedBeforeCleanupCounts.metadataEntryCount == 1)
        #expect(inFlightDebt.scope == .unscoped)
        #expect(inFlightDebt.contributionCount == 1)
        #expect(inFlightDebt.metadataEntryCount == 0)
        #expect(inFlightDebt.hasQueuedRemainder)
        #expect(queuedDuringInFlight.contributionCount == 0)
        #expect(queuedDuringInFlight.itemCount == 0)
        #expect(queuedDuringInFlight.byteCount == 0)
        #expect(queuedDuringInFlight.metadataEntryCount == 1)
        #expect(
            queuedDuringInFlight.contributionCount + inFlightDebt.contributionCount
                == queuedBeforeCleanupCounts.contributionCount
        )
        #expect(
            queuedDuringInFlight.itemCount + inFlightDebt.itemCount
                == queuedBeforeCleanupCounts.itemCount
        )
        #expect(
            queuedDuringInFlight.byteCount + inFlightDebt.byteCount
                == queuedBeforeCleanupCounts.byteCount
        )
        #expect(
            queuedDuringInFlight.metadataEntryCount + inFlightDebt.metadataEntryCount
                == queuedBeforeCleanupCounts.metadataEntryCount
        )
        #expect(inFlightSnapshot.isQuiescent == false)
        #expect(
            cleanupResult.result
                == .performed(
                    AdmissionCleanupTurn(
                        release: .entriesAndBytes(count: 1, bytes: 1),
                        wake: .scheduleDrain
                    ))
        )
        #expect(afterContributionCleanup.inFlightCleanup == .vacant)
        #expect(
            afterContributionCleanup.queuedCleanup
                == .retained(
                    GatherShutdownCleanupCounts(
                        contributionCount: 0,
                        itemCount: 0,
                        byteCount: 0,
                        metadataEntryCount: 1
                    ))
        )
        #expect(
            metadataCleanup
                == .performed(
                    AdmissionCleanupTurn(
                        release: .entriesAndBytes(count: 1, bytes: 0),
                        wake: .noWake
                    ))
        )
        #expect(completedSnapshot.isQuiescent)
    }

    private var generousLimits: GatherMailboxLimits {
        GatherMailboxLimits(
            maximumDeclaredKeys: 3,
            maximumRetainedContributions: 6,
            maximumRetainedItems: 16,
            maximumRetainedBytes: 64,
            maximumRetainedContributionsPerKey: 3,
            maximumRetainedItemsPerKey: 8,
            maximumRetainedBytesPerKey: 32,
            maximumContributionsPerLease: 3,
            maximumItemsPerLease: 8,
            maximumBytesPerLease: 32,
            cleanupQuantum: .entriesAndBytes(maximumEntries: 2, maximumBytes: 32)
        )
    }

    private var singleContributionLimits: GatherMailboxLimits {
        GatherMailboxLimits(
            maximumDeclaredKeys: 1,
            maximumRetainedContributions: 1,
            maximumRetainedItems: 1,
            maximumRetainedBytes: 1,
            maximumRetainedContributionsPerKey: 1,
            maximumRetainedItemsPerKey: 1,
            maximumRetainedBytesPerKey: 1,
            maximumContributionsPerLease: 1,
            maximumItemsPerLease: 1,
            maximumBytesPerLease: 1,
            cleanupQuantum: .entriesAndBytes(maximumEntries: 1, maximumBytes: 1)
        )
    }

    private func makeMailbox(
        declaredKeys: Set<GatherTestKey>
    ) -> BoundedGatherMailbox<GatherTestKey, GatherTestPayload> {
        BoundedGatherMailbox(
            generation: generation,
            declaredKeys: declaredKeys,
            limits: generousLimits
        )
    }

    private func shutdownDebtByKey(
        _ snapshot: GatherShutdownDebtSnapshot<GatherTestKey>
    ) throws -> [GatherTestKey: GatherShutdownKeyDebt<GatherTestKey>] {
        let debtByKey = Dictionary(uniqueKeysWithValues: snapshot.keyDebt.map { ($0.key, $0) })
        try #require(debtByKey.count == snapshot.keyDebt.count)
        return debtByKey
    }

    private func requireInFlightCleanup(
        _ snapshot: GatherShutdownDebtSnapshot<GatherTestKey>
    ) throws -> GatherShutdownInFlightCleanupDebt<GatherTestKey> {
        guard case .retained(let debt) = snapshot.inFlightCleanup else {
            Issue.record("Expected retained in-flight cleanup debt")
            throw ShutdownDebtTestError.expectedInFlightCleanup
        }
        return debt
    }

    private func requireQueuedCleanup(
        _ snapshot: GatherShutdownDebtSnapshot<GatherTestKey>
    ) throws -> GatherShutdownCleanupCounts {
        guard case .retained(let counts) = snapshot.queuedCleanup else {
            Issue.record("Expected retained queued cleanup debt")
            throw ShutdownDebtTestError.expectedQueuedCleanup
        }
        return counts
    }
}

private enum ShutdownDebtTestError: Error {
    case expectedInFlightCleanup
    case expectedQueuedCleanup
}

private func offerBlockingPayload(
    through producer: GatherProducerPort<GatherTestKey, ShutdownDebtPayload>,
    generation: AdmissionGeneration,
    cleanupGate: ShutdownDebtCleanupGate
) -> GatherOfferResult<GatherTestKey> {
    producer.offer(
        generation: generation,
        contribution: GatherContribution(
            key: .alpha,
            payload: ShutdownDebtPayload(cleanupGate: cleanupGate),
            footprint: GatherFootprint(itemCount: 1, byteCount: 1),
            recoverySignal: .ordinary
        )
    )
}

private final class ShutdownDebtCleanupGate: @unchecked Sendable {
    let destructorEntered = DispatchSemaphore(value: 0)
    let releaseDestructor = DispatchSemaphore(value: 0)
    let cleanupCompleted = DispatchSemaphore(value: 0)
}

private final class ShutdownDebtPayload: @unchecked Sendable {
    private let cleanupGate: ShutdownDebtCleanupGate?

    init(cleanupGate: ShutdownDebtCleanupGate? = nil) {
        self.cleanupGate = cleanupGate
    }

    deinit {
        guard let cleanupGate else { return }
        cleanupGate.destructorEntered.signal()
        cleanupGate.releaseDestructor.wait()
    }
}

private final class ShutdownDebtCleanupResultBox: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock<AdmissionCleanupTurnResult?>(initialState: nil)

    func store(_ result: AdmissionCleanupTurnResult) {
        lock.withLock { $0 = result }
    }

    var result: AdmissionCleanupTurnResult? {
        lock.withLock { $0 }
    }
}
