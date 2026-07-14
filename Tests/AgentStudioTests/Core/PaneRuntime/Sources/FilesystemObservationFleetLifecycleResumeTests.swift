import Testing

@testable import AgentStudio

@Suite("Filesystem observation fleet lifecycle resume")
struct FilesystemObservationFleetLifecycleResumeTests {
    @Test("resume preserves one UUIDv7 shutdown identity and advances one bounded turn")
    func resumePreservesIdentityAndAdvancesOneBoundedTurn() async throws {
        let fixture = try makeFixture(sourceCount: 2)
        try admitOneObservationPerSource(fixture)
        let harness = try makeHarness(fixture)
        let lifecycle = FilesystemObservationFleetLifecycle()
        let begun = requireAppliedShutdownDebtSnapshot(
            lifecycle.beginShutdownAndSnapshot(mailbox: fixture.mailbox)
        )
        try await prepareActorDrainState(
            lifecycle: lifecycle,
            fixture: fixture,
            harness: harness,
            shutdownIdentity: begun.shutdownIdentity
        )

        let first = await lifecycle.resumeShutdown(
            mailbox: fixture.mailbox,
            drainPort: await harness.fleetShutdownDrainPort
        )
        let firstIncomplete = requireIncomplete(first)

        #expect(firstIncomplete.snapshot.shutdownIdentity == begun.shutdownIdentity)
        #expect(firstIncomplete.snapshot.shutdownIdentity.isUUIDv7)
        #expect(queuedContributionCount(firstIncomplete.snapshot) == 1)
        #expect(firstIncomplete.turnPlan == .advanceActorDrain)

        let second = await lifecycle.resumeShutdown(
            mailbox: fixture.mailbox,
            drainPort: await harness.fleetShutdownDrainPort
        )
        let secondIncomplete = requireIncomplete(second)

        #expect(secondIncomplete.snapshot.shutdownIdentity == begun.shutdownIdentity)
        #expect(queuedContributionCount(secondIncomplete.snapshot) == 0)
        #expect(secondIncomplete.turnPlan == .beginSourceGateShutdown)
    }

    @Test("resume replays the newest exact incomplete debt when its owner must progress")
    func resumeReplaysNewestIncompleteOwnerWaitDebt() async throws {
        let fixture = try makeFixture(sourceCount: 1)
        try admitOneObservationPerSource(fixture)
        let harness = try makeHarness(fixture)
        let lifecycle = FilesystemObservationFleetLifecycle()
        let begun = requireAppliedShutdownDebtSnapshot(
            lifecycle.beginShutdownAndSnapshot(mailbox: fixture.mailbox)
        )
        try await prepareActorDrainState(
            lifecycle: lifecycle,
            fixture: fixture,
            harness: harness,
            shutdownIdentity: begun.shutdownIdentity
        )
        guard case .lease = await harness.takeLease() else {
            Issue.record("Arrange must retain one actor-owned active lease")
            return
        }

        let first = requireIncomplete(
            await lifecycle.resumeShutdown(
                mailbox: fixture.mailbox,
                drainPort: await harness.fleetShutdownDrainPort
            )
        )
        let replay = requireIncomplete(
            await lifecycle.resumeShutdown(
                mailbox: fixture.mailbox,
                drainPort: await harness.fleetShutdownDrainPort
            )
        )

        #expect(first == replay)
        guard case .awaitOwnedProgress(.genericLeaseCompletion) = first.turnPlan else {
            Issue.record("Active lease must remain exact owner-wait debt: \(first.turnPlan)")
            return
        }
        let recaptured = await lifecycle.shutdownDebtSnapshot(
            mailbox: fixture.mailbox,
            drainPort: await harness.fleetShutdownDrainPort
        )
        guard case .captured(let snapshot, let turnPlan) = recaptured else {
            Issue.record("Fresh recapture failed after owner-wait replay: \(recaptured)")
            return
        }
        #expect(snapshot == replay.snapshot)
        #expect(turnPlan == replay.turnPlan)
    }

