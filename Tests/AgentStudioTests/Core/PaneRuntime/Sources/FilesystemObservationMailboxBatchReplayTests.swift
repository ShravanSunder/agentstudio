import Foundation
import Testing

@testable import AgentStudio

@Suite("Filesystem observation mailbox batch replay custody")
struct FilesystemMailboxBatchReplayTests {
    @Test("identical batch replay retains its exact admission and desired identity")
    func identicalBatchReplayRetainsExactAdmission() throws {
        // Arrange
        let mailbox = try makeBatchReplayMailbox()
        let configuration = makeBatchReplayConfiguration(sourceOrdinal: 1)
        let batch = makeBatchReplayInstallBatch(
            revision: 10,
            configuration: configuration
        )

        // Act
        let firstResult = mailbox.admitConfigurationIntents(batch)
        let replayedResult = mailbox.admitConfigurationIntents(batch)

        // Assert
        #expect(replayedResult == firstResult)
        let firstDesiredRegistration = try requireBatchReplayInstalledRegistration(
            firstResult,
            sourceID: configuration.sourceID
        )
        let replayedDesiredRegistration = try requireBatchReplayInstalledRegistration(
            replayedResult,
            sourceID: configuration.sourceID
        )
        #expect(replayedDesiredRegistration.identity == firstDesiredRegistration.identity)
        #expect(replayedDesiredRegistration.identity.isUUIDv7)

        let selection = try requireBatchReplaySelection(
            mailbox.selectNextDesiredSource()
        )
        #expect(selection.desiredRegistration == firstDesiredRegistration)
        #expect(mailbox.selectNextDesiredSource() == .noDeferredDesiredSource)
    }

    @Test("different batch at the retained revision is a typed conflict")
    func differentBatchAtRetainedRevisionIsConflict() throws {
        // Arrange
        let mailbox = try makeBatchReplayMailbox()
        let retainedConfiguration = makeBatchReplayConfiguration(sourceOrdinal: 1)
        let conflictingConfiguration = makeBatchReplayConfiguration(sourceOrdinal: 2)
        let retainedBatch = makeBatchReplayInstallBatch(
            revision: 20,
            configuration: retainedConfiguration
        )
        let conflictingBatch = makeBatchReplayInstallBatch(
            revision: 20,
            configuration: conflictingConfiguration
        )
        _ = mailbox.admitConfigurationIntents(retainedBatch)

        // Act
        let result = mailbox.admitConfigurationIntents(conflictingBatch)

        // Assert
        #expect(
            result
                == .rejected(
                    .conflictingBatchForAcceptedTopologyRevision(
                        FilesystemObservationAcceptedTopologyRevision(value: 20)
                    )
                )
        )
        let selection = try requireBatchReplaySelection(
            mailbox.selectNextDesiredSource()
        )
        #expect(selection.desiredRegistration.sourceID == retainedConfiguration.sourceID)
        #expect(mailbox.selectNextDesiredSource() == .noDeferredDesiredSource)
    }

    @Test("batch older than retained revision is typed stale without mutation")
    func olderBatchIsStaleWithoutMutation() throws {
        // Arrange
        let mailbox = try makeBatchReplayMailbox()
        let retainedConfiguration = makeBatchReplayConfiguration(sourceOrdinal: 1)
        let staleConfiguration = makeBatchReplayConfiguration(sourceOrdinal: 2)
        let retainedRevision = FilesystemObservationAcceptedTopologyRevision(value: 30)
        let staleRevision = FilesystemObservationAcceptedTopologyRevision(value: 29)
        _ = mailbox.admitConfigurationIntents(
            makeBatchReplayInstallBatch(
                revision: retainedRevision.value,
                configuration: retainedConfiguration
            )
        )

        // Act
        let result = mailbox.admitConfigurationIntents(
            makeBatchReplayInstallBatch(
                revision: staleRevision.value,
                configuration: staleConfiguration
            )
        )

        // Assert
        #expect(
            result
                == .rejected(
                    .staleAcceptedTopologyRevision(
                        submitted: staleRevision,
                        retained: retainedRevision
                    )
                )
        )
        let selection = try requireBatchReplaySelection(
            mailbox.selectNextDesiredSource()
        )
        #expect(selection.desiredRegistration.sourceID == retainedConfiguration.sourceID)
        #expect(mailbox.selectNextDesiredSource() == .noDeferredDesiredSource)
    }

    @Test("newer batch applies and replaces retained exact replay")
    func newerBatchReplacesRetainedReplay() throws {
        // Arrange
        let mailbox = try makeBatchReplayMailbox()
        let firstConfiguration = makeBatchReplayConfiguration(sourceOrdinal: 1)
        let newerConfiguration = makeBatchReplayConfiguration(sourceOrdinal: 2)
        let firstBatch = makeBatchReplayInstallBatch(
            revision: 40,
            configuration: firstConfiguration
        )
        let newerBatch = makeBatchReplayInstallBatch(
            revision: 41,
            configuration: newerConfiguration
        )
        let firstResult = mailbox.admitConfigurationIntents(firstBatch)

        // Act
        let newerResult = mailbox.admitConfigurationIntents(newerBatch)
        let replayedNewerResult = mailbox.admitConfigurationIntents(newerBatch)
        let supersededReplayResult = mailbox.admitConfigurationIntents(firstBatch)

        // Assert
        #expect(replayedNewerResult == newerResult)
        #expect(
            supersededReplayResult
                == .rejected(
                    .staleAcceptedTopologyRevision(
                        submitted: FilesystemObservationAcceptedTopologyRevision(value: 40),
                        retained: FilesystemObservationAcceptedTopologyRevision(value: 41)
                    )
                )
        )

        let firstDesiredRegistration = try requireBatchReplayInstalledRegistration(
            firstResult,
            sourceID: firstConfiguration.sourceID
        )
        let newerDesiredRegistration = try requireBatchReplayInstalledRegistration(
            newerResult,
            sourceID: newerConfiguration.sourceID
        )
        let replayedNewerDesiredRegistration = try requireBatchReplayInstalledRegistration(
            replayedNewerResult,
            sourceID: newerConfiguration.sourceID
        )
        #expect(newerDesiredRegistration.identity == replayedNewerDesiredRegistration.identity)
        #expect(firstDesiredRegistration.identity != newerDesiredRegistration.identity)
        #expect(firstDesiredRegistration.sourceID == firstConfiguration.sourceID)
        #expect(newerDesiredRegistration.sourceID == newerConfiguration.sourceID)
        #expect(firstDesiredRegistration.identity.isUUIDv7)
        #expect(newerDesiredRegistration.identity.isUUIDv7)

        let firstSelection = try requireBatchReplaySelection(
            mailbox.selectNextDesiredSource()
        )
        #expect(firstSelection.desiredRegistration == firstDesiredRegistration)
        let secondSelection = try requireBatchReplaySelection(
            mailbox.selectNextDesiredSource()
        )
        #expect(secondSelection.desiredRegistration == newerDesiredRegistration)
        #expect(mailbox.selectNextDesiredSource() == .noDeferredDesiredSource)
    }
}

