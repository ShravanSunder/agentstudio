import Foundation
import Testing

@testable import AgentStudio

@Suite("Filesystem observation context-release lifecycle")
struct FilesystemObservationContextReleaseLifecycleTests {
    @Test("final receipt alone cannot recycle its physical slot")
    func finalReceiptAloneCannotRecyclePhysicalSlot() throws {
        // Arrange
        let fixture = try makeUnpublishedContextReleaseFixture()
        _ = fixture.mailbox.installTestConfiguration(makeRegistration(generation: 2))

        // Act
        let selectionBeforeAcknowledgement = fixture.mailbox.selectNextDesiredSource()

        // Assert
        #expect(selectionBeforeAcknowledgement == .deferredBehindSlotCapacity)
        #expect(
            fixture.mailbox.physicalSlotState(of: fixture.binding.physicalSlotID)
                == .retiredAwaitingContextRelease(
                    .unpublished(
                        FilesystemUnpublishedRetiredContextReleaseLifetime(
                            receipt: fixture.finalReceipt
                        )
                    )
                )
        )
    }

    @Test("matching acknowledgement applies once and replays while vacant or selected")
    func matchingAcknowledgementAppliesOnceAndReplaysBeforeCommitment() throws {
        // Arrange
        let fixture = try makeUnpublishedContextReleaseFixture()
        let acknowledgement = try consumeUnpublishedRetirementPermit(fixture)

        // Act
        let firstApplication = fixture.mailbox.lifecyclePort
            .applyContextReleaseAcknowledgement(acknowledgement)
        let vacantReplay = fixture.mailbox.lifecyclePort
            .applyContextReleaseAcknowledgement(acknowledgement)
        _ = fixture.mailbox.installTestConfiguration(makeRegistration(generation: 2))
        let replacementSelection = try requireSelectedDesiredSource(
            fixture.mailbox.selectNextDesiredSource()
        )
        let selectedReplay = fixture.mailbox.lifecyclePort
            .applyContextReleaseAcknowledgement(acknowledgement)

        // Assert
        let application = try requireAppliedContextRelease(firstApplication)
        #expect(application.acknowledgement == acknowledgement)
        #expect(application.successorDisposition == .none)
        #expect(vacantReplay == .alreadyApplied(acknowledgement))
        #expect(selectedReplay == .alreadyApplied(acknowledgement))
        #expect(replacementSelection.reservation.physicalSlotID == fixture.binding.physicalSlotID)
        #expect(
            fixture.mailbox.physicalSlotState(of: fixture.binding.physicalSlotID)
                == .selected(replacementSelection)
        )
    }

    @Test("reuse mints a new UUIDv7 binding and makes old acknowledgement stale")
    func reuseMintsFreshBindingAndStalesOldAcknowledgement() throws {
        // Arrange
        let fixture = try makeUnpublishedContextReleaseFixture()
        let acknowledgement = try consumeUnpublishedRetirementPermit(fixture)
        let application = try requireAppliedContextRelease(
            fixture.mailbox.lifecyclePort.applyContextReleaseAcknowledgement(acknowledgement)
        )
        #expect(application.acknowledgement == acknowledgement)
        _ = fixture.mailbox.installTestConfiguration(makeRegistration(generation: 2))
        let replacementSelection = try requireSelectedDesiredSource(
            fixture.mailbox.selectNextDesiredSource()
        )

        // Act
        let replacementLifetime = try requireCommittedNativeLifetime(
            fixture.mailbox.beginNativeLifetime(replacementSelection.reservation)
        )
        let staleReplay = fixture.mailbox.lifecyclePort
            .applyContextReleaseAcknowledgement(acknowledgement)

        // Assert
        #expect(replacementLifetime.binding.physicalSlotID == fixture.binding.physicalSlotID)
        #expect(replacementLifetime.binding.identity.isUUIDv7)
        #expect(replacementLifetime.binding.identity != fixture.binding.identity)
        #expect(replacementLifetime.binding.controlBlockIdentity.isUUIDv7)
        #expect(
            replacementLifetime.binding.controlBlockIdentity
                != fixture.binding.controlBlockIdentity
        )
        guard case .staleBinding = staleReplay else {
            Issue.record("old acknowledgement must be stale after binding reuse")
            return
        }
        #expect(
            fixture.mailbox.physicalSlotState(of: fixture.binding.physicalSlotID)
                == .starting(replacementLifetime)
        )
    }

    @Test("native owner finalizes exact unpublished permit once")
    func nativeOwnerFinalizesExactUnpublishedPermitOnce() throws {
        // Arrange
        let fixture = try makeUnpublishedContextReleaseFixture()

        // Act
        let firstFinalization = fixture.nativeOwner.finalizeNativeLifetime(
            using: .unpublished(fixture.finalReceipt),
            contextFinalizer: fixture.contextFinalizer
        )
        let replayedFinalization = fixture.nativeOwner.finalizeNativeLifetime(
            using: .unpublished(fixture.finalReceipt),
            contextFinalizer: fixture.contextFinalizer
        )

        // Assert
        guard case .finalized(let firstAcknowledgement) = firstFinalization,
            case .alreadyFinalized(let replayedAcknowledgement) = replayedFinalization
        else {
            Issue.record("exact unpublished permit must retain one release acknowledgement")
            return
        }
        #expect(firstAcknowledgement == replayedAcknowledgement)
        #expect(firstAcknowledgement.binding == fixture.binding)
        #expect(firstAcknowledgement.releaseAuthority.isUUIDv7)
        #expect(firstAcknowledgement.permit == .unpublished(fixture.finalReceipt))
        #expect(fixture.contextFinalizer.retainedPointerReleaseCount == 0)
        #expect(
            fixture.mailbox.physicalSlotState(of: fixture.binding.physicalSlotID)
                == .retiredAwaitingContextRelease(
                    .unpublished(
                        FilesystemUnpublishedRetiredContextReleaseLifetime(
                            receipt: fixture.finalReceipt
                        )
                    )
                )
        )
    }

    @Test("foreign lineage and release authority leave retired state unchanged")
    func acknowledgementMismatchMatrixLeavesRetiredStateUnchanged() throws {
        // Arrange
        let fixture = try makeUnpublishedContextReleaseFixture(generationValue: 10)
        let foreignFixture = try makeUnpublishedContextReleaseFixture(generationValue: 11)
        let exactAcknowledgement = try consumeUnpublishedRetirementPermit(fixture)
        let foreignAcknowledgement = try consumeUnpublishedRetirementPermit(foreignFixture)
        let foreignLineageAcknowledgement = replacingUnpublishedRetirementAuthority(
            in: exactAcknowledgement
        )
        let foreignReleaseAcknowledgement = replacingContextReleaseAuthority(
            in: exactAcknowledgement
        )
        let stateBeforeMismatches = fixture.mailbox.physicalSlotState(
            of: fixture.binding.physicalSlotID
        )

        // Act
        let foreignBindingResult = fixture.mailbox.lifecyclePort
            .applyContextReleaseAcknowledgement(foreignAcknowledgement)
        let permitLineageResult = fixture.mailbox.lifecyclePort
            .applyContextReleaseAcknowledgement(foreignLineageAcknowledgement)
        let releaseAuthorityResult = fixture.mailbox.lifecyclePort
            .applyContextReleaseAcknowledgement(foreignReleaseAcknowledgement)

        // Assert
        #expect(foreignBindingResult == .foreignFleet)
        #expect(permitLineageResult == .permitLineageMismatch)
        #expect(releaseAuthorityResult == .releaseAuthorityMismatch)
        #expect(
            fixture.mailbox.physicalSlotState(of: fixture.binding.physicalSlotID)
                == stateBeforeMismatches
        )
        #expect(fixture.contextFinalizer.retainedPointerReleaseCount == 0)
    }

    @Test("unpublished acknowledgement preserves pending desired-record repair")
    func unpublishedAcknowledgementPreservesPendingDesiredRecordRepair() throws {
        // Arrange
        let fixture = try makeUnpublishedRegistryContextReleaseFixture()
        let repairBeforeAcknowledgement = fixture.registry.read
            .pendingContinuityRepairState(for: fixture.sourceID)
        let desiredBeforeAcknowledgement = fixture.registry.read.desiredState(
            for: fixture.sourceID
        )

        // Act
        let result = fixture.registry.applyContextReleaseAcknowledgement(
            fixture.acknowledgement
        )

        // Assert
        let application = try requireAppliedContextRelease(result)
        #expect(application.acknowledgement == fixture.acknowledgement)
        #expect(application.successorDisposition == .none)
        #expect(
            fixture.registry.read.pendingContinuityRepairState(for: fixture.sourceID)
                == repairBeforeAcknowledgement
        )
        #expect(
            fixture.registry.read.desiredState(for: fixture.sourceID)
                == desiredBeforeAcknowledgement
        )
        guard case .pending(let repairAuthority) = repairBeforeAcknowledgement else {
            Issue.record("failed unpublished installation must retain exact repair authority")
            return
        }
        #expect(repairAuthority.identity.isUUIDv7)
        #expect(fixture.registry.read.state(of: fixture.binding.physicalSlotID) == .vacant)
    }

    @Test("predecessor acknowledgement promotes one successor fence exactly once")
    func predecessorAcknowledgementPromotesSuccessorFenceExactlyOnce() async throws {
        // Arrange
        let mailbox = try FilesystemObservationMailbox(
            generation: AdmissionGeneration(owner: .filesystemObservation, value: 20),
            maximumSimultaneousSourceCount: 1,
            replacementReserveSlotCount: 1,
            limits: successorPromotionMailboxLimits()
        )
        _ = mailbox.installTestConfiguration(makeRegistration(generation: 20))
        let predecessor = try await startContextReleaseGeneration(in: mailbox)
        _ = mailbox.installTestConfiguration(makeRegistration(generation: 21))
        let predecessorDrainReceipt = try await closeContextReleaseGeneration(predecessor)
        let predecessorInstalledLifetime = try requireInstalledRetirementFence(
            mailbox.lifecyclePort.requestRetirementFence(predecessorDrainReceipt)
        )
        let successor = try await startContextReleaseGeneration(in: mailbox)
        let successorDrainReceipt = try await closeContextReleaseGeneration(successor)
        let successorAwaitingLifetime = try requireAwaitingPredecessor(
            mailbox.lifecyclePort.requestRetirementFence(successorDrainReceipt)
        )
        let drainHarness = try FilesystemObservationDrainHarnessActor(
            mailbox: mailbox,
            bindings: [predecessor.binding, successor.binding],
            maximumContributionsPerLease: 1
        )
        let predecessorLease = try await requireContextReleaseLease(from: drainHarness)
        let predecessorTransferReceipt = try requireContextReleaseTransferReceipt(
            await drainHarness.transferLease(
                predecessorLease,
                recoveryContext: .notRequired
            )
        )
        guard
            case .retired(let predecessorRetirementReceipt) =
                predecessorTransferReceipt.outcome,
            case .issued(let predecessorPermit) = mailbox.lifecyclePort
                .fenceBackedRetirementPermit(for: predecessorRetirementReceipt),
            case .finalized(let predecessorAcknowledgement) = predecessor.nativeOwner
                .finalizeNativeLifetime(
                    using: predecessorPermit,
                    contextFinalizer: predecessor.contextFinalizer
                )
        else {
            throw FilesystemObservationContextReleaseTestFailure.predecessorRetirementUnavailable
        }
        let offeredBeforeAcknowledgement = mailbox.lifecyclePort.diagnostics.gather.admission.offered

        // Act
        let firstApplication = mailbox.lifecyclePort.applyContextReleaseAcknowledgement(
            predecessorAcknowledgement
        )
        let offeredAfterAcknowledgement = mailbox.lifecyclePort.diagnostics.gather.admission.offered
        let replayedApplication = mailbox.lifecyclePort.applyContextReleaseAcknowledgement(
            predecessorAcknowledgement
        )
        let offeredAfterReplay = mailbox.lifecyclePort.diagnostics.gather.admission.offered

        // Assert
        let application = try requireAppliedContextRelease(firstApplication)
        guard case .promoted(let promotedLifetime) = application.successorDisposition else {
            Issue.record("predecessor release must promote the exact successor fence")
            return
        }
        #expect(predecessorInstalledLifetime.binding == predecessor.binding)
        #expect(successorAwaitingLifetime.binding == successor.binding)
        #expect(promotedLifetime.binding == successor.binding)
        #expect(promotedLifetime.fence.identity.isUUIDv7)
        #expect(offeredAfterAcknowledgement == offeredBeforeAcknowledgement + 1)
        #expect(replayedApplication == .alreadyApplied(predecessorAcknowledgement))
        #expect(offeredAfterReplay == offeredAfterAcknowledgement)
        #expect(predecessor.contextFinalizer.retainedPointerReleaseCount == 1)
        guard
            case .retirementFenceInstalled(let installedSuccessorLifetime) =
                mailbox.physicalSlotState(of: successor.binding.physicalSlotID)
        else {
            Issue.record("promoted successor fence must install through the mailbox progress turn")
            return
        }
        #expect(installedSuccessorLifetime.pendingLifetime == promotedLifetime)
    }
}

