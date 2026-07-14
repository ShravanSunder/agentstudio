import Foundation
import Testing

@testable import AgentStudio

@Suite("Filesystem observation slot registry reservation lifecycle")
struct FilesystemObservationSlotRegistryTestsReservation {
    @Test("selected withdrawal releases exact reservation and rejects stale identity")
    func selectedWithdrawalReleasesReservation() throws {
        // Arrange
        let registry = try makeRegistry(physicalSlotCount: 1)
        let oldDesired = try requireEnqueuedDesiredRegistration(
            registry.recordDesiredRegistration(makeRegistration(generation: 1))
        )
        let currentDesired = try requireReplacedDesiredRegistration(
            registry.recordDesiredRegistration(makeRegistration(generation: 2))
        )
        let selection = try requireSelectedDesiredSource(registry.selectNextDesiredSource())

        // Act
        let staleResult = registry.withdrawDesiredSource(
            sourceID: currentDesired.sourceID,
            desiredIdentity: oldDesired.identity
        )
        let exactResult = registry.withdrawDesiredSource(
            sourceID: currentDesired.sourceID,
            desiredIdentity: currentDesired.identity
        )

        // Assert
        #expect(staleResult == .staleDesiredIdentity(currentDesired.identity))
        #expect(exactResult == .releasedSelectedReservation(selection))
        #expect(registry.state(of: selection.reservation.physicalSlotID) == .vacant)
        #expect(registry.desiredState(for: currentDesired.sourceID) == .absent)
    }

