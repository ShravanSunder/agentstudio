import Foundation
import Testing

@testable import AgentStudio

@Suite("Filesystem recovery evidence register")
struct FilesystemRecoveryEvidenceRegisterTests {
    @Test("new evidence advances while identical retained evidence shares its revision")
    func evidenceJoinIsMonotonicAndIdempotent() throws {
        let registration = makeRegistration(generation: 1)
        let register = try makeRegister(registrations: [registration])

        let continuity = requireRecorded(
            register.record(.continuityLoss, for: registration)
        )
        #expect(continuity.revision.stamp == .sequenced(1))
        #expect(continuity.evidence == .continuityLoss)

        let duplicate = requireRecorded(
            register.record(.continuityLoss, for: registration)
        )
        #expect(duplicate == continuity)

        let rootIdentity = requireRecorded(
            register.record(.rootIdentityRevalidation, for: registration)
        )
        #expect(rootIdentity.revision.stamp == .sequenced(2))
        #expect(rootIdentity.evidence.contains(.continuityLoss))
        #expect(rootIdentity.evidence.contains(.rootIdentityRevalidation))
    }

    @Test("the bounded reason set retains every recovery category")
    func everyRecoveryCategoryIsRetained() throws {
        let registration = makeRegistration(generation: 2)
        let register = try makeRegister(registrations: [registration])

        for evidence in [
            FilesystemRecoveryEvidence.continuityLoss,
            .rootIdentityRevalidation,
            .callbackCaptureTruncation,
            .callbackAdmissionOverflow,
            .unsupportedNativeFlags,
        ] {
            _ = requireRecorded(register.record(evidence, for: registration))
        }

        let snapshot = requireSnapshot(register.snapshot(for: registration))
        #expect(snapshot.revision.stamp == .sequenced(5))
        #expect(snapshot.evidence.contains(.continuityLoss))
        #expect(snapshot.evidence.contains(.rootIdentityRevalidation))
        #expect(snapshot.evidence.contains(.callbackCaptureTruncation))
        #expect(snapshot.evidence.contains(.callbackAdmissionOverflow))
        #expect(snapshot.evidence.contains(.unsupportedNativeFlags))
    }

    @Test("unknown registrations are rejected without changing declared slots")
    func unknownRegistrationDoesNotMutateRegister() throws {
        let declared = makeRegistration(generation: 3)
        let unknown = makeRegistration(generation: 4)
        let register = try makeRegister(registrations: [declared])

        #expect(register.record(.continuityLoss, for: unknown) == .unknownRegistration)
        #expect(register.snapshot(for: unknown) == .unknownRegistration)
        #expect(register.snapshot(for: declared) == .noEvidence(.sequenced(0)))
    }

