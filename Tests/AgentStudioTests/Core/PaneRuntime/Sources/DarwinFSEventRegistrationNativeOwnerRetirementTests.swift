import Foundation
import Testing

@testable import AgentStudio

@Suite("Darwin FSEvent native owner retirement")
struct DarwinNativeOwnerRetirementTests {
    @Test("native finalization remains inert until an explicit retirement permit arrives")
    func explicitRetirementPermitIsRequiredBeforeNativeFinalization() async throws {
        // Arrange
        let fixture = try makeRetirementFixture()
        _ = try await prepareRetainedContextPermit(fixture)

        // Act: no permit is presented.

        // Assert
        #expect(fixture.finalizationLedger.finalizations.isEmpty)
        #expect(fixture.nativeOwner.nativeFinalizationSnapshot == .pending)
    }

    @Test("retained callback context finalizes once and replays one acknowledgement")
    func retainedCallbackContextFinalizesExactlyOnce() async throws {
        // Arrange
        let fixture = try makeRetirementFixture()
        let permit = try await prepareRetainedContextPermit(fixture)

        // Act
        let firstResult = fixture.nativeOwner.finalizeNativeLifetime(
            using: permit,
            contextFinalizer: fixture.finalizationLedger
        )
        let replayedResult = fixture.nativeOwner.finalizeNativeLifetime(
            using: permit,
            contextFinalizer: fixture.finalizationLedger
        )

        // Assert
        guard case .finalized(let firstAcknowledgement) = firstResult,
            case .alreadyFinalized(let replayedAcknowledgement) = replayedResult
        else {
            Issue.record("exact retirement must finalize once and replay its acknowledgement")
            return
        }
        #expect(firstAcknowledgement == replayedAcknowledgement)
        expectExactAcknowledgement(firstAcknowledgement, for: permit)
        #expect(fixture.finalizationLedger.retainedPointerReleaseCount == 1)
    }

    @Test("creation abandonment finalizes as never materialized without pointer release")
    func creationAbandonmentFinalizesWithoutPointerRelease() throws {
        // Arrange
        let fixture = try makeRetirementFixture()
        guard case .creationAbandoned(let abandonment) = fixture.nativeOwner.abandonCreation()
        else {
            Issue.record("fixture must abandon before native callback context materialization")
            return
        }
        let retiringLifetime = try requireRetiringLifetime(
            fixture.mailbox.retireUnpublishedNativeGenerationAfterCreateOrStartFailure(
                abandonment.startingNativeLifetime
            )
        )
        let completion = DarwinFSEventUnpublishedNativeCompletion.creationAbandoned(abandonment)
        let finalReceipt = try requireUnpublishedFinalReceipt(
            fixture.mailbox.lifecyclePort.finalizeUnpublishedNativeGeneration(
                retiringLifetime,
                completion: completion
            )
        )
        let permit = FilesystemObservationNativeRetirementPermit.unpublished(finalReceipt)
        #expect(fixture.nativeOwner.retainRetirementPermit(permit) == .alreadyRetained)

        // Act
        let firstResult = fixture.nativeOwner.finalizeNativeLifetime(
            using: permit,
            contextFinalizer: fixture.finalizationLedger
        )
        let replayedResult = fixture.nativeOwner.finalizeNativeLifetime(
            using: permit,
            contextFinalizer: fixture.finalizationLedger
        )

        // Assert
        guard case .finalized(let firstAcknowledgement) = firstResult,
            case .alreadyFinalized(let replayedAcknowledgement) = replayedResult
        else {
            Issue.record("never-materialized finalization must be retained and replayable")
            return
        }
        #expect(firstAcknowledgement == replayedAcknowledgement)
        guard
            case .unpublished(.neverMaterialized(_, let finalization, _)) =
                firstAcknowledgement
        else {
            Issue.record("creation abandonment must acknowledge exact never-materialized state")
            return
        }
        #expect(finalization.startingNativeLifetime == fixture.startingNativeLifetime)
        #expect(fixture.finalizationLedger.retainedPointerReleaseCount == 0)
        #expect(fixture.nativeDriverLedger.events.isEmpty)
    }

