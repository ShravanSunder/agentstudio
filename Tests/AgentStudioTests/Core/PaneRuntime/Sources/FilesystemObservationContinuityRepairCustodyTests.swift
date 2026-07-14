import Foundation
import Testing

@testable import AgentStudio

@Suite("Filesystem observation continuity-repair custody")
struct FilesystemObservationContinuityRepairCustodyTests {
    @Test("failed start retains pending repair and prepares one replayable handoff")
    func failedStartRetainsPendingRepairAndPreparesReplayableHandoff() throws {
        // Arrange
        let fixture = try makeContinuityRepairFixture()

        // Act
        let firstPreparation = fixture.registry.prepareContinuityRepairHandoff(
            for: fixture.acceptingNativeLifetime
        )
        let replayedPreparation = fixture.registry.prepareContinuityRepairHandoff(
            for: fixture.acceptingNativeLifetime
        )

        // Assert
        let firstHandoff = try requirePreparedHandoff(firstPreparation)
        let replayedHandoff = try requireReplayedHandoff(replayedPreparation)
        #expect(firstHandoff == replayedHandoff)
        #expect(firstHandoff.authority.handoffIdentity.isUUIDv7)
        #expect(firstHandoff.authority.acceptingBinding == fixture.acceptingNativeLifetime.binding)
        #expect(firstHandoff.authority.desiredIdentity == fixture.desiredRegistration.identity)
        #expect(
            firstHandoff.authority.acceptedTopologyRevision
                == fixture.desiredRegistration.acceptedTopologyRevision
        )
        #expect(firstHandoff.successorDisposition == .sameDesired)
        #expect(
            fixture.registry.read.pendingContinuityRepairState(for: fixture.sourceID)
                == .handoffInFlight(firstHandoff)
        )
    }

    @Test("exact SourceGate acceptance acknowledges same-desired custody once")
    func exactAcceptanceAcknowledgesSameDesiredOnce() throws {
        // Arrange
        let fixture = try makeContinuityRepairFixture()
        let handoff = try prepareContinuityRepairHandoff(fixture)
        let acceptance = try admitContinuityRepair(handoff.authority)

        // Act
        let firstAcknowledgement = fixture.registry.acknowledgeContinuityRepairHandoff(acceptance)
        let replayedAcknowledgement = fixture.registry.acknowledgeContinuityRepairHandoff(acceptance)

        // Assert
        #expect(
            firstAcknowledgement
                == .acknowledged(
                    .sameDesired(
                        handoff: handoff,
                        acceptance: acceptance
                    )
                )
        )
        #expect(
            replayedAcknowledgement
                == .alreadyAcknowledged(
                    .sameDesired(
                        handoff: handoff,
                        acceptance: acceptance
                    )
                )
        )
        #expect(fixture.registry.read.pendingContinuityRepairState(for: fixture.sourceID) == .absent)
    }

    @Test("supersession during handoff preserves one newer pending authority")
    func supersessionDuringHandoffPreservesNewerPendingAuthority() throws {
        // Arrange
        let fixture = try makeContinuityRepairFixture()
        let originalHandoff = try prepareContinuityRepairHandoff(fixture)
        let newerConfiguration = makeContinuityRepairConfiguration(
            sourceID: fixture.sourceID,
            generation: 2
        )

        // Act
        _ = fixture.registry.installDesiredConfiguration(
            newerConfiguration,
            acceptedTopologyRevision: FilesystemObservationAcceptedTopologyRevision(value: 2)
        )
        let updatedHandoff = try requireInFlightHandoff(
            fixture.registry.read.pendingContinuityRepairState(for: fixture.sourceID)
        )
        let acceptance = try admitContinuityRepair(originalHandoff.authority)
        let acknowledgement = fixture.registry.acknowledgeContinuityRepairHandoff(acceptance)

        // Assert
        let successorAuthority = try requireSupersededAuthority(
            updatedHandoff.successorDisposition
        )
        #expect(updatedHandoff.authority == originalHandoff.authority)
        #expect(successorAuthority.desiredIdentity != originalHandoff.authority.desiredIdentity)
        #expect(successorAuthority.acceptedTopologyRevision.value == 2)
        #expect(
            acknowledgement
                == .acknowledged(
                    .superseded(
                        handoff: updatedHandoff,
                        acceptance: acceptance,
                        successorAuthority: successorAuthority
                    )
                )
        )
        #expect(
            fixture.registry.read.pendingContinuityRepairState(for: fixture.sourceID)
                == .pending(successorAuthority)
        )
    }

    @Test("removal during handoff consumes desired repair after exact acknowledgement")
    func removalDuringHandoffConsumesDesiredRepair() throws {
        // Arrange
        let fixture = try makeContinuityRepairFixture()
        let originalHandoff = try prepareContinuityRepairHandoff(fixture)
        let removalRevision = FilesystemObservationAcceptedTopologyRevision(value: 3)

        // Act
        let removalAdmission = fixture.registry.admitRemoval(
            of: fixture.acceptingNativeLifetime.binding,
            acceptedTopologyRevision: removalRevision
        )
        let removalAuthority = try requireRemovalAuthority(removalAdmission)
        let updatedHandoff = try requireInFlightHandoff(
            fixture.registry.read.pendingContinuityRepairState(for: fixture.sourceID)
        )
        let acceptance = try admitContinuityRepair(originalHandoff.authority)
        let acknowledgement = fixture.registry.acknowledgeContinuityRepairHandoff(acceptance)

        // Assert
        #expect(updatedHandoff.authority == originalHandoff.authority)
        #expect(updatedHandoff.successorDisposition == .removed(removalAuthority))
        #expect(
            acknowledgement
                == .acknowledged(
                    .removed(
                        handoff: updatedHandoff,
                        acceptance: acceptance,
                        removalAuthority: removalAuthority
                    )
                )
        )
        #expect(fixture.registry.read.pendingContinuityRepairState(for: fixture.sourceID) == .absent)
    }

    @Test("foreign and stale SourceGate acceptances cannot mutate retained handoff")
    func foreignAndStaleAcceptancesCannotMutateRetainedHandoff() throws {
        // Arrange
        let fixture = try makeContinuityRepairFixture()
        let retainedHandoff = try prepareContinuityRepairHandoff(fixture)
        let foreignFixture = try makeContinuityRepairFixture(sourceOrdinal: 2)
        let foreignHandoff = try prepareContinuityRepairHandoff(foreignFixture)
        let foreignAcceptance = try admitContinuityRepair(foreignHandoff.authority)
        let staleAuthority = FilesystemContinuityRepairHandoffAuthority(
            acceptingBinding: retainedHandoff.authority.acceptingBinding,
            handoffIdentity: FilesystemContinuityRepairHandoffIdentity(value: UUIDv7.generate()),
            desiredIdentity: retainedHandoff.authority.desiredIdentity,
            acceptedTopologyRevision: retainedHandoff.authority.acceptedTopologyRevision
        )
        let staleAcceptance = try admitContinuityRepair(staleAuthority)

        // Act
        let foreignResult = fixture.registry.acknowledgeContinuityRepairHandoff(
            foreignAcceptance
        )
        let staleResult = fixture.registry.acknowledgeContinuityRepairHandoff(staleAcceptance)

        // Assert
        #expect(foreignResult == .bindingMismatch)
        #expect(staleResult == .staleAcceptance)
        #expect(
            fixture.registry.read.pendingContinuityRepairState(for: fixture.sourceID)
                == .handoffInFlight(retainedHandoff)
        )
    }

    @Test("handoff preparation distinguishes absent and mismatched accepting authority")
    func preparationDistinguishesAbsentAndMismatchedAcceptingAuthority() throws {
        // Arrange
        let fixture = try makeContinuityRepairFixture()
        let unrelatedFixture = try makeContinuityRepairFixture(sourceOrdinal: 3)
        let emptyRegistry = try FilesystemObservationSlotRegistry(
            maximumSimultaneousSourceCount: 1,
            replacementReserveSlotCount: 1
        )

        // Act
        let absentResult = emptyRegistry.prepareContinuityRepairHandoff(
            for: fixture.acceptingNativeLifetime
        )
        let bindingMismatchResult = fixture.registry.prepareContinuityRepairHandoff(
            for: unrelatedFixture.acceptingNativeLifetime
        )
        let mismatchedDesiredLifetime = FilesystemObservationAcceptingNativeLifetime(
            startingNativeLifetime: FilesystemObservationStartingNativeLifetime(
                desiredRegistration: unrelatedFixture.desiredRegistration,
                consumedReservation: fixture.acceptingNativeLifetime.startingNativeLifetime
                    .consumedReservation,
                binding: fixture.acceptingNativeLifetime.binding,
                nativeGenerationIdentity: fixture.acceptingNativeLifetime.startingNativeLifetime
                    .nativeGenerationIdentity
            ),
            callbackAdmissionPortIdentity: fixture.acceptingNativeLifetime
                .callbackAdmissionPortIdentity
        )
        let desiredMismatchResult = fixture.registry.prepareContinuityRepairHandoff(
            for: mismatchedDesiredLifetime
        )

        // Assert
        #expect(absentResult == .absent)
        #expect(bindingMismatchResult == .bindingMismatch)
        #expect(desiredMismatchResult == .desiredIdentityMismatch)
    }

    @Test("installed-awaiting-repair receipt carries the complete typed handoff authority")
    func installedAwaitingRepairCarriesCompleteTypedAuthority() throws {
        // Arrange
        let fixture = try makeContinuityRepairFixture()
        let handoff = try prepareContinuityRepairHandoff(fixture)

        // Act
        let receipt = try FilesystemSourceConfigurationReceipt(
            acceptedTopologyRevision: handoff.authority.acceptedTopologyRevision.value,
            requestedSourceIDs: [fixture.sourceID],
            dispositions: [
                fixture.sourceID: .installedAwaitingContinuityRepair(
                    desiredConfiguration: fixture.desiredRegistration.configuration,
                    handoffAuthority: handoff.authority
                )
            ]
        )

        // Assert
        #expect(handoff.authority.handoffIdentity.isUUIDv7)
        #expect(handoff.authority.acceptingBinding == fixture.acceptingNativeLifetime.binding)
        #expect(handoff.authority.desiredIdentity == fixture.desiredRegistration.identity)
        #expect(receipt.currentness == .nonCurrent(retrySources: [fixture.sourceID]))
    }
}

