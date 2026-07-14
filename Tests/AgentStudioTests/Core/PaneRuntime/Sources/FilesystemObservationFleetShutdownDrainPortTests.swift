import Foundation
import Testing
import os

@testable import AgentStudio

@Suite("Filesystem observation fleet shutdown drain port")
struct FilesystemObservationFleetShutdownDrainPortTests {
    @Test("full debt capture normalizes actor projections into mailbox slot order")
    func fullDebtCaptureNormalizesActorProjectionsIntoMailboxSlotOrder() async throws {
        let fixture = try makeFixture(sourceCount: 3)
        let actorOrder = [fixture.bindings[2], fixture.bindings[0], fixture.bindings[1]]
        let harness = try makeHarness(
            fixture: fixture,
            bindingsInDeclarationOrder: actorOrder
        )
        let lifecycle = FilesystemObservationFleetLifecycle()
        _ = lifecycle.beginShutdownAndSnapshot(mailbox: fixture.mailbox)

        let result = await lifecycle.shutdownDebtSnapshot(
            mailbox: fixture.mailbox,
            drainPort: await harness.fleetShutdownDrainPort
        )

        guard case .captured(let snapshot, let turnPlan) = result else {
            Issue.record("full debt capture rejected valid reordered actor coverage: \(result)")
            return
        }
        let mailboxOrder = snapshot.mailbox.slots.map(\.physicalSlotID)
        #expect(snapshot.actor.semanticReplay.slots.map(\.physicalSlotID) == mailboxOrder)
        #expect(
            snapshot.actor.sourceGatesInBindingDeclarationOrder.map(\.binding.physicalSlotID)
                == mailboxOrder
        )
        #expect(turnPlan == .beginSourceGateShutdown)
        #expect(snapshot.shutdownIdentity.isUUIDv7)