    @Test("concurrent resume is single-flight and returns retained exact debt")
    func concurrentResumeIsSingleFlight() async throws {
        let fixture = try makeFixture(sourceCount: 2)
        try admitOneObservationPerSource(fixture)
        let harness = try makeHarness(fixture)
        let basePort = await harness.fleetShutdownDrainPort
        let gate = FleetShutdownResumeFirstAdvanceGate()
        let controlledPort = controlledDrainPort(basePort, gate: gate)
        let lifecycle = FilesystemObservationFleetLifecycle()
        let begun = requireAppliedShutdownDebtSnapshot(
            lifecycle.beginShutdownAndSnapshot(mailbox: fixture.mailbox)
        )
        try await prepareActorDrainState(
            lifecycle: lifecycle,
            fixture: fixture,
            harness: harness,
            shutdownIdentity: begun.shutdownIdentity
        )

        let firstTask = Task {
            await lifecycle.resumeShutdown(
                mailbox: fixture.mailbox,
                drainPort: controlledPort
            )
        }
        await gate.waitUntilFirstAdvanceEntered()
        let concurrent = await lifecycle.resumeShutdown(
            mailbox: fixture.mailbox,
            drainPort: controlledPort
        )

        guard
            case .resumeAlreadyInProgress(
                .incomplete(let retainedSnapshot, let retainedTurnPlan)
            ) = concurrent
        else {
            Issue.record("Concurrent resume did not replay retained in-flight debt: \(concurrent)")
            await gate.releaseFirstAdvance()
            _ = await firstTask.value
            return
        }
        #expect(retainedSnapshot.shutdownIdentity == begun.shutdownIdentity)
        #expect(retainedTurnPlan == .advanceActorDrain)
        #expect(await gate.advanceInvocationCount == 1)

        await gate.releaseFirstAdvance()
        let completedTurn = requireIncomplete(await firstTask.value)
        #expect(completedTurn.snapshot.shutdownIdentity == begun.shutdownIdentity)
        #expect(queuedContributionCount(completedTurn.snapshot) == 1)
        #expect(await gate.advanceInvocationCount == 1)
    }

    @Test("request cancellation cannot revert progress or replace shutdown identity")
    func cancellationCannotRevertProgressOrReplaceIdentity() async throws {
        let fixture = try makeFixture(sourceCount: 2)
        try admitOneObservationPerSource(fixture)
        let harness = try makeHarness(fixture)
        let basePort = await harness.fleetShutdownDrainPort
        let gate = FleetShutdownResumeFirstAdvanceGate()
        let controlledPort = controlledDrainPort(basePort, gate: gate)
        let lifecycle = FilesystemObservationFleetLifecycle()
        let begun = requireAppliedShutdownDebtSnapshot(
            lifecycle.beginShutdownAndSnapshot(mailbox: fixture.mailbox)
        )
        try await prepareActorDrainState(
            lifecycle: lifecycle,
            fixture: fixture,
            harness: harness,
            shutdownIdentity: begun.shutdownIdentity
        )

        let abandonedRequest = Task {
            await lifecycle.resumeShutdown(
                mailbox: fixture.mailbox,
                drainPort: controlledPort
            )
        }
        await gate.waitUntilFirstAdvanceEntered()
        abandonedRequest.cancel()
        await gate.releaseFirstAdvance()
        _ = await abandonedRequest.value

        let replay = requireIncomplete(
            await lifecycle.resumeShutdown(
                mailbox: fixture.mailbox,
                drainPort: basePort
            )
        )

        #expect(replay.snapshot.shutdownIdentity == begun.shutdownIdentity)
        #expect(replay.snapshot.shutdownIdentity.isUUIDv7)
        #expect(queuedContributionCount(replay.snapshot) == 0)
        #expect(replay.turnPlan == .beginSourceGateShutdown)
    }