    @Test("precommit failure releases reservation and rotates current desired to FIFO tail")
    func precommitFailureRotatesDesiredToTail() throws {
        // Arrange
        let registry = try makeRegistry(physicalSlotCount: 1)
        let firstDesired = try requireEnqueuedDesiredRegistration(
            registry.recordDesiredRegistration(
                makeRegistration(sourceOrdinal: 1, generation: 1)
            )
        )
        let secondDesired = try requireEnqueuedDesiredRegistration(
            registry.recordDesiredRegistration(
                makeRegistration(sourceOrdinal: 2, generation: 1)
            )
        )
        let failedSelection = try requireSelectedDesiredSource(
            registry.selectNextDesiredSource()
        )

        // Act
        let failureResult = registry.releaseSelectedReservationAfterFailure(
            failedSelection.reservation
        )
        let nextSelection = try requireSelectedDesiredSource(
            registry.selectNextDesiredSource()
        )

        // Assert
        #expect(failureResult == .releasedAndRotatedToDeferredTail(firstDesired))
        #expect(
            registry.deferredDesiredRegistrationsInFIFOOrder == [firstDesired]
        )
        #expect(nextSelection.desiredRegistration == secondDesired)
        #expect(
            nextSelection.reservation.physicalSlotID
                == failedSelection.reservation.physicalSlotID
        )
        #expect(nextSelection.reservation.identity != failedSelection.reservation.identity)
    }

    @Test("commit rejects withdrawn stale and foreign reservations")
    func commitmentRejectsNoncurrentReservations() throws {
        // Arrange
        let registry = try makeRegistry(physicalSlotCount: 1)
        let foreignRegistry = try makeRegistry(physicalSlotCount: 1)
        let withdrawnDesired = try requireEnqueuedDesiredRegistration(
            registry.recordDesiredRegistration(
                makeRegistration(sourceOrdinal: 1, generation: 1)
            )
        )
        let withdrawnSelection = try requireSelectedDesiredSource(
            registry.selectNextDesiredSource()
        )
        _ = registry.withdrawDesiredSource(
            sourceID: withdrawnDesired.sourceID,
            desiredIdentity: withdrawnDesired.identity
        )
        let currentDesired = try requireEnqueuedDesiredRegistration(
            registry.recordDesiredRegistration(
                makeRegistration(sourceOrdinal: 2, generation: 1)
            )
        )
        let currentSelection = try requireSelectedDesiredSource(
            registry.selectNextDesiredSource()
        )
        _ = foreignRegistry.recordDesiredRegistration(
            makeRegistration(sourceOrdinal: 3, generation: 1)
        )
        let foreignSelection = try requireSelectedDesiredSource(
            foreignRegistry.selectNextDesiredSource()
        )

        // Act / Assert
        #expect(
            registry.beginNativeLifetime(withdrawnSelection.reservation)
                == .staleReservation(currentSelection.reservation)
        )
        #expect(
            registry.beginNativeLifetime(foreignSelection.reservation) == .foreignFleet
        )
        #expect(
            registry.desiredState(for: currentDesired.sourceID)
                == .selected(currentSelection)
        )
    }

    @Test("starting native lifetime cannot release through reservation failure API")
    func startingNativeLifetimeCannotReleaseReservation() throws {
        // Arrange
        let registry = try makeRegistry(physicalSlotCount: 1)
        _ = registry.recordDesiredRegistration(makeRegistration(generation: 1))
        let selection = try requireSelectedDesiredSource(registry.selectNextDesiredSource())
        let startingNativeLifetime = try requireCommittedNativeLifetime(
            registry.beginNativeLifetime(selection.reservation)
        )

        // Act
        let result = registry.releaseSelectedReservationAfterFailure(selection.reservation)

        // Assert
        #expect(result == .nativeLifetimeAlreadyCommitted(startingNativeLifetime))
        #expect(
            registry.state(of: selection.reservation.physicalSlotID)
                == .starting(startingNativeLifetime)
        )
        #expect(
            registry.storedBindingCurrentness(of: startingNativeLifetime.binding)
                == .storedCurrent
        )
    }

    @Test("newest selected-source request is retained and blocks stale commitment")
    func selectedSourceRetainsNewestPendingConfiguration() throws {
        // Arrange
        let registry = try makeRegistry(physicalSlotCount: 1)
        _ = registry.recordDesiredRegistration(makeRegistration(generation: 1))
        let selection = try requireSelectedDesiredSource(registry.selectNextDesiredSource())

        // Act
        let updateResult = registry.recordDesiredRegistration(
            makeRegistration(generation: 2)
        )
        let commitmentResult = registry.beginNativeLifetime(selection.reservation)

        // Assert
        guard case .deferredToConfigurationCurrentness(let pendingDesired) = updateResult else {
            Issue.record("Expected newest selected-source request to be retained for D1c")
            return
        }
        #expect(
            registry.pendingConfigurationState(for: pendingDesired.sourceID)
                == .retained(pendingDesired)
        )
        #expect(commitmentResult == .deferredToConfigurationCurrentness(pendingDesired))
        #expect(
            registry.releaseSelectedReservationAfterFailure(selection.reservation)
                == .releasedAndRotatedToDeferredTail(pendingDesired)
        )
        #expect(registry.deferredDesiredRegistrationsInFIFOOrder == [pendingDesired])
    }

    @Test("starting withdrawal retains committed generation identity and retirement obligation")
    func startingWithdrawalRetainsGenerationRetirementObligation() throws {
        // Arrange
        let registry = try makeRegistry(physicalSlotCount: 1)
        let originalDesired = try requireEnqueuedDesiredRegistration(
            registry.recordDesiredRegistration(makeRegistration(generation: 1))
        )
        let selection = try requireSelectedDesiredSource(registry.selectNextDesiredSource())
        let startingNativeLifetime = try requireCommittedNativeLifetime(
            registry.beginNativeLifetime(selection.reservation)
        )
        let pendingUpdate = registry.recordDesiredRegistration(
            makeRegistration(generation: 2)
        )

        // Act
        let withdrawalResult = registry.withdrawDesiredSource(
            sourceID: originalDesired.sourceID,
            desiredIdentity: originalDesired.identity
        )

        // Assert
        guard case .deferredToConfigurationCurrentness(let pendingDesired) = pendingUpdate else {
            Issue.record("Expected newest starting-source request to be retained for D1c")
            return
        }
        guard case .retiringGeneration(.unpublished(let retiringNativeLifetime)) = withdrawalResult
        else {
            Issue.record("Expected exact starting lifetime to require retirement")
            return
        }
        let releaseResult = registry.releaseSelectedReservationAfterFailure(
            selection.reservation
        )
        #expect(retiringNativeLifetime.startingNativeLifetime == startingNativeLifetime)
        #expect(retiringNativeLifetime.cause == .desiredWithdrawn)
        #expect(
            registry.desiredState(for: originalDesired.sourceID)
                == .retiringGenerations(.oldest(.unpublished(retiringNativeLifetime)))
        )
        #expect(
            registry.state(of: startingNativeLifetime.binding.physicalSlotID)
                == .retiringUnpublishedGeneration(retiringNativeLifetime)
        )
        #expect(releaseResult == .nativeLifetimeAlreadyCommitted(startingNativeLifetime))
        #expect(registry.deferredDesiredRegistrationsInFIFOOrder.isEmpty)
        #expect(
            registry.pendingConfigurationState(for: originalDesired.sourceID)
                == .retained(pendingDesired)
        )
        #expect(
            registry.storedBindingCurrentness(of: startingNativeLifetime.binding)
                == .storedSuperseded
        )
    }
}

