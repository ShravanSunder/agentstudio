import Foundation
import Testing

@testable import AgentStudio

struct BoundRegistryFixture {
    let registry: WorktreeContentRepairConsumerRegistry
    let registration: FSEventRegistrationToken
    let consumer: ContentRepairConsumerRegistration
    let capture: ContentRepairPreparedCapture
    let activated: ContentRepairActivatedGeneration

    var bound: ContentRepairBoundGeneration {
        activated.boundGeneration
    }
}

enum ContentRepairRegistryTestError: Error {
    case registration
    case capture
    case binding
    case request
    case lookup
    case replacement
    case acknowledgement
    case withdrawal
}

func makeBoundFixture() async throws -> BoundRegistryFixture {
    let registry = WorktreeContentRepairConsumerRegistry()
    let registration = makeRegistration()
    let consumer = try await requireRegistration(
        registry.register(registration: registration, eligibility: .eligible)
    )
    let capture = try await requirePrepared(prepareCapture(registry, registration: registration))
    let activated = try await bindActive(capture, registry: registry)
    return BoundRegistryFixture(
        registry: registry,
        registration: registration,
        consumer: consumer,
        capture: capture,
        activated: activated
    )
}

func bindActive(
    _ capture: ContentRepairPreparedCapture,
    registry: WorktreeContentRepairConsumerRegistry
) async throws -> ContentRepairActivatedGeneration {
    let result = await registry.bind(capture, to: makeRepair(capture: capture))
    guard case .boundActive(let activated) = result else {
        throw ContentRepairRegistryTestError.binding
    }
    return activated
}

func prepareCapture(
    _ registry: WorktreeContentRepairConsumerRegistry,
    registration: FSEventRegistrationToken,
    identity: ContentRepairCaptureIdentity = .generate()
) async -> ContentRepairCapturePreparationResult {
    await registry.prepareCapture(identity: identity, registration: registration)
}

func makeRegistration() -> FSEventRegistrationToken {
    FSEventRegistrationToken(
        sourceID: FilesystemSourceID(
            kind: .registeredWorktreeContent,
            rootID: UUIDv7.generate()
        ),
        registrationGeneration: 3,
        rootGeneration: 5
    )
}

func makeRepair(capture: ContentRepairPreparedCapture) -> RepairGeneration {
    RepairGeneration(
        id: RepairGenerationID(
            registration: capture.registration,
            sequence: capture.invalidationGeneration.value
        ),
        watermark: .recoveryRevision(capture.invalidationGeneration.value),
        trigger: .continuityLoss,
        participants: capture.sourceGateParticipants
    )
}

func requireRegistration(
    _ result: ContentRepairConsumerRegistrationResult
) throws -> ContentRepairConsumerRegistration {
    guard case .registered(let registration) = result else {
        throw ContentRepairRegistryTestError.registration
    }
    return registration
}

func requirePrepared(
    _ result: ContentRepairCapturePreparationResult
) throws -> ContentRepairPreparedCapture {
    guard case .prepared(let capture) = result else {
        throw ContentRepairRegistryTestError.capture
    }
    return capture
}

func requireRequest(
    for consumer: ContentRepairConsumerToken,
    in bound: ContentRepairBoundGeneration
) throws -> ContentRepairDeliveryRequest {
    guard let request = bound.deliveryRequests.first(where: { $0.consumer == consumer }) else {
        throw ContentRepairRegistryTestError.request
    }
    return request
}

func requireLookup(
    _ result: ContentRepairConsumerLookupResult
) throws -> ContentRepairConsumerRegistration {
    guard case .registered(let registration) = result else {
        throw ContentRepairRegistryTestError.lookup
    }
    return registration
}

func requireReplacement(
    _ result: ContentRepairConsumerReplacementResult
) throws -> ContentRepairConsumerReplacement {
    guard case .replaced(let replacement) = result else {
        throw ContentRepairRegistryTestError.replacement
    }
    return replacement
}

func requireAccepted(
    _ result: ContentRepairAcknowledgementResult
) throws -> ContentRepairAcceptedAcknowledgement {
    guard case .accepted(let accepted) = result else {
        throw ContentRepairRegistryTestError.acknowledgement
    }
    return accepted
}

func requireWithdrawalAccepted(
    _ result: ContentRepairWithdrawalResult
) throws -> ContentRepairAcceptedAcknowledgement {
    guard case .withdrawnAndAcknowledged(let accepted) = result else {
        throw ContentRepairRegistryTestError.withdrawal
    }
    return accepted
}

func emptyShutdownDebt() -> WorktreeContentRepairConsumerRegistryShutdownDebt {
    WorktreeContentRepairConsumerRegistryShutdownDebt(
        preparedCaptures: [],
        activeRepairGenerations: [],
        pendingRepairGenerations: [],
        retainedRetries: [],
        outboundAcknowledgements: []
    )
}