    @Test("fatal actor drain outcomes remain typed resume failures")
    func fatalActorDrainOutcomesRemainTypedResumeFailures() async throws {
        for injectedFailure in FleetShutdownInjectedActorFailure.allCases {
            let fixture = try makeFixture(sourceCount: 1)
            try admitOneObservationPerSource(fixture)
            let harness = try makeHarness(fixture)
            let basePort = await harness.fleetShutdownDrainPort
            let lifecycle = FilesystemObservationFleetLifecycle()
            let begun = requireAppliedShutdownDebtSnapshot(
                lifecycle.beginShutdownAndSnapshot(mailbox: fixture.mailbox)
            )
            try await prepareActorDrainState(
                lifecycle: lifecycle,
                fixture: fixture,
                harness: harness,
                shutdownIdentity: begun.shutdownIdentity
            )
            let injectedNoProgress = injectedFailure.noProgress(fixture: fixture)
            let controlledPort = drainPort(
                basePort,
                injecting: .noProgress(injectedNoProgress)
            )

            let result = await lifecycle.resumeShutdown(
                mailbox: fixture.mailbox,
                drainPort: controlledPort
            )

            #expect(
                result
                    == .unavailable(
                        injectedFailure.resumeFailure(fixture: fixture)
                    )
            )
        }
    }

    @Test("unavailable recovery context remains explicit awaited actor progress")
    func unavailableRecoveryContextRemainsExplicitAwaitedActorProgress() async throws {
        let fixture = try makeFixture(sourceCount: 1)
        let evidence = requireRetainedRecovery(
            try fixture.fixedSlotFixture.admitCallback(
                .requiresRecovery(
                    try makeObservation(
                        registration: fixture.registrations[0],
                        path: "/fleet-lifecycle-resume/recovery",
                        eventID: 1
                    ),
                    evidence: .continuityLoss
                ),
                for: fixture.registrations[0]
            )
        )
        let harness = try makeHarness(fixture)
        let lifecycle = FilesystemObservationFleetLifecycle()
        let begun = requireAppliedShutdownDebtSnapshot(
            lifecycle.beginShutdownAndSnapshot(mailbox: fixture.mailbox)
        )
        try await prepareActorDrainState(
            lifecycle: lifecycle,
            fixture: fixture,
            harness: harness,
            shutdownIdentity: begun.shutdownIdentity
        )

        let result = await lifecycle.resumeShutdown(
            mailbox: fixture.mailbox,
            drainPort: await harness.fleetShutdownDrainPort
        )

        guard
            case .awaitingActorProgress(
                .recoveryContextUnavailable(let binding, let retainedEvidence),
                let snapshot,
                let turnPlan
            ) = result
        else {
            Issue.record("Expected explicit recovery-context wait, received \(result)")
            return
        }
        #expect(binding == fixture.bindings[0])
        #expect(retainedEvidence == evidence.revision)
        #expect(snapshot.shutdownIdentity == begun.shutdownIdentity)
        #expect(queuedContributionCount(snapshot) == 1)
        #expect(turnPlan == .advanceActorDrain)
    }

    @Test("quiescent resume completes once and every lifecycle entry point replays its receipt")
    func quiescentResumeCompletesAndReplaysStableReceipt() async throws {
        let fixture = try makeFixture(sourceCount: 1)
        let startingNativeLifetime = try #require(
            fixture.fixedSlotFixture.startingNativeLifetimesByRegistration[
                fixture.registrations[0]
            ]
        )
        _ = requireShutdownDebtNativePorts(
            fixture.mailbox.nativeGenerationPorts(for: startingNativeLifetime)
        )
        let harness = try makeHarness(fixture)
        let lifecycle = FilesystemObservationFleetLifecycle()
        let begun = requireAppliedShutdownDebtSnapshot(
            lifecycle.beginShutdownAndSnapshot(mailbox: fixture.mailbox)
        )

        let receipt = try await advanceToCompletion(
            lifecycle: lifecycle,
            fixture: fixture,
            harness: harness
        )
        let resumedReceipt = requireCompletedResume(
            await lifecycle.resumeShutdown(
                mailbox: fixture.mailbox,
                drainPort: await harness.fleetShutdownDrainPort
            )
        )
        let begunReceipt = requireCompletedBegin(
            lifecycle.beginShutdownAndSnapshot(mailbox: fixture.mailbox)
        )
        let capturedReceipt = requireCompletedCapture(
            await lifecycle.shutdownDebtSnapshot(
                mailbox: fixture.mailbox,
                drainPort: await harness.fleetShutdownDrainPort
            )
        )

        #expect(receipt.shutdownIdentity == begun.shutdownIdentity)
        #expect(receipt.shutdownIdentity.isUUIDv7)
        #expect(receipt.completionIdentity.isUUIDv7)
        #expect(receipt.fleetMailboxIdentity == fixture.mailbox.fleetMailboxIdentity)
        #expect(receipt.finalDebt.shutdownIdentity == begun.shutdownIdentity)
        #expect(receipt.finalDebt.mailbox.fleetMailboxIdentity == receipt.fleetMailboxIdentity)
        #expect(receipt.finalDebt.isQuiescent)
        #expect(fixture.mailbox.diagnostics.lifecycleState == .finished)
        #expect(fixture.mailbox.diagnostics.doorbellState == .finished)
        #expect(resumedReceipt == receipt)
        #expect(begunReceipt == receipt)
        #expect(capturedReceipt == receipt)
    }

    @Test("cancelled final resume retains one receipt after its response is discarded")
    func cancelledFinalResumeRetainsOneReceiptAfterLostResponse() async throws {
        let fixture = try makeFixture(sourceCount: 1)
        let startingNativeLifetime = try #require(
            fixture.fixedSlotFixture.startingNativeLifetimesByRegistration[
                fixture.registrations[0]
            ]
        )
        _ = requireShutdownDebtNativePorts(
            fixture.mailbox.nativeGenerationPorts(for: startingNativeLifetime)
        )
        let harness = try makeHarness(fixture)
        let lifecycle = FilesystemObservationFleetLifecycle()
        let begun = requireAppliedShutdownDebtSnapshot(
            lifecycle.beginShutdownAndSnapshot(mailbox: fixture.mailbox)
        )
        let completionReadyDebt = try await advanceToCompletionReadiness(
            lifecycle: lifecycle,
            fixture: fixture,
            harness: harness,
            shutdownIdentity: begun.shutdownIdentity
        )

        let abandonedCompletionRequest = Task {
            withUnsafeCurrentTask { task in
                task?.cancel()
            }
            #expect(Task.isCancelled)
            return await lifecycle.resumeShutdown(
                mailbox: fixture.mailbox,
                drainPort: await harness.fleetShutdownDrainPort
            )
        }
        _ = await abandonedCompletionRequest.value

        let begunReceipt = requireCompletedBegin(
            lifecycle.beginShutdownAndSnapshot(mailbox: fixture.mailbox)
        )
        let resumedReceipt = requireCompletedResume(
            await lifecycle.resumeShutdown(
                mailbox: fixture.mailbox,
                drainPort: await harness.fleetShutdownDrainPort
            )
        )
        let capturedReceipt = requireCompletedCapture(
            await lifecycle.shutdownDebtSnapshot(
                mailbox: fixture.mailbox,
                drainPort: await harness.fleetShutdownDrainPort
            )
        )

        #expect(begunReceipt.shutdownIdentity == begun.shutdownIdentity)
        #expect(begunReceipt.shutdownIdentity.isUUIDv7)
        #expect(begunReceipt.completionIdentity.isUUIDv7)
        #expect(begunReceipt.finalDebt == completionReadyDebt)
        #expect(begunReceipt.finalDebt.isQuiescent)
        #expect(resumedReceipt == begunReceipt)
        #expect(capturedReceipt == begunReceipt)
        #expect(fixture.mailbox.diagnostics.lifecycleState == .finished)
        #expect(fixture.mailbox.diagnostics.doorbellState == .finished)
    }
}