private struct StartedContextReleaseGeneration {
    let generation: DarwinFSEventRegistrationGeneration
    let nativeOwner: DarwinFSEventRegistrationNativeOwner
    let binding: FilesystemObservationSlotBinding
    let contextFinalizer: D3NativeFinalizationLedger
}

private func startContextReleaseGeneration(
    in mailbox: FilesystemObservationMailbox
) async throws -> StartedContextReleaseGeneration {
    let selection = try requireSelectedDesiredSource(
        mailbox.selectNextDesiredSource()
    )
    let startingNativeLifetime = try requireCommittedNativeLifetime(
        mailbox.beginNativeLifetime(selection.reservation)
    )
    guard case .created(let ports) = mailbox.nativeGenerationPorts(for: startingNativeLifetime)
    else {
        throw FilesystemObservationContextReleaseTestFailure.fixtureConstructionFailed
    }
    let controlBlock = try makeControlBlock(
        startingNativeLifetime: startingNativeLifetime,
        captureLimits: try FSEventCaptureLimits(
            maximumInspectedNativeRecords: 8,
            maximumCopiedRecords: 8,
            maximumCopiedUTF8Bytes: 4096,
            maximumSinglePathUTF8Bytes: 1024
        ),
        callbackQueueLabel: "test.context-release.successor-promotion"
    )
    let adapter = LeaseTransferCallbackAdapter(
        controlBlock: controlBlock,
        callbackAdmissionPort: ports.callbackAdmissionPort
    )
    guard
        case .created(let generation) = ports.nativeOwner.createOrReplay(
            controlBlock: controlBlock,
            adapter: adapter,
            nativeDriver: LeaseTransferNativeDriver(),
            callbackQueueBarrier: LeaseTransferCallbackQueueBarrier()
        ),
        case .started = await ports.nativeOwner.startOrReplay(creation: generation)
    else {
        throw FilesystemObservationContextReleaseTestFailure.fixtureConstructionFailed
    }
    return StartedContextReleaseGeneration(
        generation: generation,
        nativeOwner: ports.nativeOwner,
        binding: startingNativeLifetime.binding,
        contextFinalizer: D3NativeFinalizationLedger()
    )
}

