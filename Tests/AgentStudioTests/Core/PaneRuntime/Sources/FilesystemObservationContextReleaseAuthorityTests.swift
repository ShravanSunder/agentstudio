import Foundation
import Testing

@testable import AgentStudio

@Suite("Filesystem observation context-release authority")
struct FilesystemObservationContextReleaseAuthorityTests {
    @Test("exact unpublished finalization replays its identical final receipt")
    func exactUnpublishedFinalizationReplaysIdenticalReceipt() throws {
        // Arrange
        let fixture = try makeUnpublishedContextReleaseFixture(generationValue: 30)
        let retiredState = fixture.mailbox.physicalSlotState(
            of: fixture.binding.physicalSlotID
        )

        // Act
        let replay = fixture.mailbox.lifecyclePort.finalizeUnpublishedNativeGeneration(
            fixture.retiringLifetime,
            completion: fixture.completion
        )

        // Assert
        #expect(replay == .alreadyFinalized(fixture.finalReceipt))
        #expect(fixture.finalReceipt.retirementAuthority.isUUIDv7)
        #expect(
            fixture.mailbox.physicalSlotState(of: fixture.binding.physicalSlotID)
                == retiredState
        )
    }

    @Test("valid-looking acknowledgement cannot recycle before native finalization")
    func validLookingAcknowledgementCannotRecycleBeforeNativeFinalization() throws {
        // Arrange
        let fixture = try makeUnpublishedContextReleaseFixture(generationValue: 31)
        let retiredState = fixture.mailbox.physicalSlotState(
            of: fixture.binding.physicalSlotID
        )
        let acknowledgement = FilesystemObservationContextReleaseAcknowledgement.unpublished(
            .neverMaterialized(
                receipt: fixture.finalReceipt,
                finalization: FilesystemObservationNeverMaterializedFinalization(
                    startingNativeLifetime: fixture.finalReceipt.startingNativeLifetime
                ),
                releaseAuthority: FilesystemObservationContextReleaseAuthority(
                    value: UUIDv7.generate()
                )
            )
        )

        // Act
        let result = fixture.mailbox.lifecyclePort.applyContextReleaseAcknowledgement(
            acknowledgement
        )

        // Assert
        #expect(result == .releaseAuthorityMismatch)
        #expect(
            fixture.mailbox.physicalSlotState(of: fixture.binding.physicalSlotID)
                == retiredState
        )
        _ = fixture.mailbox.installTestConfiguration(makeRegistration(generation: 32))
        #expect(fixture.mailbox.selectNextDesiredSource() == .deferredBehindSlotCapacity)
    }

    @Test("fence-backed authority mismatches preserve retired custody")
    func fenceBackedAuthorityMismatchesPreserveRetiredCustody() async throws {
        // Arrange
        let fixture = try await makeFenceBackedContextReleaseFixture(generationValue: 32)
        let foreignFixture = try await makeFenceBackedContextReleaseFixture(
            generationValue: 33
        )
        let fenceMismatch = replacingFenceIdentity(in: fixture.acknowledgement)
        let retirementAuthorityMismatch = replacingFenceRetirementAuthority(
            in: fixture.acknowledgement,
            with: foreignFixture.retirementReceipt.retirementAuthority
        )
        let releaseAuthorityMismatch = replacingFenceReleaseAuthority(
            in: fixture.acknowledgement
        )
        let retiredState = fixture.mailbox.physicalSlotState(
            of: fixture.binding.physicalSlotID
        )

        // Act
        let fenceResult = fixture.mailbox.lifecyclePort.applyContextReleaseAcknowledgement(
            fenceMismatch
        )
        let retirementAuthorityResult = fixture.mailbox.lifecyclePort
            .applyContextReleaseAcknowledgement(retirementAuthorityMismatch)
        let releaseAuthorityResult = fixture.mailbox.lifecyclePort
            .applyContextReleaseAcknowledgement(releaseAuthorityMismatch)

        // Assert
        #expect(fenceResult == .fenceMismatch)
        #expect(retirementAuthorityResult == .retirementAuthorityMismatch)
        #expect(releaseAuthorityResult == .releaseAuthorityMismatch)
        #expect(
            fixture.mailbox.physicalSlotState(of: fixture.binding.physicalSlotID)
                == retiredState
        )
        #expect(fixture.contextFinalizer.retainedPointerReleaseCount == 1)
    }
}