private enum FilesystemMailboxBatchReplayTestError: Error {
    case expectedAdmission
    case expectedInstallation
    case expectedSelection
}

private func makeBatchReplayMailbox() throws -> FilesystemObservationMailbox {
    try FilesystemObservationMailbox(
        generation: AdmissionGeneration(owner: .filesystemObservation, value: 1),
        maximumSimultaneousSourceCount: 2,
        replacementReserveSlotCount: 1,
        limits: GatherMailboxLimits(
            maximumDeclaredKeys: 3,
            maximumRetainedContributions: 24,
            maximumRetainedItems: 192,
            maximumRetainedBytes: 196_608,
            maximumRetainedContributionsPerKey: 8,
            maximumRetainedItemsPerKey: 64,
            maximumRetainedBytesPerKey: 65_536,
            maximumContributionsPerLease: 8,
            maximumItemsPerLease: 64,
            maximumBytesPerLease: 65_536,
            cleanupQuantum: .entriesAndBytes(
                maximumEntries: 8,
                maximumBytes: 65_536
            )
        )
    )
}

private func makeBatchReplayInstallBatch(
    revision: UInt64,
    configuration: FilesystemObservationSourceConfiguration
) -> FilesystemSourceConfigurationIntentBatch {
    FilesystemSourceConfigurationIntentBatch(
        acceptedTopologyRevision: FilesystemObservationAcceptedTopologyRevision(
            value: revision
        ),
        intentsBySourceID: [
            configuration.sourceID: .install(
                FilesystemSourceInstallationIntent(
                    desiredConfiguration: configuration
                )
            )
        ]
    )
}

private func makeBatchReplayConfiguration(
    sourceOrdinal: Int
) -> FilesystemObservationSourceConfiguration {
    let sourceID = FilesystemSourceID(
        kind: .registeredWorktreeContent,
        rootID: UUID(
            uuidString: String(
                format: "20000000-0000-0000-0000-%012d",
                sourceOrdinal
            )
        )!
    )
    let generation = UInt64(sourceOrdinal)
    return FilesystemObservationSourceConfiguration(
        registration: FSEventRegistrationToken(
            sourceID: sourceID,
            registrationGeneration: generation,
            rootGeneration: generation
        ),
        canonicalResolvedRootIdentity: FilesystemCanonicalResolvedRootIdentity(
            path: "/private/test/batch-replay/\(sourceID.rootID.uuidString)"
        ),
        authorizationScopeIdentity: FilesystemAuthorizationScopeIdentity(
            value: sourceID.rootID
        ),
        eventCoverage: .recursiveFileEvents
    )
}

private func requireBatchReplayInstalledRegistration(
    _ result: FilesystemConfigurationIntentBatchAdmissionResult,
    sourceID: FilesystemSourceID
) throws -> FilesystemObservationDesiredRegistration {
    guard case .admitted(let admission) = result else {
        throw FilesystemMailboxBatchReplayTestError.expectedAdmission
    }
    guard
        case .installation(.enqueued(let desiredRegistration)) =
            admission.admissionsBySourceID[sourceID]
    else {
        throw FilesystemMailboxBatchReplayTestError.expectedInstallation
    }
    return desiredRegistration
}

private func requireBatchReplaySelection(
    _ result: FilesystemObservationDesiredSelectionResult
) throws -> FilesystemObservationDesiredSelection {
    guard case .selected(let selection) = result else {
        throw FilesystemMailboxBatchReplayTestError.expectedSelection
    }
    return selection
}