private struct FleetShutdownResumeFixture {
    let fixedSlotFixture: FixedSlotFilesystemObservationMailboxFixture
    let registrations: [FSEventRegistrationToken]
    let bindings: [FilesystemObservationSlotBinding]

    var mailbox: FilesystemObservationMailbox { fixedSlotFixture.mailbox }
}

private enum FleetShutdownInjectedActorFailure: CaseIterable {
    case configurationRejected
    case undeclaredBinding
    case mailboxClosed

    func noProgress(
        fixture: FleetShutdownResumeFixture
    ) -> FilesystemObservationFleetShutdownDrainNoProgress {
        switch self {
        case .configurationRejected:
            return .configurationRejected(configurationRejection(fixture: fixture))
        case .undeclaredBinding:
            return .undeclaredBinding(fixture.bindings[0])
        case .mailboxClosed:
            return .mailboxClosed
        }
    }

    func resumeFailure(
        fixture: FleetShutdownResumeFixture
    ) -> FilesystemObservationFleetShutdownResumeFailure {
        switch self {
        case .configurationRejected:
            return .actorDrainConfigurationRejected(
                configurationRejection(fixture: fixture)
            )
        case .undeclaredBinding:
            return .actorDrainUndeclaredBinding(fixture.bindings[0])
        case .mailboxClosed:
            return .actorDrainMailboxClosed
        }
    }

