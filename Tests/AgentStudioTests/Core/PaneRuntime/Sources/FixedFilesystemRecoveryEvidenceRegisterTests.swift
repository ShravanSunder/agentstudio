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
        let fixture = try makeBoundFixture()

        let first = try requireRecorded(
            fixture.register.record(
                .continuityLoss,
                genericRecoveryStamp: .sequenced(7),
                for: fixture.binding
            )
        )
        let duplicate = try requireRecorded(
            fixture.register.record(
                .continuityLoss,
                genericRecoveryStamp: .sequenced(7),
                for: fixture.binding
            )
        )

        #expect(first.revision.binding == fixture.binding)
        #expect(first.revision.genericRecoveryStamp == .sequenced(7))
        #expect(first.revision.recoveryCustodyIdentity.isUUIDv7)
        #expect(first.evidence == .continuityLoss)
        #expect(duplicate == first)
    }

    @Test("joined evidence retains custody while updating evidence and generic metadata")
    func joinedEvidenceRetainsCustody() throws {
        let fixture = try makeBoundFixture()
        let first = try requireRecorded(
            fixture.register.record(
                .continuityLoss,
                genericRecoveryStamp: .sequenced(1),
                for: fixture.binding
            )
        )

        let joined = try requireRecorded(
            fixture.register.record(
                .callbackCaptureTruncation,
                genericRecoveryStamp: .sequenced(2),
                for: fixture.binding
            )
        )

        #expect(joined.revision.binding == first.revision.binding)
        #expect(
            joined.revision.recoveryCustodyIdentity
                == first.revision.recoveryCustodyIdentity
        )
        #expect(joined.revision.genericRecoveryStamp == .sequenced(2))
        #expect(joined.evidence.contains(.continuityLoss))
        #expect(joined.evidence.contains(.callbackCaptureTruncation))
        #expect(fixture.register.snapshot(for: fixture.binding) == .retained(joined))
    }

    @Test("only the exact newest snapshot can clear retained evidence")
    func acknowledgementRequiresExactSnapshot() throws {
        let fixture = try makeBoundFixture()
        let older = try requireRecorded(
            fixture.register.record(
                .continuityLoss,
                genericRecoveryStamp: .sequenced(1),
                for: fixture.binding
            )
        )
        let newer = try requireRecorded(
            fixture.register.record(
                .rootIdentityRevalidation,
                genericRecoveryStamp: .sequenced(2),
                for: fixture.binding
            )
        )

        #expect(
            fixture.register.acknowledge(older)
                == .newerEvidenceRetained(newer)
        )
        #expect(fixture.register.acknowledge(newer) == .cleared(newer.revision))
        #expect(fixture.register.snapshot(for: fixture.binding) == .clear(fixture.binding))
        #expect(fixture.register.acknowledge(newer) == .alreadyClear(fixture.binding))
    }

    @Test("reincarnated identical evidence and stamp receive distinct custody")
    func reincarnatedEvidenceRejectsOldAcknowledgement() throws {
        let fixture = try makeBoundFixture()
        let oldSnapshot = try requireRecorded(
            fixture.register.record(
                .continuityLoss,
                genericRecoveryStamp: .authorityExhausted,
                for: fixture.binding
            )
        )
        #expect(
            fixture.register.acknowledge(oldSnapshot)
                == .cleared(oldSnapshot.revision)
        )

        let reincarnatedSnapshot = try requireRecorded(
            fixture.register.record(
                .continuityLoss,
                genericRecoveryStamp: .authorityExhausted,
                for: fixture.binding
            )
        )

        #expect(reincarnatedSnapshot.revision.binding == oldSnapshot.revision.binding)
        #expect(
            reincarnatedSnapshot.revision.genericRecoveryStamp
                == oldSnapshot.revision.genericRecoveryStamp
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
        let fixture = try makeBoundFixture()
        let retained = try requireRecorded(
            fixture.register.record(
                .unsupportedNativeFlags,
                genericRecoveryStamp: .sequenced(1),
                for: fixture.binding
            )
        )

        #expect(
            fixture.register.retire(fixture.binding)
                == .recoveryEvidenceRetained(retained)
        )
        #expect(fixture.register.acknowledge(retained) == .cleared(retained.revision))
        #expect(fixture.register.retire(fixture.binding) == .retired(fixture.binding))
        #expect(fixture.register.snapshot(for: fixture.binding) == .unboundPhysicalSlot)
        #expect(fixture.register.retire(fixture.binding) == .alreadyVacant)
        #expect(fixture.register.physicalSlotCount == fixture.registry.physicalSlotCount)
    }

    @Test("foreign undeclared unbound and current-binding mismatches are typed no-ops")
    func invalidBindingOperationsAreTypedNoOps() throws {
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

        #expect(fixture.register.bind(foreignFixture.binding) == .foreignFleet)
        #expect(
            fixture.register.record(
                .continuityLoss,
                genericRecoveryStamp: .sequenced(1),
                for: foreignFixture.binding
            ) == .foreignFleet
        )
        #expect(fixture.register.snapshot(for: foreignFixture.binding) == .foreignFleet)
        #expect(fixture.register.retire(foreignFixture.binding) == .foreignFleet)

        #expect(fixture.register.bind(undeclaredBinding) == .undeclaredPhysicalSlot)
        #expect(fixture.register.snapshot(for: undeclaredBinding) == .undeclaredPhysicalSlot)
        #expect(fixture.register.snapshot(for: vacantBinding) == .unboundPhysicalSlot)

        #expect(
            fixture.register.record(
                .continuityLoss,
                genericRecoveryStamp: .sequenced(1),
                for: conflictingBinding
            ) == .currentBindingMismatch(fixture.binding)
        )
        #expect(
            fixture.register.snapshot(for: conflictingBinding)
                == .currentBindingMismatch(fixture.binding)
        )
        #expect(
            fixture.register.retire(conflictingBinding)
                == .currentBindingMismatch(fixture.binding)
        )
        #expect(
            fixture.register.state(of: fixture.binding.physicalSlotID)
                == .boundClear(fixture.binding)
        )
    }

    @Test("equal generic stamps on distinct bindings remain isolated")
    func equalGenericStampsDoNotAuthorizeAcrossBindings() throws {
        let registry = try makeRegistry(sourceCount: 2, reserveCount: 0)
        let firstBinding = try makeBinding(in: registry, sourceOrdinal: 1, generation: 1)
        let secondBinding = try makeBinding(in: registry, sourceOrdinal: 2, generation: 1)
        let register = FixedFilesystemRecoveryEvidenceRegister(slotRegistry: registry)
        #expect(register.bind(firstBinding) == .boundClear(firstBinding))
        #expect(register.bind(secondBinding) == .boundClear(secondBinding))
        let firstSnapshot = try requireRecorded(
            register.record(
                .continuityLoss,
                genericRecoveryStamp: .authorityExhausted,
                for: firstBinding
            )
        )
        let secondSnapshot = try requireRecorded(
            register.record(
                .rootIdentityRevalidation,
                genericRecoveryStamp: .authorityExhausted,
                for: secondBinding
            )
        )

        #expect(firstSnapshot.revision.genericRecoveryStamp == secondSnapshot.revision.genericRecoveryStamp)
        #expect(firstSnapshot.revision.binding != secondSnapshot.revision.binding)
        #expect(register.acknowledge(firstSnapshot) == .cleared(firstSnapshot.revision))
        #expect(register.snapshot(for: secondBinding) == .retained(secondSnapshot))
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
        _ = registry.recordDesiredRegistration(
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
}

private struct RecoveryFixture {
    let registry: FilesystemObservationSlotRegistry
    let register: FixedFilesystemRecoveryEvidenceRegister
    let binding: FilesystemObservationSlotBinding
}

private enum FixedFilesystemRecoveryEvidenceRegisterTestError: Error {
    case expectedRecordedEvidence
}
