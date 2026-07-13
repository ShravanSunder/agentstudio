import Foundation
import Testing

@testable import AgentStudio

@Suite("Filesystem observation slot registry")
struct FilesystemObservationSlotRegistryTests {
    @Test("fixed pool cardinality is maximum sources plus replacement reserve")
    func fixedPoolCardinalityAndIdentities() throws {
        // Arrange
        let registry = try FilesystemObservationSlotRegistry(
            maximumSimultaneousSourceCount: 3,
            replacementReserveSlotCount: 2
        )

        // Act
        let physicalSlotIDs = registry.physicalSlotIDs
        let sourceOffsets = 0..<registry.maximumSimultaneousSourceCount
        let startingNativeLifetimes = try sourceOffsets.map { sourceOffset in
            _ = registry.recordDesiredRegistration(
                makeRegistration(sourceOrdinal: sourceOffset + 1, generation: 1)
            )
            let selection = try requireSelectedDesiredSource(
                registry.selectNextDesiredSource()
            )
            return try requireCommittedNativeLifetime(
                registry.beginNativeLifetime(selection.reservation)
            )
        }
        let bindings = startingNativeLifetimes.map(\.binding)

        // Assert
        #expect(registry.maximumSimultaneousSourceCount == 3)
        #expect(registry.replacementReserveSlotCount == 2)
        #expect(registry.physicalSlotCount == 5)
        #expect(physicalSlotIDs.count == 5)
        #expect(Set(physicalSlotIDs).count == 5)
        #expect(registry.fleetMailboxIdentity.isUUIDv7)
        #expect(physicalSlotIDs.allSatisfy { $0.isUUIDv7 })
        #expect(Set(bindings.map(\.identity)).count == 3)
        #expect(bindings.allSatisfy { $0.identity.isUUIDv7 })
        #expect(Set(bindings.map(\.controlBlockIdentity)).count == 3)
        #expect(bindings.allSatisfy { $0.controlBlockIdentity.isUUIDv7 })
        #expect(
            physicalSlotIDs.filter { physicalSlotID in
                registry.state(of: physicalSlotID) == .vacant
            }.count == 2
        )
    }

    @Test("exact selected reservation atomically commits one complete UUIDv7 binding")
    func selectedReservationCommitsCompleteBinding() throws {
        // Arrange
        let registry = try makeRegistry(physicalSlotCount: 1)
        let registration = makeRegistration(generation: 7)
        let desiredRegistration = try requireEnqueuedDesiredRegistration(
            registry.recordDesiredRegistration(registration)
        )
        let selection = try requireSelectedDesiredSource(registry.selectNextDesiredSource())

        // Act
        let result = registry.beginNativeLifetime(selection.reservation)

        // Assert
        guard case .committed(let startingNativeLifetime) = result else {
            Issue.record("Expected exact selected reservation to commit native lifetime")
            return
        }
        let binding = startingNativeLifetime.binding
        #expect(selection.desiredRegistration == desiredRegistration)
        #expect(selection.reservation.desiredIdentity == desiredRegistration.identity)
        #expect(binding.fleetMailboxIdentity == registry.fleetMailboxIdentity)
        #expect(binding.physicalSlotID == selection.reservation.physicalSlotID)
        #expect(binding.registration == registration)
        #expect(binding.identity.isUUIDv7)
        #expect(binding.controlBlockIdentity.isUUIDv7)
        #expect(startingNativeLifetime.nativeGenerationIdentity.isUUIDv7)
        #expect(registry.storedBindingCurrentness(of: binding) == .storedCurrent)
        #expect(
            registry.state(of: selection.reservation.physicalSlotID)
                == .starting(startingNativeLifetime)
        )
    }

    @Test("double commitment is typed already committed and preserves exact binding")
    func doubleCommitmentPreservesExactBinding() throws {
        // Arrange
        let registry = try makeRegistry(physicalSlotCount: 1)
        _ = registry.recordDesiredRegistration(makeRegistration(generation: 11))
        let selection = try requireSelectedDesiredSource(registry.selectNextDesiredSource())
        let startingNativeLifetime = try requireCommittedNativeLifetime(
            registry.beginNativeLifetime(selection.reservation)
        )

        // Act
        let secondResult = registry.beginNativeLifetime(selection.reservation)

        // Assert
        #expect(secondResult == .alreadyCommitted(startingNativeLifetime))
        #expect(
            registry.storedBindingCurrentness(of: startingNativeLifetime.binding)
                == .storedCurrent
        )
        #expect(
            registry.state(of: selection.reservation.physicalSlotID)
                == .starting(startingNativeLifetime)
        )
    }

    @Test("slot and binding classifications distinguish undeclared vacant current and foreign")
    func classificationUsesClosedResults() throws {
        // Arrange
        let registry = try makeRegistry(physicalSlotCount: 2)
        let foreignRegistry = try makeRegistry(physicalSlotCount: 1)
        let vacantSlotID = try #require(registry.physicalSlotIDs.last)
        _ = registry.recordDesiredRegistration(makeRegistration(generation: 17))
        let currentSelection = try requireSelectedDesiredSource(
            registry.selectNextDesiredSource()
        )
        let currentStarting = try requireCommittedNativeLifetime(
            registry.beginNativeLifetime(currentSelection.reservation)
        )
        _ = foreignRegistry.recordDesiredRegistration(makeRegistration(generation: 18))
        let foreignSelection = try requireSelectedDesiredSource(
            foreignRegistry.selectNextDesiredSource()
        )
        let foreignStarting = try requireCommittedNativeLifetime(
            foreignRegistry.beginNativeLifetime(foreignSelection.reservation)
        )

        // Act / Assert
        #expect(registry.fleetMailboxIdentity != foreignRegistry.fleetMailboxIdentity)
        #expect(registry.state(of: vacantSlotID) == .vacant)
        #expect(
            registry.state(of: foreignSelection.reservation.physicalSlotID)
                == .undeclaredPhysicalSlot
        )
        #expect(
            registry.storedBindingCurrentness(of: currentStarting.binding) == .storedCurrent
        )
        #expect(registry.storedBindingCurrentness(of: foreignStarting.binding) == .foreignFleet)
    }

    @Test("invalid capacity inputs fail with exact configuration results")
    func invalidCapacityIsRejected() {
        #expect(throws: FilesystemObservationSlotConfigurationError.self) {
            try FilesystemObservationSlotRegistry(
                maximumSimultaneousSourceCount: 0,
                replacementReserveSlotCount: 1
            )
        }
        #expect(throws: FilesystemObservationSlotConfigurationError.self) {
            try FilesystemObservationSlotRegistry(
                maximumSimultaneousSourceCount: 1,
                replacementReserveSlotCount: -1
            )
        }
    }

    @Test("desired FIFO selects each zero-based rank within q plus one selections")
    func desiredFIFOSelectionFairness() throws {
        // Arrange
        let registry = try makeRegistry(physicalSlotCount: 1)
        let deliberatelyNonUUIDSortedSourceOrdinals = [3, 1, 2]
        let desiredRegistrations = try deliberatelyNonUUIDSortedSourceOrdinals.map { sourceOrdinal in
            try requireEnqueuedDesiredRegistration(
                registry.recordDesiredRegistration(
                    makeRegistration(sourceOrdinal: sourceOrdinal, generation: 1)
                )
            )
        }

        // Act
        let firstSelection = try requireSelectedDesiredSource(
            registry.selectNextDesiredSource()
        )
        _ = registry.releaseSelectedReservationAfterFailure(firstSelection.reservation)
        let secondSelection = try requireSelectedDesiredSource(
            registry.selectNextDesiredSource()
        )
        _ = registry.releaseSelectedReservationAfterFailure(secondSelection.reservation)
        let thirdSelection = try requireSelectedDesiredSource(
            registry.selectNextDesiredSource()
        )
        let selections = [firstSelection, secondSelection, thirdSelection]

        // Assert
        #expect(Set(desiredRegistrations.map { $0.identity }).count == 3)
        #expect(desiredRegistrations.allSatisfy { $0.identity.isUUIDv7 })
        #expect(selections.map { $0.desiredRegistration } == desiredRegistrations)
        #expect(Set(selections.map { $0.reservation.identity }).count == 3)
        #expect(selections.allSatisfy { $0.reservation.identity.isUUIDv7 })
        #expect(Set(selections.map { $0.reservation.physicalSlotID }).count == 1)
        #expect(
            registry.deferredDesiredRegistrationsInFIFOOrder
                == Array(desiredRegistrations[0...1])
        )
    }

    @Test("N plus three and N plus four overwrite deferred payload without rank change")
    func deferredOverwritePreservesQueueRank() throws {
        // Arrange
        let registry = try makeRegistry(physicalSlotCount: 3)
        let firstRegistration = makeRegistration(sourceOrdinal: 1, generation: 1)
        let middleRegistration = makeRegistration(sourceOrdinal: 2, generation: 1)
        let lastRegistration = makeRegistration(sourceOrdinal: 3, generation: 1)
        _ = registry.recordDesiredRegistration(firstRegistration)
        let originalMiddle = try requireEnqueuedDesiredRegistration(
            registry.recordDesiredRegistration(middleRegistration)
        )
        _ = registry.recordDesiredRegistration(lastRegistration)

        // Act
        let desiredNPlusThree = try requireReplacedDesiredRegistration(
            registry.recordDesiredRegistration(
                makeRegistration(sourceOrdinal: 2, generation: 3)
            )
        )
        let desiredNPlusFour = try requireReplacedDesiredRegistration(
            registry.recordDesiredRegistration(
                makeRegistration(sourceOrdinal: 2, generation: 4)
            )
        )

        // Assert
        #expect(originalMiddle.identity != desiredNPlusThree.identity)
        #expect(desiredNPlusThree.identity != desiredNPlusFour.identity)
        #expect(desiredNPlusFour.registration.registrationGeneration == 4)
        #expect(
            registry.deferredDesiredRegistrationsInFIFOOrder.map { $0.sourceID }
                == [
                    firstRegistration.sourceID, middleRegistration.sourceID,
                    lastRegistration.sourceID,
                ]
        )
        #expect(registry.deferredDesiredRegistrationsInFIFOOrder[1] == desiredNPlusFour)
    }

    @Test("active source capacity preserves physical reserve for replacement overlap")
    func activeSourceCapacityPreservesReplacementReserve() throws {
        for replacementReserveSlotCount in [0, 1, 2, 3] {
            // Arrange
            let maximumSourceCount = 3
            let registry = try FilesystemObservationSlotRegistry(
                maximumSimultaneousSourceCount: maximumSourceCount,
                replacementReserveSlotCount: replacementReserveSlotCount
            )
            for sourceOrdinal in 1...(maximumSourceCount + 1) {
                _ = registry.recordDesiredRegistration(
                    makeRegistration(sourceOrdinal: sourceOrdinal, generation: 1)
                )
            }

            // Act
            let successfulSelections = try (1...maximumSourceCount).map { _ in
                try requireSelectedDesiredSource(registry.selectNextDesiredSource())
            }
            let capacityResult = registry.selectNextDesiredSource()

            // Assert
            #expect(successfulSelections.count == maximumSourceCount)
            #expect(capacityResult == .deferredBehindActiveSourceCapacity)
            #expect(registry.deferredDesiredRegistrationsInFIFOOrder.count == 1)

            let occupiedSlotIDs = Set(successfulSelections.map(\.reservation.physicalSlotID))
            #expect(occupiedSlotIDs.count == maximumSourceCount)
            #expect(
                registry.physicalSlotIDs.filter { physicalSlotID in
                    registry.state(of: physicalSlotID) == .vacant
                }.count == replacementReserveSlotCount
            )
        }

        let replacementRegistry = try FilesystemObservationSlotRegistry(
            maximumSimultaneousSourceCount: 1,
            replacementReserveSlotCount: 1
        )
        _ = replacementRegistry.recordDesiredRegistration(makeRegistration(generation: 1))
        let originalSelection = try requireSelectedDesiredSource(
            replacementRegistry.selectNextDesiredSource()
        )
        let originalStartingNativeLifetime = try requireCommittedNativeLifetime(
            replacementRegistry.beginNativeLifetime(originalSelection.reservation)
        )
        let unrelatedDesired = try requireEnqueuedDesiredRegistration(
            replacementRegistry.recordDesiredRegistration(
                makeRegistration(sourceOrdinal: 2, generation: 1)
            )
        )
        _ = replacementRegistry.recordDesiredRegistration(makeRegistration(generation: 2))
        _ = try requireRetirementRequired(
            replacementRegistry.retireUnpublishedNativeGenerationAfterCreateOrStartFailure(
                originalStartingNativeLifetime
            )
        )

        let deferredBeforeReplacementSelection =
            replacementRegistry.deferredDesiredRegistrationsInFIFOOrder
        let replacementSelection = try requireSelectedDesiredSource(
            replacementRegistry.selectNextDesiredSource()
        )
        let unrelatedCapacityResult = replacementRegistry.selectNextDesiredSource()

        #expect(deferredBeforeReplacementSelection.first == unrelatedDesired)
        #expect(
            replacementSelection.desiredRegistration.sourceID
                == originalStartingNativeLifetime.desiredRegistration.sourceID
        )
        #expect(
            replacementSelection.reservation.physicalSlotID
                != originalStartingNativeLifetime.binding.physicalSlotID
        )
        #expect(unrelatedCapacityResult == .deferredBehindActiveSourceCapacity)
        #expect(
            replacementRegistry.deferredDesiredRegistrationsInFIFOOrder == [unrelatedDesired]
        )
    }

    @Test("deferred withdrawal distinguishes stale exact and absent identities")
    func deferredWithdrawalIsExact() throws {
        // Arrange
        let registry = try makeRegistry(physicalSlotCount: 1)
        let originalDesired = try requireEnqueuedDesiredRegistration(
            registry.recordDesiredRegistration(makeRegistration(generation: 1))
        )
        let currentDesired = try requireReplacedDesiredRegistration(
            registry.recordDesiredRegistration(makeRegistration(generation: 2))
        )

        // Act
        let staleResult = registry.withdrawDesiredSource(
            sourceID: currentDesired.sourceID,
            desiredIdentity: originalDesired.identity
        )
        let exactResult = registry.withdrawDesiredSource(
            sourceID: currentDesired.sourceID,
            desiredIdentity: currentDesired.identity
        )
        let absentResult = registry.withdrawDesiredSource(
            sourceID: currentDesired.sourceID,
            desiredIdentity: currentDesired.identity
        )

        // Assert
        #expect(staleResult == .staleDesiredIdentity(currentDesired.identity))
        #expect(exactResult == .withdrewDeferred(currentDesired))
        #expect(absentResult == .alreadyAbsent)
        #expect(registry.desiredState(for: currentDesired.sourceID) == .absent)
    }

}

