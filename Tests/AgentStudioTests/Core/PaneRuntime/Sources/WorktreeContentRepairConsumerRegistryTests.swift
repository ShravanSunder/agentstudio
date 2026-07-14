import Foundation
import Testing

@testable import AgentStudio

@Suite("WorktreeContentRepairConsumerRegistryTests")
struct WorktreeContentRepairConsumerRegistryTests {
    @Test("registration mints UUIDv7 identity and deterministic ordinal")
    func registrationMintsUUIDv7IdentityAndDeterministicOrdinal() async throws {
        // Arrange
        let registry = WorktreeContentRepairConsumerRegistry()
        let registration = makeRegistration()

        // Act
        let first = try await requireRegistration(
            registry.register(registration: registration, eligibility: .eligible)
        )
        let second = try await requireRegistration(
            registry.register(registration: registration, eligibility: .ineligibleNoRetainedContent)
        )

        // Assert
        #expect(first.token.identity.isUUIDv7)
        #expect(second.token.identity.isUUIDv7)
        #expect(UUIDv7.isV7(registration.sourceID.rootID))
        #expect(first.token.registrationOrdinal == 0)
        #expect(second.token.registrationOrdinal == 1)
        #expect(first.token.sourceGateParticipant.kind == .contentConsumer)
        #expect(first.token.sourceGateParticipant.participantGeneration == 0)
        #expect(first.currentness == .current(.baseline(registration)))
    }