    @Test("a lost finalization response replays the exact acknowledgement")
    func lostResponseReplaysExactContextReleaseAcknowledgement() async throws {
        // Arrange
        let fixture = try makeRetirementFixture()
        let permit = try await prepareRetainedContextPermit(fixture)
        let lostResponse = fixture.nativeOwner.finalizeNativeLifetime(
            using: permit,
            contextFinalizer: fixture.finalizationLedger
        )
        guard case .finalized(let lostAcknowledgement) = lostResponse else {
            Issue.record("first exact permit must mint one acknowledgement")
            return
        }

        // Act
        let retryResult = fixture.nativeOwner.finalizeNativeLifetime(
            using: permit,
            contextFinalizer: fixture.finalizationLedger
        )

        // Assert
        guard case .alreadyFinalized(let replayedAcknowledgement) = retryResult else {
            Issue.record("retry after a lost response must replay already-finalized evidence")
            return
        }
        #expect(replayedAcknowledgement == lostAcknowledgement)
        #expect(
            fixture.nativeOwner.nativeFinalizationSnapshot
                == .finalized(lostAcknowledgement)
        )
        #expect(fixture.finalizationLedger.finalizations.count == 1)
    }

    @Test("a foreign permit binding cannot release locally retained context")
    func foreignPermitBindingCannotFinalizeNativeLifetime() async throws {
        // Arrange
        let localFixture = try makeRetirementFixture(generationValue: 901)
        let foreignFixture = try makeRetirementFixture(generationValue: 902)
        _ = try await prepareRetainedContextPermit(localFixture)
        let foreignPermit = try await prepareRetainedContextPermit(foreignFixture)

        // Act
        let result = localFixture.nativeOwner.finalizeNativeLifetime(
            using: foreignPermit,
            contextFinalizer: localFixture.finalizationLedger
        )

        // Assert
        guard case .rejected(.bindingMismatch) = result else {
            Issue.record("foreign binding must be rejected before context finalization")
            return
        }
        #expect(localFixture.finalizationLedger.finalizations.isEmpty)
        #expect(localFixture.nativeOwner.nativeFinalizationSnapshot == .pending)
    }

    @Test("a foreign permit lineage cannot release the matching binding")
    func foreignPermitLineageCannotFinalizeMatchingBinding() async throws {
        // Arrange
        let fixture = try makeRetirementFixture(generationValue: 903)
        let exactPermit = try await prepareRetainedContextPermit(fixture)
        #expect(fixture.nativeOwner.retainRetirementPermit(exactPermit) == .alreadyRetained)
        let foreignLineagePermit = makeForeignLineagePermit(
            from: exactPermit
        )

        // Act
        let result = fixture.nativeOwner.finalizeNativeLifetime(
            using: foreignLineagePermit,
            contextFinalizer: fixture.finalizationLedger
        )

        // Assert
        guard case .rejected(.permitLineageMismatch) = result else {
            Issue.record("matching binding with foreign permit lineage must be rejected")
            return
        }
        #expect(fixture.finalizationLedger.finalizations.isEmpty)
        #expect(fixture.nativeOwner.nativeFinalizationSnapshot == .pending)
    }

    @Test("fence-backed final receipt releases retained context once and replays acknowledgement")
    func fenceBackedFinalReceiptFinalizesRetainedContextExactlyOnce() async throws {
        // Arrange
        let fixture = try makeRetirementFixture(generationValue: 904)
        let generation = try requireCreatedGeneration(fixture)
        guard case .started = await fixture.nativeOwner.startOrReplay(creation: generation),
            case .closed(let leaseDrainReceipt) = await generation.close(),
            case .installed = fixture.mailbox.lifecyclePort.requestRetirementFence(
                leaseDrainReceipt
            )
        else {
            throw D3NativeOwnerRetirementTestFailure.expectedFenceInstallation
        }
        let drainHarness = try FilesystemObservationDrainHarnessActor(
            mailbox: fixture.mailbox,
            bindings: [fixture.startingNativeLifetime.binding],
            maximumContributionsPerLease: 1
        )
        let fenceLease = try requireFenceLease(await drainHarness.takeLease())
        let retirementReceipt = try requireFenceRetirementReceipt(
            await drainHarness.transferLease(
                fenceLease,
                recoveryContext: .notRequired
            )
        )
        let permit = try requireFenceBackedPermit(
            fixture.mailbox.lifecyclePort.fenceBackedRetirementPermit(
                for: retirementReceipt
            )
        )
        #expect(fixture.nativeOwner.retainRetirementPermit(permit) == .alreadyRetained)

        // Act
        let firstResult = fixture.nativeOwner.finalizeNativeLifetime(
            using: permit,
            contextFinalizer: fixture.finalizationLedger
        )
        let replayedResult = fixture.nativeOwner.finalizeNativeLifetime(
            using: permit,
            contextFinalizer: fixture.finalizationLedger
        )

        // Assert
        guard case .finalized(let firstAcknowledgement) = firstResult,
            case .alreadyFinalized(let replayedAcknowledgement) = replayedResult,
            case .fenceBacked = firstAcknowledgement
        else {
            Issue.record("exact H2 permit must finalize once and replay fence-backed evidence")
            return
        }
        #expect(firstAcknowledgement == replayedAcknowledgement)
        expectExactAcknowledgement(firstAcknowledgement, for: permit)
        #expect(fixture.finalizationLedger.retainedPointerReleaseCount == 1)
    }

    @Test("create rejection retains callback context and finalizes exactly once")
    func createRejectedCompletionFinalizesRetainedContextExactlyOnce() throws {
        // Arrange
        let fixture = try makeRetirementFixture(
            generationValue: 905,
            createSucceeds: false
        )
        let creationResult = fixture.nativeOwner.createOrReplay(
            controlBlock: fixture.controlBlock,
            adapter: fixture.adapter,
            nativeDriver: fixture.nativeDriver,
            callbackQueueBarrier: fixture.callbackQueueBarrier
        )
        guard case .creationRejected(let cleanup) = creationResult else {
            throw D3NativeOwnerRetirementTestFailure.expectedCreateRejection
        }
        let permit = try prepareUnpublishedPermit(
            fixture,
            completion: .creationRejected(cleanup)
        )

        // Act
        let firstResult = fixture.nativeOwner.finalizeNativeLifetime(
            using: permit,
            contextFinalizer: fixture.finalizationLedger
        )
        let replayedResult = fixture.nativeOwner.finalizeNativeLifetime(
            using: permit,
            contextFinalizer: fixture.finalizationLedger
        )

        // Assert
        guard case .finalized(let firstAcknowledgement) = firstResult,
            case .alreadyFinalized(let replayedAcknowledgement) = replayedResult,
            case .unpublished(.releasedRetainedContext) = firstAcknowledgement
        else {
            Issue.record("create rejection must release retained callback context exactly once")
            return
        }
        #expect(firstAcknowledgement == replayedAcknowledgement)
        expectExactAcknowledgement(firstAcknowledgement, for: permit)
        #expect(fixture.finalizationLedger.retainedPointerReleaseCount == 1)
    }

    @Test("start rejection after drain finalizes retained context exactly once")
    func startRejectedAfterDrainFinalizesRetainedContextExactlyOnce() async throws {
        // Arrange
        let fixture = try makeRetirementFixture(
            generationValue: 906,
            startSucceeds: false
        )
        let generation = try requireCreatedGeneration(fixture)
        let startResult = await fixture.nativeOwner.startOrReplay(creation: generation)
        guard case .unpublished(.startRejectedAfterDrain(let quiescence)) = startResult else {
            throw D3NativeOwnerRetirementTestFailure.expectedStartRejectionAfterDrain
        }
        let permit = try prepareUnpublishedPermit(
            fixture,
            completion: .startRejectedAfterDrain(quiescence)
        )

        // Act
        let firstResult = fixture.nativeOwner.finalizeNativeLifetime(
            using: permit,
            contextFinalizer: fixture.finalizationLedger
        )
        let replayedResult = fixture.nativeOwner.finalizeNativeLifetime(
            using: permit,
            contextFinalizer: fixture.finalizationLedger
        )

        // Assert
        guard case .finalized(let firstAcknowledgement) = firstResult,
            case .alreadyFinalized(let replayedAcknowledgement) = replayedResult,
            case .unpublished(.releasedRetainedContext) = firstAcknowledgement
        else {
            Issue.record("start rejection must release retained callback context exactly once")
            return
        }
        #expect(firstAcknowledgement == replayedAcknowledgement)
        expectExactAcknowledgement(firstAcknowledgement, for: permit)
        #expect(fixture.finalizationLedger.retainedPointerReleaseCount == 1)
    }

    private func requireCreatedGeneration(
        _ fixture: D3NativeOwnerRetirementFixture
    ) throws -> DarwinFSEventRegistrationGeneration {
        let result = fixture.nativeOwner.createOrReplay(
            controlBlock: fixture.controlBlock,
            adapter: fixture.adapter,
            nativeDriver: fixture.nativeDriver,
            callbackQueueBarrier: fixture.callbackQueueBarrier
        )
        guard case .created(let generation) = result else {
            throw D3NativeOwnerRetirementTestFailure.expectedCreatedGeneration
        }
        return generation
    }

    private func expectExactAcknowledgement(
        _ acknowledgement: FilesystemObservationContextReleaseAcknowledgement,
        for permit: FilesystemObservationNativeRetirementPermit
    ) {
        #expect(acknowledgement.releaseAuthority.isUUIDv7)
        #expect(acknowledgement.permit == permit)
    }

    private func prepareRetainedContextPermit(
        _ fixture: D3NativeOwnerRetirementFixture
    ) async throws -> FilesystemObservationNativeRetirementPermit {
        let generation = try requireCreatedGeneration(fixture)
        let startAbandonment = await fixture.nativeOwner.abandonStartAfterCreate(
            creation: generation
        )
        guard case .unpublished(.createdNeverStartedClosed(let quiescence)) = startAbandonment
        else {
            throw D3NativeOwnerRetirementTestFailure.expectedRetainedContextQuiescence
        }
        let retiringLifetime = try requireRetiringLifetime(
            fixture.mailbox.retireUnpublishedNativeGenerationAfterCreateOrStartFailure(
                fixture.startingNativeLifetime
            )
        )
        let completion = DarwinFSEventUnpublishedNativeCompletion.createdNeverStartedClosed(
            quiescence
        )
        let finalReceipt = try requireUnpublishedFinalReceipt(
            fixture.mailbox.lifecyclePort.finalizeUnpublishedNativeGeneration(
                retiringLifetime,
                completion: completion
            )
        )
        let permit = FilesystemObservationNativeRetirementPermit.unpublished(finalReceipt)
        #expect(fixture.nativeOwner.retainRetirementPermit(permit) == .alreadyRetained)
        return permit
    }

    private func requireRetiringLifetime(
        _ result: FilesystemObservationNativeLifetimeFailureResult
    ) throws -> FilesystemObservationRetiringUnpublishedNativeLifetime {
        guard case .retirementRequired(let retiringLifetime) = result else {
            throw D3NativeOwnerRetirementTestFailure.expectedRetiringLifetime
        }
        return retiringLifetime
    }

    private func requireUnpublishedFinalReceipt(
        _ result: FilesystemObservationUnpublishedFinalReceiptResult
    ) throws -> FilesystemObservationUnpublishedFinalReceipt {
        guard case .finalized(let finalReceipt) = result else {
            throw D3NativeOwnerRetirementTestFailure.expectedUnpublishedFinalReceipt
        }
        return finalReceipt
    }

    private func prepareUnpublishedPermit(
        _ fixture: D3NativeOwnerRetirementFixture,
        completion: DarwinFSEventUnpublishedNativeCompletion
    ) throws -> FilesystemObservationNativeRetirementPermit {
        let retiringLifetime = try requireRetiringLifetime(
            fixture.mailbox.retireUnpublishedNativeGenerationAfterCreateOrStartFailure(
                fixture.startingNativeLifetime
            )
        )
        let finalReceipt = try requireUnpublishedFinalReceipt(
            fixture.mailbox.lifecyclePort.finalizeUnpublishedNativeGeneration(
                retiringLifetime,
                completion: completion
            )
        )
        let permit = FilesystemObservationNativeRetirementPermit.unpublished(finalReceipt)
        #expect(fixture.nativeOwner.retainRetirementPermit(permit) == .alreadyRetained)
        return permit
    }

    private func requireFenceLease(
        _ result: FilesystemObservationDrainHarnessTakeResult
    ) throws -> FilesystemObservationDrainLease {
        guard case .lease(let lease) = result else {
            throw D3NativeOwnerRetirementTestFailure.expectedFenceLease
        }
        return lease
    }

    private func requireFenceRetirementReceipt(
        _ result: FilesystemObservationDrainHarnessTransferResult
    ) throws -> FilesystemObservationSlotRetirementReceipt {
        guard case .completed(.transferred(let wholeLeaseReceipt)) = result,
            case .retired(let retirementReceipt) = wholeLeaseReceipt.outcome
        else {
            throw D3NativeOwnerRetirementTestFailure.expectedFenceRetirementReceipt
        }
        return retirementReceipt
    }

    private func requireFenceBackedPermit(
        _ result: FilesystemFenceRetirementPermitResult
    ) throws -> FilesystemObservationNativeRetirementPermit {
        guard case .issued(let permit) = result else {
            throw D3NativeOwnerRetirementTestFailure.expectedFenceBackedPermit
        }
        return permit
    }

    private func makeForeignLineagePermit(
        from permit: FilesystemObservationNativeRetirementPermit
    ) -> FilesystemObservationNativeRetirementPermit {
        switch permit {
        case .unpublished(let receipt):
            return .unpublished(
                FilesystemObservationUnpublishedFinalReceipt(
                    retiringLifetime: receipt.retiringLifetime,
                    completion: receipt.completion,
                    retirementAuthority: FilesystemUnpublishedRetirementAuthority(
                        value: UUIDv7.generate()
                    )
                )
            )
        case .fenceBacked:
            preconditionFailure("D3 native-owner tests mutate unpublished permit lineage only")
        }
    }

    private func makeRetirementFixture(
        generationValue: UInt64 = 900,
        createSucceeds: Bool = true,
        startSucceeds: Bool = true
    ) throws -> D3NativeOwnerRetirementFixture {
        try makeD3NativeOwnerRetirementFixture(
            generationValue: generationValue,
            createSucceeds: createSucceeds,
            startSucceeds: startSucceeds
        )
    }
}
