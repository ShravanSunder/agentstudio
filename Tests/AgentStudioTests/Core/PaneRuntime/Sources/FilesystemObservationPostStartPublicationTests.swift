import Foundation
import Testing

@testable import AgentStudio

@Suite("Filesystem observation post-start publication")
struct FilesystemObservationPostStartPublicationTests {
    @Test("current publication replays one exact retained result")
    func currentPublicationReplaysExactResult() throws {
        // Arrange
        let fixture = try makePostStartPublicationFixture()
        let startingNativeLifetime = try beginPostStartNativeLifetime(
            in: fixture,
            generation: 1
        )

        // Act
        let results = publishPostStartTwice(
            in: fixture.registry,
            startingNativeLifetime: startingNativeLifetime,
            callbackAdmissionPortIdentity: fixture.callbackAdmissionPortIdentity
        )

        // Assert
        let firstPublication = try requireFirstPostStartPublication(results.first)
        let replayedPublication = try requireReplayedPostStartPublication(results.replayed)
        let expectedAcceptingNativeLifetime = makeExpectedAcceptingNativeLifetime(
            startingNativeLifetime: startingNativeLifetime,
            callbackAdmissionPortIdentity: fixture.callbackAdmissionPortIdentity
        )
        #expect(firstPublication == replayedPublication)
        #expect(firstPublication.acceptingNativeLifetime == expectedAcceptingNativeLifetime)
        #expect(firstPublication.disposition == .current)
        #expect(
            fixture.registry.read.state(of: startingNativeLifetime.binding.physicalSlotID)
                == .accepting(expectedAcceptingNativeLifetime)
        )
    }

    @Test("replacement publication replays exact predecessor close obligation")
    func replacementPublicationReplaysExactPredecessorCloseObligation() throws {
        // Arrange
        let fixture = try makePostStartPublicationFixture()
        let predecessorStartingNativeLifetime = try beginPostStartNativeLifetime(
            in: fixture,
            generation: 1
        )
        let predecessorPublicationResults = publishPostStartTwice(
            in: fixture.registry,
            startingNativeLifetime: predecessorStartingNativeLifetime,
            callbackAdmissionPortIdentity: fixture.callbackAdmissionPortIdentity
        )
        let predecessorPublication = try requireFirstPostStartPublication(
            predecessorPublicationResults.first
        )
        let replacementStartingNativeLifetime = try beginPostStartReplacementLifetime(
            in: fixture,
            generation: 2,
            exactPriorBinding: predecessorStartingNativeLifetime.binding
        )

        // Act
        let results = publishPostStartTwice(
            in: fixture.registry,
            startingNativeLifetime: replacementStartingNativeLifetime,
            callbackAdmissionPortIdentity: fixture.callbackAdmissionPortIdentity
        )

        // Assert
        let firstPublication = try requireFirstPostStartPublication(results.first)
        let replayedPublication = try requireReplayedPostStartPublication(results.replayed)
        #expect(firstPublication == replayedPublication)
        #expect(
            firstPublication.disposition
                == .closePredecessor(predecessorPublication.acceptingNativeLifetime)
        )
        #expect(
            fixture.registry.read.storedBindingCurrentness(
                of: predecessorStartingNativeLifetime.binding
            ) == .storedSuperseded
        )
        #expect(
            fixture.registry.read.storedBindingCurrentness(
                of: replacementStartingNativeLifetime.binding
            ) == .storedCurrent
        )
    }

    @Test("successful start publication wins concurrent removal and replays published close")
    func successfulStartPublicationWinsRemoval() throws {
        // Arrange
        let fixture = try makePostStartPublicationFixture()
        let startingNativeLifetime = try beginPostStartNativeLifetime(
            in: fixture,
            generation: 1
        )

        // Act: native start has succeeded, but accepting publication is paused while removal wins
        // the registry lock. Post-start publication must still publish before closing.
        _ = fixture.registry.withdrawDesiredSource(
            sourceID: startingNativeLifetime.desiredRegistration.sourceID,
            desiredIdentity: startingNativeLifetime.desiredRegistration.identity
        )
        let results = publishPostStartTwice(
            in: fixture.registry,
            startingNativeLifetime: startingNativeLifetime,
            callbackAdmissionPortIdentity: fixture.callbackAdmissionPortIdentity
        )

        // Assert
        let firstPublication = try requireFirstPostStartPublication(results.first)
        let replayedPublication = try requireReplayedPostStartPublication(results.replayed)
        let expectedPublishedLifetime = makeExpectedAcceptingNativeLifetime(
            startingNativeLifetime: startingNativeLifetime,
            callbackAdmissionPortIdentity: fixture.callbackAdmissionPortIdentity
        )
        #expect(firstPublication == replayedPublication)
        #expect(firstPublication.acceptingNativeLifetime == expectedPublishedLifetime)
        #expect(firstPublication.disposition == .closePublished(expectedPublishedLifetime))
        #expect(
            fixture.registry.read.state(of: startingNativeLifetime.binding.physicalSlotID)
                != .retiringUnpublishedGeneration(
                    FilesystemObservationRetiringUnpublishedNativeLifetime(
                        startingNativeLifetime: startingNativeLifetime,
                        cause: .desiredWithdrawn
                    )
                )
        )
    }

    @Test("superseded replacement replays ordered predecessor and published close obligations")
    func supersededReplacementReplaysBothOrderedCloseObligations() throws {
        // Arrange
        let fixture = try makePostStartPublicationFixture()
        let predecessorStartingNativeLifetime = try beginPostStartNativeLifetime(
            in: fixture,
            generation: 1
        )
        let predecessorPublicationResults = publishPostStartTwice(
            in: fixture.registry,
            startingNativeLifetime: predecessorStartingNativeLifetime,
            callbackAdmissionPortIdentity: fixture.callbackAdmissionPortIdentity
        )
        let predecessorPublication = try requireFirstPostStartPublication(
            predecessorPublicationResults.first
        )
        let replacementStartingNativeLifetime = try beginPostStartReplacementLifetime(
            in: fixture,
            generation: 2,
            exactPriorBinding: predecessorStartingNativeLifetime.binding
        )
        let newestDesiredRegistration = try requirePostStartPendingDesiredRegistration(
            fixture.registry.installTestConfiguration(
                makePostStartRegistration(generation: 3)
            )
        )

        // Act: N+1 has started successfully, but N+2 supersedes it before accepting publication.
        let results = publishPostStartTwice(
            in: fixture.registry,
            startingNativeLifetime: replacementStartingNativeLifetime,
            callbackAdmissionPortIdentity: fixture.callbackAdmissionPortIdentity
        )

        // Assert
        let firstPublication = try requireFirstPostStartPublication(results.first)
        let replayedPublication = try requireReplayedPostStartPublication(results.replayed)
        let expectedPublishedLifetime = makeExpectedAcceptingNativeLifetime(
            startingNativeLifetime: replacementStartingNativeLifetime,
            callbackAdmissionPortIdentity: fixture.callbackAdmissionPortIdentity
        )
        #expect(firstPublication == replayedPublication)
        #expect(
            firstPublication.disposition
                == .closePredecessorAndPublished(
                    predecessor: predecessorPublication.acceptingNativeLifetime,
                    published: expectedPublishedLifetime
                )
        )
        #expect(
            fixture.registry.read.pendingConfigurationState(
                for: newestDesiredRegistration.sourceID
            ) == .retained(newestDesiredRegistration)
        )
        #expect(
            !fixture.registry.read.deferredDesiredRegistrationsInFIFOOrder.contains {
                $0.sourceID == newestDesiredRegistration.sourceID
            }
        )
    }
}

