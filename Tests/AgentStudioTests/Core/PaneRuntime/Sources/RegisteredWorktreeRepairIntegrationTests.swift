import Testing

@testable import AgentStudio

@Suite("RegisteredWorktreeRepairIntegrationTests")
struct RegisteredWorktreeRepairIntegrationTests {
    @Test("repair stays unhealthy until every independently captured participant acknowledges")
    func repairRequiresEveryIndependentParticipantBeforeHealthy() async throws {
        // Arrange
        let fixture = try await makeRegisteredWorktreeHealthyRepairFixture()
        #expect(fixture.capturedContentParticipants == fixture.expectedContentParticipants)

        // Act
        let receipt = try requireRegisteredWorktreeProjectionReceipt(
            await fixture.projector.project(fixture.projectionRequest)
        )

        // Assert: C2 serially delivered and forwarded every captured consumer exactly once.
        #expect(await fixture.deliveryLedger.maximumActiveDeliveryCount == 1)
        #expect(await fixture.deliveryLedger.deliveredRequests == fixture.deliveryRequests)
        #expect(receipt.acknowledgedConsumers == Set(fixture.consumers.map(\.token)))
        let consumerAndProjectorParticipants = fixture.expectedContentParticipants.union([
            fixture.projectorParticipant
        ])
        let expectedForwardedAcknowledgements = Set(
            consumerAndProjectorParticipants.map {
                FilesystemRepairAcknowledgementToken(
                    repairGenerationID: fixture.acceptance.repairGeneration.id,
                    participant: $0
                )
            }
        )
        #expect(
            Set(await fixture.sourceGate.acceptedAcknowledgements)
                == expectedForwardedAcknowledgements
        )
        #expect(await fixture.sourceGate.acceptedAcknowledgements.count == 4)