extension WorktreeContentRepairConsumerRegistryTests {
    @Test("projection eligibility accepts only exact active and retained completed generations")
    func projectionEligibilityAcceptsExactLifecycleAuthority() async throws {
        // Arrange
        let activeFixture = try await makeBoundFixture()
        let completedFixture = try await makeBoundFixture()
        let completedAcknowledgement = try requireAccepted(
            await completedFixture.registry.acknowledge(
                repairGenerationID: completedFixture.bound.repairGeneration.id,
                consumer: completedFixture.consumer.token,
                disposition: .rebuiltCurrent(consumerRevision: 19)
            )
        )
        let zeroConsumerRegistry = WorktreeContentRepairConsumerRegistry()
        let zeroConsumerRegistration = makeRegistration()
        let zeroConsumerCapture = try await requirePrepared(
            prepareCapture(zeroConsumerRegistry, registration: zeroConsumerRegistration)
        )
        let zeroConsumerActivation = try await bindActive(
            zeroConsumerCapture,
            registry: zeroConsumerRegistry
        )

        // Act
        let activeEligibility = await activeFixture.registry.validateProjectionEligibility(
            activeFixture.activated
        )
        let completedEligibility = await completedFixture.registry.validateProjectionEligibility(
            completedFixture.activated
        )
        let zeroConsumerEligibility = await zeroConsumerRegistry.validateProjectionEligibility(
            zeroConsumerActivation
        )

        // Assert
        #expect(activeEligibility == .eligible(.currentActive(activeFixture.activated)))
        #expect(completedEligibility == .eligible(.retainedCompleted(completedFixture.activated)))
        #expect(zeroConsumerEligibility == .eligible(.retainedCompleted(zeroConsumerActivation)))
        #expect(
            completedAcknowledgement.sourceGateAcknowledgement.repairGenerationID
                == completedFixture.bound.repairGeneration.id
        )
    }

    @Test("projection eligibility rejects pending superseded mismatched foreign and shutdown generations")
    func projectionEligibilityRejectsEveryNonAuthoritativeLifecycle() async throws {
        // Arrange
        let registration = makeRegistration()
        let pendingRegistry = WorktreeContentRepairConsumerRegistry()
        _ = try await requireRegistration(
            pendingRegistry.register(registration: registration, eligibility: .eligible)
        )
        let pendingActiveCapture = try await requirePrepared(
            prepareCapture(pendingRegistry, registration: registration)
        )
        let pendingActive = try await bindActive(pendingActiveCapture, registry: pendingRegistry)
        let pendingCapture = try await requirePrepared(
            prepareCapture(pendingRegistry, registration: registration)
        )
        let pendingBoundResult = await pendingRegistry.bind(
            pendingCapture,
            to: makeRepair(capture: pendingCapture)
        )
        guard case .boundPending(let pendingBound) = pendingBoundResult else {
            Issue.record("Expected pending generation")
            return
        }

        let parallelRegistry = WorktreeContentRepairConsumerRegistry()
        let parallelConsumer = try await requireRegistration(
            parallelRegistry.register(registration: registration, eligibility: .eligible)
        )
        let parallelFirstCapture = try await requirePrepared(
            prepareCapture(parallelRegistry, registration: registration)
        )
        let parallelFirst = try await bindActive(parallelFirstCapture, registry: parallelRegistry)
        _ = await parallelRegistry.acknowledge(
            repairGenerationID: parallelFirst.boundGeneration.repairGeneration.id,
            consumer: parallelConsumer.token,
            disposition: .rebuiltCurrent(consumerRevision: 1)
        )
        let parallelPendingCapture = try await requirePrepared(
            prepareCapture(parallelRegistry, registration: registration)
        )
        let parallelPendingActivation = try await bindActive(
            parallelPendingCapture,
            registry: parallelRegistry
        )

        let mismatchRegistry = WorktreeContentRepairConsumerRegistry()
        _ = try await requireRegistration(
            mismatchRegistry.register(registration: registration, eligibility: .eligible)
        )
        let mismatchCapture = try await requirePrepared(
            prepareCapture(mismatchRegistry, registration: registration)
        )
        let mismatchedActivation = try await bindActive(mismatchCapture, registry: mismatchRegistry)

        let foreignFixture = try await makeBoundFixture()
        let shutdownRegistry = WorktreeContentRepairConsumerRegistry()
        let shutdownRegistration = makeRegistration()
        let shutdownCapture = try await requirePrepared(
            prepareCapture(shutdownRegistry, registration: shutdownRegistration)
        )
        let shutdownActivation = try await bindActive(shutdownCapture, registry: shutdownRegistry)
        _ = await shutdownRegistry.beginOrResumeShutdown()

        // Act
        let pending = await pendingRegistry.validateProjectionEligibility(parallelPendingActivation)
        let supersededActivationResult = await pendingRegistry.activateBoundGeneration(
            pendingBound.repairGeneration.id
        )
        guard case .activated(let newestActive) = supersededActivationResult else {
            Issue.record("Expected pending generation activation")
            return
        }
        let superseded = await pendingRegistry.validateProjectionEligibility(pendingActive)
        let newest = await pendingRegistry.validateProjectionEligibility(newestActive)
        let mismatch = await pendingRegistry.validateProjectionEligibility(mismatchedActivation)
        let foreign = await pendingRegistry.validateProjectionEligibility(foreignFixture.activated)
        let shuttingDown = await shutdownRegistry.validateProjectionEligibility(shutdownActivation)

        // Assert
        #expect(pending == .ineligible(.pendingGeneration(pendingBound.repairGeneration.id)))
        #expect(superseded == .ineligible(.supersededGeneration(pendingActive.boundGeneration.repairGeneration.id)))
        #expect(newest == .eligible(.currentActive(newestActive)))
        #expect(mismatch == .ineligible(.activationMismatch(mismatchedActivation.boundGeneration.repairGeneration.id)))
        #expect(foreign == .ineligible(.foreignSource(foreignFixture.registration.sourceID)))
        #expect(shuttingDown == .shuttingDown)
    }

    @Test("projection eligibility rejects completed generations evicted from the capture ledger")
    func projectionEligibilityRejectsEvictedCompletedGeneration() async throws {
        // Arrange
        let registry = WorktreeContentRepairConsumerRegistry()
        let registration = makeRegistration()
        var oldestActivation: ContentRepairActivatedGeneration?
        for generationOffset in 0...256 {
            let capture = try await requirePrepared(
                prepareCapture(registry, registration: registration)
            )
            let activation = try await bindActive(capture, registry: registry)
            if generationOffset == 0 {
                oldestActivation = activation
            }
        }
        guard let oldestActivation else {
            Issue.record("Expected oldest activation")
            return
        }

        // Act
        let eligibility = await registry.validateProjectionEligibility(oldestActivation)

        // Assert
        #expect(
            eligibility
                == .ineligible(
                    .staleGeneration(oldestActivation.boundGeneration.repairGeneration.id)
                )
        )
    }

    @Test("acknowledgement forwarding eligibility distinguishes exact pending and confirmed custody")
    func acknowledgementForwardingEligibilityIsExactAcrossOperations() async throws {
        // Arrange
        let normal = try await makeBoundFixture()
        let withdrawal = try await makeBoundFixture()
        let replacement = try await makeBoundFixture()
        let normalAccepted = try requireAccepted(
            await normal.registry.acknowledge(
                repairGenerationID: normal.bound.repairGeneration.id,
                consumer: normal.consumer.token,
                disposition: .rebuiltCurrent(consumerRevision: 41)
            )
        )
        let withdrawalAccepted = try requireWithdrawalAccepted(
            await withdrawal.registry.withdraw(
                withdrawal.consumer.token,
                disposition: .noRetainedState
            )
        )
        let replaced = try requireReplacement(
            await replacement.registry.replace(replacement.consumer.token, eligibility: .eligible)
        )
        guard case .transferred(let replacementAccepted) = replaced.repairDisposition else {
            Issue.record("Expected replacement acknowledgement")
            return
        }
        let mismatched = ContentRepairAcceptedAcknowledgement(
            sourceGateAcknowledgement: normalAccepted.sourceGateAcknowledgement,
            disposition: .rebuiltCurrent(consumerRevision: 42)
        )

        // Act
        let normalPending = await normal.registry.validateAcknowledgementForwardingEligibility(
            normalAccepted
        )
        let withdrawalPending = await withdrawal.registry.validateAcknowledgementForwardingEligibility(
            withdrawalAccepted
        )
        let replacementPending = await replacement.registry.validateAcknowledgementForwardingEligibility(
            replacementAccepted
        )
        let mismatch = await normal.registry.validateAcknowledgementForwardingEligibility(mismatched)
        _ = await normal.registry.confirmSourceGateAcknowledgement(
            normalAccepted.sourceGateAcknowledgement
        )
        let normalConfirmed = await normal.registry.validateAcknowledgementForwardingEligibility(
            normalAccepted
        )

        // Assert
        #expect(normalPending == .eligible(.pendingExact(normalAccepted)))
        #expect(withdrawalPending == .eligible(.pendingExact(withdrawalAccepted)))
        #expect(replacementPending == .eligible(.pendingExact(replacementAccepted)))
        #expect(
            mismatch
                == .ineligible(
                    .acknowledgementMismatch(normalAccepted.sourceGateAcknowledgement)
                )
        )
        #expect(normalConfirmed == .eligible(.confirmedExact(normalAccepted)))
    }

    @Test("acknowledgement forwarding eligibility rejects confirmed custody evicted at the bound")
    func acknowledgementForwardingEligibilityRejectsEvictedConfirmation() async throws {
        // Arrange
        let registry = WorktreeContentRepairConsumerRegistry()
        let registration = makeRegistration()
        for _ in 0...256 {
            _ = try await requireRegistration(
                registry.register(registration: registration, eligibility: .eligible)
            )
        }
        let capture = try await requirePrepared(
            prepareCapture(registry, registration: registration)
        )
        let bound = try await bindActive(capture, registry: registry).boundGeneration
        var oldestAcknowledgement: ContentRepairAcceptedAcknowledgement?
        for request in bound.deliveryRequests {
            let accepted = try requireAccepted(
                await registry.acknowledge(
                    repairGenerationID: bound.repairGeneration.id,
                    consumer: request.consumer,
                    disposition: .rebuiltCurrent(
                        consumerRevision: request.consumer.registrationOrdinal
                    )
                )
            )
            if oldestAcknowledgement == nil {
                oldestAcknowledgement = accepted
            }
            _ = await registry.confirmSourceGateAcknowledgement(
                accepted.sourceGateAcknowledgement
            )
        }
        guard let oldestAcknowledgement else {
            Issue.record("Expected oldest acknowledgement")
            return
        }

        // Act
        let eligibility = await registry.validateAcknowledgementForwardingEligibility(
            oldestAcknowledgement
        )

        // Assert
        #expect(
            eligibility
                == .ineligible(
                    .staleAcknowledgement(oldestAcknowledgement.sourceGateAcknowledgement)
                )
        )
    }

    @Test("acknowledgement forwarding eligibility rejects retired foreign unsupported and shutdown sources")
    func acknowledgementForwardingEligibilityRejectsUnavailableSources() async throws {
        // Arrange
        let retired = try await makeBoundFixture()
        let retiredAccepted = try requireAccepted(
            await retired.registry.acknowledge(
                repairGenerationID: retired.bound.repairGeneration.id,
                consumer: retired.consumer.token,
                disposition: .rebuiltCurrent(consumerRevision: 71)
            )
        )
        _ = await retired.registry.confirmSourceGateAcknowledgement(
            retiredAccepted.sourceGateAcknowledgement
        )
        _ = await retired.registry.retireSource(retired.registration.sourceID)

        let foreignRegistry = WorktreeContentRepairConsumerRegistry()
        let shutdown = try await makeBoundFixture()
        let shutdownAccepted = try requireAccepted(
            await shutdown.registry.acknowledge(
                repairGenerationID: shutdown.bound.repairGeneration.id,
                consumer: shutdown.consumer.token,
                disposition: .rebuiltCurrent(consumerRevision: 81)
            )
        )
        _ = await shutdown.registry.confirmSourceGateAcknowledgement(
            shutdownAccepted.sourceGateAcknowledgement
        )
        _ = await shutdown.registry.beginOrResumeShutdown()
        let unsupportedSourceID = FilesystemSourceID(
            kind: .watchedParentMembership,
            rootID: UUIDv7.generate()
        )
        let unsupported = ContentRepairAcceptedAcknowledgement(
            sourceGateAcknowledgement: FilesystemRepairAcknowledgementToken(
                repairGenerationID: RepairGenerationID(
                    registration: FSEventRegistrationToken(
                        sourceID: unsupportedSourceID,
                        registrationGeneration: 0,
                        rootGeneration: 0
                    ),
                    sequence: 0
                ),
                participant: retiredAccepted.sourceGateAcknowledgement.participant
            ),
            disposition: retiredAccepted.disposition
        )

        // Act
        let retiredResult = await retired.registry.validateAcknowledgementForwardingEligibility(
            retiredAccepted
        )
        let foreignResult = await foreignRegistry.validateAcknowledgementForwardingEligibility(
            retiredAccepted
        )
        let unsupportedResult = await foreignRegistry.validateAcknowledgementForwardingEligibility(
            unsupported
        )
        let shutdownResult = await shutdown.registry.validateAcknowledgementForwardingEligibility(
            shutdownAccepted
        )

        // Assert
        #expect(
            retiredResult
                == .ineligible(.foreignOrRetiredSource(retired.registration.sourceID))
        )
        #expect(
            foreignResult
                == .ineligible(.foreignOrRetiredSource(retired.registration.sourceID))
        )
        #expect(unsupportedResult == .ineligible(.sourceKindNotSupported(unsupportedSourceID)))
        #expect(shutdownResult == .shuttingDown)
    }
}