private struct PostStartPublicationFixture {
    let registry: FilesystemObservationSlotRegistry
    let recoveryRegister: FixedFilesystemRecoveryEvidenceRegister
    let callbackAdmissionPortIdentity: FilesystemObservationCallbackAdmissionPortIdentity
}

private struct PostStartPublicationResults {
    let first: FilesystemObservationAcceptingPublicationResult
    let replayed: FilesystemObservationAcceptingPublicationResult
}

private enum PostStartPublicationTestError: Error {
    case expectedSelectedDesiredSource
    case expectedCommittedNativeLifetime
    case expectedPendingDesiredRegistration
    case expectedRecoveryBinding
    case expectedPriorContinuityAuthority
    case expectedReplacementAdmission
    case expectedFirstPublication
    case expectedReplayedPublication
}

private func makePostStartPublicationFixture() throws -> PostStartPublicationFixture {
    let registry = try FilesystemObservationSlotRegistry(
        maximumSimultaneousSourceCount: 1,
        replacementReserveSlotCount: 1
    )
    return PostStartPublicationFixture(
        registry: registry,
        recoveryRegister: FixedFilesystemRecoveryEvidenceRegister(slotRegistry: registry),
        callbackAdmissionPortIdentity: FilesystemObservationCallbackAdmissionPortIdentity(
            value: UUIDv7.generate()
        )
    )
}