private func closeContextReleaseGeneration(
    _ generation: StartedContextReleaseGeneration
) async throws -> DarwinFSEventRegistrationLeaseDrainReceipt {
    guard case .closed(let receipt) = await generation.generation.close() else {
        throw FilesystemObservationContextReleaseTestFailure.nativeCloseFailed
    }
    return receipt
}

private func requireInstalledRetirementFence(
    _ result: FilesystemObservationRetirementFenceRequestResult
) throws -> FilesystemRetirementFenceInstalledLifetime {
    guard case .installed(let installedLifetime) = result else {
        throw FilesystemObservationContextReleaseTestFailure.retirementFenceUnavailable
    }
    return installedLifetime
}

private func requireAwaitingPredecessor(
    _ result: FilesystemObservationRetirementFenceRequestResult
) throws -> FilesystemClosingAwaitingPredecessorLifetime {
    guard case .awaitingPredecessor(let awaitingLifetime) = result else {
        throw FilesystemObservationContextReleaseTestFailure.successorDidNotAwaitPredecessor
    }
    return awaitingLifetime
}

private func requireContextReleaseLease(
    from harness: FilesystemObservationDrainHarnessActor
) async throws -> FilesystemObservationDrainLease {
    guard case .lease(let lease) = await harness.takeLease() else {
        throw FilesystemObservationContextReleaseTestFailure.leaseUnavailable
    }
    return lease
}