    private func configurationRejection(
        fixture: FleetShutdownResumeFixture
    ) -> FilesystemObservationFleetShutdownDrainConfigurationRejection {
        .physicalSlotCoverageMismatch(
            mailboxPhysicalSlotIDsInDeclarationOrder: fixture.mailbox.physicalSlotIDs,
            actorBindingsInDeclarationOrder: []
        )
    }
}

private actor FleetShutdownResumeFirstAdvanceGate {
    private var firstAdvanceEntered = false
    private var firstAdvanceReleased = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var advanceInvocationCount = 0

    func pauseFirstAdvance() async {
        advanceInvocationCount += 1
        guard advanceInvocationCount == 1 else { return }
        firstAdvanceEntered = true
        let waiters = entryWaiters
        entryWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        guard !firstAdvanceReleased else { return }
        await withCheckedContinuation { continuation in
            releaseWaiters.append(continuation)
        }
    }

    func waitUntilFirstAdvanceEntered() async {
        guard !firstAdvanceEntered else { return }
        await withCheckedContinuation { continuation in
            entryWaiters.append(continuation)
        }
    }

    func releaseFirstAdvance() {
        firstAdvanceReleased = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }
}

private func controlledDrainPort(
    _ basePort: FilesystemObservationFleetShutdownDrainPort,
    gate: FleetShutdownResumeFirstAdvanceGate
) -> FilesystemObservationFleetShutdownDrainPort {
    FilesystemObservationFleetShutdownDrainPort(
        snapshot: { await basePort.snapshot() },
        advanceOneTurn: {
            await gate.pauseFirstAdvance()
            return await basePort.advanceOneTurn()
        },
        beginOneReadySourceGateShutdown: {
            await basePort.beginOneReadySourceGateShutdown()
        }
    )
}

private func drainPort(
    _ basePort: FilesystemObservationFleetShutdownDrainPort,
    injecting advanceResult: FilesystemObservationFleetShutdownDrainAdvanceResult
) -> FilesystemObservationFleetShutdownDrainPort {
    FilesystemObservationFleetShutdownDrainPort(
        snapshot: { await basePort.snapshot() },
        advanceOneTurn: { advanceResult },
        beginOneReadySourceGateShutdown: {
            await basePort.beginOneReadySourceGateShutdown()
        }
    )
}

private func makeFixture(sourceCount: Int) throws -> FleetShutdownResumeFixture {
    let registrations = (0..<sourceCount).map { index in
        FSEventRegistrationToken(
            sourceID: FilesystemSourceID(
                kind: .registeredWorktreeContent,
                rootID: UUIDv7.generate()
            ),
            registrationGeneration: UInt64(8100 + index),
            rootGeneration: 1
        )
    }
    let fixedSlotFixture = try makeFixedSlotMailboxFixture(
        generation: AdmissionGeneration(owner: .filesystemObservation, value: 8100),
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
        callbackQueueLabel: "test.filesystem-observation-fleet-lifecycle-resume"
    )
    return FleetShutdownResumeFixture(
        fixedSlotFixture: fixedSlotFixture,
        registrations: registrations,
        bindings: registrations.map { fixedSlotFixture.binding(for: $0) }
    )
}