private func beginPostStartNativeLifetime(
    in fixture: PostStartPublicationFixture,
    generation: UInt64
) throws -> FilesystemObservationStartingNativeLifetime {
    let registry = fixture.registry
    _ = registry.installTestConfiguration(makePostStartRegistration(generation: generation))
    guard case .selected(let selection) = registry.selectNextDesiredSource() else {
        throw PostStartPublicationTestError.expectedSelectedDesiredSource
    }
    guard
        case .committed(let startingNativeLifetime) =
            registry.beginNativeLifetime(selection.reservation)
    else {
        throw PostStartPublicationTestError.expectedCommittedNativeLifetime
    }
    guard case .boundClear = fixture.recoveryRegister.bind(startingNativeLifetime.binding) else {
        throw PostStartPublicationTestError.expectedRecoveryBinding
    }
    return startingNativeLifetime
}

private func beginPostStartReplacementLifetime(
    in fixture: PostStartPublicationFixture,
    generation: UInt64,
    exactPriorBinding: FilesystemObservationSlotBinding
) throws -> FilesystemObservationStartingNativeLifetime {
    guard
        case .issued(let priorContinuityAuthority) =
            fixture.recoveryRegister.issuePriorContinuityAuthority(
                for: exactPriorBinding
            )
    else {
        throw PostStartPublicationTestError.expectedPriorContinuityAuthority
    }
    let registration = makePostStartRegistration(generation: generation)
    guard
        case .admitted = fixture.registry.admitReplacementDesiredConfiguration(
            makeTestFilesystemObservationSourceConfiguration(registration),
            acceptedTopologyRevision: FilesystemObservationAcceptedTopologyRevision(
                value: generation
            ),
            exactPriorBinding: exactPriorBinding,
            priorContinuityAuthority: priorContinuityAuthority
        )
    else {
        throw PostStartPublicationTestError.expectedReplacementAdmission
    }
    guard case .selected(let selection) = fixture.registry.selectNextDesiredSource() else {
        throw PostStartPublicationTestError.expectedSelectedDesiredSource
    }
    guard
        case .committed(let startingNativeLifetime) =
            fixture.registry.beginNativeLifetime(selection.reservation)
    else {
        throw PostStartPublicationTestError.expectedCommittedNativeLifetime
    }
    guard case .boundClear = fixture.recoveryRegister.bind(startingNativeLifetime.binding) else {
        throw PostStartPublicationTestError.expectedRecoveryBinding
    }
    return startingNativeLifetime
}

private func makePostStartRegistration(generation: UInt64) -> FSEventRegistrationToken {
    FSEventRegistrationToken(
        sourceID: FilesystemSourceID(
            kind: .registeredWorktreeContent,
            rootID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        ),
        registrationGeneration: generation,
        rootGeneration: generation
    )
}

private func publishPostStartTwice(
    in registry: FilesystemObservationSlotRegistry,
    startingNativeLifetime: FilesystemObservationStartingNativeLifetime,
    callbackAdmissionPortIdentity: FilesystemObservationCallbackAdmissionPortIdentity
) -> PostStartPublicationResults {
    PostStartPublicationResults(
        first: registry.publishAcceptingNativeLifetime(
            startingNativeLifetime,
            callbackAdmissionPortIdentity: callbackAdmissionPortIdentity
        ),
        replayed: registry.publishAcceptingNativeLifetime(
            startingNativeLifetime,
            callbackAdmissionPortIdentity: callbackAdmissionPortIdentity
        )
    )
}

private func makeExpectedAcceptingNativeLifetime(
    startingNativeLifetime: FilesystemObservationStartingNativeLifetime,
    callbackAdmissionPortIdentity: FilesystemObservationCallbackAdmissionPortIdentity
) -> FilesystemObservationAcceptingNativeLifetime {
    FilesystemObservationAcceptingNativeLifetime(
        startingNativeLifetime: startingNativeLifetime,
        callbackAdmissionPortIdentity: callbackAdmissionPortIdentity
    )
}

private func requirePostStartPendingDesiredRegistration(
    _ result: FilesystemObservationDesiredUpdateResult
) throws -> FilesystemObservationDesiredRegistration {
    guard case .deferredToConfigurationCurrentness(let desiredRegistration) = result else {
        throw PostStartPublicationTestError.expectedPendingDesiredRegistration
    }
    return desiredRegistration
}

private func requireFirstPostStartPublication(
    _ result: FilesystemObservationAcceptingPublicationResult
) throws -> FilesystemObservationPostStartPublication {
    guard case .published(let publication) = result else {
        throw PostStartPublicationTestError.expectedFirstPublication
    }
    return publication
}

private func requireReplayedPostStartPublication(
    _ result: FilesystemObservationAcceptingPublicationResult
) throws -> FilesystemObservationPostStartPublication {
    guard case .alreadyPublished(let publication) = result else {
        throw PostStartPublicationTestError.expectedReplayedPublication
    }
    return publication
}