@Suite("Filesystem observation slot registry retirement lifecycle")
struct FilesystemObservationSlotRegistryTestsRetirement {
    @Test("postcommit create failure retires generation and rotates newest desired")
    func postcommitCreateFailureRetiresAndRotatesNewestDesired() throws {
        // Arrange
        let registry = try makeRegistry(physicalSlotCount: 2)
        _ = registry.recordDesiredRegistration(makeRegistration(generation: 1))
        let selection = try requireSelectedDesiredSource(registry.selectNextDesiredSource())
        let startingNativeLifetime = try requireCommittedNativeLifetime(
            registry.beginNativeLifetime(selection.reservation)
        )
        let pendingResult = registry.recordDesiredRegistration(
            makeRegistration(generation: 2)
        )
        guard case .deferredToConfigurationCurrentness(let newestDesired) = pendingResult else {
            Issue.record("Expected newest desired registration to wait for currentness")
            return
        }

        // Act
        let failureResult = registry.retireUnpublishedNativeGenerationAfterCreateOrStartFailure(
            startingNativeLifetime
        )

        // Assert
        guard case .retirementRequired(let retiringNativeLifetime) = failureResult else {
            Issue.record("Expected create failure to require unpublished-generation retirement")
            return
        }
        #expect(
            retiringNativeLifetime.cause == .nativeCreateOrStartFailed(newestDesired)
        )
        #expect(
            registry.state(of: startingNativeLifetime.binding.physicalSlotID)
                == .retiringUnpublishedGeneration(retiringNativeLifetime)
        )
        #expect(
            registry.deferredDesiredRegistrationsInFIFOOrder == [newestDesired]
        )
        #expect(registry.pendingConfigurationState(for: newestDesired.sourceID) == .absent)
        #expect(
            registry.releaseSelectedReservationAfterFailure(selection.reservation)
                == .nativeLifetimeAlreadyCommitted(startingNativeLifetime)
        )
        let replacementSelection = try requireSelectedDesiredSource(
            registry.selectNextDesiredSource()
        )
        #expect(replacementSelection.desiredRegistration == newestDesired)
        #expect(
            replacementSelection.reservation.physicalSlotID
                != startingNativeLifetime.binding.physicalSlotID
        )
    }

    @Test("two retiring generations preserve order and defer a third generation")
    func twoRetiringGenerationsPreserveOrderAndDeferThirdGeneration() throws {
        // Arrange
        let fixture = try makeTwoRetiringGenerationsFixture()

        // Act
        let replayedOldestFailure =
            fixture.registry.retireUnpublishedNativeGenerationAfterCreateOrStartFailure(
                fixture.oldestStartingNativeLifetime
            )
        let replayedSuccessorFailure =
            fixture.registry.retireUnpublishedNativeGenerationAfterCreateOrStartFailure(
                fixture.successorStartingNativeLifetime
            )
        let thirdSelectionResult = fixture.registry.selectNextDesiredSource()
        let thirdPhysicalSlotID = try #require(
            fixture.registry.physicalSlotIDs.first { physicalSlotID in
                physicalSlotID != fixture.oldestStartingNativeLifetime.binding.physicalSlotID
                    && physicalSlotID
                        != fixture.successorStartingNativeLifetime.binding.physicalSlotID
            }
        )

        // Assert
        #expect(
            fixture.oldestStartingNativeLifetime.binding.physicalSlotID
                != fixture.successorStartingNativeLifetime.binding.physicalSlotID
        )
        #expect(
            fixture.oldestStartingNativeLifetime.binding.identity
                != fixture.successorStartingNativeLifetime.binding.identity
        )
        #expect(
            fixture.oldestStartingNativeLifetime.nativeGenerationIdentity
                != fixture.successorStartingNativeLifetime.nativeGenerationIdentity
        )
        #expect(
            fixture.registry.state(of: fixture.oldestStartingNativeLifetime.binding.physicalSlotID)
                == .retiringUnpublishedGeneration(fixture.oldestRetirement)
        )
        #expect(
            fixture.registry.state(
                of: fixture.successorStartingNativeLifetime.binding.physicalSlotID
            ) == .retiringUnpublishedGeneration(fixture.successorRetirement)
        )
        #expect(
            replayedOldestFailure
                == .alreadyRetirementRequired(fixture.oldestRetirement)
        )
        #expect(
            replayedSuccessorFailure
                == .alreadyRetirementRequired(fixture.successorRetirement)
        )
        #expect(
            fixture.registry.retiringGenerationChain(
                for: fixture.newestDesired.sourceID
            ) == fixture.fullRetirementChain
        )
        #expect(
            fixture.registry.deferredDesiredRegistrationsInFIFOOrder
                == [fixture.newestDesired]
        )
        #expect(
            thirdSelectionResult
                == .deferredBehindRetiringGenerationLimit(
                    oldest: .unpublished(fixture.oldestRetirement),
                    successor: .unpublished(fixture.successorRetirement)
                )
        )
        #expect(fixture.registry.state(of: thirdPhysicalSlotID) == .vacant)
    }

    @Test("full retirement chain does not block an unrelated eligible source")
    func fullRetirementChainPreservesFleetFairness() throws {
        // Arrange
        let fixture = try makeTwoRetiringGenerationsFixture()
        let unrelatedDesired = try requireEnqueuedDesiredRegistration(
            fixture.registry.recordDesiredRegistration(
                makeRegistration(sourceOrdinal: 2, generation: 1)
            )
        )

        // Act
        let deferredBeforeSelection =
            fixture.registry.deferredDesiredRegistrationsInFIFOOrder
        let unrelatedSelection = try requireSelectedDesiredSource(
            fixture.registry.selectNextDesiredSource()
        )

        // Assert
        #expect(deferredBeforeSelection == [fixture.newestDesired, unrelatedDesired])
        #expect(unrelatedSelection.desiredRegistration == unrelatedDesired)
        #expect(
            unrelatedSelection.reservation.physicalSlotID
                != fixture.oldestStartingNativeLifetime.binding.physicalSlotID
        )
        #expect(
            unrelatedSelection.reservation.physicalSlotID
                != fixture.successorStartingNativeLifetime.binding.physicalSlotID
        )
        #expect(
            fixture.registry.deferredDesiredRegistrationsInFIFOOrder
                == [fixture.newestDesired]
        )
        #expect(
            fixture.registry.retiringGenerationChain(
                for: fixture.newestDesired.sourceID
            ) == fixture.fullRetirementChain
        )
        #expect(
            fixture.registry.state(of: unrelatedSelection.reservation.physicalSlotID)
                == .selected(unrelatedSelection)
        )
    }

    @Test("withdrawn generation failure is already retiring and never requeues")
    func withdrawnGenerationFailureDoesNotRequeue() throws {
        // Arrange
        let registry = try makeRegistry(physicalSlotCount: 1)
        let desiredRegistration = try requireEnqueuedDesiredRegistration(
            registry.recordDesiredRegistration(makeRegistration(generation: 1))
        )
        let selection = try requireSelectedDesiredSource(registry.selectNextDesiredSource())
        let startingNativeLifetime = try requireCommittedNativeLifetime(
            registry.beginNativeLifetime(selection.reservation)
        )
        let withdrawalResult = registry.withdrawDesiredSource(
            sourceID: desiredRegistration.sourceID,
            desiredIdentity: desiredRegistration.identity
        )
        guard case .retiringGeneration(.unpublished(let retiringNativeLifetime)) = withdrawalResult
        else {
            Issue.record("Expected withdrawal to require unpublished-generation retirement")
            return
        }

        // Act
        let firstFailureResult =
            registry.retireUnpublishedNativeGenerationAfterCreateOrStartFailure(
                startingNativeLifetime
            )
        let repeatedFailureResult =
            registry.retireUnpublishedNativeGenerationAfterCreateOrStartFailure(
                startingNativeLifetime
            )

        // Assert
        #expect(firstFailureResult == .alreadyRetirementRequired(retiringNativeLifetime))
        #expect(repeatedFailureResult == .alreadyRetirementRequired(retiringNativeLifetime))
        #expect(registry.deferredDesiredRegistrationsInFIFOOrder.isEmpty)
        #expect(
            registry.state(of: startingNativeLifetime.binding.physicalSlotID)
                == .retiringUnpublishedGeneration(retiringNativeLifetime)
        )
    }

    @Test("postcommit failure rejects foreign fleet lifetime")
    func postcommitFailureRejectsForeignFleet() throws {
        // Arrange
        let registry = try makeRegistry(physicalSlotCount: 1)
        let foreignRegistry = try makeRegistry(physicalSlotCount: 1)
        _ = foreignRegistry.recordDesiredRegistration(makeRegistration(generation: 1))
        let foreignSelection = try requireSelectedDesiredSource(
            foreignRegistry.selectNextDesiredSource()
        )
        let foreignStartingNativeLifetime = try requireCommittedNativeLifetime(
            foreignRegistry.beginNativeLifetime(foreignSelection.reservation)
        )

        // Act
        let result = registry.retireUnpublishedNativeGenerationAfterCreateOrStartFailure(
            foreignStartingNativeLifetime
        )

        // Assert
        #expect(result == .foreignFleet)
    }

    @Test("pending configuration desired identity withdraws without releasing selection")
    func pendingConfigurationWithdrawalPreservesSelection() throws {
        // Arrange
        let registry = try makeRegistry(physicalSlotCount: 1)
        _ = registry.recordDesiredRegistration(makeRegistration(generation: 1))
        let selection = try requireSelectedDesiredSource(registry.selectNextDesiredSource())
        let updateResult = registry.recordDesiredRegistration(
            makeRegistration(generation: 2)
        )
        guard case .deferredToConfigurationCurrentness(let pendingDesired) = updateResult else {
            Issue.record("Expected pending configuration desired identity")
            return
        }

        // Act
        let withdrawalResult = registry.withdrawDesiredSource(
            sourceID: pendingDesired.sourceID,
            desiredIdentity: pendingDesired.identity
        )

        // Assert
        #expect(withdrawalResult == .withdrewPendingConfiguration(pendingDesired))
        #expect(registry.pendingConfigurationState(for: pendingDesired.sourceID) == .absent)
        #expect(registry.desiredState(for: pendingDesired.sourceID) == .selected(selection))
        #expect(
            registry.state(of: selection.reservation.physicalSlotID) == .selected(selection)
        )
    }
}
