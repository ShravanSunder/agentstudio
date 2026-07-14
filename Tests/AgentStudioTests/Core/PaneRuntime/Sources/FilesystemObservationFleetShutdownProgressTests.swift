import Dispatch
import Foundation
import Testing

@testable import AgentStudio

@Suite("Filesystem observation fleet shutdown bounded progress")
struct FilesystemObservationFleetShutdownProgressTests {
    @Test("accepting completion prepares a fence and the next turn installs it")
    func acceptingCompletionAndFenceInstallationAreSeparateTurns() async throws {
        // Arrange
        let fixture = try await makeAcceptingShutdownProgressFixture(
            generationValue: 11_025
        )
        let shutdown = requireAppliedShutdownDebtSnapshot(
            FilesystemObservationFleetLifecycle().beginShutdownAndSnapshot(
                mailbox: fixture.mailbox
            )
        )

        // Act
        let nativeTurn = requireProgressReceipt(
            await fixture.mailbox.advanceFleetShutdownOneTurn(for: shutdown.shutdownIdentity)
        )
        let completionTurn = requireProgressReceipt(
            await fixture.mailbox.advanceFleetShutdownOneTurn(for: shutdown.shutdownIdentity)
        )
        let fenceTurn = requireProgressReceipt(
            await fixture.mailbox.advanceFleetShutdownOneTurn(for: shutdown.shutdownIdentity)
        )

        // Assert
        guard
            case .nativeOwnerAdvanced(.completed(.acceptingGenerationClosed)) =
                nativeTurn.progress,
            case .closingAwaitingCallbackLeaseDrain =
                nativeTurn.debt.slots[0].registry.lifecycle
        else {
            Issue.record("native advance did not retain exact callback-close custody")
            return
        }
        guard
            case .nativeCompletionApplied = completionTurn.progress,
            case .retirementFencePending = completionTurn.debt.slots[0].registry.lifecycle
        else {
            Issue.record("completion apply did not stop at prepared pending-fence custody")
            return
        }
        #expect(completionTurn.debt.genericMailboxDebt.isQuiescent)
        #expect(
            fenceTurn.progress
                == .retirementFenceAdvanced(fixture.binding.physicalSlotID)
        )
        guard case .retirementFenceInstalled = fenceTurn.debt.slots[0].registry.lifecycle else {
            Issue.record("next explicit turn did not install the prepared retirement fence")
            return
        }
    }

    @Test("unfrozen foreign and quiescent turns return exact no-progress states")
    func noProgressStatesAreExact() async throws {
        // Arrange
        let mailbox = try makeShutdownDebtMailbox(
            generation: AdmissionGeneration(owner: .filesystemObservation, value: 11_000),
            slotCount: 1
        )
        let foreignMailbox = try makeShutdownDebtMailbox(
            generation: AdmissionGeneration(owner: .filesystemObservation, value: 11_009),
            slotCount: 1
        )
        let foreignShutdown = requireAppliedShutdownDebtSnapshot(
            FilesystemObservationFleetLifecycle().beginShutdownAndSnapshot(
                mailbox: foreignMailbox
            )
        )

        // Act / Assert
        #expect(
            await mailbox.advanceFleetShutdownOneTurn(
                for: foreignShutdown.shutdownIdentity
            ) == .shutdownNotFrozen
        )
        let shutdown = requireAppliedShutdownDebtSnapshot(
            FilesystemObservationFleetLifecycle().beginShutdownAndSnapshot(mailbox: mailbox)
        )
        #expect(
            await mailbox.advanceFleetShutdownOneTurn(
                for: foreignShutdown.shutdownIdentity
            )
                == .shutdownIdentityMismatch(
                    expected: shutdown.shutdownIdentity,
                    presented: foreignShutdown.shutdownIdentity
                )
        )
        guard
            case .noProgress(let debt) = await mailbox.advanceFleetShutdownOneTurn(
                for: shutdown.shutdownIdentity
            )
        else {
            Issue.record("quiescent frozen mailbox did not return exact no-progress debt")
            return
        }
        #expect(debt == shutdown)
    }

    @Test("one turn withdraws one desired item in declared slot order")
    func desiredWithdrawalUsesDeclaredSlotOrder() async throws {
        // Arrange
        let mailbox = try makeShutdownDebtMailbox(
            generation: AdmissionGeneration(owner: .filesystemObservation, value: 11_001),
            slotCount: 2
        )
        let firstRegistration = makeFleetRegistration(index: 11_001)
        let secondRegistration = makeFleetRegistration(index: 11_002)
        #expect(mailbox.installTestConfiguration(firstRegistration).isShutdownDebtEnqueued)
        #expect(mailbox.installTestConfiguration(secondRegistration).isShutdownDebtEnqueued)
        let firstSelection = requireShutdownDebtSelection(mailbox.selectNextDesiredSource())
        let secondSelection = requireShutdownDebtSelection(mailbox.selectNextDesiredSource())
        let shutdown = requireAppliedShutdownDebtSnapshot(
            FilesystemObservationFleetLifecycle().beginShutdownAndSnapshot(mailbox: mailbox)
        )

        // Act
        let firstTurn = await mailbox.advanceFleetShutdownOneTurn(
            for: shutdown.shutdownIdentity
        )
        let secondTurn = await mailbox.advanceFleetShutdownOneTurn(
            for: shutdown.shutdownIdentity
        )

        // Assert
        let firstReceipt = requireProgressReceipt(firstTurn)
        #expect(
            firstReceipt.progress
                == .desiredCustodyWithdrawn(
                    desiredReference(from: firstSelection)
                )
        )
        #expect(
            firstReceipt.debt.slots.map(\.registry.lifecycle)
                == [
                    .vacant,
                    .selected(
                        desired: desiredReference(from: secondSelection),
                        reservation: secondSelection.reservation
                    ),
                ]
        )
        let secondReceipt = requireProgressReceipt(secondTurn)
        #expect(
            secondReceipt.progress
                == .desiredCustodyWithdrawn(
                    desiredReference(from: secondSelection)
                )
        )
        #expect(secondReceipt.debt.slots.allSatisfy { $0.registry.lifecycle == .vacant })
        #expect(secondReceipt.debt.desiredCustody.isVacant)
    }

    @Test("generic cleanup and a contracted fence retry consume separate turns")
    func genericCleanupPrecedesFenceRetryWithoutCombiningTransitions() async throws {
        // Arrange
        let fixture = try await makeContractedFenceWithQueuedCleanupFixture(
            generationValue: 11_051
        )
        guard
            case .pendingAfterContraction(let pendingFence, _) = fixture.mailbox.lifecyclePort
                .requestRetirementFence(fixture.receipt)
        else {
            Issue.record("zero-capacity fixture did not retain a contracted pending fence")
            return
        }
        let shutdown = requireAppliedShutdownDebtSnapshot(
            FilesystemObservationFleetLifecycle().beginShutdownAndSnapshot(
                mailbox: fixture.mailbox
            )
        )
        guard case .retained = shutdown.genericMailboxDebt.queuedCleanup else {
            Issue.record("contracted fence fixture did not retain queued generic cleanup")
            return
        }

        // Act
        let nativeTurn = requireProgressReceipt(
            await fixture.mailbox.advanceFleetShutdownOneTurn(for: shutdown.shutdownIdentity)
        )
        let cleanupTurn = requireProgressReceipt(
            await fixture.mailbox.advanceFleetShutdownOneTurn(for: shutdown.shutdownIdentity)
        )
        let fenceTurn = requireProgressReceipt(
            await fixture.mailbox.advanceFleetShutdownOneTurn(for: shutdown.shutdownIdentity)
        )

        // Assert
        guard case .nativeOwnerAdvanced = nativeTurn.progress else {
            Issue.record("native owner did not consume its earlier shutdown phase")
            return
        }
        #expect(cleanupTurn.progress == .genericCleanupPerformed)
        guard
            case .retirementFencePending(_, _, let retainedFence, _) =
                cleanupTurn.debt.slots[0].registry.lifecycle
        else {
            Issue.record("cleanup turn also advanced the pending retirement fence")
            return
        }
        #expect(retainedFence == pendingFence.fence)
        #expect(
            fenceTurn.progress
                == .retirementFenceAdvanced(fixture.binding.physicalSlotID)
        )
    }

    @Test("each turn advances exactly one unpublished native custody phase")
    func unpublishedNativeLifetimeAdvancesOnePhasePerTurn() async throws {
        // Arrange
        let fixture = try makeShutdownDebtStartingFixture(
            generation: AdmissionGeneration(owner: .filesystemObservation, value: 11_101),
            registrationIndex: 11_101
        )
        let ports = requireShutdownDebtNativePorts(
            fixture.mailbox.nativeGenerationPorts(for: fixture.startingLifetime)
        )
        let shutdown = requireAppliedShutdownDebtSnapshot(
            FilesystemObservationFleetLifecycle().beginShutdownAndSnapshot(
                mailbox: fixture.mailbox
            )
        )

        // Act / Assert — owner-local creation authority advances outside the mailbox lock.
        let nativeTurn = requireProgressReceipt(
            await fixture.mailbox.advanceFleetShutdownOneTurn(
                for: shutdown.shutdownIdentity
            )
        )
        guard
            case .nativeOwnerAdvanced(
                .completed(.unpublished(.creationAbandoned))
            ) = nativeTurn.progress
        else {
            Issue.record("first turn did not abandon exact creation authority")
            return
        }
        guard case .starting = nativeTurn.debt.slots[0].registry.lifecycle else {
            Issue.record("native advance must not also mutate registry custody")
            return
        }

        // Act / Assert — the replayed completion changes only registry retirement custody.
        let completionTurn = requireProgressReceipt(
            await fixture.mailbox.advanceFleetShutdownOneTurn(
                for: shutdown.shutdownIdentity
            )
        )
        guard case .nativeCompletionApplied = completionTurn.progress,
            case .retiringUnpublished = completionTurn.debt.slots[0].registry.lifecycle
        else {
            Issue.record("second turn did not apply exact unpublished completion")
            return
        }

        // Act / Assert — retirement makes retained desired custody withdrawable.
        let desiredWithdrawalTurn = requireProgressReceipt(
            await fixture.mailbox.advanceFleetShutdownOneTurn(
                for: shutdown.shutdownIdentity
            )
        )
        guard case .desiredCustodyWithdrawn = desiredWithdrawalTurn.progress else {
            Issue.record("third turn did not withdraw newly eligible desired custody")
            return
        }
        let deferredWithdrawalTurn = requireProgressReceipt(
            await fixture.mailbox.advanceFleetShutdownOneTurn(
                for: shutdown.shutdownIdentity
            )
        )
        guard case .desiredCustodyWithdrawn = deferredWithdrawalTurn.progress else {
            Issue.record("fourth turn did not withdraw deferred desired custody")
            return
        }

        // Act / Assert — final receipt and permit retention are one later bounded transition.
        let permitTurn = requireProgressReceipt(
            await fixture.mailbox.advanceFleetShutdownOneTurn(
                for: shutdown.shutdownIdentity
            )
        )
        #expect(
            permitTurn.progress
                == .finalRetirementPermitRetained(fixture.startingLifetime.binding)
        )
        guard case .retiredAwaitingContextRelease = permitTurn.debt.slots[0].registry.lifecycle
        else {
            Issue.record("fifth turn did not retain final retirement permit")
            return
        }

        await assertFinalizationAndAcknowledgementTurns(
            fixture: fixture,
            ports: ports,
            shutdownIdentity: shutdown.shutdownIdentity
        )
    }

    @Test("lost native responses replay into one later mailbox transition")
    func lostNativeResponsesReplayWithoutDuplicateProgress() async throws {
        // Arrange
        let fixture = try makeShutdownDebtStartingFixture(
            generation: AdmissionGeneration(owner: .filesystemObservation, value: 11_201),
            registrationIndex: 11_201
        )
        let ports = requireShutdownDebtNativePorts(
            fixture.mailbox.nativeGenerationPorts(for: fixture.startingLifetime)
        )
        let shutdown = requireAppliedShutdownDebtSnapshot(
            FilesystemObservationFleetLifecycle().beginShutdownAndSnapshot(
                mailbox: fixture.mailbox
            )
        )
        _ = await fixture.mailbox.advanceFleetShutdownOneTurn(for: shutdown.shutdownIdentity)
        guard case .completed = await ports.nativeOwner.advanceFleetShutdown() else {
            Issue.record("fixture did not retain a lost native completion")
            return
        }

        // Act — the mailbox observes the retained result, withdraws newly eligible desired
        // custody, then advances the later permit phase.
        let appliedLostCompletion = requireProgressReceipt(
            await fixture.mailbox.advanceFleetShutdownOneTurn(for: shutdown.shutdownIdentity)
        )
        let withdrewDesiredCustody = requireProgressReceipt(
            await fixture.mailbox.advanceFleetShutdownOneTurn(for: shutdown.shutdownIdentity)
        )
        let withdrewDeferredCustody = requireProgressReceipt(
            await fixture.mailbox.advanceFleetShutdownOneTurn(for: shutdown.shutdownIdentity)
        )
        let retainedPermit = requireProgressReceipt(
            await fixture.mailbox.advanceFleetShutdownOneTurn(for: shutdown.shutdownIdentity)
        )
        guard
            case .retiredAwaitingContextRelease =
                retainedPermit.debt.slots[0].registry.lifecycle
        else {
            Issue.record("fixture did not retain exact native retirement permit")
            return
        }
        guard
            case .retiredAwaitingContextRelease(let retiredLifetime) =
                fixture.mailbox.physicalSlotState(
                    of: fixture.startingLifetime.binding.physicalSlotID
                )
        else {
            Issue.record("fixture did not expose its live retained retirement permit")
            return
        }
        guard
            case .finalized(let lostAcknowledgement) = ports.nativeOwner.finalizeNativeLifetime(
                using: retiredLifetime.permit,
                contextFinalizer: D3NativeFinalizationLedger()
            )
        else {
            Issue.record("fixture did not retain a lost finalization acknowledgement")
            return
        }
        let appliedLostAcknowledgement = requireProgressReceipt(
            await fixture.mailbox.advanceFleetShutdownOneTurn(for: shutdown.shutdownIdentity)
        )

        // Assert
        guard case .nativeCompletionApplied = appliedLostCompletion.progress else {
            Issue.record("retained completion was not applied exactly once")
            return
        }
        guard case .desiredCustodyWithdrawn = withdrewDesiredCustody.progress else {
            Issue.record("newly eligible desired custody was not withdrawn exactly once")
            return
        }
        guard case .desiredCustodyWithdrawn = withdrewDeferredCustody.progress else {
            Issue.record("deferred desired custody was not withdrawn exactly once")
            return
        }
        #expect(
            retainedPermit.progress
                == .finalRetirementPermitRetained(fixture.startingLifetime.binding)
        )
        #expect(
            appliedLostAcknowledgement.progress
                == .contextReleaseAcknowledgementApplied(
                    binding: lostAcknowledgement.binding,
                    releaseAuthority: lostAcknowledgement.releaseAuthority
                )
        )
        #expect(appliedLostAcknowledgement.debt.slots[0].registry.lifecycle == .vacant)
    }

    @Test("a blocked native finalizer leaves the mailbox lock free and rejects a second turn")
    func nativeFinalizationIsOutsideLockAndSingleFlight() async throws {
        // Arrange
        let fixture = try makeShutdownDebtStartingFixture(
            generation: AdmissionGeneration(owner: .filesystemObservation, value: 11_301),
            registrationIndex: 11_301
        )
        let ports = requireShutdownDebtNativePorts(
            fixture.mailbox.nativeGenerationPorts(for: fixture.startingLifetime)
        )
        let captureLimits = try FSEventCaptureLimits(
            maximumInspectedNativeRecords: 8,
            maximumCopiedRecords: 8,
            maximumCopiedUTF8Bytes: 4096,
            maximumSinglePathUTF8Bytes: 1024
        )
        let controlBlock = try makeControlBlock(
            startingNativeLifetime: fixture.startingLifetime,
            captureLimits: captureLimits,
            callbackQueueLabel: "test.shutdown-progress.single-flight"
        )
        let adapter = LeaseTransferCallbackAdapter(
            controlBlock: controlBlock,
            callbackAdmissionPort: ports.callbackAdmissionPort
        )
        guard
            case .created = ports.nativeOwner.createOrReplay(
                controlBlock: controlBlock,
                adapter: adapter,
                nativeDriver: LeaseTransferNativeDriver(),
                callbackQueueBarrier: LeaseTransferCallbackQueueBarrier()
            )
        else {
            Issue.record("single-flight fixture did not create retained native context")
            return
        }
        let shutdown = requireAppliedShutdownDebtSnapshot(
            FilesystemObservationFleetLifecycle().beginShutdownAndSnapshot(
                mailbox: fixture.mailbox
            )
        )
        _ = requireProgressReceipt(
            await fixture.mailbox.advanceFleetShutdownOneTurn(for: shutdown.shutdownIdentity)
        )
        _ = requireProgressReceipt(
            await fixture.mailbox.advanceFleetShutdownOneTurn(for: shutdown.shutdownIdentity)
        )
        _ = requireProgressReceipt(
            await fixture.mailbox.advanceFleetShutdownOneTurn(for: shutdown.shutdownIdentity)
        )
        _ = requireProgressReceipt(
            await fixture.mailbox.advanceFleetShutdownOneTurn(for: shutdown.shutdownIdentity)
        )
        let permitTurn = requireProgressReceipt(
            await fixture.mailbox.advanceFleetShutdownOneTurn(for: shutdown.shutdownIdentity)
        )
        #expect(
            permitTurn.progress
                == .finalRetirementPermitRetained(fixture.startingLifetime.binding)
        )
        let blockingFinalizer = FleetShutdownBlockingContextFinalizer()

        // Act. A detached executor job is intentional: the synchronous finalizer blocks one
        // thread while this test proves the mailbox coordination lock remains available.
        // swiftlint:disable:next no_task_detached
        let firstTurnTask = Task.detached {
            await fixture.mailbox.advanceFleetShutdownOneTurn(
                for: shutdown.shutdownIdentity,
                contextFinalizer: blockingFinalizer
            )
        }
        guard blockingFinalizer.waitUntilFinalizationEntered() else {
            blockingFinalizer.allowFinalizationToComplete()
            _ = await firstTurnTask.value
            Issue.record("native finalization did not reach the controlled outside-lock seam")
            return
        }
        let overlappingTurn = await fixture.mailbox.advanceFleetShutdownOneTurn(
            for: shutdown.shutdownIdentity
        )
        blockingFinalizer.allowFinalizationToComplete()
        let completedFirstTurn = await firstTurnTask.value

        // Assert. Obtaining exact debt here proves the second call acquired the mailbox lock
        // while native finalization was blocked, and single-flight prevented a second action.
        guard case .noProgress(let overlappingDebt) = overlappingTurn else {
            Issue.record("overlapping progress turn did not return exact no-progress debt")
            return
        }
        #expect(overlappingDebt.shutdownIdentity == shutdown.shutdownIdentity)
        guard
            case .progressed(let receipt) = completedFirstTurn,
            case .nativeContextFinalized(let binding, _) = receipt.progress
        else {
            Issue.record("the claimed finalization turn did not complete after release")
            return
        }
        #expect(binding == fixture.startingLifetime.binding)
    }

    private func makeContractedFenceWithQueuedCleanupFixture(
        generationValue: UInt64
    ) async throws -> ShutdownDebtClosedFenceFixture {
        let startingFixture = try makeShutdownDebtStartingFixture(
            generation: AdmissionGeneration(
                owner: .filesystemObservation,
                value: generationValue
            ),
            registrationIndex: Int(generationValue),
            limits: fleetMailboxLimits(global: 1, perRegistration: 1, perLease: 1)
        )
        let ports = requireShutdownDebtNativePorts(
            startingFixture.mailbox.nativeGenerationPorts(
                for: startingFixture.startingLifetime
            )
        )
        let captureLimits = try FSEventCaptureLimits(
            maximumInspectedNativeRecords: 8,
            maximumCopiedRecords: 8,
            maximumCopiedUTF8Bytes: 4096,
            maximumSinglePathUTF8Bytes: 1024
        )
        let controlBlock = try makeControlBlock(
            startingNativeLifetime: startingFixture.startingLifetime,
            captureLimits: captureLimits,
            callbackQueueLabel: "test.shutdown-progress.cleanup-fence"
        )
        let adapter = LeaseTransferCallbackAdapter(
            controlBlock: controlBlock,
            callbackAdmissionPort: ports.callbackAdmissionPort
        )
        guard
            case .created(let nativeGeneration) = ports.nativeOwner.createOrReplay(
                controlBlock: controlBlock,
                adapter: adapter,
                nativeDriver: LeaseTransferNativeDriver(),
                callbackQueueBarrier: LeaseTransferCallbackQueueBarrier()
            ),
            case .started = await nativeGeneration.start(),
            case .acquired(let callbackLease) = controlBlock.acquireCallbackLease()
        else {
            throw FleetShutdownProgressTestFailure.nativeGenerationUnavailable
        }
        let observation = try makeObservation(
            registration: startingFixture.registration,
            path: "/shutdown-progress/queued-cleanup",
            eventID: 1
        )
        expectRetainedCallback(
            ports.callbackAdmissionPort.admit(
                using: callbackLease,
                preflight: FilesystemObservationCallbackPreflight(
                    captureLimits: captureLimits
                )
            ) {
                .offer(.authoritative(observation))
            }
        )
        _ = callbackLease.release()
        guard case .closed(let receipt) = await nativeGeneration.close() else {
            throw FleetShutdownProgressTestFailure.nativeGenerationUnavailable
        }
        return ShutdownDebtClosedFenceFixture(
            mailbox: startingFixture.mailbox,
            binding: startingFixture.startingLifetime.binding,
            receipt: receipt
        )
    }

    private func makeAcceptingShutdownProgressFixture(
        generationValue: UInt64
    ) async throws -> FleetShutdownAcceptingFixture {
        let startingFixture = try makeShutdownDebtStartingFixture(
            generation: AdmissionGeneration(
                owner: .filesystemObservation,
                value: generationValue
            ),
            registrationIndex: Int(generationValue)
        )
        let ports = requireShutdownDebtNativePorts(
            startingFixture.mailbox.nativeGenerationPorts(
                for: startingFixture.startingLifetime
            )
        )
        let captureLimits = try FSEventCaptureLimits(
            maximumInspectedNativeRecords: 8,
            maximumCopiedRecords: 8,
            maximumCopiedUTF8Bytes: 4096,
            maximumSinglePathUTF8Bytes: 1024
        )
        let controlBlock = try makeControlBlock(
            startingNativeLifetime: startingFixture.startingLifetime,
            captureLimits: captureLimits,
            callbackQueueLabel: "test.shutdown-progress.accepting"
        )
        let adapter = LeaseTransferCallbackAdapter(
            controlBlock: controlBlock,
            callbackAdmissionPort: ports.callbackAdmissionPort
        )
        guard
            case .created(let nativeGeneration) = ports.nativeOwner.createOrReplay(
                controlBlock: controlBlock,
                adapter: adapter,
                nativeDriver: LeaseTransferNativeDriver(),
                callbackQueueBarrier: LeaseTransferCallbackQueueBarrier()
            ),
            case .started = await ports.nativeOwner.startOrReplay(
                creation: nativeGeneration
            )
        else {
            throw FleetShutdownProgressTestFailure.nativeGenerationUnavailable
        }
        return FleetShutdownAcceptingFixture(
            mailbox: startingFixture.mailbox,
            binding: startingFixture.startingLifetime.binding
        )
    }

    private func assertFinalizationAndAcknowledgementTurns(
        fixture: ShutdownDebtStartingFixture,
        ports: FilesystemObservationNativeGenerationPorts,
        shutdownIdentity: FilesystemObservationFleetShutdownIdentity
    ) async {
        // Native finalization remains outside the mailbox lock.
        let finalizationTurn = requireProgressReceipt(
            await fixture.mailbox.advanceFleetShutdownOneTurn(
                for: shutdownIdentity,
                contextFinalizer: D3NativeFinalizationLedger()
            )
        )
        guard case .nativeContextFinalized(let binding, _) = finalizationTurn.progress else {
            Issue.record("sixth turn did not finalize native context")
            return
        }
        #expect(binding == fixture.startingLifetime.binding)
        guard
            case .retiredAwaitingContextRelease =
                finalizationTurn.debt.slots[0].registry.lifecycle
        else {
            Issue.record("native finalization must not also recycle the registry slot")
            return
        }

        // Exact retained acknowledgement recycles only on the next turn.
        let acknowledgementTurn = requireProgressReceipt(
            await fixture.mailbox.advanceFleetShutdownOneTurn(for: shutdownIdentity)
        )
        guard
            case .contextReleaseAcknowledgementApplied(let acknowledgedBinding, _) =
                acknowledgementTurn.progress
        else {
            Issue.record("seventh turn did not apply exact release acknowledgement")
            return
        }
        #expect(acknowledgedBinding == fixture.startingLifetime.binding)
        #expect(acknowledgementTurn.debt.slots[0].registry.lifecycle == .vacant)
        #expect(acknowledgementTurn.debt.slots[0].nativeOwner == .vacant)
        #expect(ports.nativeOwner.nativeFinalizationSnapshot.isFinalized)
    }

    private func requireProgressReceipt(
        _ result: FilesystemObservationFleetShutdownProgressResult,
        sourceLocation: SourceLocation = #_sourceLocation
    ) -> FilesystemObservationFleetShutdownProgressReceipt {
        guard case .progressed(let receipt) = result else {
            Issue.record("Expected one bounded progress receipt, got \(result)", sourceLocation: sourceLocation)
            preconditionFailure("Expected one fleet shutdown progress receipt")
        }
        return receipt
    }

    private func desiredReference(
        from selection: FilesystemObservationDesiredSelection
    ) -> FilesystemObservationDesiredShutdownReference {
        FilesystemObservationDesiredShutdownReference(
            sourceID: selection.desiredRegistration.sourceID,
            registration: selection.desiredRegistration.configuration.registration,
            desiredIdentity: selection.desiredRegistration.identity,
            acceptedTopologyRevision: selection.desiredRegistration.acceptedTopologyRevision
        )
    }

}

private let fleetShutdownProgressProofTimeout: DispatchTimeInterval = .seconds(30)

private enum FleetShutdownProgressTestFailure: Error {
    case nativeGenerationUnavailable
}

private struct FleetShutdownAcceptingFixture {
    let mailbox: FilesystemObservationMailbox
    let binding: FilesystemObservationSlotBinding
}

private final class FleetShutdownBlockingContextFinalizer:
    DarwinFSEventCallbackContextFinalizer,
    @unchecked Sendable
{
    private let finalizationEntered = DispatchSemaphore(value: 0)
    private let finalizationPermission = DispatchSemaphore(value: 0)

    func releaseRetainedContext(at _: UInt) {
        finalizationEntered.signal()
        _ = finalizationPermission.wait(timeout: .now() + fleetShutdownProgressProofTimeout)
    }

    func waitUntilFinalizationEntered() -> Bool {
        finalizationEntered.wait(timeout: .now() + fleetShutdownProgressProofTimeout) == .success
    }

    func allowFinalizationToComplete() {
        finalizationPermission.signal()
    }
}

extension DarwinFSEventNativeFinalizationSnapshot {
    fileprivate var isFinalized: Bool {
        guard case .finalized = self else { return false }
        return true
    }
}