private func requireContextReleaseTransferReceipt(
    _ result: FilesystemObservationDrainHarnessTransferResult
) throws -> FilesystemObservationWholeLeaseTransferReceipt {
    guard case .completed(.transferred(let receipt)) = result else {
        throw FilesystemObservationContextReleaseTestFailure.transferDidNotComplete
    }
    return receipt
}

private func successorPromotionMailboxLimits() -> GatherMailboxLimits {
    GatherMailboxLimits(
        maximumDeclaredKeys: 2,
        maximumRetainedContributions: 8,
        maximumRetainedItems: 8,
        maximumRetainedBytes: 65_536,
        maximumRetainedContributionsPerKey: 8,
        maximumRetainedItemsPerKey: 8,
        maximumRetainedBytesPerKey: 65_536,
        maximumContributionsPerLease: 1,
        maximumItemsPerLease: 8,
        maximumBytesPerLease: 65_536,
        cleanupQuantum: .entriesAndBytes(maximumEntries: 8, maximumBytes: 65_536)
    )
}

private func consumeUnpublishedRetirementPermit(
    _ fixture: UnpublishedContextReleaseFixture
) throws -> FilesystemObservationContextReleaseAcknowledgement {
    guard
        case .finalized(let acknowledgement) = fixture.nativeOwner
            .finalizeNativeLifetime(
                using: .unpublished(fixture.finalReceipt),
                contextFinalizer: fixture.contextFinalizer
            )
    else {
        throw FilesystemObservationContextReleaseTestFailure.acknowledgementUnavailable
    }
    return acknowledgement
}

private func requireAppliedContextRelease(
    _ result: FilesystemObservationContextReleaseApplyResult
) throws -> FilesystemObservationContextReleaseApplication {
    guard case .applied(let application) = result else {
        throw FilesystemObservationContextReleaseTestFailure.expectedAppliedAcknowledgement
    }
    return application
}