        let incompleteSourceGateActor = FilesystemObservationFleetShutdownActorDebtSnapshot(
            semanticReplay: snapshot.actor.semanticReplay,
            sourceGatesInBindingDeclarationOrder: Array(
                snapshot.actor.sourceGatesInBindingDeclarationOrder.dropLast()
            )
        )
        guard
            case .rejected(.sourceGateCoverageMismatch(let expectedSlots, let presentedBindings)) =
                FilesystemObservationFleetShutdownDebtJoiner.join(
                    mailbox: snapshot.mailbox,
                    actor: incompleteSourceGateActor
                )
        else {
            Issue.record("incomplete SourceGate coverage produced a full fleet snapshot")
            return
        }
        #expect(expectedSlots == mailboxOrder)
        #expect(
            presentedBindings
                == incompleteSourceGateActor.sourceGatesInBindingDeclarationOrder.map(\.binding)
        )

        let replay = await lifecycle.shutdownDebtSnapshot(
            mailbox: fixture.mailbox,
            drainPort: await harness.fleetShutdownDrainPort
        )
        #expect(replay == result)
    }

    @Test("full debt capture rejects incomplete actor coverage before planning")
    func fullDebtCaptureRejectsIncompleteActorCoverageBeforePlanning() async throws {
        let fixture = try makeFixture(sourceCount: 2)
        let incompleteBindings = [fixture.bindings[1]]
        let harness = try makeHarness(
            fixture: fixture,
            bindingsInDeclarationOrder: incompleteBindings
        )
        let lifecycle = FilesystemObservationFleetLifecycle()
        let mailboxSnapshot = requireAppliedShutdownDebtSnapshot(
            lifecycle.beginShutdownAndSnapshot(mailbox: fixture.mailbox)
        )

        let result = await lifecycle.shutdownDebtSnapshot(
            mailbox: fixture.mailbox,
            drainPort: await harness.fleetShutdownDrainPort
        )

        guard case .debtJoinRejected(.semanticSlotCoverageMismatch(let mailbox, let actor)) = result
        else {
            Issue.record("incomplete actor coverage produced a plan: \(result)")
            return
        }
        #expect(mailbox == mailboxSnapshot.slots.map(\.physicalSlotID))
        #expect(actor == incompleteBindings.map(\.physicalSlotID))
    }

    @Test("full debt join rejects foreign SourceGate fleet identity before planning")
    func fullDebtJoinRejectsForeignSourceGateFleetIdentityBeforePlanning() async throws {
        let fixture = try makeFixture(sourceCount: 1)
        let foreignFixture = try makeFixture(sourceCount: 1)
        let harness = try makeHarness(fixture: fixture)
        let snapshot = await requireCapturedDebt(fixture: fixture, harness: harness)
        let sourceGate = try #require(snapshot.actor.sourceGatesInBindingDeclarationOrder.first)
        let originalBinding = sourceGate.binding
        let foreignBinding = FilesystemObservationSlotBinding(
            fleetMailboxIdentity: foreignFixture.mailbox.fleetMailboxIdentity,
            physicalSlotID: originalBinding.physicalSlotID,
            identity: originalBinding.identity,
            registration: originalBinding.registration,
            controlBlockIdentity: originalBinding.controlBlockIdentity
        )
        let foreignSourceGate = FilesystemSourceGateShutdownDebtSnapshot(
            binding: foreignBinding,
            repairLifecycle: sourceGate.repairLifecycle,
            mailboxRecoveryReplay: sourceGate.mailboxRecoveryReplay,
            continuityRepairReplay: sourceGate.continuityRepairReplay
        )
        let foreignActor = FilesystemObservationFleetShutdownActorDebtSnapshot(
            semanticReplay: snapshot.actor.semanticReplay,
            sourceGatesInBindingDeclarationOrder: [foreignSourceGate]
        )

        let joinResult = FilesystemObservationFleetShutdownDebtJoiner.join(
            mailbox: snapshot.mailbox,
            actor: foreignActor
        )

        #expect(
            joinResult
                == .rejected(
                    .sourceGateFleetMailboxMismatch(
                        expected: fixture.mailbox.fleetMailboxIdentity,
                        presentedBindings: [foreignBinding]
                    )
                )
        )
    }

    @Test("detached desired custody waits instead of falsely advancing mailbox")
    func detachedDesiredCustodyWaitsInsteadOfFalselyAdvancingMailbox() async throws {
        let fixture = try makeFixture(sourceCount: 1)
        let harness = try makeHarness(fixture: fixture)
        let snapshot = await requireCapturedDebt(fixture: fixture, harness: harness)
        let sourceGate = try #require(snapshot.actor.sourceGatesInBindingDeclarationOrder.first)
        let registration = fixture.registrations[0]
        let detachedDesired = FilesystemObservationDesiredShutdownReference(
            sourceID: registration.sourceID,
            registration: registration,
            desiredIdentity: FilesystemObservationDesiredIdentity(value: UUIDv7.generate()),
            acceptedTopologyRevision: FilesystemObservationAcceptedTopologyRevision(value: 1)
        )
        let detachedCustody = FilesystemObservationPendingDesiredShutdownCustody(
            desired: detachedDesired,
            continuityRepair: .absent
        )
        let desiredCustody = FilesystemObservationDesiredShutdownCustody(
            deferredFIFO: [],
            pendingInDeclaredSlotOrder: [],
            pendingInDeferredFIFOOrder: [],
            detachedPending: FilesystemObservationDetachedPendingShutdownInventory(
                pendingBySourceID: [registration.sourceID: detachedCustody]
            )
        )
        let mailbox = FilesystemObservationFleetShutdownMailboxDebtSnapshot(
            fleetMailboxIdentity: snapshot.mailbox.fleetMailboxIdentity,
            shutdownIdentity: snapshot.mailbox.shutdownIdentity,
            fleetIngressLifecycle: snapshot.mailbox.fleetIngressLifecycle,
            fleetOrdinaryAdmissionDisposition: snapshot.mailbox.fleetOrdinaryAdmissionDisposition,
            mailboxLifecycle: snapshot.mailbox.mailboxLifecycle,
            slots: snapshot.mailbox.slots,
            desiredCustody: desiredCustody,
            activeLease: snapshot.mailbox.activeLease,
            pendingWholeLeaseCompletion: snapshot.mailbox.pendingWholeLeaseCompletion,
            genericMailboxDebt: snapshot.mailbox.genericMailboxDebt,
            retirementFenceReadyFIFO: snapshot.mailbox.retirementFenceReadyFIFO,
            isQuiescent: false
        )
        let actor = FilesystemObservationFleetShutdownActorDebtSnapshot(
            semanticReplay: snapshot.actor.semanticReplay,
            sourceGatesInBindingDeclarationOrder: [
                FilesystemSourceGateShutdownDebtSnapshot(
                    binding: sourceGate.binding,
                    repairLifecycle: .repairAdmissionOpen(.noOutstandingRepair),
                    mailboxRecoveryReplay: .vacant,
                    continuityRepairReplay: sourceGate.continuityRepairReplay
                )
            ]
        )

        let turnPlan = FilesystemObservationFleetShutdownTurnPlanner.plan(
            FilesystemObservationFleetShutdownDebtSnapshot(mailbox: mailbox, actor: actor)
        )

        #expect(turnPlan == .beginSourceGateShutdown)
    }

    @Test("queued observation produces one actor-drain turn plan")
    func queuedObservationProducesOneActorDrainTurnPlan() async throws {
        let fixture = try makeFixture(sourceCount: 1)
        expectRetainedCallback(
            try fixture.fixture.admitCallback(
                .authoritative(
                    try makeObservation(
                        registration: fixture.registrations[0],
                        path: "/fleet-shutdown-plan/actor-drain",
                        eventID: 1
                    )
                ),
                for: fixture.registrations[0]
            )
        )
        let harness = try makeHarness(fixture: fixture)
        let lifecycle = FilesystemObservationFleetLifecycle()
        _ = lifecycle.beginShutdownAndSnapshot(mailbox: fixture.mailbox)

        let result = await lifecycle.shutdownDebtSnapshot(
            mailbox: fixture.mailbox,
            drainPort: await harness.fleetShutdownDrainPort
        )

        guard case .captured(let snapshot, .advanceMailbox) = result else {
            Issue.record("queued observation did not produce a full debt plan: \(result)")
            return
        }
        let originalSlot = try #require(snapshot.mailbox.slots.first)
        let actorDrainSlot = FilesystemObservationSlotShutdownDebt(
            physicalSlotID: originalSlot.physicalSlotID,
            registry: originalSlot.registry,
            nativeOwner: .vacant,
            retryEvidence: originalSlot.retryEvidence,
            recoveryEvidence: originalSlot.recoveryEvidence,
            generic: originalSlot.generic,
            completedReleaseReplay: originalSlot.completedReleaseReplay
        )
        let actorDrainMailbox = FilesystemObservationFleetShutdownMailboxDebtSnapshot(
            fleetMailboxIdentity: snapshot.mailbox.fleetMailboxIdentity,
            shutdownIdentity: snapshot.mailbox.shutdownIdentity,
            fleetIngressLifecycle: snapshot.mailbox.fleetIngressLifecycle,
            fleetOrdinaryAdmissionDisposition: snapshot.mailbox.fleetOrdinaryAdmissionDisposition,
            mailboxLifecycle: snapshot.mailbox.mailboxLifecycle,
            slots: [actorDrainSlot],
            desiredCustody: snapshot.mailbox.desiredCustody,
            activeLease: snapshot.mailbox.activeLease,
            pendingWholeLeaseCompletion: snapshot.mailbox.pendingWholeLeaseCompletion,
            genericMailboxDebt: snapshot.mailbox.genericMailboxDebt,
            retirementFenceReadyFIFO: snapshot.mailbox.retirementFenceReadyFIFO,
            isQuiescent: false
        )
        let actorDrainSnapshot = FilesystemObservationFleetShutdownDebtSnapshot(
            mailbox: actorDrainMailbox,
            actor: snapshot.actor
        )

        #expect(
            FilesystemObservationFleetShutdownTurnPlanner.plan(actorDrainSnapshot)
                == .advanceActorDrain
        )
    }

    @Test("full debt capture distinguishes shutdown not begun and foreign mailbox")
    func fullDebtCaptureDistinguishesNotBegunAndForeignMailbox() async throws {
        let fixture = try makeFixture(sourceCount: 1)
        let foreignFixture = try makeFixture(sourceCount: 1)
        let harness = try makeHarness(fixture: fixture)
        let lifecycle = FilesystemObservationFleetLifecycle()
        let port = await harness.fleetShutdownDrainPort

        #expect(
            await lifecycle.shutdownDebtSnapshot(mailbox: fixture.mailbox, drainPort: port)
                == .shutdownNotBegun
        )
        _ = lifecycle.beginShutdownAndSnapshot(mailbox: fixture.mailbox)
        guard
            case .fleetMailboxMismatch(let expected, let presented) =
                await lifecycle.shutdownDebtSnapshot(
                    mailbox: foreignFixture.mailbox,
                    drainPort: port
                )
        else {
            Issue.record("foreign mailbox was not rejected by retained lifecycle binding")
            return
        }
        #expect(expected == fixture.mailbox.fleetMailboxIdentity)
        #expect(presented == foreignFixture.mailbox.fleetMailboxIdentity)
    }

    @Test("snapshot preserves binding declaration order and remains exact")
    func snapshotPreservesBindingDeclarationOrderAndRemainsExact() async throws {
        let fixture = try makeFixture(sourceCount: 3)
        let declarationOrder = [
            fixture.bindings[2],
            fixture.bindings[0],
            fixture.bindings[1],
        ]
        let harness = try makeHarness(
            fixture: fixture,
            bindingsInDeclarationOrder: declarationOrder
        )
        let port = await harness.fleetShutdownDrainPort

        let first = await port.snapshot()
        let replay = await port.snapshot()

        #expect(first == replay)
        #expect(first.semanticReplay.isQuiescent)
        #expect(
            first.sourceGatesInBindingDeclarationOrder.map(\.binding)
                == declarationOrder
        )
        #expect(
            first.sourceGatesInBindingDeclarationOrder.allSatisfy {
                $0.shutdownBeginReadiness == .ready
            }
        )
        #expect(!first.isQuiescent)
    }

    @Test("one drain turn transfers at most one lease")
    func oneDrainTurnTransfersAtMostOneLease() async throws {
        let fixture = try makeFixture(sourceCount: 2)
        for (index, registration) in fixture.registrations.enumerated() {
            expectRetainedCallback(
                try fixture.fixture.admitCallback(
                    .authoritative(
                        try makeObservation(
                            registration: registration,
                            path: "/fleet-shutdown-drain/\(index)",
                            eventID: UInt64(index + 1)
                        )
                    ),
                    for: registration
                )
            )
        }
        let harness = try makeHarness(fixture: fixture)
        let port = await harness.fleetShutdownDrainPort

        let first = await port.advanceOneTurn()
        let second = await port.advanceOneTurn()
        let third = await port.advanceOneTurn()

        guard case .leaseTransfer(let firstBinding, .transferred) = first else {
            Issue.record("first bounded turn did not transfer one lease: \(first)")
            return
        }
        guard case .leaseTransfer(let secondBinding, .transferred) = second else {
            Issue.record("second bounded turn did not transfer one lease: \(second)")
            return
        }
        #expect(firstBinding != secondBinding)
        #expect(third == .noProgress(.mailboxEmpty))
    }

    @Test("omitted binding rejects configuration before mailbox custody is taken")
    func omittedBindingRejectsConfigurationBeforeMailboxCustodyIsTaken() async throws {
        let fixture = try makeFixture(sourceCount: 2)
        expectRetainedCallback(
            try fixture.fixture.admitCallback(
                .authoritative(
                    try makeObservation(
                        registration: fixture.registrations[1],
                        path: "/fleet-shutdown-drain/omitted-binding",
                        eventID: 1
                    )
                ),
                for: fixture.registrations[1]
            )
        )
        let configuredBindings = [fixture.bindings[0]]
        let harness = try makeHarness(
            fixture: fixture,
            bindingsInDeclarationOrder: configuredBindings
        )
        let port = await harness.fleetShutdownDrainPort
        let expectedRejection =
            FilesystemObservationFleetShutdownDrainConfigurationRejection
            .physicalSlotCoverageMismatch(
                mailboxPhysicalSlotIDsInDeclarationOrder: fixture.mailbox.physicalSlotIDs,
                actorBindingsInDeclarationOrder: configuredBindings
            )

        let first = await port.advanceOneTurn()
        let second = await port.advanceOneTurn()

        #expect(first == .noProgress(.configurationRejected(expectedRejection)))
        #expect(second == .noProgress(.configurationRejected(expectedRejection)))
        guard case .configurationRejected(let takeRejection) = await harness.takeLease() else {
            Issue.record("invalid harness configuration reached mailbox lease custody")
            return
        }
        #expect(takeRejection == expectedRejection)

        let validHarness = try makeHarness(fixture: fixture)
        guard case .lease(let retainedLease) = await validHarness.takeLease() else {
            Issue.record("omitted contribution was lost or stranded by configuration rejection")
            return
        }
        #expect(retainedLease.binding == fixture.bindings[1])
        guard case .contributions(let retainedContributions) = retainedLease.payload else {
            Issue.record("omitted authoritative contribution changed payload kind")
            return
        }
        #expect(retainedContributions.remaining.isEmpty)
    }

    @Test("cleanup-required turn performs exactly one cleanup quantum")
    func cleanupRequiredTurnPerformsExactlyOneCleanupQuantum() async throws {
        let fixture = try makeFixture(sourceCount: 1)
        let probe = DrainPortCleanupProbe(underlying: fixture.mailbox.actorConsumerPort)
        let harness = try makeHarness(
            fixture: fixture,
            consumerPort: probe.port
        )
        let port = await harness.fleetShutdownDrainPort

        let first = await port.advanceOneTurn()

        #expect(
            first
                == .cleanup(
                    .performed(
                        AdmissionCleanupTurn(
                            release: .entries(count: 1),
                            wake: .noWake
                        )
                    )
                )
        )
        #expect(probe.cleanupCallCount == 1)
    }

    @Test("empty active-lease and closed outcomes are strict no-progress results")
    func emptyActiveLeaseAndClosedOutcomesAreStrictNoProgressResults() async throws {
        let emptyFixture = try makeFixture(sourceCount: 1)
        let emptyHarness = try makeHarness(fixture: emptyFixture)
        let emptyPort = await emptyHarness.fleetShutdownDrainPort
        #expect(await emptyPort.advanceOneTurn() == .noProgress(.mailboxEmpty))

        let leasedFixture = try makeFixture(sourceCount: 1)
        expectRetainedCallback(
            try leasedFixture.fixture.admitCallback(
                .authoritative(
                    try makeObservation(
                        registration: leasedFixture.registrations[0],
                        path: "/fleet-shutdown-drain/already-leased",
                        eventID: 1
                    )
                )
            )
        )
        let leasedHarness = try makeHarness(fixture: leasedFixture)
        guard case .lease = await leasedHarness.takeLease() else {
            Issue.record("arrange failed to retain the actor-owned active lease")
            return
        }
        let leasedPort = await leasedHarness.fleetShutdownDrainPort
        #expect(
            await leasedPort.advanceOneTurn()
                == .noProgress(.activeLeaseAlreadyTaken)
        )

        let closedFixture = try makeFixture(sourceCount: 1)
        let closedHarness = try makeHarness(fixture: closedFixture)
        #expect(closedFixture.mailbox.lifecyclePort.seal() == .applied)
        let closedPort = await closedHarness.fleetShutdownDrainPort
        #expect(await closedPort.advanceOneTurn() == .noProgress(.mailboxClosed))
    }

    @Test("missing actor recovery context leaves mailbox custody unchanged")
    func missingActorRecoveryContextLeavesMailboxCustodyUnchanged() async throws {
        let fixture = try makeFixture(sourceCount: 1)
        let evidence = requireRetainedRecovery(
            try fixture.fixture.admitCallback(
                .requiresRecovery(
                    try makeObservation(
                        registration: fixture.registrations[0],
                        path: "/fleet-shutdown-drain/recovery",
                        eventID: 1
                    ),
                    evidence: .continuityLoss
                )
            )
        )
        let harness = try makeHarness(
            fixture: fixture,
            recoveryContextResolver: FilesystemObservationRecoveryContextResolver { _, _ in
                .unavailable
            }
        )
        let port = await harness.fleetShutdownDrainPort

        let first = await port.advanceOneTurn()
        let replay = await port.advanceOneTurn()

        let expected =
            FilesystemObservationFleetShutdownDrainNoProgress
            .recoveryContextUnavailable(
                binding: fixture.bindings[0],
                evidence: evidence.revision
            )
        #expect(first == .noProgress(expected))
        #expect(replay == .noProgress(expected))
        guard case .lease(let retainedLease) = await harness.takeLease() else {
            Issue.record("unavailable recovery context took or mutated mailbox custody")
            return
        }
        #expect(requireRecovery(retainedLease).revision == evidence.revision)
    }

    @Test("actor recovery resolver transfers the exact recovery-bearing lease")
    func actorRecoveryResolverTransfersExactRecoveryBearingLease() async throws {
        let fixture = try makeFixture(sourceCount: 1)
        let evidence = requireRetainedRecovery(
            try fixture.fixture.admitCallback(
                .requiresRecovery(
                    try makeObservation(
                        registration: fixture.registrations[0],
                        path: "/fleet-shutdown-drain/recovery-resolved",
                        eventID: 1
                    ),
                    evidence: .continuityLoss
                )
            )
        )
        let harness = try makeHarness(
            fixture: fixture,
            recoveryContextResolver: FilesystemObservationRecoveryContextResolver {
                // swiftlint:disable:next closure_parameter_position
                binding, presentedEvidence in
                guard
                    binding == evidence.revision.binding,
                    presentedEvidence.revision == evidence.revision
                else {
                    return .unavailable
                }
                return .resolved(requiredRecoveryAdmissionContext())
            }
        )
        let port = await harness.fleetShutdownDrainPort

        let result = await port.advanceOneTurn()

        guard case .leaseTransfer(let binding, .transferred) = result else {
            Issue.record("actor-local recovery policy did not transfer: \(result)")
            return
        }
        #expect(binding == evidence.revision.binding)
        #expect((await port.snapshot()).semanticReplay.isQuiescent)
    }

    @Test("semantic replay debt remains exact until the lease transfer succeeds")
    func semanticReplayDebtRemainsExactUntilLeaseTransferSucceeds() async throws {
        let fixture = try makeFixture(sourceCount: 1)
        expectRetainedCallback(
            try fixture.fixture.admitCallback(
                .authoritative(
                    try makeObservation(
                        registration: fixture.registrations[0],
                        path: "/fleet-shutdown-drain/semantic-replay",
                        eventID: 1
                    )
                )
            )
        )
        let harness = try makeHarness(fixture: fixture)
        await harness.rejectNextAcknowledgement()
        let port = await harness.fleetShutdownDrainPort

        let rejected = await port.advanceOneTurn()
        let retained = await port.snapshot()
        await harness.rebindConsumer()
        let replayed = await port.advanceOneTurn()
        let cleared = await port.snapshot()

        #expect(
            rejected
                == .leaseTransfer(
                    binding: fixture.bindings[0],
                    .rejected(.genericAcknowledgement)
                )
        )
        #expect(!retained.semanticReplay.isQuiescent)
        guard case .retained(let retainedDebt) = retained.semanticReplay.slots[0] else {
            Issue.record("failed transfer did not retain exact semantic replay debt")
            return
        }
        #expect(retainedDebt.fingerprint.binding == fixture.bindings[0])
        guard case .leaseTransfer(let binding, .transferred) = replayed else {
            Issue.record("retained semantic debt did not replay to completion: \(replayed)")
            return
        }
        #expect(binding == fixture.bindings[0])
        #expect(cleared.semanticReplay.isQuiescent)
    }

    @Test("source gate begin skips debt and advances only the first ready gate")
    func sourceGateBeginSkipsDebtAndAdvancesOnlyFirstReadyGate() async throws {
        let fixture = try makeFixture(sourceCount: 3)
        let harness = try makeHarness(fixture: fixture)
        var blockedGate = FilesystemSourceGate(binding: fixture.bindings[0])
        _ = try admitRepair(to: &blockedGate, sequence: 1)
        #expect(await harness.replaceSourceGateForTesting(blockedGate))
        let port = await harness.fleetShutdownDrainPort

        let first = await port.beginOneReadySourceGateShutdown()
        let afterFirst = await port.snapshot()

        guard case .applied(let binding, let debt) = first else {
            Issue.record("ready gate after outstanding debt was not advanced: \(first)")
            return
        }
        #expect(binding == fixture.bindings[1])
        #expect(debt.shutdownBeginReadiness == .alreadyBegan)
        #expect(
            afterFirst.sourceGatesInBindingDeclarationOrder.map(\.shutdownBeginReadiness)
                == [.awaitingRepairLifecycle, .alreadyBegan, .ready]
        )

        let second = await port.beginOneReadySourceGateShutdown()
        guard case .applied(let secondBinding, _) = second else {
            Issue.record("second ready gate did not advance: \(second)")
            return
        }
        #expect(secondBinding == fixture.bindings[2])
        #expect(
            await port.beginOneReadySourceGateShutdown()
                == .outstandingDebt(await port.snapshot())
        )
    }

    @Test("source gate readiness projections remain exact across every alternative")
    func sourceGateReadinessProjectionsRemainExactAcrossEveryAlternative() async throws {
        let fixture = try makeFixture(sourceCount: 5)
        let harness = try makeHarness(fixture: fixture)

        var repairOnly = FilesystemSourceGate(binding: fixture.bindings[0])
        _ = try admitRepair(to: &repairOnly, sequence: 10)
        #expect(await harness.replaceSourceGateForTesting(repairOnly))

        let combinedRecoveryEvidence = requireRetainedRecovery(
            try fixture.fixture.admitCallback(
                .requiresRecovery(
                    try makeObservation(
                        registration: fixture.registrations[1],
                        path: "/fleet-shutdown-drain/mailbox-recovery",
                        eventID: 11
                    ),
                    evidence: .continuityLoss
                ),
                for: fixture.registrations[1]
            )
        )
        var combined = FilesystemSourceGate(binding: fixture.bindings[1])
        _ = try requireRecoveryAdmission(
            into: &combined,
            evidence: combinedRecoveryEvidence
        )
        #expect(await harness.replaceSourceGateForTesting(combined))

        let mailboxOnlyRecoveryEvidence = requireRetainedRecovery(
            try fixture.fixture.admitCallback(
                .requiresRecovery(
                    try makeObservation(
                        registration: fixture.registrations[2],
                        path: "/fleet-shutdown-drain/mailbox-recovery-only",
                        eventID: 12
                    ),
                    evidence: .continuityLoss
                ),
                for: fixture.registrations[2]
            )
        )
        var mailboxOnly = FilesystemSourceGate(binding: fixture.bindings[2])
        let recoveryAcceptance = try requireRecoveryAdmission(
            into: &mailboxOnly,
            evidence: mailboxOnlyRecoveryEvidence
        )
        #expect(mailboxOnly.beginReconciliation(recoveryAcceptance.repairGeneration.id) == .applied)
        #expect(mailboxOnly.completeReconciliation(recoveryAcceptance.repairGeneration.id) == .applied)
        acknowledgeAll(recoveryAcceptance.repairGeneration, in: &mailboxOnly)
        #expect(await harness.replaceSourceGateForTesting(mailboxOnly))

        var alreadyBegan = FilesystemSourceGate(binding: fixture.bindings[3])
        guard case .applied = alreadyBegan.beginShutdown() else {
            Issue.record("arrange failed to begin SourceGate shutdown")
            return
        }
        #expect(await harness.replaceSourceGateForTesting(alreadyBegan))

        let snapshot = await (await harness.fleetShutdownDrainPort).snapshot()

        #expect(
            snapshot.sourceGatesInBindingDeclarationOrder.map(\.shutdownBeginReadiness)
                == [
                    .awaitingRepairLifecycle,
                    .awaitingRepairLifecycleAndMailboxRecoveryTransfer,
                    .awaitingMailboxRecoveryTransfer,
                    .alreadyBegan,
                    .ready,
                ]
        )
    }

    @Test("retained continuity replay does not independently block quiescence")
    func retainedContinuityReplayDoesNotIndependentlyBlockQuiescence() async throws {
        let fixture = try makeFixture(sourceCount: 1)
        let harness = try makeHarness(fixture: fixture)
        var gate = FilesystemSourceGate(binding: fixture.bindings[0])
        let authority = FilesystemContinuityRepairHandoffAuthority(
            acceptingBinding: gate.binding,
            handoffIdentity: FilesystemContinuityRepairHandoffIdentity(value: UUIDv7.generate()),
            desiredIdentity: FilesystemObservationDesiredIdentity(value: UUIDv7.generate()),
            acceptedTopologyRevision: FilesystemObservationAcceptedTopologyRevision(value: 1)
        )
        guard
            case .admitted(let acceptance) = gate.acceptContinuityRepairHandoff(
                authority,
                trigger: .continuityLoss,
                watermark: .recoveryRevision(1),
                participants: makeRequiredParticipants()
            )
        else {
            Issue.record("arrange failed to retain continuity repair replay")
            return
        }
        #expect(gate.beginReconciliation(acceptance.repairGeneration.id) == .applied)
        #expect(gate.completeReconciliation(acceptance.repairGeneration.id) == .applied)
        acknowledgeAll(acceptance.repairGeneration, in: &gate)
        #expect(gate.shutdownDebtSnapshot.shutdownBeginReadiness == .ready)
        #expect(gate.shutdownDebtSnapshot.continuityRepairReplay != .vacant)
        #expect(await harness.replaceSourceGateForTesting(gate))
        let port = await harness.fleetShutdownDrainPort

        guard case .applied = await port.beginOneReadySourceGateShutdown() else {
            Issue.record("continuity replay incorrectly blocked SourceGate shutdown")
            return
        }
        let snapshot = await port.snapshot()

        #expect(snapshot.isQuiescent)
        #expect(
            snapshot.sourceGatesInBindingDeclarationOrder[0].continuityRepairReplay
                != .vacant
        )
        #expect(
            await port.beginOneReadySourceGateShutdown()
                == .allGatesAlreadyShutdown(snapshot)
        )
    }

    private struct Fixture {
        let fixture: FixedSlotFilesystemObservationMailboxFixture
        let registrations: [FSEventRegistrationToken]
        let bindings: [FilesystemObservationSlotBinding]

        var mailbox: FilesystemObservationMailbox { fixture.mailbox }
    }

    private func makeFixture(sourceCount: Int) throws -> Fixture {
        let registrations = (0..<sourceCount).map { index in
            FSEventRegistrationToken(
                sourceID: FilesystemSourceID(
                    kind: .registeredWorktreeContent,
                    rootID: UUIDv7.generate()
                ),
                registrationGeneration: UInt64(4000 + index),
                rootGeneration: 1
            )
        }
        let fixture = try makeFixedSlotMailboxFixture(
            generation: AdmissionGeneration(owner: .filesystemObservation, value: 4000),
            registrations: registrations,
            limits: GatherMailboxLimits(
                maximumDeclaredKeys: sourceCount,
                maximumRetainedContributions: sourceCount * 4,
                maximumRetainedItems: sourceCount * 4,
                maximumRetainedBytes: sourceCount * 65_536,
                maximumRetainedContributionsPerKey: 4,
                maximumRetainedItemsPerKey: 4,
                maximumRetainedBytesPerKey: 65_536,
                maximumContributionsPerLease: 1,
                maximumItemsPerLease: 4,
                maximumBytesPerLease: 65_536,
                cleanupQuantum: .entriesAndBytes(
                    maximumEntries: 4,
                    maximumBytes: 65_536
                )
            ),
            captureLimits: makeCaptureLimits(),
            callbackQueueLabel: "test.filesystem-observation-fleet-shutdown-drain-port"
        )
        return Fixture(
            fixture: fixture,
            registrations: registrations,
            bindings: registrations.map { fixture.binding(for: $0) }
        )
    }

    private func makeHarness(
        fixture: Fixture,
        bindingsInDeclarationOrder: [FilesystemObservationSlotBinding]? = nil,
        consumerPort: FilesystemObservationActorConsumerPort? = nil,
        recoveryContextResolver: FilesystemObservationRecoveryContextResolver = .unavailable
    ) throws -> FilesystemObservationDrainHarnessActor {
        try FilesystemObservationDrainHarnessActor(
            mailbox: fixture.mailbox,
            bindings: bindingsInDeclarationOrder ?? fixture.bindings,
            maximumContributionsPerLease: 1,
            consumerPort: consumerPort,
            recoveryContextResolver: recoveryContextResolver
        )
    }

    private func requireCapturedDebt(
        fixture: Fixture,
        harness: FilesystemObservationDrainHarnessActor
    ) async -> FilesystemObservationFleetShutdownDebtSnapshot {
        let lifecycle = FilesystemObservationFleetLifecycle()
        _ = lifecycle.beginShutdownAndSnapshot(mailbox: fixture.mailbox)
        let result = await lifecycle.shutdownDebtSnapshot(
            mailbox: fixture.mailbox,
            drainPort: await harness.fleetShutdownDrainPort
        )
        guard case .captured(let snapshot, _) = result else {
            Issue.record("arrange failed to capture complete fleet shutdown debt: \(result)")
            preconditionFailure("Expected complete fleet shutdown debt")
        }
        return snapshot
    }

    private func admitRepair(
        to gate: inout FilesystemSourceGate,
        sequence: UInt64
    ) throws -> RepairGeneration {
        guard
            case .admitted(let repair) = gate.recordRepair(
                trigger: .continuityLoss,
                watermark: .recoveryRevision(sequence),
                participants: makeRequiredParticipants()
            )
        else {
            throw FleetShutdownDrainPortTestFailure.repairAdmissionFailed
        }
        return repair
    }

    private func requireRecoveryAdmission(
        into gate: inout FilesystemSourceGate,
        evidence: FixedFilesystemRecoveryEvidenceSnapshot
    ) throws -> FilesystemSourceGateRecoveryAcceptance {
        guard
            case .admitted(let acceptance) = gate.acceptMailboxRecovery(
                evidence,
                trigger: .continuityLoss,
                watermark: .recoveryRevision(1),
                participants: makeRequiredParticipants()
            )
        else {
            throw FleetShutdownDrainPortTestFailure.repairAdmissionFailed
        }
        return acceptance
    }

    private func acknowledgeAll(
        _ repair: RepairGeneration,
        in gate: inout FilesystemSourceGate
    ) {
        for participant in repair.participants {
            #expect(
                gate.acknowledge(
                    FilesystemRepairAcknowledgementToken(
                        repairGenerationID: repair.id,
                        participant: participant
                    )
                ) == .applied
            )
        }
    }
}

private enum FleetShutdownDrainPortTestFailure: Error {
    case repairAdmissionFailed
}

private final class DrainPortCleanupProbe: @unchecked Sendable {
    private let underlying: FilesystemObservationActorConsumerPort
    private let cleanupCalls = OSAllocatedUnfairLock(initialState: 0)

    init(underlying: FilesystemObservationActorConsumerPort) {
        self.underlying = underlying
    }

    var cleanupCallCount: Int {
        cleanupCalls.withLock { $0 }
    }

    var port: FilesystemObservationActorConsumerPort {
        FilesystemObservationActorConsumerPort(
            bind: underlying.bindConsumer,
            take: { _ in .cleanupRequired },
            acknowledge: underlying.acknowledge,
            cleanup: performCleanup,
            preflightWholeLeaseTransfer: underlying.preflightWholeLeaseTransfer,
            completeWholeLeaseTransfer: underlying.completeWholeLeaseTransfer
        )
    }

    private func performCleanup() -> AdmissionCleanupTurnResult {
        cleanupCalls.withLock { $0 += 1 }
        return .performed(
            AdmissionCleanupTurn(
                release: .entries(count: 1),
                wake: .noWake
            )
        )
    }
}
