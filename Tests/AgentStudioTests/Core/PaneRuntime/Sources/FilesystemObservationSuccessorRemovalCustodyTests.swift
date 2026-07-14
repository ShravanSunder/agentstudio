import Foundation
import Testing

@testable import AgentStudio

@Suite("Filesystem observation successor removal custody")
struct FilesystemObservationSuccessorRemovalCustodyTests {
    @Test("accepting removal consumes the deferred successor in FIFO custody")
    func acceptingRemovalConsumesDeferredSuccessor() throws {
        // Arrange
        let fixture = try makeSuccessorRemovalFixture()
        _ = try admitSuccessorReplacement(
            in: fixture,
            generation: 2
        )

        // Act
        let removalResult = fixture.registry.admitRemoval(
            of: fixture.predecessorStartingLifetime.binding,
            acceptedTopologyRevision: FilesystemObservationAcceptedTopologyRevision(value: 3)
        )

        // Assert
        let closeObligation = try requireSuccessorRemovalCloseObligation(removalResult)
        #expect(
            closeObligation.acceptingNativeLifetime
                == fixture.predecessorAcceptingLifetime
        )
        #expect(fixture.registry.selectNextDesiredSource() == .noDeferredDesiredSource)
    }

    @Test("accepting removal releases a selected successor and rejects its old commit")
    func acceptingRemovalReleasesSelectedSuccessor() throws {
        // Arrange
        let fixture = try makeSuccessorRemovalFixture()
        _ = try admitSuccessorReplacement(
            in: fixture,
            generation: 2
        )
        let successorSelection = try requireSelectedDesiredSource(
            fixture.registry.selectNextDesiredSource()
        )

        // Act
        let removalResult = fixture.registry.admitRemoval(
            of: fixture.predecessorStartingLifetime.binding,
            acceptedTopologyRevision: FilesystemObservationAcceptedTopologyRevision(value: 3)
        )
        let staleCommitResult = fixture.registry.beginNativeLifetime(
            successorSelection.reservation
        )

        // Assert
        let closeObligation = try requireSuccessorRemovalCloseObligation(removalResult)
        #expect(
            closeObligation.acceptingNativeLifetime
                == fixture.predecessorAcceptingLifetime
        )
        #expect(
            fixture.registry.read.state(of: successorSelection.reservation.physicalSlotID)
                == .vacant
        )
        #expect(staleCommitResult == .reservationNoLongerCurrent)
    }

    @Test("accepting removal retains a starting successor until publication closes both")
    func acceptingRemovalRetainsStartingSuccessorUntilPublication() throws {
        // Arrange
        let fixture = try makeSuccessorRemovalFixture()
        _ = try admitSuccessorReplacement(in: fixture, generation: 2)
        let successorSelection = try requireSelectedDesiredSource(
            fixture.registry.selectNextDesiredSource()
        )
        let successorStartingLifetime = try requireCommittedNativeLifetime(
            fixture.registry.beginNativeLifetime(successorSelection.reservation)
        )
        guard
            case .boundClear = fixture.recoveryRegister.bind(
                successorStartingLifetime.binding
            )
        else {
            throw SuccessorRemovalCustodyTestError.expectedRecoveryBinding
        }

        // Act
        let removalResult = fixture.registry.admitRemoval(
            of: fixture.predecessorStartingLifetime.binding,
            acceptedTopologyRevision: FilesystemObservationAcceptedTopologyRevision(value: 3)
        )
        let stateAfterRemoval = fixture.registry.read.state(
            of: successorStartingLifetime.binding.physicalSlotID
        )
        let firstPublicationResult = fixture.registry.publishAcceptingNativeLifetime(
            successorStartingLifetime,
            callbackAdmissionPortIdentity: fixture.callbackAdmissionPortIdentity
        )
        let replayedPublicationResult = fixture.registry.publishAcceptingNativeLifetime(
            successorStartingLifetime,
            callbackAdmissionPortIdentity: fixture.callbackAdmissionPortIdentity
        )

        // Assert
        let closeObligation = try requireSuccessorRemovalCloseObligation(removalResult)
        #expect(
            closeObligation.acceptingNativeLifetime
                == fixture.predecessorAcceptingLifetime
        )
        #expect(
            stateAfterRemoval == .starting(successorStartingLifetime)
        )
        let firstPublication = try requireSuccessorRemovalPublication(
            firstPublicationResult
        )
        let replayedPublication = try requireReplayedSuccessorRemovalPublication(
            replayedPublicationResult
        )
        let expectedPublishedLifetime = FilesystemObservationAcceptingNativeLifetime(
            startingNativeLifetime: successorStartingLifetime,
            callbackAdmissionPortIdentity: fixture.callbackAdmissionPortIdentity
        )
        #expect(firstPublication == replayedPublication)
        #expect(firstPublication.acceptingNativeLifetime == expectedPublishedLifetime)
        #expect(
            firstPublication.disposition
                == .closePredecessorAndPublished(
                    predecessor: fixture.predecessorAcceptingLifetime,
                    published: expectedPublishedLifetime
                )
        )
    }
}