private func makeHarness(
    _ fixture: FleetShutdownResumeFixture
) throws -> FilesystemObservationDrainHarnessActor {
    try FilesystemObservationDrainHarnessActor(
        mailbox: fixture.mailbox,
        bindings: fixture.bindings,
        maximumContributionsPerLease: 1
    )
}

private func admitOneObservationPerSource(
    _ fixture: FleetShutdownResumeFixture
) throws {
    for (index, registration) in fixture.registrations.enumerated() {
        expectRetainedCallback(
            try fixture.fixedSlotFixture.admitCallback(
                .authoritative(
                    try makeObservation(
                        registration: registration,
                        path: "/fleet-lifecycle-resume/\(index)",
                        eventID: UInt64(index + 1)
                    )
                ),
                for: registration
            )
        )
    }
}

private func prepareActorDrainState(
    lifecycle: FilesystemObservationFleetLifecycle,
    fixture: FleetShutdownResumeFixture,
    harness: FilesystemObservationDrainHarnessActor,
    shutdownIdentity: FilesystemObservationFleetShutdownIdentity
) async throws {
    let maximumArrangeTurns = fixture.registrations.count * 32 + 16
    for _ in 0..<maximumArrangeTurns {
        let capture = await lifecycle.shutdownDebtSnapshot(
            mailbox: fixture.mailbox,
            drainPort: await harness.fleetShutdownDrainPort
        )
        guard case .captured(_, let turnPlan) = capture else {
            Issue.record("Arrange could not capture shutdown debt: \(capture)")
            throw FleetShutdownResumeTestFailure.arrangeFailed
        }
        switch turnPlan {
        case .advanceActorDrain:
            return
        case .advanceMailbox:
            let result = await fixture.mailbox.advanceFleetShutdownOneTurn(
                for: shutdownIdentity
            )
            guard case .progressed = result else {
                Issue.record("Arrange mailbox turn did not make bounded progress: \(result)")
                throw FleetShutdownResumeTestFailure.arrangeFailed
            }
        case .beginSourceGateShutdown, .awaitOwnedProgress, .readyForCompletion:
            Issue.record("Arrange reached unexpected turn plan: \(turnPlan)")
            throw FleetShutdownResumeTestFailure.arrangeFailed
        }
    }
    Issue.record("Arrange exceeded its fixed mailbox-turn bound")
    throw FleetShutdownResumeTestFailure.arrangeFailed
}

private func advanceToCompletion(
    lifecycle: FilesystemObservationFleetLifecycle,
    fixture: FleetShutdownResumeFixture,
    harness: FilesystemObservationDrainHarnessActor
) async throws -> FilesystemObservationFleetShutdownReceipt {
    let maximumArrangeTurns = fixture.registrations.count * 32 + 16
    for _ in 0..<maximumArrangeTurns {
        let result = await lifecycle.resumeShutdown(
            mailbox: fixture.mailbox,
            drainPort: await harness.fleetShutdownDrainPort
        )
        switch result {
        case .completed(let receipt):
            return receipt
        case .incomplete, .awaitingActorProgress:
            continue
        case .resumeAlreadyInProgress, .unavailable:
            Issue.record("Arrange could not advance to completion: \(result)")
            throw FleetShutdownResumeTestFailure.arrangeFailed
        }
    }
    Issue.record("Arrange exceeded its fixed completion turn bound")
    throw FleetShutdownResumeTestFailure.arrangeFailed
}