func makeRegistry(
    physicalSlotCount: Int
) throws -> FilesystemObservationSlotRegistry {
    try FilesystemObservationSlotRegistry(
        maximumSimultaneousSourceCount: physicalSlotCount,
        replacementReserveSlotCount: 0
    )
}

func makeTwoRetiringGenerationsFixture() throws
    -> FilesystemObservationTwoRetiringGenerationsFixture
{
    let registry = try makeRegistry(physicalSlotCount: 3)
    _ = registry.recordDesiredRegistration(makeRegistration(generation: 1))
    let oldestSelection = try requireSelectedDesiredSource(
        registry.selectNextDesiredSource()
    )
    let oldestStartingNativeLifetime = try requireCommittedNativeLifetime(
        registry.beginNativeLifetime(oldestSelection.reservation)
    )
    _ = registry.recordDesiredRegistration(makeRegistration(generation: 2))
    let oldestRetirement = try requireRetirementRequired(
        registry.retireUnpublishedNativeGenerationAfterCreateOrStartFailure(
            oldestStartingNativeLifetime
        )
    )
    let successorSelection = try requireSelectedDesiredSource(
        registry.selectNextDesiredSource()
    )
    let successorStartingNativeLifetime = try requireCommittedNativeLifetime(
        registry.beginNativeLifetime(successorSelection.reservation)
    )
    let newestUpdate = registry.recordDesiredRegistration(
        makeRegistration(generation: 3)
    )
    guard case .deferredToConfigurationCurrentness(let newestDesired) = newestUpdate
    else {
        throw FilesystemObservationSlotRegistryTestError.expectedPendingDesiredRegistration
    }
    let successorRetirement = try requireRetirementRequired(
        registry.retireUnpublishedNativeGenerationAfterCreateOrStartFailure(
            successorStartingNativeLifetime
        )
    )
    return FilesystemObservationTwoRetiringGenerationsFixture(
        registry: registry,
        oldestStartingNativeLifetime: oldestStartingNativeLifetime,
        successorStartingNativeLifetime: successorStartingNativeLifetime,
        oldestRetirement: oldestRetirement,
        successorRetirement: successorRetirement,
        newestDesired: newestDesired,
        fullRetirementChain: .oldestAndSuccessor(
            oldest: oldestRetirement,
            successor: successorRetirement
        )
    )
}