private struct ContinuityRepairFixture {
    let registry: FilesystemObservationSlotRegistry
    let sourceID: FilesystemSourceID
    let desiredRegistration: FilesystemObservationDesiredRegistration
    let acceptingNativeLifetime: FilesystemObservationAcceptingNativeLifetime
}

private enum ContinuityRepairCustodyTestError: Error {
    case expectedEnqueuedDesired
    case expectedSelection
    case expectedStartingLifetime
    case expectedRetirement
    case expectedPendingRepair
    case expectedPublication
    case expectedPreparedHandoff
    case expectedReplayedHandoff
    case expectedInFlightHandoff
    case expectedSupersededAuthority
    case expectedRemovalAuthority
    case expectedSourceGateAcceptance
}

private func makeContinuityRepairFixture(
    sourceOrdinal: Int = 1
) throws -> ContinuityRepairFixture {
    let sourceID = FilesystemSourceID(
        kind: .registeredWorktreeContent,
        rootID: UUID(
            uuidString: String(format: "20000000-0000-0000-0000-%012d", sourceOrdinal)
        )!
    )
    let configuration = makeContinuityRepairConfiguration(
        sourceID: sourceID,
        generation: 1
    )
    let registry = try FilesystemObservationSlotRegistry(
        maximumSimultaneousSourceCount: 1,
        replacementReserveSlotCount: 1
    )
    guard
        case .enqueued(let desiredRegistration) = registry.installDesiredConfiguration(
            configuration,
            acceptedTopologyRevision: FilesystemObservationAcceptedTopologyRevision(value: 1)
        )
    else {
        throw ContinuityRepairCustodyTestError.expectedEnqueuedDesired
    }
    let failedStartingLifetime = try selectAndBeginNativeLifetime(registry)
    guard
        case .retirementRequired =
            registry.retireUnpublishedNativeGenerationAfterCreateOrStartFailure(
                failedStartingLifetime
            )
    else {
        throw ContinuityRepairCustodyTestError.expectedRetirement
    }
    guard
        case .pending = registry.read.pendingContinuityRepairState(for: sourceID)
    else {
        throw ContinuityRepairCustodyTestError.expectedPendingRepair
    }
    let retryStartingLifetime = try selectAndBeginNativeLifetime(registry)
    let callbackAdmissionPortIdentity = FilesystemObservationCallbackAdmissionPortIdentity(
        value: UUIDv7.generate()
    )
    guard
        case .published(let publication) = registry.publishAcceptingNativeLifetime(
            retryStartingLifetime,
            callbackAdmissionPortIdentity: callbackAdmissionPortIdentity
        )
    else {
        throw ContinuityRepairCustodyTestError.expectedPublication
    }
    return ContinuityRepairFixture(
        registry: registry,
        sourceID: sourceID,
        desiredRegistration: desiredRegistration,
        acceptingNativeLifetime: publication.acceptingNativeLifetime
    )
}