private struct SuccessorRemovalFixture {
    let registry: FilesystemObservationSlotRegistry
    let recoveryRegister: FixedFilesystemRecoveryEvidenceRegister
    let callbackAdmissionPortIdentity: FilesystemObservationCallbackAdmissionPortIdentity
    let predecessorStartingLifetime: FilesystemObservationStartingNativeLifetime
    let predecessorAcceptingLifetime: FilesystemObservationAcceptingNativeLifetime
}

private enum SuccessorRemovalCustodyTestError: Error {
    case expectedRecoveryBinding
    case expectedPriorContinuityAuthority
    case expectedReplacementAdmission
    case expectedAcceptingPublication
    case expectedRemovalCloseObligation
    case expectedPublishedSuccessor
    case expectedReplayedSuccessor
}

private func makeSuccessorRemovalFixture() throws -> SuccessorRemovalFixture {
    let registry = try FilesystemObservationSlotRegistry(
        maximumSimultaneousSourceCount: 1,
        replacementReserveSlotCount: 1
    )
    let recoveryRegister = FixedFilesystemRecoveryEvidenceRegister(slotRegistry: registry)
    let callbackAdmissionPortIdentity = FilesystemObservationCallbackAdmissionPortIdentity(
        value: UUIDv7.generate()
    )
    _ = registry.installTestConfiguration(makeRegistration(generation: 1))
    let predecessorSelection = try requireSelectedDesiredSource(
        registry.selectNextDesiredSource()
    )
    let predecessorStartingLifetime = try requireCommittedNativeLifetime(
        registry.beginNativeLifetime(predecessorSelection.reservation)
    )
    guard case .boundClear = recoveryRegister.bind(predecessorStartingLifetime.binding) else {
        throw SuccessorRemovalCustodyTestError.expectedRecoveryBinding
    }
    guard
        case .published(let publication) = registry.publishAcceptingNativeLifetime(
            predecessorStartingLifetime,
            callbackAdmissionPortIdentity: callbackAdmissionPortIdentity
        )
    else {
        throw SuccessorRemovalCustodyTestError.expectedAcceptingPublication
    }
    return SuccessorRemovalFixture(
        registry: registry,
        recoveryRegister: recoveryRegister,
        callbackAdmissionPortIdentity: callbackAdmissionPortIdentity,
        predecessorStartingLifetime: predecessorStartingLifetime,
        predecessorAcceptingLifetime: publication.acceptingNativeLifetime
    )
}

private func admitSuccessorReplacement(
    in fixture: SuccessorRemovalFixture,
    generation: UInt64
) throws -> FilesystemObservationDesiredRegistration {
    guard
        case .issued(let priorContinuityAuthority) =
            fixture.recoveryRegister.issuePriorContinuityAuthority(
                for: fixture.predecessorStartingLifetime.binding
            )
    else {
        throw SuccessorRemovalCustodyTestError.expectedPriorContinuityAuthority
    }
    let desiredConfiguration = makeTestFilesystemObservationSourceConfiguration(
        makeRegistration(generation: generation)
    )
    guard
        case .admitted(.enqueued(let desiredRegistration)) =
            fixture.registry.admitReplacementDesiredConfiguration(
                desiredConfiguration,
                acceptedTopologyRevision: FilesystemObservationAcceptedTopologyRevision(
                    value: generation
                ),
                exactPriorBinding: fixture.predecessorStartingLifetime.binding,
                priorContinuityAuthority: priorContinuityAuthority
            )
    else {
        throw SuccessorRemovalCustodyTestError.expectedReplacementAdmission
    }
    return desiredRegistration
}

private func requireSuccessorRemovalCloseObligation(
    _ result: FilesystemObservationRemovalAdmissionResult
) throws -> FilesystemAcceptingRemovalCloseObligation {
    guard case .closeAccepting(let closeObligation) = result else {
        throw SuccessorRemovalCustodyTestError.expectedRemovalCloseObligation
    }
    return closeObligation
}

private func requireSuccessorRemovalPublication(
    _ result: FilesystemObservationAcceptingPublicationResult
) throws -> FilesystemObservationPostStartPublication {
    guard case .published(let publication) = result else {
        throw SuccessorRemovalCustodyTestError.expectedPublishedSuccessor
    }
    return publication
}

private func requireReplayedSuccessorRemovalPublication(
    _ result: FilesystemObservationAcceptingPublicationResult
) throws -> FilesystemObservationPostStartPublication {
    guard case .alreadyPublished(let publication) = result else {
        throw SuccessorRemovalCustodyTestError.expectedReplayedSuccessor
    }
    return publication
}
