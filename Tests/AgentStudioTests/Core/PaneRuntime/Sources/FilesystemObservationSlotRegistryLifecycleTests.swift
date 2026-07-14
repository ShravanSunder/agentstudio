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
            registry.installTestConfiguration(makeRegistration(generation: 1))
        )
        let currentDesired = try requireReplacedDesiredRegistration(
            registry.installTestConfiguration(makeRegistration(generation: 2))
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
        #expect(registry.read.state(of: selection.reservation.physicalSlotID) == .vacant)
        #expect(registry.read.desiredState(for: currentDesired.sourceID) == .absent)
    }

    @Test("precommit failure releases reservation and rotates current desired to FIFO tail")
    func precommitFailureRotatesDesiredToTail() throws {
        // Arrange
        let registry = try makeRegistry(physicalSlotCount: 1)
        let firstDesired = try requireEnqueuedDesiredRegistration(
            registry.installTestConfiguration(
                makeRegistration(sourceOrdinal: 1, generation: 1)
            )
        )
        let secondDesired = try requireEnqueuedDesiredRegistration(
            registry.installTestConfiguration(
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
            registry.read.deferredDesiredRegistrationsInFIFOOrder == [firstDesired]
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
            registry.installTestConfiguration(
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
            registry.installTestConfiguration(
                makeRegistration(sourceOrdinal: 2, generation: 1)
            )
        )
        let currentSelection = try requireSelectedDesiredSource(
            registry.selectNextDesiredSource()
        )
        _ = foreignRegistry.installTestConfiguration(
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
            registry.read.desiredState(for: currentDesired.sourceID)
                == .selected(currentSelection)
        )
    }

    @Test("starting native lifetime cannot release through reservation failure API")
    func startingNativeLifetimeCannotReleaseReservation() throws {
        // Arrange
        let registry = try makeRegistry(physicalSlotCount: 1)
        _ = registry.installTestConfiguration(makeRegistration(generation: 1))
        let selection = try requireSelectedDesiredSource(registry.selectNextDesiredSource())
        let startingNativeLifetime = try requireCommittedNativeLifetime(
            registry.beginNativeLifetime(selection.reservation)
        )

        // Act
        let result = registry.releaseSelectedReservationAfterFailure(selection.reservation)

        // Assert
        #expect(result == .nativeLifetimeAlreadyCommitted(startingNativeLifetime))
        #expect(
            registry.read.state(of: selection.reservation.physicalSlotID)
                == .starting(startingNativeLifetime)
        )
        #expect(
            registry.read.storedBindingCurrentness(of: startingNativeLifetime.binding)
                == .storedCurrent
        )
    }

    @Test("newest selected-source request is retained and blocks stale commitment")
    func selectedSourceRetainsNewestPendingConfiguration() throws {
        // Arrange
        let registry = try makeRegistry(physicalSlotCount: 1)
        _ = registry.installTestConfiguration(makeRegistration(generation: 1))
        let selection = try requireSelectedDesiredSource(registry.selectNextDesiredSource())

        // Act
        let updateResult = registry.installTestConfiguration(
            makeRegistration(generation: 2)
        )
        let commitmentResult = registry.beginNativeLifetime(selection.reservation)

        // Assert
        guard case .deferredToConfigurationCurrentness(let pendingDesired) = updateResult else {
            Issue.record("Expected newest selected-source request to be retained for D1c")
            return
        }
        #expect(
            registry.read.pendingConfigurationState(for: pendingDesired.sourceID)
                == .retained(pendingDesired)
        )
        #expect(commitmentResult == .deferredToConfigurationCurrentness(pendingDesired))
        #expect(
            registry.releaseSelectedReservationAfterFailure(selection.reservation)
                == .releasedAndRotatedToDeferredTail(pendingDesired)
        )
        #expect(registry.read.deferredDesiredRegistrationsInFIFOOrder == [pendingDesired])
    }

    @Test("starting withdrawal awaits accepting publication with exact committed identity")
    func startingWithdrawalAwaitsAcceptingPublication() throws {
        // Arrange
        let registry = try makeRegistry(physicalSlotCount: 1)
        let originalDesired = try requireEnqueuedDesiredRegistration(
            registry.installTestConfiguration(makeRegistration(generation: 1))
        )
        let selection = try requireSelectedDesiredSource(registry.selectNextDesiredSource())
        let startingNativeLifetime = try requireCommittedNativeLifetime(
            registry.beginNativeLifetime(selection.reservation)
        )
        let pendingUpdate = registry.installTestConfiguration(
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
        guard case .awaitingAcceptingPublication(let awaitingLifetime) = withdrawalResult else {
            Issue.record("Expected successful-start publication to remain authoritative")
            return
        }
        let releaseResult = registry.releaseSelectedReservationAfterFailure(
            selection.reservation
        )
        #expect(awaitingLifetime.startingNativeLifetime == startingNativeLifetime)
        #expect(
            registry.read.desiredState(for: originalDesired.sourceID)
                == .starting(startingNativeLifetime)
        )
        #expect(
            registry.read.state(of: startingNativeLifetime.binding.physicalSlotID)
                == .starting(startingNativeLifetime)
        )
        #expect(releaseResult == .nativeLifetimeAlreadyCommitted(startingNativeLifetime))
        #expect(registry.read.deferredDesiredRegistrationsInFIFOOrder.isEmpty)
        #expect(
            registry.read.pendingConfigurationState(for: originalDesired.sourceID)
                == .retained(pendingDesired)
        )
        #expect(
            registry.read.storedBindingCurrentness(of: startingNativeLifetime.binding)
                == .storedCurrent
        )
    }
}

