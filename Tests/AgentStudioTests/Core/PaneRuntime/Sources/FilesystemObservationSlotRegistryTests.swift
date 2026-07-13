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
        let bindings = try physicalSlotIDs.enumerated().map { offset, physicalSlotID in
            try requireIssuedBinding(
                registry.issueInitialBinding(
                    physicalSlotID: physicalSlotID,
                    registration: makeRegistration(generation: UInt64(offset + 1))
                )
            )
        }

        // Assert
        #expect(registry.maximumSimultaneousSourceCount == 3)
        #expect(registry.replacementReserveSlotCount == 2)
        #expect(registry.physicalSlotCount == 5)
        #expect(physicalSlotIDs.count == 5)
        #expect(Set(physicalSlotIDs).count == 5)
        #expect(registry.fleetMailboxIdentity.isUUIDv7)
        #expect(physicalSlotIDs.allSatisfy { $0.isUUIDv7 })
        #expect(Set(bindings.map(\.identity)).count == 5)
        #expect(bindings.allSatisfy { $0.identity.isUUIDv7 })
        #expect(Set(bindings.map(\.controlBlockIdentity)).count == 5)
        #expect(bindings.allSatisfy { $0.controlBlockIdentity.isUUIDv7 })
    }

    @Test("a declared vacant slot issues one complete UUIDv7 binding")
    func vacantSlotIssuesCompleteBinding() throws {
        // Arrange
        let registry = try makeRegistry(physicalSlotCount: 1)
        let physicalSlotID = try #require(registry.physicalSlotIDs.first)
        let registration = makeRegistration(generation: 7)

        // Act
        let result = registry.issueInitialBinding(
            physicalSlotID: physicalSlotID,
            registration: registration
        )

        // Assert
        guard case .issued(let binding) = result else {
            Issue.record("Expected the declared vacant slot to issue a binding")
            return
        }
        #expect(binding.fleetMailboxIdentity == registry.fleetMailboxIdentity)
        #expect(binding.physicalSlotID == physicalSlotID)
        #expect(binding.registration == registration)
        #expect(binding.identity.isUUIDv7)
        #expect(binding.controlBlockIdentity.isUUIDv7)
        #expect(registry.currentness(of: binding) == .current)
        #expect(registry.state(of: physicalSlotID) == .current(binding))
    }

    @Test("a second bind is typed occupied and preserves the exact current binding")
    func occupiedSlotRejectsSecondBindingWithoutMutation() throws {
        // Arrange
        let registry = try makeRegistry(physicalSlotCount: 1)
        let physicalSlotID = try #require(registry.physicalSlotIDs.first)
        let firstBinding = try requireIssuedBinding(
            registry.issueInitialBinding(
                physicalSlotID: physicalSlotID,
                registration: makeRegistration(generation: 11)
            )
        )

        // Act
        let secondResult = registry.issueInitialBinding(
            physicalSlotID: physicalSlotID,
            registration: makeRegistration(generation: 12)
        )

        // Assert
        #expect(secondResult == .occupied(firstBinding))
        #expect(registry.currentness(of: firstBinding) == .current)
        #expect(registry.state(of: physicalSlotID) == .current(firstBinding))
    }

    @Test("slot and binding classifications distinguish undeclared unbound current and foreign")
    func classificationUsesClosedResults() throws {
        // Arrange
        let registry = try makeRegistry(physicalSlotCount: 2)
        let foreignRegistry = try makeRegistry(physicalSlotCount: 1)
        let currentSlotID = try #require(registry.physicalSlotIDs.first)
        let unboundSlotID = try #require(registry.physicalSlotIDs.last)
        let foreignSlotID = try #require(foreignRegistry.physicalSlotIDs.first)
        let currentBinding = try requireIssuedBinding(
            registry.issueInitialBinding(
                physicalSlotID: currentSlotID,
                registration: makeRegistration(generation: 17)
            )
        )
        let foreignBinding = try requireIssuedBinding(
            foreignRegistry.issueInitialBinding(
                physicalSlotID: foreignSlotID,
                registration: makeRegistration(generation: 18)
            )
        )

        // Act / Assert
        #expect(registry.fleetMailboxIdentity != foreignRegistry.fleetMailboxIdentity)
        #expect(registry.state(of: unboundSlotID) == .unbound)
        #expect(registry.state(of: foreignSlotID) == .undeclaredPhysicalSlot)
        #expect(
            registry.issueInitialBinding(
                physicalSlotID: foreignSlotID,
                registration: makeRegistration(generation: 19)
            ) == .undeclaredPhysicalSlot
        )
        #expect(registry.currentness(of: currentBinding) == .current)
        #expect(registry.currentness(of: foreignBinding) == .foreignFleet)
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

    private func makeRegistry(
        physicalSlotCount: Int
    ) throws -> FilesystemObservationSlotRegistry {
        try FilesystemObservationSlotRegistry(
            maximumSimultaneousSourceCount: physicalSlotCount,
            replacementReserveSlotCount: 0
        )
    }

    private func makeRegistration(generation: UInt64) -> FSEventRegistrationToken {
        FSEventRegistrationToken(
            sourceID: FilesystemSourceID(
                kind: .registeredWorktreeContent,
                rootID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
            ),
            registrationGeneration: generation,
            rootGeneration: generation
        )
    }

    private func requireIssuedBinding(
        _ result: FilesystemObservationSlotBindingIssueResult
    ) throws -> FilesystemObservationSlotBinding {
        guard case .issued(let binding) = result else {
            throw FilesystemObservationSlotRegistryTestError.expectedIssuedBinding
        }
        return binding
    }
}

private enum FilesystemObservationSlotRegistryTestError: Error {
    case expectedIssuedBinding
}