func makeRegistration(
    sourceOrdinal: Int = 1,
    generation: UInt64
) -> FSEventRegistrationToken {
    FSEventRegistrationToken(
        sourceID: FilesystemSourceID(
            kind: .registeredWorktreeContent,
            rootID: UUID(
                uuidString: String(
                    format: "00000000-0000-0000-0000-%012d",
                    sourceOrdinal
                )
            )!
        ),
        registrationGeneration: generation,
        rootGeneration: generation
    )
}

func requireEnqueuedDesiredRegistration(
    _ result: FilesystemObservationDesiredUpdateResult
) throws -> FilesystemObservationDesiredRegistration {
    guard case .enqueued(let desiredRegistration) = result else {
        throw FilesystemObservationSlotRegistryTestError.expectedEnqueuedDesiredRegistration
    }
    return desiredRegistration
}

func requireReplacedDesiredRegistration(
    _ result: FilesystemObservationDesiredUpdateResult
) throws -> FilesystemObservationDesiredRegistration {
    guard case .replacedDeferred(_, let currentDesiredRegistration) = result else {
        throw FilesystemObservationSlotRegistryTestError.expectedReplacedDesiredRegistration
    }
    return currentDesiredRegistration
}

func requireSelectedDesiredSource(
    _ result: FilesystemObservationDesiredSelectionResult
) throws -> FilesystemObservationDesiredSelection {
    guard case .selected(let selection) = result else {
        throw FilesystemObservationSlotRegistryTestError.expectedSelectedDesiredSource
    }
    return selection
}