private func makeContinuityRepairConfiguration(
    sourceID: FilesystemSourceID,
    generation: UInt64
) -> FilesystemObservationSourceConfiguration {
    FilesystemObservationSourceConfiguration(
        registration: FSEventRegistrationToken(
            sourceID: sourceID,
            registrationGeneration: generation,
            rootGeneration: generation
        ),
        canonicalResolvedRootIdentity: FilesystemCanonicalResolvedRootIdentity(
            path: "/private/test/continuity-repair/\(sourceID.rootID.uuidString)"
        ),
        authorizationScopeIdentity: FilesystemAuthorizationScopeIdentity(
            value: sourceID.rootID
        ),
        eventCoverage: .recursiveFileEvents
    )
}

private func selectAndBeginNativeLifetime(
    _ registry: FilesystemObservationSlotRegistry
) throws -> FilesystemObservationStartingNativeLifetime {
    guard case .selected(let selection) = registry.selectNextDesiredSource() else {
        throw ContinuityRepairCustodyTestError.expectedSelection
    }
    guard case .committed(let lifetime) = registry.beginNativeLifetime(selection.reservation) else {
        throw ContinuityRepairCustodyTestError.expectedStartingLifetime
    }
    return lifetime
}

private func prepareContinuityRepairHandoff(
    _ fixture: ContinuityRepairFixture
) throws -> FilesystemContinuityRepairHandoff {
    try requirePreparedHandoff(
        fixture.registry.prepareContinuityRepairHandoff(
            for: fixture.acceptingNativeLifetime
        )
    )
}

