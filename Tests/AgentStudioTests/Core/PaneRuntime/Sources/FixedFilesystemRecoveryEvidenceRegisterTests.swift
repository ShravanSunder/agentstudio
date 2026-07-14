import Foundation
import Testing

@testable import AgentStudio

@Suite("Fixed filesystem recovery evidence register")
struct FixedFilesystemRecoveryEvidenceRegisterTests {
    @Test("initialization creates exactly one vacant shell per physical slot")
    func initializationCreatesFixedVacantShells() throws {
        let registry = try makeRegistry(sourceCount: 2, reserveCount: 1)
        let register = FixedFilesystemRecoveryEvidenceRegister(slotRegistry: registry)

        #expect(register.physicalSlotCount == 3)
        for physicalSlotID in registry.physicalSlotIDs {
            #expect(register.state(of: physicalSlotID) == .vacant)
        }
    }

    @Test("exact binding is idempotent and a different binding cannot replace it")
    func bindingRequiresExactCurrentIdentity() throws {
        let fixture = try makeFixture()
        let conflictingBinding = makeSyntheticBinding(
            fleetMailboxIdentity: fixture.registry.fleetMailboxIdentity,
            physicalSlotID: fixture.binding.physicalSlotID,
            registration: makeRegistration(generation: 101)
        )

        #expect(fixture.register.bind(fixture.binding) == .boundClear(fixture.binding))
        #expect(fixture.register.bind(fixture.binding) == .alreadyBoundClear(fixture.binding))
        #expect(
            fixture.register.bind(conflictingBinding)
                == .currentBindingMismatch(fixture.binding)
        )
        #expect(
            fixture.register.state(of: fixture.binding.physicalSlotID)
                == .boundClear(fixture.binding)
        )
    }

    @Test("record mints UUIDv7 custody and duplicate input preserves exact snapshot")
    func firstAndDuplicateRecordPreserveCustody() throws {
        // Arrange
        let fixture = try makeBoundFixture()
        let recoveryRevision = makeRecoveryRevision(
            for: fixture.binding.physicalSlotID
        )

        // Act
        let first = try requireRecorded(
            fixture.register.record(
                .continuityLoss,
                genericRecoveryRevision: recoveryRevision,
                for: fixture.binding
            )
        )
        let duplicate = try requireRecorded(
            fixture.register.record(
                .continuityLoss,
                genericRecoveryRevision: recoveryRevision,
                for: fixture.binding
            )
        )

        // Assert
        #expect(first.revision.binding == fixture.binding)
        #expect(first.revision.genericRecoveryRevision == recoveryRevision)
        #expect(first.revision.recoveryCustodyIdentity.isUUIDv7)
        #expect(first.evidence == .continuityLoss)
        #expect(duplicate == first)
    }

    @Test("joined evidence retains custody while updating evidence and generic metadata")
    func joinedEvidenceRetainsCustody() throws {
        // Arrange
        let fixture = try makeBoundFixture()
        let recoveryRevisionSource = makeRecoveryRevisionSource(
            for: fixture.binding.physicalSlotID
        )
        let firstRecoveryRevision = recoveryRevisionSource.nextRevision()
        let first = try requireRecorded(
            fixture.register.record(
                .continuityLoss,
                genericRecoveryRevision: firstRecoveryRevision,
                for: fixture.binding
            )
        )
        let joinedRecoveryRevision = recoveryRevisionSource.nextRevision()

        // Act
        let joined = try requireRecorded(
            fixture.register.record(
                .callbackCaptureTruncation,
                genericRecoveryRevision: joinedRecoveryRevision,
                for: fixture.binding
            )
        )

        // Assert
        #expect(joined.revision.binding == first.revision.binding)
        #expect(
            joined.revision.recoveryCustodyIdentity
                == first.revision.recoveryCustodyIdentity
        )
        #expect(joined.revision.genericRecoveryRevision == joinedRecoveryRevision)
        #expect(joined.revision.genericRecoveryRevision != firstRecoveryRevision)
        #expect(joined.evidence.contains(.continuityLoss))
        #expect(joined.evidence.contains(.callbackCaptureTruncation))
        #expect(fixture.register.snapshot(for: fixture.binding) == .retained(joined))
    }

    @Test("only the exact newest snapshot can clear retained evidence")
    func acknowledgementRequiresExactSnapshot() throws {
        // Arrange
        let fixture = try makeBoundFixture()
        let recoveryRevisionSource = makeRecoveryRevisionSource(
            for: fixture.binding.physicalSlotID
        )
        let older = try requireRecorded(
            fixture.register.record(
                .continuityLoss,
                genericRecoveryRevision: recoveryRevisionSource.nextRevision(),
                for: fixture.binding
            )
        )
        let newer = try requireRecorded(
            fixture.register.record(
                .rootIdentityRevalidation,
                genericRecoveryRevision: recoveryRevisionSource.nextRevision(),
                for: fixture.binding
            )
        )

        // Act
        let staleAcknowledgement = fixture.register.acknowledge(older)
        let currentAcknowledgement = fixture.register.acknowledge(newer)

        // Assert
        #expect(
            staleAcknowledgement == .newerEvidenceRetained(newer)
        )
        #expect(currentAcknowledgement == .cleared(newer.revision))
        #expect(fixture.register.snapshot(for: fixture.binding) == .clear(fixture.binding))
        #expect(fixture.register.acknowledge(newer) == .alreadyClear(fixture.binding))
    }

    @Test("reincarnated identical evidence and revision receive distinct custody")
    func reincarnatedEvidenceRejectsOldAcknowledgement() throws {
        // Arrange
        let fixture = try makeBoundFixture()
        let recoveryRevision = makeRecoveryRevision(
            for: fixture.binding.physicalSlotID
        )
        let oldSnapshot = try requireRecorded(
            fixture.register.record(
                .continuityLoss,
                genericRecoveryRevision: recoveryRevision,
                for: fixture.binding
            )
        )
        #expect(
            fixture.register.acknowledge(oldSnapshot)
                == .cleared(oldSnapshot.revision)
        )

        // Act
        let reincarnatedSnapshot = try requireRecorded(
            fixture.register.record(
                .continuityLoss,
                genericRecoveryRevision: recoveryRevision,
                for: fixture.binding
            )
        )

        // Assert
        #expect(reincarnatedSnapshot.revision.binding == oldSnapshot.revision.binding)
        #expect(
            reincarnatedSnapshot.revision.genericRecoveryRevision
                == oldSnapshot.revision.genericRecoveryRevision
        )
        #expect(
            reincarnatedSnapshot.revision.recoveryCustodyIdentity
                != oldSnapshot.revision.recoveryCustodyIdentity
        )
        #expect(
            fixture.register.acknowledge(oldSnapshot)
                == .newerEvidenceRetained(reincarnatedSnapshot)
        )
    }

    @Test("retirement requires exact clear binding and never drops recovery debt")
    func retirementRequiresClearExactBinding() throws {
        // Arrange
        let fixture = try makeBoundFixture()
        let retained = try requireRecorded(
            fixture.register.record(
                .unsupportedNativeFlags,
                genericRecoveryRevision: makeRecoveryRevision(
                    for: fixture.binding.physicalSlotID
                ),
                for: fixture.binding
            )
        )

        // Act
        let retainedRetirement = fixture.register.retire(fixture.binding)
        let acknowledgement = fixture.register.acknowledge(retained)
        let clearedRetirement = fixture.register.retire(fixture.binding)
        let retiredSnapshot = fixture.register.snapshot(for: fixture.binding)
        let repeatedRetirement = fixture.register.retire(fixture.binding)

        // Assert
        #expect(retainedRetirement == .recoveryEvidenceRetained(retained))
        #expect(acknowledgement == .cleared(retained.revision))
        #expect(clearedRetirement == .retired(fixture.binding))
        #expect(retiredSnapshot == .unboundPhysicalSlot)
        #expect(repeatedRetirement == .alreadyVacant)
        #expect(fixture.register.physicalSlotCount == fixture.registry.physicalSlotCount)
    }

    @Test("foreign undeclared unbound and current-binding mismatches are typed no-ops")
    func invalidBindingOperationsAreTypedNoOps() throws {
        // Arrange
        let fixture = try makeBoundFixture()
        let foreignFixture = try makeFixture()
        let undeclaredBinding = makeSyntheticBinding(
            fleetMailboxIdentity: fixture.registry.fleetMailboxIdentity,
            physicalSlotID: foreignFixture.binding.physicalSlotID,
            registration: fixture.binding.registration
        )
        let conflictingBinding = makeSyntheticBinding(
            fleetMailboxIdentity: fixture.registry.fleetMailboxIdentity,
            physicalSlotID: fixture.binding.physicalSlotID,
            registration: makeRegistration(generation: 202)
        )
        let vacantBinding = try makeBinding(
            in: fixture.registry,
            sourceOrdinal: 2,
            generation: 2
        )
        let foreignRecoveryRevision = makeRecoveryRevision(
            for: foreignFixture.binding.physicalSlotID
        )
        let conflictingRecoveryRevision = makeRecoveryRevision(
            for: conflictingBinding.physicalSlotID
        )

        // Act
        let foreignBind = fixture.register.bind(foreignFixture.binding)
        let foreignRecord = fixture.register.record(
            .continuityLoss,
            genericRecoveryRevision: foreignRecoveryRevision,
            for: foreignFixture.binding
        )
        let foreignSnapshot = fixture.register.snapshot(for: foreignFixture.binding)
        let foreignRetirement = fixture.register.retire(foreignFixture.binding)
        let undeclaredBind = fixture.register.bind(undeclaredBinding)
        let undeclaredSnapshot = fixture.register.snapshot(for: undeclaredBinding)
        let vacantSnapshot = fixture.register.snapshot(for: vacantBinding)
        let conflictingRecord = fixture.register.record(
            .continuityLoss,
            genericRecoveryRevision: conflictingRecoveryRevision,
            for: conflictingBinding
        )
        let conflictingSnapshot = fixture.register.snapshot(for: conflictingBinding)
        let conflictingRetirement = fixture.register.retire(conflictingBinding)
        let retainedState = fixture.register.state(of: fixture.binding.physicalSlotID)

        // Assert
        #expect(foreignBind == .foreignFleet)
        #expect(foreignRecord == .foreignFleet)
        #expect(foreignSnapshot == .foreignFleet)
        #expect(foreignRetirement == .foreignFleet)
        #expect(undeclaredBind == .undeclaredPhysicalSlot)
        #expect(undeclaredSnapshot == .undeclaredPhysicalSlot)
        #expect(vacantSnapshot == .unboundPhysicalSlot)
        #expect(
            conflictingRecord == .currentBindingMismatch(fixture.binding)
        )
        #expect(
            conflictingSnapshot == .currentBindingMismatch(fixture.binding)
        )
        #expect(conflictingRetirement == .currentBindingMismatch(fixture.binding))
        #expect(retainedState == .boundClear(fixture.binding))
    }

    @Test("equal opaque revisions on distinct bindings remain isolated")
    func equalOpaqueRevisionsDoNotAuthorizeAcrossBindings() throws {
        // Arrange
        let registry = try makeRegistry(sourceCount: 1, reserveCount: 0)
        let firstBinding = try makeBinding(in: registry, sourceOrdinal: 1, generation: 1)
        let secondBinding = makeSyntheticBinding(
            fleetMailboxIdentity: registry.fleetMailboxIdentity,
            physicalSlotID: firstBinding.physicalSlotID,
            registration: makeRegistration(generation: 2)
        )
        let firstRegister = FixedFilesystemRecoveryEvidenceRegister(slotRegistry: registry)
        let secondRegister = FixedFilesystemRecoveryEvidenceRegister(slotRegistry: registry)
        #expect(firstRegister.bind(firstBinding) == .boundClear(firstBinding))
        #expect(secondRegister.bind(secondBinding) == .boundClear(secondBinding))
        let firstRecoveryRevision = makeRecoveryRevision(
            for: firstBinding.physicalSlotID
        )
        let secondRecoveryRevision = makeRecoveryRevision(
            for: secondBinding.physicalSlotID
        )
        #expect(firstRecoveryRevision == secondRecoveryRevision)

        // Act
        let firstSnapshot = try requireRecorded(
            firstRegister.record(
                .continuityLoss,
                genericRecoveryRevision: firstRecoveryRevision,
                for: firstBinding
            )
        )
        let secondSnapshot = try requireRecorded(
            secondRegister.record(
                .rootIdentityRevalidation,
                genericRecoveryRevision: secondRecoveryRevision,
                for: secondBinding
            )
        )
        let foreignAcknowledgement = secondRegister.acknowledge(firstSnapshot)

        // Assert
        #expect(
            firstSnapshot.revision.genericRecoveryRevision
                == secondSnapshot.revision.genericRecoveryRevision
        )
        #expect(firstSnapshot.revision.binding != secondSnapshot.revision.binding)
        #expect(
            firstSnapshot.revision.recoveryCustodyIdentity
                != secondSnapshot.revision.recoveryCustodyIdentity
        )
        #expect(foreignAcknowledgement == .currentBindingMismatch(secondBinding))
        #expect(secondRegister.snapshot(for: secondBinding) == .retained(secondSnapshot))
    }

    @Test("clear prior continuity authority projects only for its exact binding")
    func clearPriorContinuityAuthorityRequiresExactBinding() throws {
        // Arrange
        let fixture = try makeBoundFixture()
        let conflictingBinding = makeSyntheticBinding(
            fleetMailboxIdentity: fixture.registry.fleetMailboxIdentity,
            physicalSlotID: fixture.binding.physicalSlotID,
            registration: makeRegistration(generation: 303)
        )

        // Act
        let authority = try requireIssuedPriorContinuityAuthority(
            fixture.register.issuePriorContinuityAuthority(for: fixture.binding)
        )
        let exactProjection = authority.project(against: fixture.binding)
        let mismatchedProjection = authority.project(against: conflictingBinding)

        // Assert
        #expect(exactProjection == .exactContinuous)
        #expect(mismatchedProjection == .bindingMismatch)
    }

    @Test("retained prior continuity authority projects the exact retained snapshot")
    func retainedPriorContinuityAuthorityProjectsExactSnapshot() throws {
        // Arrange
        let fixture = try makeBoundFixture()
        let retainedSnapshot = try requireRecorded(
            fixture.register.record(
                .continuityLoss,
                genericRecoveryRevision: makeRecoveryRevision(
                    for: fixture.binding.physicalSlotID
                ),
                for: fixture.binding
            )
        )

        // Act
        let authority = try requireIssuedPriorContinuityAuthority(
            fixture.register.issuePriorContinuityAuthority(for: fixture.binding)
        )
        let projection = authority.project(against: fixture.binding)

        // Assert
        #expect(projection == .exactDiscontinuous(retainedSnapshot))
    }

    @Test("prior continuity authority issuance rejects every non-exact slot state")
    func priorContinuityAuthorityIssuanceRejectsNonExactSlotState() throws {
        // Arrange
        let fixture = try makeBoundFixture()
        let foreignFixture = try makeFixture()
        let undeclaredBinding = makeSyntheticBinding(
            fleetMailboxIdentity: fixture.registry.fleetMailboxIdentity,
            physicalSlotID: foreignFixture.binding.physicalSlotID,
            registration: fixture.binding.registration
        )
        let vacantBinding = try makeBinding(
            in: fixture.registry,
            sourceOrdinal: 2,
            generation: 2
        )
        let conflictingBinding = makeSyntheticBinding(
            fleetMailboxIdentity: fixture.registry.fleetMailboxIdentity,
            physicalSlotID: fixture.binding.physicalSlotID,
            registration: makeRegistration(generation: 404)
        )

        // Act
        let foreignResult = fixture.register.issuePriorContinuityAuthority(
            for: foreignFixture.binding
        )
        let undeclaredResult = fixture.register.issuePriorContinuityAuthority(
            for: undeclaredBinding
        )
        let vacantResult = fixture.register.issuePriorContinuityAuthority(for: vacantBinding)
        let mismatchResult = fixture.register.issuePriorContinuityAuthority(
            for: conflictingBinding
        )

        // Assert
        guard case .foreignFleet = foreignResult else {
            Issue.record("Expected foreign-fleet prior continuity rejection")
            return
        }
        guard case .undeclaredPhysicalSlot = undeclaredResult else {
            Issue.record("Expected undeclared-slot prior continuity rejection")
            return
        }
        guard case .unboundPhysicalSlot = vacantResult else {
            Issue.record("Expected vacant-slot prior continuity rejection")
            return
        }
        guard case .currentBindingMismatch(let currentBinding) = mismatchResult else {
            Issue.record("Expected current-binding prior continuity rejection")
            return
        }
        #expect(currentBinding == fixture.binding)
    }

    private func makeFixture() throws -> RecoveryFixture {
        let registry = try makeRegistry(sourceCount: 2, reserveCount: 0)
        let binding = try makeBinding(in: registry, sourceOrdinal: 1, generation: 1)
        return RecoveryFixture(
            registry: registry,
            register: FixedFilesystemRecoveryEvidenceRegister(slotRegistry: registry),
            binding: binding
        )
    }

    private func makeBoundFixture() throws -> RecoveryFixture {
        let fixture = try makeFixture()
        #expect(fixture.register.bind(fixture.binding) == .boundClear(fixture.binding))
        return fixture
    }

    private func makeRegistry(
        sourceCount: Int,
        reserveCount: Int
    ) throws -> FilesystemObservationSlotRegistry {
        try FilesystemObservationSlotRegistry(
            maximumSimultaneousSourceCount: sourceCount,
            replacementReserveSlotCount: reserveCount
        )
    }

    private func makeBinding(
        in registry: FilesystemObservationSlotRegistry,
        sourceOrdinal: Int,
        generation: UInt64
    ) throws -> FilesystemObservationSlotBinding {
        _ = registry.installTestConfiguration(
            makeRegistration(sourceOrdinal: sourceOrdinal, generation: generation)
        )
        let selection = try requireSelectedDesiredSource(registry.selectNextDesiredSource())
        return try requireCommittedNativeLifetime(
            registry.beginNativeLifetime(selection.reservation)
        ).binding
    }

    private func makeSyntheticBinding(
        fleetMailboxIdentity: FilesystemObservationFleetMailboxIdentity,
        physicalSlotID: FilesystemObservationPhysicalSlotID,
        registration: FSEventRegistrationToken
    ) -> FilesystemObservationSlotBinding {
        FilesystemObservationSlotBinding(
            fleetMailboxIdentity: fleetMailboxIdentity,
            physicalSlotID: physicalSlotID,
            identity: FilesystemObservationSlotBindingIdentity(value: UUIDv7.generate()),
            registration: registration,
            controlBlockIdentity: FilesystemObservationControlBlockIdentity(
                value: UUIDv7.generate()
            )
        )
    }

    private func requireRecorded(
        _ result: FixedFilesystemRecoveryEvidenceRecordResult,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws -> FixedFilesystemRecoveryEvidenceSnapshot {
        guard case .recorded(let snapshot) = result else {
            Issue.record("Expected recorded fixed recovery evidence", sourceLocation: sourceLocation)
            throw FixedFilesystemRecoveryEvidenceRegisterTestError.expectedRecordedEvidence
        }
        return snapshot
    }

    private func requireIssuedPriorContinuityAuthority(
        _ result: FixedFilesystemRecoveryEvidenceRegister.PriorContinuityAuthorityIssueResult,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws -> FixedFilesystemRecoveryEvidenceRegister.PriorContinuityAuthority {
        guard case .issued(let authority) = result else {
            Issue.record("Expected issued prior continuity authority", sourceLocation: sourceLocation)
            throw FixedFilesystemRecoveryEvidenceRegisterTestError
                .expectedPriorContinuityAuthority
        }
        return authority
    }

    private func makeRecoveryRevision(
        for physicalSlotID: FilesystemObservationPhysicalSlotID
    ) -> GatherRecoveryRevision<FilesystemObservationPhysicalSlotID> {
        makeRecoveryRevisionSource(for: physicalSlotID).nextRevision()
    }

    private func makeRecoveryRevisionSource(
        for physicalSlotID: FilesystemObservationPhysicalSlotID
    ) -> RecoveryRevisionSource {
        RecoveryRevisionSource(
            generation: AdmissionGeneration(owner: .filesystemObservation, value: 1),
            physicalSlotID: physicalSlotID
        )
    }
}

private final class RecoveryRevisionSource {
    private let generation: AdmissionGeneration
    private let physicalSlotID: FilesystemObservationPhysicalSlotID
    private let mailbox:
        BoundedGatherMailbox<
            FilesystemObservationPhysicalSlotID,
            GatherTestPayload
        >

    init(
        generation: AdmissionGeneration,
        physicalSlotID: FilesystemObservationPhysicalSlotID
    ) {
        self.generation = generation
        self.physicalSlotID = physicalSlotID
        mailbox = BoundedGatherMailbox(
            generation: generation,
            declaredKeys: [physicalSlotID],
            limits: hashProbeLimits(maximumDeclaredKeys: 1, maximumContributions: 8)
        )
    }

    func nextRevision() -> GatherRecoveryRevision<FilesystemObservationPhysicalSlotID> {
        let offer = mailbox.producerPort.offer(
            generation: generation,
            contribution: GatherContribution(
                key: physicalSlotID,
                payload: GatherTestPayload(label: "fixed-recovery-register"),
                footprint: GatherFootprint(itemCount: 1, byteCount: 1),
                recoverySignal: .authoritativeRecoveryRequired
            )
        )
        return requireRecoveryRevision(requireGenericAdmission(offer))
    }
}

private struct RecoveryFixture {
    let registry: FilesystemObservationSlotRegistry
    let register: FixedFilesystemRecoveryEvidenceRegister
    let binding: FilesystemObservationSlotBinding
}

private enum FixedFilesystemRecoveryEvidenceRegisterTestError: Error {
    case expectedRecordedEvidence
    case expectedPriorContinuityAuthority
}