    @Test("capture includes only eligible consumers and abort restores exact prior currentness")
    func captureEligibilityAndExactAbortRollback() async throws {
        // Arrange
        let registry = WorktreeContentRepairConsumerRegistry()
        let registration = makeRegistration()
        let eligible = try await requireRegistration(
            registry.register(registration: registration, eligibility: .eligible)
        )
        let ineligible = try await requireRegistration(
            registry.register(registration: registration, eligibility: .ineligibleNoRetainedContent)
        )
        let firstCapture = try await requirePrepared(prepareCapture(registry, registration: registration))
        let firstBound = try await bindActive(firstCapture, registry: registry).boundGeneration
        let firstRequest = try requireRequest(for: eligible.token, in: firstBound)
        _ = await registry.acknowledge(
            repairGenerationID: firstBound.repairGeneration.id,
            consumer: eligible.token,
            disposition: .rebuiltCurrent(consumerRevision: 41)
        )
        let rebuilt = try await requireLookup(registry.lookup(eligible.token))

        // Act
        let secondCapture = try await requirePrepared(prepareCapture(registry, registration: registration))
        let eligibleDuringCapture = try await requireLookup(registry.lookup(eligible.token))
        let ineligibleDuringCapture = try await requireLookup(registry.lookup(ineligible.token))
        let firstAbort = await registry.abortCapture(secondCapture)
        let replayedAbort = await registry.abortCapture(secondCapture)
        let eligibleAfterAbort = try await requireLookup(registry.lookup(eligible.token))

        // Assert
        #expect(firstRequest.consumer == eligible.token)
        #expect(firstCapture.identity.isUUIDv7)
        #expect(firstRequest.retryToken.identity.isUUIDv7)
        #expect(firstCapture.consumers == [eligible.token])
        #expect(secondCapture.consumers == [eligible.token])
        #expect(
            eligibleDuringCapture.currentness
                == .nonCurrent(
                    .capturePending(
                        identity: secondCapture.identity,
                        invalidationGeneration: secondCapture.invalidationGeneration
                    )
                )
        )
        #expect(ineligibleDuringCapture.currentness == ineligible.currentness)
        #expect(firstAbort == .aborted(secondCapture))
        #expect(replayedAbort == .alreadyAborted(secondCapture.identity))
        #expect(eligibleAfterAbort.currentness == rebuilt.currentness)
    }

    @Test("late registration sees no-retained-content and is not retroactively captured")
    func lateRegistrationReceivesAuthoritativeNonCurrentSnapshot() async throws {
        // Arrange
        let registry = WorktreeContentRepairConsumerRegistry()
        let registration = makeRegistration()
        let captured = try await requireRegistration(
            registry.register(registration: registration, eligibility: .eligible)
        )
        let capture = try await requirePrepared(prepareCapture(registry, registration: registration))

        // Act
        let late = try await requireRegistration(
            registry.register(registration: registration, eligibility: .eligible)
        )
        let bound = try await bindActive(capture, registry: registry).boundGeneration
        let lateAfterBinding = try await requireLookup(registry.lookup(late.token))

        // Assert
        #expect(capture.consumers == [captured.token])
        #expect(late.currentness == .nonCurrent(.noRetainedContent(capture.invalidationGeneration)))
        #expect(bound.deliveryRequests.map(\.consumer) == [captured.token])
        #expect(
            lateAfterBinding.currentness
                == .nonCurrent(.noRetainedContent(capture.invalidationGeneration))
        )
    }

    @Test("not-applicable terminalizes only the captured obligation")
    func notApplicablePreservesRegistrationForFutureCapture() async throws {
        // Arrange
        let registry = WorktreeContentRepairConsumerRegistry()
        let registration = makeRegistration()
        let consumer = try await requireRegistration(
            registry.register(registration: registration, eligibility: .eligible)
        )
        let capture = try await requirePrepared(prepareCapture(registry, registration: registration))
        let bound = try await bindActive(capture, registry: registry).boundGeneration

        // Act
        let acknowledgement = await registry.acknowledge(
            repairGenerationID: bound.repairGeneration.id,
            consumer: consumer.token,
            disposition: .notApplicableNoRetainedState
        )
        let retained = try await requireLookup(registry.lookup(consumer.token))
        let nextCapture = try await requirePrepared(prepareCapture(registry, registration: registration))

        // Assert
        guard case .accepted(let accepted) = acknowledgement else {
            Issue.record("Expected accepted not-applicable disposition")
            return
        }
        #expect(accepted.disposition == .notApplicableNoRetainedState)
        #expect(
            retained.currentness
                == .nonCurrent(.noRetainedContent(capture.invalidationGeneration))
        )
        #expect(nextCapture.consumers == [consumer.token])
    }

    @Test("completed exact acknowledgement replays but conflicting completion is stale")
    func completedAcknowledgementReplayIsExact() async throws {
        // Arrange
        let fixture = try await makeBoundFixture()
        let disposition = ContentRepairConsumerDisposition.rebuiltCurrent(consumerRevision: 7)

        // Act
        let first = await fixture.registry.acknowledge(
            repairGenerationID: fixture.bound.repairGeneration.id,
            consumer: fixture.consumer.token,
            disposition: disposition
        )
        let replay = await fixture.registry.acknowledge(
            repairGenerationID: fixture.bound.repairGeneration.id,
            consumer: fixture.consumer.token,
            disposition: disposition
        )
        let conflict = await fixture.registry.acknowledge(
            repairGenerationID: fixture.bound.repairGeneration.id,
            consumer: fixture.consumer.token,
            disposition: .rebuiltCurrent(consumerRevision: 8)
        )
        let completedBindingReplay = await fixture.registry.bind(
            fixture.capture,
            to: fixture.bound.repairGeneration
        )

        // Assert
        guard case .accepted(let accepted) = first else {
            Issue.record("Expected first acknowledgement to be accepted")
            return
        }
        #expect(replay == .replayed(accepted))
        #expect(conflict == .debtRetained(.staleConsumerToken))
        #expect(completedBindingReplay == .replayedCompleted(fixture.bound))
    }

    @Test("retry custody blocks shutdown until exact retry completes")
    func retryCustodyBlocksShutdown() async throws {
        // Arrange
        let fixture = try await makeBoundFixture()
        let request = try requireRequest(for: fixture.consumer.token, in: fixture.bound)
        let acknowledgement = await fixture.registry.acknowledge(
            repairGenerationID: fixture.bound.repairGeneration.id,
            consumer: fixture.consumer.token,
            disposition: .markedNonCurrent(retry: request.retryToken)
        )

        // Act
        let blocked = await fixture.registry.beginOrResumeShutdown()
        let rejectedRegistration = await fixture.registry.register(
            registration: fixture.registration,
            eligibility: .eligible
        )
        let completion = await fixture.registry.completeRetry(
            request.retryToken,
            consumerRevision: 91
        )
        guard case .accepted(let accepted) = acknowledgement else {
            Issue.record("Expected retry acknowledgement to be accepted")
            return
        }
        let confirmation = await fixture.registry.confirmSourceGateAcknowledgement(
            accepted.sourceGateAcknowledgement
        )
        let resumed = await fixture.registry.beginOrResumeShutdown()

        // Assert
        guard case .awaitingDebt(let debt) = blocked else {
            Issue.record("Expected retry custody to block shutdown")
            return
        }
        #expect(debt.retainedRetries == [request.retryToken])
        #expect(rejectedRegistration == .shuttingDown)
        guard case .completed(let registration) = completion else {
            Issue.record("Expected exact retry completion")
            return
        }
        #expect(
            registration.currentness
                == .current(
                    .rebuilt(
                        repairGenerationID: fixture.bound.repairGeneration.id,
                        consumerRevision: 91
                    )
                )
        )
        #expect(confirmation == .confirmed(accepted))
        #expect(resumed == .alreadyCompleted(emptyShutdownDebt()))
    }

    @Test("withdrawal is explicit and UI disappearance alone leaves debt")
    func withdrawalIsExplicitAcknowledgement() async throws {
        // Arrange
        let registry = WorktreeContentRepairConsumerRegistry()
        let registration = makeRegistration()
        let first = try await requireRegistration(
            registry.register(registration: registration, eligibility: .eligible)
        )
        let second = try await requireRegistration(
            registry.register(registration: registration, eligibility: .eligible)
        )
        let capture = try await requirePrepared(prepareCapture(registry, registration: registration))
        let bound = try await bindActive(capture, registry: registry).boundGeneration

        // Act
        _ = await registry.lookup(first.token)
        let debtBeforeWithdrawal = await registry.shutdownDebtSnapshot()
        let withdrawal = await registry.withdraw(first.token, disposition: .noRetainedState)
        let debtAfterWithdrawal = await registry.shutdownDebtSnapshot()

        // Assert
        #expect(debtBeforeWithdrawal.activeRepairGenerations == [bound.repairGeneration.id])
        guard case .withdrawnAndAcknowledged(let accepted) = withdrawal else {
            Issue.record("Expected explicit withdrawal acknowledgement")
            return
        }
        #expect(accepted.disposition == .withdrawnNoRetainedState)
        #expect(accepted.sourceGateAcknowledgement.participant == first.token.sourceGateParticipant)
        #expect(debtAfterWithdrawal.activeRepairGenerations == [bound.repairGeneration.id])
        let retainedSecond = try await requireLookup(registry.lookup(second.token))
        #expect(await registry.lookup(second.token) == .registered(retainedSecond))
    }

    @Test("replacement keeps identity transfers custody and rejects old completion")
    func replacementTransfersExactCustody() async throws {
        // Arrange
        let fixture = try await makeBoundFixture()

        // Act
        let replacementResult = await fixture.registry.replace(
            fixture.consumer.token,
            eligibility: .eligible
        )
        let replacement = try requireReplacement(replacementResult)
        let staleCompletion = await fixture.registry.acknowledge(
            repairGenerationID: fixture.bound.repairGeneration.id,
            consumer: fixture.consumer.token,
            disposition: .rebuiltCurrent(consumerRevision: 1)
        )

        // Assert
        #expect(replacement.registration.token.identity == fixture.consumer.token.identity)
        #expect(replacement.registration.token.generation == fixture.consumer.token.generation + 1)
        #expect(replacement.registration.token.registrationOrdinal == fixture.consumer.token.registrationOrdinal)
        guard case .transferred(let accepted) = replacement.repairDisposition else {
            Issue.record("Expected captured obligation transfer")
            return
        }
        #expect(
            accepted.disposition
                == .transferredToReplacement(replacement.registration.token)
        )
        #expect(
            accepted.sourceGateAcknowledgement.participant
                == fixture.consumer.token.sourceGateParticipant
        )
        #expect(staleCompletion == .debtRetained(.staleConsumerToken))
        guard case .nonCurrent(.retryRetained(let transferredRetry)) = replacement.registration.currentness else {
            Issue.record("Expected retry custody on replacement")
            return
        }
        #expect(transferredRetry.consumer == replacement.registration.token)
    }

    @Test("prepared capture freezes replacement and withdrawal without mutating state")
    func preparedCaptureFreezesConsumerLifecycleMutation() async throws {
        // Arrange
        let registry = WorktreeContentRepairConsumerRegistry()
        let registration = makeRegistration()
        let consumer = try await requireRegistration(
            registry.register(registration: registration, eligibility: .eligible)
        )
        let capture = try await requirePrepared(prepareCapture(registry, registration: registration))
        let stateBeforeMutation = try await requireLookup(registry.lookup(consumer.token))

        // Act
        let replacement = await registry.replace(consumer.token, eligibility: .ineligibleNoRetainedContent)
        let withdrawal = await registry.withdraw(consumer.token, disposition: .noRetainedState)
        let stateAfterMutation = try await requireLookup(registry.lookup(consumer.token))
        let replayedCapture = await registry.prepareCapture(
            identity: capture.identity,
            registration: registration
        )

        // Assert
        #expect(replacement == .captureInProgress(capture.identity))
        #expect(withdrawal == .captureInProgress(capture.identity))
        #expect(stateAfterMutation == stateBeforeMutation)
        #expect(replayedCapture == .replayed(capture))
    }

    @Test("capture binding and abort are exact idempotent operations")
    func captureBindingAndAbortAreExact() async throws {
        // Arrange
        let registry = WorktreeContentRepairConsumerRegistry()
        let registration = makeRegistration()
        let consumer = try await requireRegistration(
            registry.register(registration: registration, eligibility: .eligible)
        )
        let capture = try await requirePrepared(prepareCapture(registry, registration: registration))
        let repair = makeRepair(capture: capture)

        // Act
        let first = await registry.bind(capture, to: repair)
        let replay = await registry.bind(capture, to: repair)
        let abortAfterBind = await registry.abortCapture(capture)

        // Assert
        guard case .boundActive(let activated) = first else {
            Issue.record("Expected active binding authority")
            return
        }
        let bound = activated.boundGeneration
        #expect(replay == .replayedActive(activated))
        #expect(abortAfterBind == .alreadyBound(repair.id))
        #expect(bound.deliveryRequests.map(\.consumer) == [consumer.token])
        #expect(bound.deliveryRequests.map(\.invalidationGeneration) == [capture.invalidationGeneration])
    }

    @Test("active repair retains only newest pending successor")
    func activeRepairRetainsNewestPendingSuccessor() async throws {
        // Arrange
        let registry = WorktreeContentRepairConsumerRegistry()
        let registration = makeRegistration()
        let consumer = try await requireRegistration(
            registry.register(registration: registration, eligibility: .eligible)
        )
        let activeCapture = try await requirePrepared(prepareCapture(registry, registration: registration))
        let activeBinding = await registry.bind(activeCapture, to: makeRepair(capture: activeCapture))
        guard case .boundActive(let activeAuthority) = activeBinding else {
            Issue.record("Expected initial generation to receive activation authority")
            return
        }
        let active = activeAuthority.boundGeneration
        let firstPendingCapture = try await requirePrepared(
            prepareCapture(registry, registration: registration)
        )
        let firstPendingBinding = await registry.bind(
            firstPendingCapture,
            to: makeRepair(capture: firstPendingCapture)
        )
        guard case .boundPending(let firstPending) = firstPendingBinding else {
            Issue.record("Expected successor generation to remain pending")
            return
        }
        let firstPendingReplay = await registry.bind(
            firstPendingCapture,
            to: firstPending.repairGeneration
        )
        let newestCapture = try await requirePrepared(prepareCapture(registry, registration: registration))
        let newestBinding = await registry.bind(newestCapture, to: makeRepair(capture: newestCapture))
        guard case .boundPending(let newest) = newestBinding else {
            Issue.record("Expected newest successor generation to remain pending")
            return
        }

        // Act
        let staleActive = await registry.acknowledge(
            repairGenerationID: active.repairGeneration.id,
            consumer: consumer.token,
            disposition: .rebuiltCurrent(consumerRevision: 1)
        )
        let supersededBind = await registry.bind(
            firstPendingCapture,
            to: firstPending.repairGeneration
        )
        let activation = await registry.activateBoundGeneration(newest.repairGeneration.id)
        let activationReplay = await registry.activateBoundGeneration(newest.repairGeneration.id)
        let stalePending = await registry.acknowledge(
            repairGenerationID: firstPending.repairGeneration.id,
            consumer: consumer.token,
            disposition: .rebuiltCurrent(consumerRevision: 2)
        )
        let stateBeforeNewestCompletion = try await requireLookup(registry.lookup(consumer.token))
        let newestCompletion = await registry.acknowledge(
            repairGenerationID: newest.repairGeneration.id,
            consumer: consumer.token,
            disposition: .rebuiltCurrent(consumerRevision: 3)
        )
        let stateAfterNewestCompletion = try await requireLookup(registry.lookup(consumer.token))

        // Assert
        #expect(staleActive == .debtRetained(.staleRepairGeneration))
        #expect(firstPendingReplay == .replayedPending(firstPending))
        #expect(
            firstPending.deliveryRequests.map(\.invalidationGeneration)
                == [firstPendingCapture.invalidationGeneration]
        )
        #expect(supersededBind == .captureSuperseded)
        guard case .activated(let activated) = activation else {
            Issue.record("Expected newest pending generation to activate")
            return
        }
        #expect(activated.boundGeneration == newest)
        #expect(activationReplay == .alreadyActive(activated))
        #expect(
            newest.deliveryRequests.map(\.invalidationGeneration)
                == [newestCapture.invalidationGeneration]
        )
        #expect(stalePending == .debtRetained(.staleRepairGeneration))
        guard case .nonCurrent(.repairPending(let newestRetry)) = stateBeforeNewestCompletion.currentness else {
            Issue.record("Expected newest repair to own currentness")
            return
        }
        #expect(newestRetry.repairGenerationID == newest.repairGeneration.id)
        guard case .accepted = newestCompletion else {
            Issue.record("Expected newest repair completion")
            return
        }
        #expect(
            stateAfterNewestCompletion.currentness
                == .current(
                    .rebuilt(
                        repairGenerationID: newest.repairGeneration.id,
                        consumerRevision: 3
                    )
                )
        )
    }

    @Test("outbound acknowledgements retain exact replay custody until confirmation")
    func outboundAcknowledgementCustodyIsExact() async throws {
        // Arrange
        let normal = try await makeBoundFixture()
        let withdrawal = try await makeBoundFixture()
        let replacement = try await makeBoundFixture()

        // Act
        let normalResult = await normal.registry.acknowledge(
            repairGenerationID: normal.bound.repairGeneration.id,
            consumer: normal.consumer.token,
            disposition: .rebuiltCurrent(consumerRevision: 11)
        )
        let normalAccepted = try requireAccepted(normalResult)
        let normalShutdown = await normal.registry.beginOrResumeShutdown()
        let wrongConfirmationToken = FilesystemRepairAcknowledgementToken(
            repairGenerationID: normalAccepted.sourceGateAcknowledgement.repairGenerationID,
            participant: FilesystemRepairParticipantToken(
                kind: .contentConsumer,
                participantID: UUIDv7.generate(),
                participantGeneration: 0
            )
        )
        let wrongConfirmation = await normal.registry.confirmSourceGateAcknowledgement(
            wrongConfirmationToken
        )
        let normalReplay = await normal.registry.acknowledge(
            repairGenerationID: normal.bound.repairGeneration.id,
            consumer: normal.consumer.token,
            disposition: .rebuiltCurrent(consumerRevision: 11)
        )
        let normalConfirmation = await normal.registry.confirmSourceGateAcknowledgement(
            normalAccepted.sourceGateAcknowledgement
        )
        let normalConfirmationReplay = await normal.registry.confirmSourceGateAcknowledgement(
            normalAccepted.sourceGateAcknowledgement
        )

        let withdrawalResult = await withdrawal.registry.withdraw(
            withdrawal.consumer.token,
            disposition: .noRetainedState
        )
        let withdrawalAccepted = try requireWithdrawalAccepted(withdrawalResult)
        _ = await withdrawal.registry.beginOrResumeShutdown()
        let withdrawalReplay = await withdrawal.registry.withdraw(
            withdrawal.consumer.token,
            disposition: .noRetainedState
        )
        let withdrawalConfirmation = await withdrawal.registry.confirmSourceGateAcknowledgement(
            withdrawalAccepted.sourceGateAcknowledgement
        )
        let withdrawalConfirmationReplay = await withdrawal.registry.confirmSourceGateAcknowledgement(
            withdrawalAccepted.sourceGateAcknowledgement
        )

        let replacementResult = await replacement.registry.replace(
            replacement.consumer.token,
            eligibility: .eligible
        )
        let replaced = try requireReplacement(replacementResult)
        guard case .transferred(let replacementAccepted) = replaced.repairDisposition else {
            Issue.record("Expected replacement transfer")
            return
        }
        let replacementConflict = await replacement.registry.replace(
            replacement.consumer.token,
            eligibility: .ineligibleNoRetainedContent
        )
        _ = await replacement.registry.beginOrResumeShutdown()
        let replacementReplay = await replacement.registry.replace(
            replacement.consumer.token,
            eligibility: .eligible
        )
        let replacementConfirmation = await replacement.registry.confirmSourceGateAcknowledgement(
            replacementAccepted.sourceGateAcknowledgement
        )
        let replacementConfirmationReplay = await replacement.registry.confirmSourceGateAcknowledgement(
            replacementAccepted.sourceGateAcknowledgement
        )

        // Assert
        guard case .awaitingDebt(let normalDebt) = normalShutdown else {
            Issue.record("Expected outbound custody to block shutdown")
            return
        }
        #expect(normalDebt.outboundAcknowledgements == [normalAccepted.sourceGateAcknowledgement])
        #expect(wrongConfirmation == .staleAcknowledgement)
        #expect(normalReplay == .replayed(normalAccepted))
        #expect(normalConfirmation == .confirmed(normalAccepted))
        #expect(normalConfirmationReplay == .replayed(normalAccepted))
        #expect(withdrawalReplay == .withdrawnAndAcknowledged(withdrawalAccepted))
        #expect(withdrawalConfirmation == .confirmed(withdrawalAccepted))
        #expect(withdrawalConfirmationReplay == .replayed(withdrawalAccepted))
        #expect(replacementReplay == .replaced(replaced))
        #expect(replacementConflict == .staleToken)
        #expect(replacementConfirmation == .confirmed(replacementAccepted))
        #expect(replacementConfirmationReplay == .replayed(replacementAccepted))
    }

    @Test("terminal capture replay compares the complete capture")
    func terminalCaptureReplayIsExact() async throws {
        // Arrange
        let abortedRegistry = WorktreeContentRepairConsumerRegistry()
        let boundRegistry = WorktreeContentRepairConsumerRegistry()
        let registration = makeRegistration()
        _ = try await requireRegistration(
            boundRegistry.register(registration: registration, eligibility: .eligible)
        )
        let aborted = try await requirePrepared(prepareCapture(abortedRegistry, registration: registration))
        let bound = try await requirePrepared(prepareCapture(boundRegistry, registration: registration))
        _ = await abortedRegistry.abortCapture(aborted)
        let boundGeneration = try await bindActive(bound, registry: boundRegistry).boundGeneration
        let malformedAborted = ContentRepairPreparedCapture(
            identity: aborted.identity,
            invalidationGeneration: ContentRepairInvalidationGeneration(
                value: aborted.invalidationGeneration.value + 1
            ),
            registration: aborted.registration,
            consumers: aborted.consumers
        )
        let malformedBound = ContentRepairPreparedCapture(
            identity: bound.identity,
            invalidationGeneration: bound.invalidationGeneration,
            registration: bound.registration,
            consumers: []
        )

        // Act
        let abortReplay = await abortedRegistry.abortCapture(malformedAborted)
        let bindReplay = await boundRegistry.bind(malformedBound, to: boundGeneration.repairGeneration)

        // Assert
        #expect(abortReplay == .staleCapture)
        #expect(bindReplay == .staleCapture)
    }

    @Test("shutdown reports simultaneous active and prepared repair debt")
    func shutdownReportsActiveAndPreparedDebt() async throws {
        // Arrange
        let registry = WorktreeContentRepairConsumerRegistry()
        let registration = makeRegistration()
        _ = try await requireRegistration(
            registry.register(registration: registration, eligibility: .eligible)
        )
        let activeCapture = try await requirePrepared(prepareCapture(registry, registration: registration))
        let active = try await bindActive(activeCapture, registry: registry).boundGeneration
        let pending = try await requirePrepared(prepareCapture(registry, registration: registration))

        // Act
        let shutdown = await registry.beginOrResumeShutdown()

        // Assert
        guard case .awaitingDebt(let debt) = shutdown else {
            Issue.record("Expected simultaneous repair debt")
            return
        }
        #expect(debt.activeRepairGenerations == [active.repairGeneration.id])
        #expect(debt.preparedCaptures == [pending.identity])
    }

    @Test("empty applicable capture completes without fabricated consumer debt")
    func emptyApplicableCaptureHasNoConsumerDebt() async throws {
        // Arrange
        let registry = WorktreeContentRepairConsumerRegistry()
        let registration = makeRegistration()
        let capture = try await requirePrepared(prepareCapture(registry, registration: registration))

        // Act
        let bound = try await bindActive(capture, registry: registry).boundGeneration
        let shutdown = await registry.beginOrResumeShutdown()

        // Assert
        #expect(capture.consumers.isEmpty)
        #expect(bound.deliveryRequests.isEmpty)
        #expect(shutdown == .completed(emptyShutdownDebt()))
    }

    @Test("retained retry blocks withdrawal and transfers through replacement")
    func retainedRetryRequiresReplacementTransfer() async throws {
        // Arrange
        let fixture = try await makeBoundFixture()
        let request = try requireRequest(for: fixture.consumer.token, in: fixture.bound)
        let acknowledgement = try requireAccepted(
            await fixture.registry.acknowledge(
                repairGenerationID: fixture.bound.repairGeneration.id,
                consumer: fixture.consumer.token,
                disposition: .markedNonCurrent(retry: request.retryToken)
            )
        )
        _ = await fixture.registry.confirmSourceGateAcknowledgement(
            acknowledgement.sourceGateAcknowledgement
        )

        // Act
        let withdrawal = await fixture.registry.withdraw(
            fixture.consumer.token,
            disposition: .noRetainedState
        )
        let replacement = try requireReplacement(
            await fixture.registry.replace(fixture.consumer.token, eligibility: .eligible)
        )
        let staleCompletion = await fixture.registry.completeRetry(
            request.retryToken,
            consumerRevision: 9
        )

        // Assert
        #expect(withdrawal == .retainedRetryRequiresTransfer(request.retryToken))
        guard case .nonCurrent(.retryRetained(let transferredRetry)) = replacement.registration.currentness else {
            Issue.record("Expected replacement retry custody")
            return
        }
        #expect(transferredRetry.consumer == replacement.registration.token)
        #expect(staleCompletion == .staleConsumerToken)
    }

    @Test("invalid capture binding and acknowledgement inputs are non-mutating")
    func invalidInputsAreRejectedExactly() async throws {
        // Arrange
        let registry = WorktreeContentRepairConsumerRegistry()
        let registration = makeRegistration()
        let first = try await requireRegistration(
            registry.register(registration: registration, eligibility: .eligible)
        )
        let second = try await requireRegistration(
            registry.register(registration: registration, eligibility: .eligible)
        )
        let capture = try await requirePrepared(prepareCapture(registry, registration: registration))
        let wrongRegistration = FSEventRegistrationToken(
            sourceID: registration.sourceID,
            registrationGeneration: registration.registrationGeneration + 1,
            rootGeneration: registration.rootGeneration
        )
        let wrongRegistrationRepair = RepairGeneration(
            id: RepairGenerationID(registration: wrongRegistration, sequence: 1),
            watermark: .recoveryRevision(1),
            trigger: .continuityLoss,
            participants: capture.sourceGateParticipants
        )
        let wrongParticipantsRepair = RepairGeneration(
            id: RepairGenerationID(registration: registration, sequence: 2),
            watermark: .recoveryRevision(2),
            trigger: .continuityLoss,
            participants: [first.token.sourceGateParticipant]
        )

        // Act
        let registrationMismatch = await registry.bind(capture, to: wrongRegistrationRepair)
        let participantMismatch = await registry.bind(capture, to: wrongParticipantsRepair)
        _ = await registry.abortCapture(capture)
        let bindAfterAbort = await registry.bind(capture, to: makeRepair(capture: capture))

        let retryRegistry = WorktreeContentRepairConsumerRegistry()
        let retryFirst = try await requireRegistration(
            retryRegistry.register(registration: registration, eligibility: .eligible)
        )
        let retrySecond = try await requireRegistration(
            retryRegistry.register(registration: registration, eligibility: .eligible)
        )
        let retryCapture = try await requirePrepared(prepareCapture(retryRegistry, registration: registration))
        let retryBound = try await bindActive(retryCapture, registry: retryRegistry).boundGeneration
        let wrongRetry = try requireRequest(for: retrySecond.token, in: retryBound).retryToken
        let retryMismatch = await retryRegistry.acknowledge(
            repairGenerationID: retryBound.repairGeneration.id,
            consumer: retryFirst.token,
            disposition: .markedNonCurrent(retry: wrongRetry)
        )

        // Assert
        #expect(
            registrationMismatch
                == .registrationMismatch(expected: registration, actual: wrongRegistration)
        )
        #expect(
            participantMismatch
                == .participantMismatch(
                    expected: capture.sourceGateParticipants,
                    actual: [first.token.sourceGateParticipant]
                )
        )
        #expect(bindAfterAbort == .captureAborted)
        #expect(retryMismatch == .debtRetained(.retryTokenMismatch))
        #expect(await registry.lookup(second.token) == .registered(second))
    }

    @Test("replacement exhaustion and source retirement reject before mutation")
    func replacementExhaustionAndSourceRetirementAreExact() async throws {
        // Arrange
        let exhaustedRegistry = WorktreeContentRepairConsumerRegistry(initialConsumerGeneration: .max)
        let retirementRegistry = WorktreeContentRepairConsumerRegistry()
        let registration = makeRegistration()
        let exhausted = try await requireRegistration(
            exhaustedRegistry.register(registration: registration, eligibility: .eligible)
        )
        let retirementConsumer = try await requireRegistration(
            retirementRegistry.register(registration: registration, eligibility: .eligible)
        )
        let retirementCapture = try await requirePrepared(
            prepareCapture(retirementRegistry, registration: registration)
        )

        // Act
        let exhaustedReplacement = await exhaustedRegistry.replace(
            exhausted.token,
            eligibility: .ineligibleNoRetainedContent
        )
        let exhaustedState = try await requireLookup(exhaustedRegistry.lookup(exhausted.token))
        let blockedRetirement = await retirementRegistry.retireSource(registration.sourceID)
        _ = await retirementRegistry.abortCapture(retirementCapture)
        let activeCapture = try await requirePrepared(
            prepareCapture(retirementRegistry, registration: registration)
        )
        let active = try await bindActive(activeCapture, registry: retirementRegistry).boundGeneration
        let activeDebt = await retirementRegistry.retireSource(registration.sourceID)
        let request = try requireRequest(for: retirementConsumer.token, in: active)
        let accepted = try requireAccepted(
            await retirementRegistry.acknowledge(
                repairGenerationID: active.repairGeneration.id,
                consumer: retirementConsumer.token,
                disposition: .markedNonCurrent(retry: request.retryToken)
            )
        )
        let outboundAndRetryDebt = await retirementRegistry.retireSource(registration.sourceID)
        _ = await retirementRegistry.confirmSourceGateAcknowledgement(
            accepted.sourceGateAcknowledgement
        )
        let retryDebt = await retirementRegistry.retireSource(registration.sourceID)
        let replacement = try requireReplacement(
            await retirementRegistry.replace(retirementConsumer.token, eligibility: .eligible)
        )
        guard case .nonCurrent(.retryRetained(let transferredRetry)) = replacement.registration.currentness else {
            Issue.record("Expected transferred retry before retirement")
            return
        }
        _ = await retirementRegistry.completeRetry(transferredRetry, consumerRevision: 13)
        let retired = await retirementRegistry.retireSource(registration.sourceID)
        let replayedRetirement = await retirementRegistry.retireSource(registration.sourceID)

        // Assert
        #expect(exhaustedReplacement == .generationExhausted)
        #expect(exhaustedState == exhausted)
        guard case .outstandingDebt(let debt) = blockedRetirement else {
            Issue.record("Expected prepared capture retirement debt")
            return
        }
        #expect(debt.preparedCaptures == [retirementCapture.identity])
        guard case .outstandingDebt(let activeRetirementDebt) = activeDebt else {
            Issue.record("Expected active repair retirement debt")
            return
        }
        #expect(activeRetirementDebt.activeRepairGenerations == [active.repairGeneration.id])
        guard case .outstandingDebt(let outboundRetryRetirementDebt) = outboundAndRetryDebt else {
            Issue.record("Expected outbound and retry retirement debt")
            return
        }
        #expect(
            outboundRetryRetirementDebt.outboundAcknowledgements
                == [accepted.sourceGateAcknowledgement]
        )
        #expect(outboundRetryRetirementDebt.retainedRetries == [request.retryToken])
        guard case .outstandingDebt(let retainedRetryDebt) = retryDebt else {
            Issue.record("Expected retained retry retirement debt")
            return
        }
        #expect(retainedRetryDebt.outboundAcknowledgements.isEmpty)
        #expect(retainedRetryDebt.retainedRetries == [request.retryToken])
        #expect(retired == .retired(registration.sourceID))
        #expect(replayedRetirement == .alreadyRetired(registration.sourceID))
        #expect(await retirementRegistry.lookup(retirementConsumer.token) == .foreignSource)
    }

    @Test("checked generations reject before mutating registry")
    func generationExhaustionRejectsBeforeMutation() async {
        // Arrange
        let registrationOrdinalRegistry = WorktreeContentRepairConsumerRegistry(
            nextConsumerRegistrationOrdinal: .max
        )
        let invalidationRegistry = WorktreeContentRepairConsumerRegistry(
            nextInvalidationGeneration: .max
        )
        let registration = makeRegistration()

        // Act
        let registrationResult = await registrationOrdinalRegistry.register(
            registration: registration,
            eligibility: .eligible
        )
        let captureResult = await prepareCapture(invalidationRegistry, registration: registration)

        // Assert
        #expect(registrationResult == .generationExhausted)
        #expect(captureResult == .generationExhausted)
        #expect(await registrationOrdinalRegistry.shutdownDebtSnapshot().isEmpty)
        #expect(await invalidationRegistry.shutdownDebtSnapshot().isEmpty)
    }
}