    @Test("an old acknowledgement cannot clear newer joined evidence")
    func oldAcknowledgementRetainsNewerEvidence() throws {
        let registration = makeRegistration(generation: 5)
        let register = try makeRegister(registrations: [registration])
        let oldSnapshot = requireRecorded(
            register.record(.continuityLoss, for: registration)
        )
        let newestSnapshot = requireRecorded(
            register.record(.callbackCaptureTruncation, for: registration)
        )

        #expect(
            register.acknowledge(oldSnapshot)
                == .newerEvidenceRetained(newestSnapshot)
        )
        #expect(register.snapshot(for: registration) == .evidence(newestSnapshot))
        #expect(register.acknowledge(newestSnapshot) == .cleared(newestSnapshot.revision))
        #expect(register.snapshot(for: registration) == .noEvidence(.sequenced(2)))
        #expect(register.acknowledge(newestSnapshot) == .alreadyCleared(.sequenced(2)))
    }

    @Test("authority exhaustion preserves exact snapshot acknowledgement safety")
    func authorityExhaustionCannotCollapseNewEvidence() throws {
        let registration = makeRegistration(generation: 6)
        let register = try makeRegister(
            registrations: [registration],
            seed: FilesystemRecoveryEvidenceAuthoritySeed(
                stampsByRegistration: [registration: .sequenced(.max)]
            )
        )
        let exhaustedSnapshot = requireRecorded(
            register.record(.continuityLoss, for: registration)
        )
        #expect(exhaustedSnapshot.revision.stamp == .authorityExhausted)

        let joinedAtExhaustion = requireRecorded(
            register.record(.unsupportedNativeFlags, for: registration)
        )
        #expect(joinedAtExhaustion.revision.stamp == .authorityExhausted)
        #expect(joinedAtExhaustion.evidence.contains(.continuityLoss))
        #expect(joinedAtExhaustion.evidence.contains(.unsupportedNativeFlags))
        #expect(
            register.acknowledge(exhaustedSnapshot)
                == .newerEvidenceRetained(joinedAtExhaustion)
        )
    }

    @Test("authority exhaustion distinguishes reincarnated identical custody")
    func authorityExhaustionRetainsReincarnatedIdenticalEvidence() throws {
        let registration = makeRegistration(generation: 7)
        let register = try makeRegister(
            registrations: [registration],
            seed: FilesystemRecoveryEvidenceAuthoritySeed(
                stampsByRegistration: [registration: .sequenced(.max)]
            )
        )
        let oldSnapshot = requireRecorded(
            register.record(.continuityLoss, for: registration)
        )
        #expect(oldSnapshot.revision.stamp == .authorityExhausted)
        #expect(register.acknowledge(oldSnapshot) == .cleared(oldSnapshot.revision))

        let reincarnatedSnapshot = requireRecorded(
            register.record(.continuityLoss, for: registration)
        )
        #expect(reincarnatedSnapshot.revision == oldSnapshot.revision)
        #expect(reincarnatedSnapshot.evidence == oldSnapshot.evidence)
        #expect(reincarnatedSnapshot != oldSnapshot)
        #expect(
            register.acknowledge(oldSnapshot)
                == .newerEvidenceRetained(reincarnatedSnapshot)
        )
        #expect(register.snapshot(for: registration) == .evidence(reincarnatedSnapshot))
    }

    @Test("registration generations have independent fixed slots")
    func generationsDoNotShareEvidence() throws {
        let older = makeRegistration(generation: 7)
        let newer = makeRegistration(generation: 8)
        let register = try makeRegister(registrations: [older, newer])

        let olderSnapshot = requireRecorded(
            register.record(.continuityLoss, for: older)
        )
        let newerSnapshot = requireRecorded(
            register.record(.rootIdentityRevalidation, for: newer)
        )

        #expect(olderSnapshot.revision.registration == older)
        #expect(newerSnapshot.revision.registration == newer)
        #expect(olderSnapshot.evidence == .continuityLoss)
        #expect(newerSnapshot.evidence == .rootIdentityRevalidation)
    }

    @Test("declared registration capacity and authority seed are validated")
    func configurationRejectsUnboundedOrAmbiguousSlots() throws {
        let first = makeRegistration(generation: 9)
        let second = makeRegistration(generation: 10)

        #expect(
            throws:
                FilesystemRecoveryRegisterConfigurationError
                .declaredRegistrationCapacityExceeded(maximum: 1, actual: 2)
        ) {
            try FilesystemRecoveryEvidenceRegister(
                maximumDeclaredRegistrations: 1,
                declaredRegistrations: [first, second]
            )
        }
        #expect(
            throws:
                FilesystemRecoveryRegisterConfigurationError
                .duplicateDeclaredRegistration(first)
        ) {
            try FilesystemRecoveryEvidenceRegister(
                maximumDeclaredRegistrations: 2,
                declaredRegistrations: [first, first]
            )
        }
        #expect(
            throws:
                FilesystemRecoveryRegisterConfigurationError
                .authoritySeedContainsUndeclaredRegistration(second)
        ) {
            try FilesystemRecoveryEvidenceRegister(
                maximumDeclaredRegistrations: 1,
                declaredRegistrations: [first],
                authoritySeed: FilesystemRecoveryEvidenceAuthoritySeed(
                    stampsByRegistration: [second: .sequenced(4)]
                )
            )
        }
    }

    @Test("registration capacity accepts empty declarations but rejects a zero maximum")
    func registrationCapacityRequiresOnlyAPositiveMaximum() throws {
        #expect(
            throws:
                FilesystemRecoveryRegisterConfigurationError
                .nonPositiveMaximumDeclaredRegistrations(0)
        ) {
            try FilesystemRecoveryEvidenceRegister(
                maximumDeclaredRegistrations: 0,
                declaredRegistrations: []
            )
        }

        let emptyRegister = try FilesystemRecoveryEvidenceRegister(
            maximumDeclaredRegistrations: 1,
            declaredRegistrations: []
        )
        #expect(
            emptyRegister.snapshot(for: makeRegistration(generation: 11))
                == .unknownRegistration
        )
    }

    private func makeRegister(
        registrations: [FSEventRegistrationToken],
        seed: FilesystemRecoveryEvidenceAuthoritySeed = .init()
    ) throws -> FilesystemRecoveryEvidenceRegister {
        try FilesystemRecoveryEvidenceRegister(
            maximumDeclaredRegistrations: registrations.count,
            declaredRegistrations: registrations,
            authoritySeed: seed
        )
    }

    private func requireRecorded(
        _ result: FilesystemRecoveryEvidenceRecordResult,
        sourceLocation: SourceLocation = #_sourceLocation
    ) -> FilesystemRecoveryEvidenceSnapshot {
        guard case .recorded(let snapshot) = result else {
            Issue.record("Expected recorded evidence, got \(result)", sourceLocation: sourceLocation)
            preconditionFailure("Expected recorded recovery evidence")
        }
        return snapshot
    }

    private func requireSnapshot(
        _ result: FilesystemRecoveryEvidenceSnapshotResult,
        sourceLocation: SourceLocation = #_sourceLocation
    ) -> FilesystemRecoveryEvidenceSnapshot {
        guard case .evidence(let snapshot) = result else {
            Issue.record("Expected retained evidence, got \(result)", sourceLocation: sourceLocation)
            preconditionFailure("Expected retained recovery evidence")
        }
        return snapshot
    }

    private func makeRegistration(generation: UInt64) -> FSEventRegistrationToken {
        FSEventRegistrationToken(
            sourceID: FilesystemSourceID(
                kind: .registeredWorktreeContent,
                rootID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
            ),
            registrationGeneration: generation,
            rootGeneration: 11
        )
    }
}
