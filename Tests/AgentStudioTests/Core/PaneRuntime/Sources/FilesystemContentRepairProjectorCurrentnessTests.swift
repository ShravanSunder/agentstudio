import Testing

@testable import AgentStudio

extension FilesystemContentRepairProjectorTests {
    private func isCompleted(_ result: FilesystemContentRepairProjectionResult) -> Bool {
        if case .completed = result { return true }
        return false
    }

    @Test("projection admission is reserved while registry eligibility is suspended")
    func eligibilitySuspensionCannotAdmitASecondJournal() async throws {
        let fixture = try await makeContentRepairProjectorFixture(consumerCount: 1)
        let suspension = FilesystemContentRepairEligibilitySuspension()
        let identity = await fixture.projector.identity
        let projector = FilesystemContentRepairProjector(
            identity: identity,
            participantGeneration: 7,
            consumerPort: FilesystemContentRepairConsumerDeliveryPort { request in
                await fixture.ledger.deliver(request)
            },
            registryPort: FilesystemContentRepairRegistryPort(
                validateProjection: { generation in
                    await suspension.validate(generation, registry: fixture.registry)
                },
                validateForwarding: { acknowledgement in
                    await fixture.registry.validateAcknowledgementForwardingEligibility(
                        acknowledgement
                    )
                },
                acknowledge: { generationID, consumer, disposition in
                    await fixture.registry.acknowledge(
                        repairGenerationID: generationID,
                        consumer: consumer,
                        disposition: disposition
                    )
                },
                confirm: { await fixture.registry.confirmSourceGateAcknowledgement($0) }
            ),
            sourceGatePort: FilesystemContentRepairSourceGatePort(
                accept: { await fixture.ledger.accept($0) },
                reject: { token, _ in await fixture.ledger.reject(token) }
            )
        )
        let first = Task { await projector.project(fixture.request) }
        await suspension.waitUntilSuspended()

        #expect(
            await projector.project(fixture.request)
                == .alreadyProcessing(fixture.request.acceptance.repairGeneration.id)
        )
        #expect(await fixture.ledger.delivered.isEmpty)
        await suspension.resumeValidation()
        #expect(isCompleted(await first.value))
        #expect(await fixture.ledger.delivered.count == 1)
    }

    @Test("confirmed external acknowledgement replays without recreating effects")
    func confirmedExternalAcknowledgementReplaysWithoutEffects() async throws {
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
        let secondLedger = FilesystemContentRepairTestLedger()
        let secondProjector = FilesystemContentRepairProjector(
            consumerPort: FilesystemContentRepairConsumerDeliveryPort { _ in
                .retryRequested(.consumerUnavailable)
            },
            registryPort: FilesystemContentRepairRegistryPort(registry: fixture.registry),
            sourceGatePort: FilesystemContentRepairSourceGatePort(
                accept: { await secondLedger.accept($0) },
                reject: { token, _ in await secondLedger.reject(token) }
            )
        )

        #expect(
            await secondProjector.forwardRegistryAcknowledgement(acknowledgement)
                == .replayed(acknowledgement)
        )
        #expect(await secondLedger.accepted.isEmpty)
        #expect((await secondProjector.shutdownDebtSnapshot()).outboundAcknowledgements.isEmpty)
    }

    @Test("registry acknowledgement debt retries without consumer redelivery")
    func registryAcknowledgementDebtRetainsExactDisposition() async throws {
        let fixture = try await makeContentRepairProjectorFixture(consumerCount: 1)
        let gate = FilesystemContentRepairRegistryAcknowledgementGate()
        let identity = await fixture.projector.identity
        let projector = FilesystemContentRepairProjector(
            identity: identity,
            participantGeneration: 7,
            consumerPort: FilesystemContentRepairConsumerDeliveryPort { request in
                await fixture.ledger.deliver(request)
            },
            registryPort: FilesystemContentRepairRegistryPort(
                validateProjection: { generation in
                    await fixture.registry.validateProjectionEligibility(generation)
                },
                validateForwarding: { acknowledgement in
                    await fixture.registry.validateAcknowledgementForwardingEligibility(
                        acknowledgement
                    )
                },
                acknowledge: { repairGenerationID, consumer, disposition in
                    await gate.acknowledge(
                        registry: fixture.registry,
                        repairGenerationID: repairGenerationID,
                        consumer: consumer,
                        disposition: disposition
                    )
                },
                confirm: { token in
                    await fixture.registry.confirmSourceGateAcknowledgement(token)
                }
            ),
            sourceGatePort: FilesystemContentRepairSourceGatePort(
                accept: { token in await fixture.ledger.accept(token) },
                reject: { token, _ in await fixture.ledger.reject(token) }
            )
        )

        guard
            case .awaitingRetry(.registryAcknowledgement(_, .debtRetained(.repairNotBound))) =
                await projector.project(fixture.request)
        else {
            Issue.record("Expected registry acknowledgement debt")
            return
        }
        #expect(await fixture.ledger.delivered.count == 1)
        #expect(isCompleted(await projector.project(fixture.request)))
        #expect(await fixture.ledger.delivered.count == 1)
        #expect(await gate.acknowledgementAttempts == 2)
    }

    @Test("stale external acknowledgement is rejected without retained debt")
    func staleExternalAcknowledgementRetainsNoIdleDebt() async throws {
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
        _ = await fixture.registry.confirmSourceGateAcknowledgement(
            acknowledgement.sourceGateAcknowledgement
        )
        _ = await fixture.registry.retireSource(
            acknowledgement.sourceGateAcknowledgement.repairGenerationID.registration.sourceID
        )

        guard
            case .registryIneligible(.foreignOrRetiredSource) =
                await fixture.projector.forwardRegistryAcknowledgement(acknowledgement)
        else {
            Issue.record("Expected stale acknowledgement rejection")
            return
        }
        #expect(await fixture.ledger.accepted.isEmpty)
        #expect((await fixture.projector.shutdownDebtSnapshot()).outboundAcknowledgements.isEmpty)
    }

    @Test("projector retirement is debt-safe exact and idempotent")
    func projectorRetirementRequiresNoDebtAndRetiresOnce() async throws {
        let fixture = try await makeContentRepairProjectorFixture(
            consumerCount: 1,
            deliveryResults: [.retryRequested(.consumerUnavailable)]
        )
        let receiptRegistry = WorktreeContentRepairConsumerRegistry()
        let registration = fixture.request.acceptance.repairGeneration.id.registration
        _ = await receiptRegistry.register(registration: registration, eligibility: .eligible)
        let receipt = try requireContentRepairRetirementReceipt(
            await receiptRegistry.retireSource(registration.sourceID)
        )
        let retirement = FilesystemContentRepairSourceRetirementRequest(
            registryReceipt: receipt,
            acceptance: fixture.request.acceptance
        )
        _ = await fixture.projector.project(fixture.request)

        guard case .outstandingDebt(let debt) = await fixture.projector.retireSource(retirement) else {
            Issue.record("Expected projector delivery debt")
            return
        }
        #expect(debt.activeRepairGenerations == [registrationRepairID(fixture.request)])
        await fixture.ledger.appendDeliveryResult(
            .disposition(.rebuiltCurrent(consumerRevision: 8))
        )
        #expect(isCompleted(await fixture.projector.project(fixture.request)))
        #expect(await fixture.projector.retireSource(retirement) == .retired(receipt))
        #expect(
            await fixture.projector.retireSource(retirement)
                == .alreadyRetired(registration.sourceID)
        )
    }

    @Test("old receipt and acceptance cannot clear newer registration state")
    func staleReceiptPairCannotClearNewerRegistration() async throws {
        let sourceID = contentRepairTestRegistration().sourceID
        let oldRegistration = contentRepairTestRegistration(
            sourceID: sourceID,
            registrationGeneration: 3
        )
        let newRegistration = contentRepairTestRegistration(
            sourceID: sourceID,
            registrationGeneration: 4
        )
        let identity = FilesystemContentRepairProjectorIdentity.generate()
        let oldFixture = try await makeContentRepairProjectorFixture(
            consumerCount: 0,
            registration: oldRegistration,
            identity: identity
        )
        let newFixture = try await makeContentRepairProjectorFixture(
            consumerCount: 0,
            registration: newRegistration,
            identity: identity
        )
        let projector = makeRoutingProjector(
            identity: identity,
            first: oldFixture,
            second: newFixture
        )
        #expect(isCompleted(await projector.project(oldFixture.request)))
        let oldReceipt = try requireContentRepairRetirementReceipt(
            await oldFixture.registry.retireSource(sourceID)
        )
        guard case .completed(let newReceipt) = await projector.project(newFixture.request) else {
            Issue.record("Expected newer registration completion")
            return
        }
        let oldDeliveryCount = await oldFixture.ledger.delivered.count
        let newDeliveryCount = await newFixture.ledger.delivered.count
        let oldAcceptanceCount = await oldFixture.ledger.accepted.count
        let newAcceptanceCount = await newFixture.ledger.accepted.count
        let staleRequest = FilesystemContentRepairSourceRetirementRequest(
            registryReceipt: oldReceipt,
            acceptance: oldFixture.request.acceptance
        )

        #expect(
            await projector.retireSource(staleRequest)
                == .rejected(
                    .currentRegistrationMismatch(
                        expected: newRegistration,
                        actual: oldRegistration
                    )
                )
        )
        #expect(await projector.project(newFixture.request) == .replayed(newReceipt))
        #expect(await oldFixture.ledger.delivered.count == oldDeliveryCount)
        #expect(await newFixture.ledger.delivered.count == newDeliveryCount)
        #expect(await oldFixture.ledger.accepted.count == oldAcceptanceCount)
        #expect(await newFixture.ledger.accepted.count == newAcceptanceCount)
    }

    @Test("registry pending and superseded classifications reject before effects")
    func pendingAndSupersededActivationsCauseNoConsumerEffects() async throws {
        let fixture = try await makeContentRepairProjectorFixture(consumerCount: 1)
        let reasons: [ContentRepairProjectionIneligibility] = [
            .pendingGeneration(fixture.request.acceptance.repairGeneration.id),
            .supersededGeneration(fixture.request.acceptance.repairGeneration.id),
        ]
        for reason in reasons {
            let ledger = FilesystemContentRepairTestLedger()
            let projector = makeEligibilityRejectingProjector(
                identity: await fixture.projector.identity,
                reason: reason,
                ledger: ledger
            )
            #expect(
                await projector.project(fixture.request)
                    == .rejected(.registryIneligible(reason))
            )
            #expect(await ledger.delivered.isEmpty)
            #expect(await ledger.accepted.isEmpty)
        }
    }

    @Test("final-consumer registry completion remains eligible for projection")
    func retainedFinalConsumerCompletionRemainsEligible() async throws {
        let fixture = try await makeContentRepairProjectorFixture(consumerCount: 1)
        let request = fixture.request.activatedGeneration.boundGeneration.deliveryRequests[0]
        guard
            case .accepted(let acknowledgement) = await fixture.registry.acknowledge(
                repairGenerationID: request.repairGeneration.id,
                consumer: request.consumer,
                disposition: .rebuiltCurrent(consumerRevision: 42)
            )
        else {
            Issue.record("Expected final consumer acknowledgement")
            return
        }
        _ = await fixture.registry.confirmSourceGateAcknowledgement(
            acknowledgement.sourceGateAcknowledgement
        )
        await fixture.ledger.appendDeliveryResult(
            .disposition(.rebuiltCurrent(consumerRevision: 42))
        )

        let result = await fixture.projector.project(fixture.request)
        guard isCompleted(result) else {
            Issue.record("Expected retained-completed projection, got \(result)")
            return
        }
        #expect(await fixture.ledger.delivered == [request])
    }

    @Test("stale activation cannot redeliver after 256-record replay eviction")
    func staleActivationAfterReplayEvictionCausesNoConsumerCalls() async throws {
        let registry = WorktreeContentRepairConsumerRegistry()
        let registration = contentRepairTestRegistration()
        let identity = FilesystemContentRepairProjectorIdentity.generate()
        let participant = identity.participant(generation: 7)
        let ledger = FilesystemContentRepairTestLedger()
        let projector = FilesystemContentRepairProjector(
            identity: identity,
            participantGeneration: 7,
            consumerPort: FilesystemContentRepairConsumerDeliveryPort { request in
                await ledger.deliver(request)
            },
            registryPort: FilesystemContentRepairRegistryPort(registry: registry),
            sourceGatePort: FilesystemContentRepairSourceGatePort(
                accept: { await ledger.accept($0) },
                reject: { token, _ in await ledger.reject(token) }
            )
        )
        var firstRequest: FilesystemContentRepairProjectionRequest?
        for sequence in 0...256 {
            guard
                case .prepared(let capture) = await registry.prepareCapture(
                    identity: .generate(),
                    registration: registration
                )
            else {
                Issue.record("Expected capture (sequence)")
                return
            }
            let acceptance = makeManualContentRepairAcceptance(
                registration: registration,
                sequence: UInt64(sequence),
                participants: [
                    participant,
                    contentRepairTestParticipant(.gitWorkingDirectoryProjector),
                    contentRepairTestParticipant(.paneFilesystemProjection),
                ]
            )
            guard
                case .boundActive(let activated) = await registry.bind(
                    capture,
                    to: acceptance.repairGeneration
                )
            else {
                Issue.record("Expected active generation (sequence)")
                return
            }
            let request = FilesystemContentRepairProjectionRequest(
                acceptance: acceptance,
                activatedGeneration: activated
            )
            if firstRequest == nil { firstRequest = request }
            #expect(isCompleted(await projector.project(request)))
        }
        let callsBeforeStaleReplay = await ledger.delivered.count
        let staleRequest = try #require(firstRequest)

        guard
            case .rejected(.registryIneligible(.staleGeneration)) =
                await projector.project(staleRequest)
        else {
            Issue.record("Expected registry currentness rejection after replay eviction")
            return
        }
        #expect(await ledger.delivered.count == callsBeforeStaleReplay)
    }

    @Test("evicted external acknowledgement cannot recreate forwarding debt")
    func evictedExternalAcknowledgementRetainsNoIdleDebt() async throws {
        let registry = WorktreeContentRepairConsumerRegistry()
        let registration = contentRepairTestRegistration()
        let projectorParticipant = contentRepairTestParticipant(.contentRepairProjector)
        var firstAcknowledgement: ContentRepairAcceptedAcknowledgement?
        for sequence in 0...256 {
            guard
                case .registered(let consumer) = await registry.register(
                    registration: registration,
                    eligibility: .eligible
                ),
                case .prepared(let capture) = await registry.prepareCapture(
                    identity: .generate(),
                    registration: registration
                )
            else {
                Issue.record("Expected registration and capture (sequence)")
                return
            }
            let acceptance = makeManualContentRepairAcceptance(
                registration: registration,
                sequence: UInt64(sequence),
                participants: capture.sourceGateParticipants.union([
                    projectorParticipant,
                    contentRepairTestParticipant(.gitWorkingDirectoryProjector),
                    contentRepairTestParticipant(.paneFilesystemProjection),
                ])
            )
            _ = await registry.bind(capture, to: acceptance.repairGeneration)
            guard
                case .withdrawnAndAcknowledged(let acknowledgement) = await registry.withdraw(
                    consumer.token,
                    disposition: .noRetainedState
                )
            else {
                Issue.record("Expected acknowledged withdrawal (sequence)")
                return
            }
            if firstAcknowledgement == nil { firstAcknowledgement = acknowledgement }
            _ = await registry.confirmSourceGateAcknowledgement(
                acknowledgement.sourceGateAcknowledgement
            )
        }
        let staleAcknowledgement = try #require(firstAcknowledgement)
        let ledger = FilesystemContentRepairTestLedger()
        let projector = FilesystemContentRepairProjector(
            consumerPort: FilesystemContentRepairConsumerDeliveryPort { _ in
                .retryRequested(.consumerUnavailable)
            },
            registryPort: FilesystemContentRepairRegistryPort(registry: registry),
            sourceGatePort: FilesystemContentRepairSourceGatePort(
                accept: { await ledger.accept($0) },
                reject: { token, _ in await ledger.reject(token) }
            )
        )

        guard
            case .registryIneligible(.staleAcknowledgement) =
                await projector.forwardRegistryAcknowledgement(staleAcknowledgement)
        else {
            Issue.record("Expected evicted acknowledgement rejection")
            return
        }
        #expect(await ledger.accepted.isEmpty)
        #expect((await projector.shutdownDebtSnapshot()).outboundAcknowledgements.isEmpty)
    }

    private func registrationRepairID(
        _ request: FilesystemContentRepairProjectionRequest
    ) -> RepairGenerationID {
        request.acceptance.repairGeneration.id
    }

    private func makeRoutingProjector(
        identity: FilesystemContentRepairProjectorIdentity,
        first: FilesystemContentRepairProjectorFixture,
        second: FilesystemContentRepairProjectorFixture
    ) -> FilesystemContentRepairProjector {
        FilesystemContentRepairProjector(
            identity: identity,
            participantGeneration: 7,
            consumerPort: FilesystemContentRepairConsumerDeliveryPort { _ in
                .retryRequested(.consumerUnavailable)
            },
            registryPort: FilesystemContentRepairRegistryPort(
                validateProjection: { generation in
                    let repairID = generation.boundGeneration.repairGeneration.id
                    return await
                        (repairID.registration == first.request.acceptance.repairGeneration.id.registration
                        ? first.registry : second.registry).validateProjectionEligibility(generation)
                },
                validateForwarding: { acknowledgement in
                    await first.registry.validateAcknowledgementForwardingEligibility(acknowledgement)
                },
                acknowledge: { _, _, _ in .shuttingDown },
                confirm: { _ in .shuttingDown }
            ),
            sourceGatePort: FilesystemContentRepairSourceGatePort(
                accept: { token in
                    let oldRegistration = first.request.acceptance.repairGeneration.id.registration
                    return await
                        (token.repairGenerationID.registration == oldRegistration
                        ? first.ledger : second.ledger).accept(token)
                },
                reject: { _, _ in .applied }
            )
        )
    }

    private func makeEligibilityRejectingProjector(
        identity: FilesystemContentRepairProjectorIdentity,
        reason: ContentRepairProjectionIneligibility,
        ledger: FilesystemContentRepairTestLedger
    ) -> FilesystemContentRepairProjector {
        FilesystemContentRepairProjector(
            identity: identity,
            participantGeneration: 7,
            consumerPort: FilesystemContentRepairConsumerDeliveryPort { request in
                await ledger.deliver(request)
            },
            registryPort: FilesystemContentRepairRegistryPort(
                validateProjection: { _ in .ineligible(reason) },
                validateForwarding: { _ in .shuttingDown },
                acknowledge: { _, _, _ in .shuttingDown },
                confirm: { _ in .shuttingDown }
            ),
            sourceGatePort: FilesystemContentRepairSourceGatePort(
                accept: { await ledger.accept($0) },
                reject: { token, _ in await ledger.reject(token) }
            )
        )
    }
}