func requireCommittedNativeLifetime(
    _ result: FilesystemObservationNativeLifetimeCommitResult
) throws -> FilesystemObservationStartingNativeLifetime {
    guard case .committed(let startingNativeLifetime) = result else {
        throw FilesystemObservationSlotRegistryTestError.expectedCommittedNativeLifetime
    }
    return startingNativeLifetime
}

func requireRetirementRequired(
    _ result: FilesystemObservationNativeLifetimeFailureResult
) throws -> FilesystemObservationRetiringUnpublishedNativeLifetime {
    guard case .retirementRequired(let retiringNativeLifetime) = result else {
        throw FilesystemObservationSlotRegistryTestError.expectedRetirementRequired
    }
    return retiringNativeLifetime
}

struct FilesystemObservationTwoRetiringGenerationsFixture {
    let registry: FilesystemObservationSlotRegistry
    let oldestStartingNativeLifetime: FilesystemObservationStartingNativeLifetime
    let successorStartingNativeLifetime: FilesystemObservationStartingNativeLifetime
    let oldestRetirement: FilesystemObservationRetiringUnpublishedNativeLifetime
    let successorRetirement: FilesystemObservationRetiringUnpublishedNativeLifetime
    let newestDesired: FilesystemObservationDesiredRegistration
    let fullRetirementChain: FilesystemObservationRetiringUnpublishedGenerationChain
}

enum FilesystemObservationSlotRegistryTestError: Error {
    case expectedEnqueuedDesiredRegistration
    case expectedReplacedDesiredRegistration
    case expectedSelectedDesiredSource
    case expectedCommittedNativeLifetime
    case expectedPendingDesiredRegistration
    case expectedRetirementRequired
}