private func admitContinuityRepair(
    _ authority: FilesystemContinuityRepairHandoffAuthority
) throws -> FilesystemSourceGateContinuityRepairAcceptance {
    var sourceGate = FilesystemSourceGate(binding: authority.acceptingBinding)
    let result = sourceGate.acceptContinuityRepairHandoff(
        authority,
        trigger: .continuityLoss,
        watermark: .recoveryRevision(authority.acceptedTopologyRevision.value),
        participants: makeRequiredParticipants()
    )
    guard case .admitted(let acceptance) = result else {
        throw ContinuityRepairCustodyTestError.expectedSourceGateAcceptance
    }
    return acceptance
}

private func requirePreparedHandoff(
    _ result: FilesystemContinuityRepairHandoffPreparationResult
) throws -> FilesystemContinuityRepairHandoff {
    guard case .prepared(let handoff) = result else {
        throw ContinuityRepairCustodyTestError.expectedPreparedHandoff
    }
    return handoff
}

private func requireReplayedHandoff(
    _ result: FilesystemContinuityRepairHandoffPreparationResult
) throws -> FilesystemContinuityRepairHandoff {
    guard case .replayed(let handoff) = result else {
        throw ContinuityRepairCustodyTestError.expectedReplayedHandoff
    }
    return handoff
}

private func requireInFlightHandoff(
    _ state: FilesystemPendingContinuityRepairState
) throws -> FilesystemContinuityRepairHandoff {
    guard case .handoffInFlight(let handoff) = state else {
        throw ContinuityRepairCustodyTestError.expectedInFlightHandoff
    }
    return handoff
}

private func requireSupersededAuthority(
    _ disposition: FilesystemContinuityRepairSuccessorDisposition
) throws -> FilesystemPendingContinuityRepairAuthority {
    guard case .superseded(let authority) = disposition else {
        throw ContinuityRepairCustodyTestError.expectedSupersededAuthority
    }
    return authority
}

private func requireRemovalAuthority(
    _ result: FilesystemObservationRemovalAdmissionResult
) throws -> FilesystemSourceRemovalAuthority {
    guard case .closeAccepting(let obligation) = result else {
        throw ContinuityRepairCustodyTestError.expectedRemovalAuthority
    }
    return obligation.removalAuthority
}