        let pendingAfterContentProjection = fixture.expectedParticipants.subtracting(
            consumerAndProjectorParticipants
        )
        #expect(
            pendingAfterContentProjection
                == [fixture.gitParticipant, fixture.paneProjectionParticipant]
        )
        #expect(
            await fixture.sourceGate.stateSnapshot()
                == .awaitingAcknowledgements(
                    AwaitingFilesystemRepairAcknowledgements(
                        generation: fixture.acceptance.repairGeneration,
                        pendingParticipants: pendingAfterContentProjection
                    )
                )
        )

        let gitAcknowledgement = FilesystemRepairAcknowledgementToken(
            repairGenerationID: fixture.acceptance.repairGeneration.id,
            participant: fixture.gitParticipant
        )
        #expect(await fixture.sourceGate.acknowledge(gitAcknowledgement) == .applied)
        #expect(
            await fixture.sourceGate.stateSnapshot()
                == .awaitingAcknowledgements(
                    AwaitingFilesystemRepairAcknowledgements(
                        generation: fixture.acceptance.repairGeneration,
                        pendingParticipants: [fixture.paneProjectionParticipant]
                    )
                )
        )

        let paneAcknowledgement = FilesystemRepairAcknowledgementToken(
            repairGenerationID: fixture.acceptance.repairGeneration.id,
            participant: fixture.paneProjectionParticipant
        )
        #expect(await fixture.sourceGate.acknowledge(paneAcknowledgement) == .applied)
        #expect(await fixture.sourceGate.stateSnapshot() == .healthy(fixture.registration))

        let rebuilt = try await requireRegisteredWorktreeConsumerLookup(
            fixture.registry.lookup(fixture.consumers[0].token)
        )
        let retrying = try await requireRegisteredWorktreeConsumerLookup(
            fixture.registry.lookup(fixture.consumers[1].token)
        )
        let notApplicable = try await requireRegisteredWorktreeConsumerLookup(
            fixture.registry.lookup(fixture.consumers[2].token)
        )
        #expect(
            rebuilt.currentness
                == .current(
                    .rebuilt(
                        repairGenerationID: fixture.acceptance.repairGeneration.id,
                        consumerRevision: 41
                    )
                )
        )
        #expect(
            retrying.currentness
                == .nonCurrent(.retryRetained(fixture.deliveryRequests[1].retryToken))
        )
        #expect(
            notApplicable.currentness
                == .nonCurrent(
                    .noRetainedContent(fixture.deliveryRequests[2].invalidationGeneration)
                )
        )
    }

    @Test("consumer rejection returns the real SourceGate to dirty debt")
    func consumerRejectionRetainsDirtySourceGateDebt() async throws {
        // Arrange
        let registration = registeredWorktreeRepairRegistration()
        let registry = WorktreeContentRepairConsumerRegistry()
        let consumer = try await requireRegisteredWorktreeConsumer(
            registry.register(registration: registration, eligibility: .eligible)
        )
        let capture = try await requireRegisteredWorktreeCapture(
            registry.prepareCapture(identity: .generate(), registration: registration)
        )
        let projectorIdentity = FilesystemContentRepairProjectorIdentity.generate()
        let projectorParticipant = projectorIdentity.participant(generation: 43)
        let expectedContentParticipant = consumer.token.sourceGateParticipant
        #expect(capture.sourceGateParticipants == [expectedContentParticipant])
        let participants: Set<FilesystemRepairParticipantToken> = [
            expectedContentParticipant,
            projectorParticipant,
            registeredWorktreeRepairParticipant(.gitWorkingDirectoryProjector, generation: 47),
            registeredWorktreeRepairParticipant(.paneFilesystemProjection, generation: 53),
        ]
        let binding = contentRepairTestBinding(registration: registration)
        let sourceGate = RegisteredWorktreeSourceGateHarness(binding: binding)
        let acceptance = try await sourceGate.admitContinuityRepair(
            authority: FilesystemContinuityRepairHandoffAuthority(
                acceptingBinding: binding,
                handoffIdentity: FilesystemContinuityRepairHandoffIdentity(
                    value: UUIDv7.generate()
                ),
                desiredIdentity: FilesystemObservationDesiredIdentity(
                    value: UUIDv7.generate()
                ),
                acceptedTopologyRevision: FilesystemObservationAcceptedTopologyRevision(
                    value: 59
                )
            ),
            participants: participants
        )
        try await sourceGate.beginAndCompleteReconciliation(
            acceptance.repairGeneration.id
        )
        let activation = try await requireRegisteredWorktreeActivation(
            registry.bind(capture, to: acceptance.repairGeneration)
        )
        let deliveryRequest = activation.boundGeneration.deliveryRequests[0]
        let deliveryLedger = RegisteredWorktreeRepairDeliveryLedger(
            resultsByConsumer: [
                deliveryRequest.consumer:
                    FilesystemContentRepairConsumerDeliveryResult.rejected(
                        .currentnessApplyFailed
                    )
            ]
        )
        let projector = FilesystemContentRepairProjector(
            identity: projectorIdentity,
            participantGeneration: 43,
            consumerPort: FilesystemContentRepairConsumerDeliveryPort { request in
                await deliveryLedger.deliver(request)
            },
            registryPort: FilesystemContentRepairRegistryPort(registry: registry),
            sourceGatePort: await sourceGate.projectorPort
        )
        let projectionRequest = FilesystemContentRepairProjectionRequest(
            acceptance: .continuity(acceptance),
            activatedGeneration: activation
        )

        // Act
        let result = await projector.project(projectionRequest)

        // Assert
        guard
            case .awaitingRetry(
                .consumerRejected(
                    request: let rejectedRequest,
                    failure: .currentnessApplyFailed,
                    sourceGateResult: .applied
                )
            ) = result
        else {
            Issue.record("Expected real SourceGate rejection debt, got \(result)")
            return
        }
        #expect(rejectedRequest == deliveryRequest)
        #expect(await deliveryLedger.deliveredRequests == [deliveryRequest])
        #expect(
            await sourceGate.rejectedAcknowledgements
                == [
                    FilesystemRepairAcknowledgementToken(
                        repairGenerationID: acceptance.repairGeneration.id,
                        participant: expectedContentParticipant
                    )
                ]
        )
        #expect(await sourceGate.stateSnapshot() == .dirty(acceptance.repairGeneration))
    }

}
