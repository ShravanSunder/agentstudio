import Testing

@testable import AgentStudio

@Suite("FilesystemContentRepairProjectorTests")
struct FilesystemContentRepairProjectorTests {
    @Test("serial projection records every strict disposition then replays completion")
    func serialProjectionRecordsEveryDispositionAndReplays() async throws {
        let fixture = try await makeContentRepairProjectorFixture(consumerCount: 3)
        let requests = fixture.request.activatedGeneration.boundGeneration.deliveryRequests
        await fixture.ledger.appendDeliveryResult(
            .disposition(.rebuiltCurrent(consumerRevision: 41))
        )
        await fixture.ledger.appendDeliveryResult(
            .disposition(.markedNonCurrent(retry: requests[1].retryToken))
        )
        await fixture.ledger.appendDeliveryResult(
            .disposition(.notApplicableNoRetainedState)
        )

        let result = await fixture.projector.project(fixture.request)
        guard case .completed(let receipt) = result else {
            Issue.record("Expected completed projection, got \(result)")
            return
        }
        #expect(await fixture.projector.identity.isUUIDv7)
        #expect(receipt.acknowledgedConsumers == Set(fixture.consumers.map(\.token)))
        #expect(await fixture.ledger.maximumActiveDeliveries == 1)
        #expect(await fixture.ledger.delivered == requests)
        #expect(await fixture.ledger.accepted.count == 4)

        guard
            case .registered(let rebuilt) = await fixture.registry.lookup(fixture.consumers[0].token),
            case .registered(let retrying) = await fixture.registry.lookup(fixture.consumers[1].token),
            case .registered(let notApplicable) = await fixture.registry.lookup(fixture.consumers[2].token)
        else {
            Issue.record("Expected all consumers to remain registered")
            return
        }
        #expect(
            rebuilt.currentness
                == .current(
                    .rebuilt(
                        repairGenerationID: receipt.repairGenerationID,
                        consumerRevision: 41
                    )
                )
        )
        #expect(retrying.currentness == .nonCurrent(.retryRetained(requests[1].retryToken)))
        #expect(
            notApplicable.currentness
                == .nonCurrent(.noRetainedContent(requests[2].invalidationGeneration))
        )

        #expect(await fixture.projector.project(fixture.request) == .replayed(receipt))
        #expect(await fixture.ledger.delivered.count == 3)
    }

    @Test("mailbox acceptance with no consumers acknowledges only the projector")
    func mailboxAcceptanceWithEmptyCaptureCompletesWithoutFabrication() async throws {
        let fixture = try await makeContentRepairProjectorFixture(
            consumerCount: 0,
            acceptanceKind: .mailbox
        )

        let result = await fixture.projector.project(fixture.request)
        guard case .completed(let receipt) = result else {
            Issue.record("Expected empty capture to complete, got \(result)")
            return
        }
        #expect(receipt.acknowledgedConsumers.isEmpty)
        #expect(receipt.invalidationGenerations.isEmpty)
        #expect(await fixture.ledger.delivered.isEmpty)
        #expect(await fixture.ledger.accepted == [receipt.projectorAcknowledgement])
    }

    @Test("acceptance mismatch rejects before any consumer effect")
    func acceptanceMismatchRejectsBeforeEffects() async throws {
        let fixture = try await makeContentRepairProjectorFixture(consumerCount: 1)
        guard case .continuity(let accepted) = fixture.request.acceptance else {
            Issue.record("Expected continuity fixture")
            return
        }
        let repair = accepted.repairGeneration
        let mismatched = RepairGeneration(
            id: repair.id,
            watermark: .recoveryRevision(999),
            trigger: repair.trigger,
            participants: repair.participants
        )
        let request = FilesystemContentRepairProjectionRequest(
            acceptance: .continuity(
                FilesystemSourceGateContinuityRepairAcceptance(
                    authority: accepted.authority,
                    repairGeneration: mismatched
                )
            ),
            activatedGeneration: fixture.request.activatedGeneration
        )

        #expect(await fixture.projector.project(request) == .rejected(.acceptanceMismatch))
        #expect(await fixture.ledger.delivered.isEmpty)
        #expect(await fixture.ledger.accepted.isEmpty)
    }

    @Test("consumer retry and SourceGate retry resume exact journal phases")
    func retryPhasesResumeWithoutLostCustodyOrRedelivery() async throws {
        let fixture = try await makeContentRepairProjectorFixture(
            consumerCount: 1,
            deliveryResults: [.retryRequested(.consumerRequestedRetry)]
        )
        let deliveryRequest = fixture.request.activatedGeneration.boundGeneration.deliveryRequests[0]

        guard
            case .awaitingRetry(.consumerRetry(let retained, .consumerRequestedRetry)) =
                await fixture.projector.project(fixture.request)
        else {
            Issue.record("Expected consumer retry debt")
            return
        }
        #expect(retained == deliveryRequest)

        await fixture.ledger.appendDeliveryResult(
            .disposition(.rebuiltCurrent(consumerRevision: 7))
        )
        await fixture.ledger.appendSourceGateResult(.invalidState(.dirty(deliveryRequest.repairGeneration)))
        guard
            case .awaitingRetry(.sourceGateAcknowledgement) =
                await fixture.projector.project(fixture.request)
        else {
            Issue.record("Expected SourceGate acknowledgement debt")
            return
        }
        #expect(await fixture.ledger.delivered.count == 2)

        await fixture.ledger.appendSourceGateResult(.applied)
        await fixture.ledger.appendSourceGateResult(.applied)
        #expect(isCompleted(await fixture.projector.project(fixture.request)))
        #expect(await fixture.ledger.delivered.count == 2)
    }

    @Test("wrong retry token retains registry debt and never reaches SourceGate")
    func wrongRetryTokenRetainsDebt() async throws {
        let fixture = try await makeContentRepairProjectorFixture(consumerCount: 1)
        let deliveryRequest = fixture.request.activatedGeneration.boundGeneration.deliveryRequests[0]
        let wrongRetry = ContentRepairRetryToken.generate(
            repairGenerationID: deliveryRequest.repairGeneration.id,
            consumer: deliveryRequest.consumer
        )
        await fixture.ledger.appendDeliveryResult(
            .disposition(.markedNonCurrent(retry: wrongRetry))
        )

        guard
            case .awaitingRetry(.registryAcknowledgement(_, let result)) =
                await fixture.projector.project(fixture.request)
        else {
            Issue.record("Expected registry acknowledgement debt")
            return
        }
        #expect(result == .debtRetained(.retryTokenMismatch))
        #expect(await fixture.ledger.accepted.isEmpty)
    }

    @Test("consumer rejection uses the typed SourceGate rejection path")
    func consumerRejectionIsNotConvertedToNotApplicable() async throws {
        let fixture = try await makeContentRepairProjectorFixture(
            consumerCount: 1,
            deliveryResults: [.rejected(.currentnessApplyFailed)]
        )

        guard
            case .awaitingRetry(
                .consumerRejected(_, .currentnessApplyFailed, .applied)
            ) = await fixture.projector.project(fixture.request)
        else {
            Issue.record("Expected typed consumer rejection debt")
            return
        }
        #expect(await fixture.ledger.rejected.count == 1)
        #expect(await fixture.ledger.accepted.isEmpty)
    }

    @Test("pre-cancelled projection cannot split acknowledgement confirmation")
    func cancellationCannotSplitAcknowledgementConfirmation() async throws {
        let fixture = try await makeContentRepairProjectorFixture(consumerCount: 1)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await fixture.projector.project(fixture.request)
        }

        #expect(isCompleted(await task.value))
        #expect((await fixture.registry.shutdownDebtSnapshot()).outboundAcknowledgements.isEmpty)
        #expect(await fixture.ledger.accepted.count == 2)
    }

    @Test("withdrawal acknowledgement forwards exactly and replays")
    func withdrawalAcknowledgementUsesExactForwardJournal() async throws {
        let fixture = try await makeContentRepairProjectorFixture(consumerCount: 1)
        guard
            case .withdrawnAndAcknowledged(let acknowledgement) = await fixture.registry.withdraw(
                fixture.consumers[0].token,
                disposition: .noRetainedState
            )
        else {
            Issue.record("Expected withdrawal acknowledgement")
            return
        }

        #expect(
            await fixture.projector.forwardRegistryAcknowledgement(acknowledgement)
                == .completed(acknowledgement)
        )
        #expect(
            await fixture.projector.forwardRegistryAcknowledgement(acknowledgement)
                == .replayed(acknowledgement)
        )
        let conflicting = ContentRepairAcceptedAcknowledgement(
            sourceGateAcknowledgement: acknowledgement.sourceGateAcknowledgement,
            disposition: .rebuiltCurrent(consumerRevision: 999)
        )
        #expect(
            await fixture.projector.forwardRegistryAcknowledgement(conflicting)
                == .acknowledgementConflict(acknowledgement.sourceGateAcknowledgement)
        )
        #expect(await fixture.ledger.accepted.count == 1)
    }

    @Test("concurrent re-entry observes the strict processing phase")
    func concurrentReentryCannotDuplicateDelivery() async throws {
        let fixture = try await makeContentRepairProjectorFixture(consumerCount: 1)
        let suspension = FilesystemContentRepairDeliverySuspension()
        let identity = await fixture.projector.identity
        let projector = FilesystemContentRepairProjector(
            identity: identity,
            participantGeneration: 7,
            consumerPort: FilesystemContentRepairConsumerDeliveryPort { _ in
                await suspension.suspendDelivery()
                return .disposition(.rebuiltCurrent(consumerRevision: 15))
            },
            registryPort: FilesystemContentRepairRegistryPort(registry: fixture.registry),
            sourceGatePort: FilesystemContentRepairSourceGatePort(
                accept: { token in await fixture.ledger.accept(token) },
                reject: { token, _ in await fixture.ledger.reject(token) }
            )
        )
        let first = Task { await projector.project(fixture.request) }
        await suspension.waitUntilSuspended()

        #expect(
            await projector.project(fixture.request)
                == .alreadyProcessing(fixture.request.acceptance.repairGeneration.id)
        )
        await suspension.resumeDelivery()
        #expect(isCompleted(await first.value))
    }

    @Test("real registry supersession retires retry journal before successor projection")
    func supersededRetryJournalCannotBlockSuccessor() async throws {
        let fixture = try await makeContentRepairProjectorFixture(
            consumerCount: 1,
            deliveryResults: [.retryRequested(.consumerUnavailable)]
        )
        guard
            case .awaitingRetry(.consumerRetry) =
                await fixture.projector.project(fixture.request),
            case .prepared(let capture) = await fixture.registry.prepareCapture(
                identity: .generate(),
                registration: fixture.request.acceptance.repairGeneration.id.registration
            )
        else {
            Issue.record("Expected retry debt followed by successor capture")
            return
        }
        let successorAcceptance = makeManualContentRepairAcceptance(
            registration: capture.registration,
            sequence: fixture.request.acceptance.repairGeneration.id.sequence + 1,
            participants: capture.sourceGateParticipants.union([
                await fixture.projector.participant,
                contentRepairTestParticipant(.gitWorkingDirectoryProjector),
                contentRepairTestParticipant(.paneFilesystemProjection),
            ])
        )
        guard
            case .boundPending = await fixture.registry.bind(
                capture,
                to: successorAcceptance.repairGeneration
            ),
            case .activated(let successor) = await fixture.registry.activateBoundGeneration(
                successorAcceptance.repairGeneration.id
            )
        else {
            Issue.record("Expected pending successor activation")
            return
        }
        let deliveryCountBeforeResume = await fixture.ledger.delivered.count

        #expect(
            await fixture.projector.project(fixture.request)
                == .rejected(
                    .registryIneligible(
                        .supersededGeneration(fixture.request.acceptance.repairGeneration.id)
                    )
                )
        )
        #expect(await fixture.ledger.delivered.count == deliveryCountBeforeResume)
        let successorRequest = FilesystemContentRepairProjectionRequest(
            acceptance: successorAcceptance,
            activatedGeneration: successor
        )
        #expect(isCompleted(await fixture.projector.project(successorRequest)))
    }

    @Test("draining resumes retained forward debt but rejects fresh token")
    func drainingRejectsFreshForwardWithoutSourceGateEffect() async throws {
        let fixture = try await makeContentRepairProjectorFixture(
            consumerCount: 2,
            sourceGateResults: [.staleGeneration]
        )
        guard
            case .withdrawnAndAcknowledged(let first) = await fixture.registry.withdraw(
                fixture.consumers[0].token,
                disposition: .noRetainedState
            ),
            case .withdrawnAndAcknowledged(let second) = await fixture.registry.withdraw(
                fixture.consumers[1].token,
                disposition: .noRetainedState
            ),
            case .awaitingSourceGate =
                await fixture.projector.forwardRegistryAcknowledgement(first)
        else {
            Issue.record("Expected two acknowledgements and retained first-token debt")
            return
        }
        let firstToken = first.sourceGateAcknowledgement
        let secondToken = second.sourceGateAcknowledgement
        #expect(
            await fixture.projector.beginOrResumeShutdown()
                == .awaitingDebt(
                    FilesystemContentRepairProjectorShutdownDebt(
                        activeRepairGenerations: [],
                        outboundAcknowledgements: [firstToken]
                    )
                )
        )
        #expect(
            await fixture.projector.forwardRegistryAcknowledgement(second) == .shuttingDown
        )
        #expect(await fixture.ledger.accepted == [firstToken])
        #expect(
            (await fixture.projector.shutdownDebtSnapshot()).outboundAcknowledgements
                == [firstToken]
        )
        #expect(firstToken != secondToken)
    }

    @Test("processing forward rejects conflicting value before effects")
    func processingForwardRejectsConflictBeforeEffects() async throws {
        let fixture = try await makeContentRepairProjectorFixture(consumerCount: 1)
        guard
            case .withdrawnAndAcknowledged(let acknowledgement) = await fixture.registry.withdraw(
                fixture.consumers[0].token,
                disposition: .noRetainedState
            )
        else {
            Issue.record("Expected withdrawal acknowledgement")
            return
        }
        let suspension = ContentRepairForwardingEligibilitySuspension()
        let projector = FilesystemContentRepairProjector(
            consumerPort: FilesystemContentRepairConsumerDeliveryPort { _ in
                .retryRequested(.consumerUnavailable)
            },
            registryPort: FilesystemContentRepairRegistryPort(
                validateProjection: { _ in .shuttingDown },
                validateForwarding: {
                    await suspension.validate($0, registry: fixture.registry)
                },
                acknowledge: { _, _, _ in .shuttingDown },
                confirm: { await fixture.registry.confirmSourceGateAcknowledgement($0) }
            ),
            sourceGatePort: FilesystemContentRepairSourceGatePort(
                accept: { await fixture.ledger.accept($0) },
                reject: { token, _ in await fixture.ledger.reject(token) }
            )
        )
        let first = Task { await projector.forwardRegistryAcknowledgement(acknowledgement) }
        await suspension.waitUntilSuspended()
        let conflict = ContentRepairAcceptedAcknowledgement(
            sourceGateAcknowledgement: acknowledgement.sourceGateAcknowledgement,
            disposition: .rebuiltCurrent(consumerRevision: 999)
        )

        #expect(
            await projector.forwardRegistryAcknowledgement(conflict)
                == .acknowledgementConflict(acknowledgement.sourceGateAcknowledgement)
        )
        #expect(await fixture.ledger.accepted.isEmpty)
        await suspension.resumeValidation()
        #expect(await first.value == .completed(acknowledgement))
        #expect(await fixture.ledger.accepted == [acknowledgement.sourceGateAcknowledgement])
    }

    @Test("shutdown retains exact generation debt and rejects new work after drain")
    func shutdownDebtIsExactAndResumable() async throws {
        let fixture = try await makeContentRepairProjectorFixture(
            consumerCount: 1,
            deliveryResults: [.retryRequested(.consumerUnavailable)]
        )
        _ = await fixture.projector.project(fixture.request)
        let generationID = fixture.request.acceptance.repairGeneration.id

        #expect(
            await fixture.projector.beginOrResumeShutdown()
                == .awaitingDebt(
                    FilesystemContentRepairProjectorShutdownDebt(
                        activeRepairGenerations: [generationID],
                        outboundAcknowledgements: []
                    )
                )
        )
        await fixture.ledger.appendDeliveryResult(
            .disposition(.rebuiltCurrent(consumerRevision: 9))
        )
        #expect(isCompleted(await fixture.projector.project(fixture.request)))
        #expect(
            await fixture.projector.beginOrResumeShutdown()
                == .alreadyCompleted(
                    FilesystemContentRepairProjectorShutdownDebt(
                        activeRepairGenerations: [],
                        outboundAcknowledgements: []
                    )
                )
        )
    }

    @Test("delivery surface contains no path or sentinel field")
    func deliverySurfaceCannotRepresentPathReplay() async throws {
        let fixture = try await makeContentRepairProjectorFixture(consumerCount: 1)
        let request = fixture.request.activatedGeneration.boundGeneration.deliveryRequests[0]
        let labels = Set(Mirror(reflecting: request).children.compactMap(\.label))

        #expect(labels == ["repairGeneration", "invalidationGeneration", "consumer", "retryToken"])
        #expect(!labels.contains("path"))
        #expect(!labels.contains("paths"))
    }

    private func isCompleted(_ result: FilesystemContentRepairProjectionResult) -> Bool {
        if case .completed = result { return true }
        return false
    }
}