@Suite("Filesystem observation slot registry retirement lifecycle")
struct FilesystemObservationSlotRegistryTestsRetirement {
    @Test("postcommit create failure retains repair custody and rotates newest desired")
    func postcommitCreateFailureRetainsRepairAndRotatesNewestDesired() throws {
        // Arrange
        let registry = try makeRegistry(physicalSlotCount: 2)
        _ = registry.installTestConfiguration(makeRegistration(generation: 1))
        let selection = try requireSelectedDesiredSource(registry.selectNextDesiredSource())
        let startingNativeLifetime = try requireCommittedNativeLifetime(
            registry.beginNativeLifetime(selection.reservation)
        )
        let pendingResult = registry.installTestConfiguration(
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
            registry.read.state(of: startingNativeLifetime.binding.physicalSlotID)
                == .retiringUnpublishedGeneration(retiringNativeLifetime)
        )
        #expect(
            registry.read.deferredDesiredRegistrationsInFIFOOrder == [newestDesired]
        )
        #expect(
            registry.read.pendingConfigurationState(for: newestDesired.sourceID)
                == .retained(newestDesired)
        )
        guard
            case .pending(let repairAuthority) =
                registry.read.pendingContinuityRepairState(for: newestDesired.sourceID)
        else {
            Issue.record("Expected failed installation to retain continuity-repair custody")
            return
        }
        #expect(repairAuthority.identity.isUUIDv7)
        #expect(repairAuthority.desiredIdentity == newestDesired.identity)
        #expect(repairAuthority.desiredConfiguration == newestDesired.configuration)
        #expect(repairAuthority.cause == .nativeCreateOrStartFailure)
        #expect(
            repairAuthority.recoveryRevision.value
                == newestDesired.acceptedTopologyRevision.value
        )
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
            fixture.registry.read.state(of: fixture.oldestStartingNativeLifetime.binding.physicalSlotID)
                == .retiringUnpublishedGeneration(fixture.oldestRetirement)
        )
        #expect(
            fixture.registry.read.state(
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
            fixture.registry.read.retiringGenerationChain(
                for: fixture.newestDesired.sourceID
            ) == fixture.fullRetirementChain
        )
        #expect(
            fixture.registry.read.deferredDesiredRegistrationsInFIFOOrder
                == [fixture.newestDesired]
        )
        #expect(
            thirdSelectionResult
                == .deferredBehindRetiringGenerationLimit(
                    oldest: .unpublished(fixture.oldestRetirement),
                    successor: .unpublished(fixture.successorRetirement)
                )
        )
        #expect(fixture.registry.read.state(of: thirdPhysicalSlotID) == .vacant)
    }

    @Test("full retirement chain does not block an unrelated eligible source")
    func fullRetirementChainPreservesFleetFairness() throws {
        // Arrange
        let fixture = try makeTwoRetiringGenerationsFixture()
        let unrelatedDesired = try requireEnqueuedDesiredRegistration(
            fixture.registry.installTestConfiguration(
                makeRegistration(sourceOrdinal: 2, generation: 1)
            )
        )

        // Act
        let deferredBeforeSelection =
            fixture.registry.read.deferredDesiredRegistrationsInFIFOOrder
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
            fixture.registry.read.deferredDesiredRegistrationsInFIFOOrder
                == [fixture.newestDesired]
        )
        #expect(
            fixture.registry.read.retiringGenerationChain(
                for: fixture.newestDesired.sourceID
            ) == fixture.fullRetirementChain
        )
        #expect(
            fixture.registry.read.state(of: unrelatedSelection.reservation.physicalSlotID)
                == .selected(unrelatedSelection)
        )
    }

    @Test("withdrawn starting failure retires once and never requeues")
    func withdrawnStartingFailureRetiresOnceWithoutRequeue() throws {
        // Arrange
        let registry = try makeRegistry(physicalSlotCount: 1)
        let desiredRegistration = try requireEnqueuedDesiredRegistration(
            registry.installTestConfiguration(makeRegistration(generation: 1))
        )
        let selection = try requireSelectedDesiredSource(registry.selectNextDesiredSource())
        let startingNativeLifetime = try requireCommittedNativeLifetime(
            registry.beginNativeLifetime(selection.reservation)
        )
        let withdrawalResult = registry.withdrawDesiredSource(
            sourceID: desiredRegistration.sourceID,
            desiredIdentity: desiredRegistration.identity
        )
        guard case .awaitingAcceptingPublication(let awaitingLifetime) = withdrawalResult else {
            Issue.record("Expected withdrawal to preserve successful-start publication authority")
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
        guard case .retirementRequired(let retiringNativeLifetime) = firstFailureResult else {
            Issue.record("Expected failed withdrawn start to require exact unpublished retirement")
            return
        }
        #expect(awaitingLifetime.startingNativeLifetime == startingNativeLifetime)
        #expect(retiringNativeLifetime.startingNativeLifetime == startingNativeLifetime)
        #expect(retiringNativeLifetime.cause == .desiredWithdrawn)
        #expect(repeatedFailureResult == .alreadyRetirementRequired(retiringNativeLifetime))
        #expect(registry.read.deferredDesiredRegistrationsInFIFOOrder.isEmpty)
        #expect(
            registry.read.state(of: startingNativeLifetime.binding.physicalSlotID)
                == .retiringUnpublishedGeneration(retiringNativeLifetime)
        )
    }

    @Test("postcommit failure rejects foreign fleet lifetime")
    func postcommitFailureRejectsForeignFleet() throws {
        // Arrange
        let registry = try makeRegistry(physicalSlotCount: 1)
        let foreignRegistry = try makeRegistry(physicalSlotCount: 1)
        _ = foreignRegistry.installTestConfiguration(makeRegistration(generation: 1))
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
        _ = registry.installTestConfiguration(makeRegistration(generation: 1))
        let selection = try requireSelectedDesiredSource(registry.selectNextDesiredSource())
        let updateResult = registry.installTestConfiguration(
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
        #expect(registry.read.pendingConfigurationState(for: pendingDesired.sourceID) == .absent)
        #expect(registry.read.desiredState(for: pendingDesired.sourceID) == .selected(selection))
        #expect(
            registry.read.state(of: selection.reservation.physicalSlotID) == .selected(selection)
        )
    }
}
