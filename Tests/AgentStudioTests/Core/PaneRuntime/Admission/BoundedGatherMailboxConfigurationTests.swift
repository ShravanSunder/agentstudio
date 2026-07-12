import Testing

@testable import AgentStudio

extension AdmissionBoundedGatherMailboxTests {
    @Test("configuration requires cleanup bytes for the largest admissible entry")
    func configurationRequiresCleanupBytesForLargestAdmissibleEntry() {
        // Arrange
        let exactLimits = GatherMailboxLimits(
            maximumDeclaredKeys: 1,
            maximumRetainedContributions: 1,
            maximumRetainedItems: 1,
            maximumRetainedBytes: 8,
            maximumRetainedContributionsPerKey: 1,
            maximumRetainedItemsPerKey: 1,
            maximumRetainedBytesPerKey: 8,
            maximumContributionsPerLease: 1,
            maximumItemsPerLease: 1,
            maximumBytesPerLease: 8,
            cleanupQuantum: AdmissionCleanupQuantum(maximumEntries: 1, maximumBytes: 8)
        )
        let undersizedCleanupLimits = GatherMailboxLimits(
            maximumDeclaredKeys: 1,
            maximumRetainedContributions: 1,
            maximumRetainedItems: 1,
            maximumRetainedBytes: 8,
            maximumRetainedContributionsPerKey: 1,
            maximumRetainedItemsPerKey: 1,
            maximumRetainedBytesPerKey: 8,
            maximumContributionsPerLease: 1,
            maximumItemsPerLease: 1,
            maximumBytesPerLease: 8,
            cleanupQuantum: AdmissionCleanupQuantum(maximumEntries: 1, maximumBytes: 7)
        )

        // Act
        let exactConfigurationIsValid = BoundedGatherMailbox<
            GatherTestKey,
            GatherTestPayload
        >.isConfigurationValid(
            declaredKeyCount: 1,
            limits: exactLimits
        )
        let undersizedConfigurationIsValid = BoundedGatherMailbox<
            GatherTestKey,
            GatherTestPayload
        >.isConfigurationValid(
            declaredKeyCount: 1,
            limits: undersizedCleanupLimits
        )
        let mailbox = makeMailbox(declaredKeys: [.alpha], limits: exactLimits)
        let offer = mailbox.producerPort.offer(
            generation: generation,
            contribution: contribution(
                key: .alpha,
                label: "exact-cleanup-bound",
                items: 1,
                bytes: 8
            )
        )

        // Assert
        #expect(exactConfigurationIsValid)
        #expect(undersizedConfigurationIsValid == false)
        #expect(requireAdmission(offer.receipt)?.payload == .retained)
    }
}