private func advanceToCompletionReadiness(
    lifecycle: FilesystemObservationFleetLifecycle,
    fixture: FleetShutdownResumeFixture,
    harness: FilesystemObservationDrainHarnessActor,
    shutdownIdentity: FilesystemObservationFleetShutdownIdentity
) async throws -> FilesystemObservationFleetShutdownDebtSnapshot {
    let drainPort = await harness.fleetShutdownDrainPort
    let maximumArrangeTurns = fixture.registrations.count * 32 + 16
    for _ in 0..<maximumArrangeTurns {
        let capture = await lifecycle.shutdownDebtSnapshot(
            mailbox: fixture.mailbox,
            drainPort: drainPort
        )
        guard case .captured(let snapshot, let turnPlan) = capture else {
            Issue.record("Arrange could not capture completion readiness: \(capture)")
            throw FleetShutdownResumeTestFailure.arrangeFailed
        }
        switch turnPlan {
        case .advanceMailbox:
            let result = await fixture.mailbox.advanceFleetShutdownOneTurn(
                for: shutdownIdentity
            )
            guard case .progressed = result else {
                Issue.record("Arrange mailbox turn did not make bounded progress: \(result)")
                throw FleetShutdownResumeTestFailure.arrangeFailed
            }
        case .advanceActorDrain:
            switch await drainPort.advanceOneTurn() {
            case .leaseTransfer, .cleanup:
                continue
            case .noProgress(let noProgress):
                Issue.record("Arrange actor drain did not make bounded progress: \(noProgress)")
                throw FleetShutdownResumeTestFailure.arrangeFailed
            }
        case .beginSourceGateShutdown:
            _ = await drainPort.beginOneReadySourceGateShutdown()
        case .readyForCompletion:
            return snapshot
        case .awaitOwnedProgress(let awaitedProgress):
            Issue.record("Arrange unexpectedly awaited owned progress: \(awaitedProgress)")
            throw FleetShutdownResumeTestFailure.arrangeFailed
        }
    }
    Issue.record("Arrange exceeded its fixed completion-readiness turn bound")
    throw FleetShutdownResumeTestFailure.arrangeFailed
}

private func requireAppliedShutdownDebtSnapshot(
    _ result: FilesystemObservationFleetShutdownBeginResult
) -> FilesystemObservationFleetShutdownMailboxDebtSnapshot {
    guard case .applied(let snapshot) = result else {
        Issue.record("Expected applied lifecycle shutdown snapshot, received \(result)")
        preconditionFailure("Expected applied lifecycle shutdown snapshot")
    }
    return snapshot
}

private func requireCompletedResume(
    _ result: FilesystemObservationFleetShutdownResumeResult
) -> FilesystemObservationFleetShutdownReceipt {
    guard case .completed(let receipt) = result else {
        Issue.record("Expected completed shutdown resume receipt, received \(result)")
        preconditionFailure("Expected completed shutdown resume receipt")
    }
    return receipt
}

private func requireCompletedBegin(
    _ result: FilesystemObservationFleetShutdownBeginResult
) -> FilesystemObservationFleetShutdownReceipt {
    guard case .completed(let receipt) = result else {
        Issue.record("Expected completed shutdown begin receipt, received \(result)")
        preconditionFailure("Expected completed shutdown begin receipt")
    }
    return receipt
}

private func requireCompletedCapture(
    _ result: FilesystemObservationFleetShutdownDebtCaptureResult
) -> FilesystemObservationFleetShutdownReceipt {
    guard case .completed(let receipt) = result else {
        Issue.record("Expected completed shutdown debt receipt, received \(result)")
        preconditionFailure("Expected completed shutdown debt receipt")
    }
    return receipt
}

private func queuedContributionCount(
    _ snapshot: FilesystemObservationFleetShutdownDebtSnapshot
) -> Int {
    snapshot.mailbox.genericMailboxDebt.keyDebt.reduce(0) {
        $0 + $1.queuedContributionCount
    }
}

private func requireIncomplete(
    _ result: FilesystemObservationFleetShutdownResumeResult
) -> FleetShutdownResumeIncompleteExpectation {
    guard case .incomplete(let snapshot, let turnPlan) = result else {
        Issue.record("Expected incomplete fleet shutdown debt, received \(result)")
        preconditionFailure("Expected incomplete fleet shutdown debt")
    }
    return FleetShutdownResumeIncompleteExpectation(
        snapshot: snapshot,
        turnPlan: turnPlan
    )
}

private struct FleetShutdownResumeIncompleteExpectation: Equatable {
    let snapshot: FilesystemObservationFleetShutdownDebtSnapshot
    let turnPlan: FilesystemObservationFleetShutdownTurnPlan
}

private enum FleetShutdownResumeTestFailure: Error {
    case arrangeFailed
}
