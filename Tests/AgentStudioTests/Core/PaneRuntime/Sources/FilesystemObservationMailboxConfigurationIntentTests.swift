import Foundation
import Testing

@testable import AgentStudio

@Suite("Filesystem observation mailbox configuration intent admission")
struct FilesystemMailboxIntentAdmissionTests {
    @Test("install key mismatch rejects the whole batch without mutation")
    func installKeyMismatchRejectsWithoutMutation() throws {
        // Arrange
        let mailbox = try makeConfigurationIntentMailbox()
        let desiredConfiguration = makeConfigurationIntentConfiguration(
            sourceOrdinal: 1,
            generation: 1
        )
        let foreignSourceID = makeConfigurationIntentSourceID(sourceOrdinal: 2)
        let revision = FilesystemObservationAcceptedTopologyRevision(value: 11)
        let batch = FilesystemSourceConfigurationIntentBatch(
            acceptedTopologyRevision: revision,
            intentsBySourceID: [
                foreignSourceID: .install(
                    FilesystemSourceInstallationIntent(
                        desiredConfiguration: desiredConfiguration
                    )
                )
            ]
        )

        // Act
        let result = mailbox.admitConfigurationIntents(batch)

        // Assert
        #expect(
            result
                == .rejected(
                    .sourceMismatches([
                        FilesystemConfigurationIntentSourceMismatch(
                            keyedSourceID: foreignSourceID,
                            representedSourceIDs: [desiredConfiguration.sourceID]
                        )
                    ])
                )
        )
        expectConfigurationIntentMailboxIsVacant(mailbox)
    }

    @Test("replacement key mismatch rejects the whole batch without mutation")
    func replacementKeyMismatchRejectsWithoutMutation() throws {
        // Arrange
        let fixture = try makeAcceptingConfigurationIntentFixture(
            sourceKind: .registeredWorktreeContent,
            sourceOrdinal: 1,
            generation: 1
        )
        let desiredConfiguration = makeConfigurationIntentConfiguration(
            sourceKind: .registeredWorktreeContent,
            sourceOrdinal: 1,
            generation: 2
        )
        let foreignSourceID = makeConfigurationIntentSourceID(sourceOrdinal: 2)
        let revision = FilesystemObservationAcceptedTopologyRevision(value: 12)
        let batch = FilesystemSourceConfigurationIntentBatch(
            acceptedTopologyRevision: revision,
            intentsBySourceID: [
                foreignSourceID: .replace(
                    FilesystemSourceReplacementIntent(
                        exactPriorBinding: fixture.startingNativeLifetime.binding,
                        desiredConfiguration: desiredConfiguration
                    )
                )
            ]
        )

        // Act
        let result = fixture.mailbox.admitConfigurationIntents(batch)

        // Assert
        #expect(
            result
                == .rejected(
                    .sourceMismatches([
                        FilesystemConfigurationIntentSourceMismatch(
                            keyedSourceID: foreignSourceID,
                            representedSourceIDs: [
                                fixture.registration.sourceID,
                                desiredConfiguration.sourceID,
                            ]
                        )
                    ])
                )
        )
        #expect(
            fixture.mailbox.physicalSlotState(
                of: fixture.startingNativeLifetime.binding.physicalSlotID
            ) == .accepting(fixture.acceptingNativeLifetime)
        )
        #expect(fixture.mailbox.selectNextDesiredSource() == .noDeferredDesiredSource)
    }

    @Test("removal key mismatch rejects the whole batch without mutation")
    func removalKeyMismatchRejectsWithoutMutation() throws {
        // Arrange
        let fixture = try makeAcceptingConfigurationIntentFixture(
            sourceKind: .registeredWorktreeContent,
            sourceOrdinal: 1,
            generation: 1
        )
        let foreignSourceID = makeConfigurationIntentSourceID(sourceOrdinal: 2)
        let revision = FilesystemObservationAcceptedTopologyRevision(value: 13)
        let batch = FilesystemSourceConfigurationIntentBatch(
            acceptedTopologyRevision: revision,
            intentsBySourceID: [
                foreignSourceID: .remove(
                    FilesystemSourceRemovalIntent(
                        exactPriorBinding: fixture.startingNativeLifetime.binding
                    )
                )
            ]
        )

        // Act
        let result = fixture.mailbox.admitConfigurationIntents(batch)

        // Assert
        #expect(
            result
                == .rejected(
                    .sourceMismatches([
                        FilesystemConfigurationIntentSourceMismatch(
                            keyedSourceID: foreignSourceID,
                            representedSourceIDs: [fixture.registration.sourceID]
                        )
                    ])
                )
        )
        #expect(
            fixture.mailbox.physicalSlotState(
                of: fixture.startingNativeLifetime.binding.physicalSlotID
            ) == .accepting(fixture.acceptingNativeLifetime)
        )
        #expect(fixture.mailbox.selectNextDesiredSource() == .noDeferredDesiredSource)
    }

    @Test("same-source replacement obtains continuous prior authority through the mailbox")
    func sameSourceReplacementUsesMailboxContinuityAuthority() throws {
        // Arrange
        let fixture = try makeAcceptingConfigurationIntentFixture(
            sourceKind: .registeredWorktreeContent,
            sourceOrdinal: 1,
            generation: 1
        )
        let desiredConfiguration = makeConfigurationIntentConfiguration(
            sourceKind: .registeredWorktreeContent,
            sourceOrdinal: 1,
            generation: 2
        )
        let revision = FilesystemObservationAcceptedTopologyRevision(value: 21)
        let batch = FilesystemSourceConfigurationIntentBatch(
            acceptedTopologyRevision: revision,
            intentsBySourceID: [
                desiredConfiguration.sourceID: .replace(
                    FilesystemSourceReplacementIntent(
                        exactPriorBinding: fixture.startingNativeLifetime.binding,
                        desiredConfiguration: desiredConfiguration
                    )
                )
            ]
        )

        // Act
        let result = fixture.mailbox.admitConfigurationIntents(batch)

        // Assert
        let admission = try requireConfigurationIntentAdmission(result)
        #expect(admission.acceptedTopologyRevision == revision)
        let desiredRegistration = try requireReplacementDesiredRegistration(
            admission.admissionsBySourceID[desiredConfiguration.sourceID]
        )
        #expect(desiredRegistration.acceptedTopologyRevision == revision)
        #expect(desiredRegistration.configuration == desiredConfiguration)
        #expect(
            desiredRegistration.admission
                == .replacementRetainingPredecessor(fixture.acceptingNativeLifetime)
        )
        let selection = try requireSelectedDesiredSource(
            fixture.mailbox.selectNextDesiredSource()
        )
        #expect(selection.desiredRegistration == desiredRegistration)
    }

    @Test("exact accepting removal replays one close obligation and clears pending desired")
    func exactAcceptingRemovalReplaysAndClearsPendingDesired() throws {
        // Arrange
        let fixture = try makeAcceptingConfigurationIntentFixture(
            sourceKind: .registeredWorktreeContent,
            sourceOrdinal: 1,
            generation: 1
        )
        let pendingConfiguration = makeConfigurationIntentConfiguration(
            sourceKind: .registeredWorktreeContent,
            sourceOrdinal: 1,
            generation: 2
        )
        guard
            case .deferredToConfigurationCurrentness(let pendingDesiredRegistration) =
                fixture.mailbox.installDesiredConfiguration(
                    pendingConfiguration,
                    acceptedTopologyRevision: FilesystemObservationAcceptedTopologyRevision(
                        value: 22
                    )
                )
        else {
            throw ConfigurationIntentTestError.expectedPendingDesiredRegistration
        }
        let revision = FilesystemObservationAcceptedTopologyRevision(value: 23)
        let batch = FilesystemSourceConfigurationIntentBatch(
            acceptedTopologyRevision: revision,
            intentsBySourceID: [
                fixture.registration.sourceID: .remove(
                    FilesystemSourceRemovalIntent(
                        exactPriorBinding: fixture.startingNativeLifetime.binding
                    )
                )
            ]
        )

        // Act
        let first = fixture.mailbox.admitConfigurationIntents(batch)
        let replayed = fixture.mailbox.admitConfigurationIntents(batch)

        // Assert
        #expect(first == replayed)
        let admission = try requireConfigurationIntentAdmission(first)
        #expect(admission.acceptedTopologyRevision == revision)
        let closeObligation = try requireAcceptingRemovalCloseObligation(
            admission.admissionsBySourceID[fixture.registration.sourceID]
        )
        #expect(
            closeObligation.acceptingNativeLifetime == fixture.acceptingNativeLifetime
        )
        #expect(
            closeObligation.withdrawnDesiredDisposition
                == FilesystemObservationRemovedDesiredDisposition(
                    pendingConfiguration: .withdrawn(pendingDesiredRegistration),
                    successorCustody: .absent
                )
        )
        #expect(fixture.mailbox.selectNextDesiredSource() == .noDeferredDesiredSource)
    }

    @Test("cross-kind change admits exact removal and install under one topology revision")
    func crossKindRemovalAndInstallShareOneRevision() throws {
        // Arrange
        let oldFixture = try makeAcceptingConfigurationIntentFixture(
            sourceKind: .watchedParentMembership,
            sourceOrdinal: 1,
            generation: 1,
            maximumSimultaneousSourceCount: 2
        )
        let newConfiguration = makeConfigurationIntentConfiguration(
            sourceKind: .registeredWorktreeContent,
            sourceOrdinal: 1,
            generation: 1
        )
        let revision = FilesystemObservationAcceptedTopologyRevision(value: 31)
        let batch = FilesystemSourceConfigurationIntentBatch(
            acceptedTopologyRevision: revision,
            intentsBySourceID: [
                oldFixture.registration.sourceID: .remove(
                    FilesystemSourceRemovalIntent(
                        exactPriorBinding: oldFixture.startingNativeLifetime.binding
                    )
                ),
                newConfiguration.sourceID: .install(
                    FilesystemSourceInstallationIntent(
                        desiredConfiguration: newConfiguration
                    )
                ),
            ]
        )

        // Act
        let result = oldFixture.mailbox.admitConfigurationIntents(batch)

        // Assert
        let admission = try requireConfigurationIntentAdmission(result)
        #expect(admission.acceptedTopologyRevision == revision)
        #expect(
            Set(admission.admissionsBySourceID.keys)
                == [oldFixture.registration.sourceID, newConfiguration.sourceID]
        )
        let closeObligation = try requireAcceptingRemovalCloseObligation(
            admission.admissionsBySourceID[oldFixture.registration.sourceID]
        )
        #expect(
            closeObligation.acceptingNativeLifetime == oldFixture.acceptingNativeLifetime
        )
        #expect(
            closeObligation.withdrawnDesiredDisposition
                == FilesystemObservationRemovedDesiredDisposition(
                    pendingConfiguration: .absent,
                    successorCustody: .absent
                )
        )
        let installedDesiredRegistration = try requireInstalledDesiredRegistration(
            admission.admissionsBySourceID[newConfiguration.sourceID]
        )
        #expect(installedDesiredRegistration.acceptedTopologyRevision == revision)
        #expect(installedDesiredRegistration.configuration == newConfiguration)
        #expect(installedDesiredRegistration.admission == .installation)
        #expect(
            installedDesiredRegistration.sourceID != oldFixture.registration.sourceID
        )
    }
}

private struct AcceptingConfigurationIntentFixture {
    let mailbox: FilesystemObservationMailbox
    let registration: FSEventRegistrationToken
    let startingNativeLifetime: FilesystemObservationStartingNativeLifetime
    let acceptingNativeLifetime: FilesystemObservationAcceptingNativeLifetime
}

private enum ConfigurationIntentTestError: Error {
    case expectedEnqueuedDesiredRegistration
    case expectedSelectedDesiredSource
    case expectedCommittedNativeLifetime
    case expectedNativeGenerationPorts
    case expectedAcceptingPublication
    case expectedIntentAdmission
    case expectedReplacementAdmission
    case expectedInstallationAdmission
    case expectedRemovalCloseObligation
    case expectedPendingDesiredRegistration
}

private func makeConfigurationIntentMailbox(
    maximumSimultaneousSourceCount: Int = 1,
    replacementReserveSlotCount: Int = 1
) throws -> FilesystemObservationMailbox {
    let physicalSlotCount = maximumSimultaneousSourceCount + replacementReserveSlotCount
    return try FilesystemObservationMailbox(
        generation: AdmissionGeneration(owner: .filesystemObservation, value: 1),
        maximumSimultaneousSourceCount: maximumSimultaneousSourceCount,
        replacementReserveSlotCount: replacementReserveSlotCount,
        limits: configurationIntentMailboxLimits(
            physicalSlotCount: physicalSlotCount
        )
    )
}

private func configurationIntentMailboxLimits(
    physicalSlotCount: Int
) -> GatherMailboxLimits {
    GatherMailboxLimits(
        maximumDeclaredKeys: physicalSlotCount,
        maximumRetainedContributions: 8 * physicalSlotCount,
        maximumRetainedItems: 64 * physicalSlotCount,
        maximumRetainedBytes: 65_536 * physicalSlotCount,
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
}

private func makeAcceptingConfigurationIntentFixture(
    sourceKind: FilesystemSourceKind,
    sourceOrdinal: Int,
    generation: UInt64,
    maximumSimultaneousSourceCount: Int = 1
) throws -> AcceptingConfigurationIntentFixture {
    let mailbox = try makeConfigurationIntentMailbox(
        maximumSimultaneousSourceCount: maximumSimultaneousSourceCount
    )
    let configuration = makeConfigurationIntentConfiguration(
        sourceKind: sourceKind,
        sourceOrdinal: sourceOrdinal,
        generation: generation
    )
    let desiredRegistration: FilesystemObservationDesiredRegistration
    switch mailbox.installDesiredConfiguration(
        configuration,
        acceptedTopologyRevision: FilesystemObservationAcceptedTopologyRevision(
            value: generation
        )
    ) {
    case .enqueued(let enqueuedDesiredRegistration):
        desiredRegistration = enqueuedDesiredRegistration
    case .fleetShutdownInProgress, .replacedDeferred, .deferredToConfigurationCurrentness:
        throw ConfigurationIntentTestError.expectedEnqueuedDesiredRegistration
    }
    let selection = try requireSelectedDesiredSource(
        mailbox.selectNextDesiredSource()
    )
    #expect(selection.desiredRegistration == desiredRegistration)
    let startingNativeLifetime = try requireCommittedNativeLifetime(
        mailbox.beginNativeLifetime(selection.reservation)
    )
    guard
        case .created(let nativeGenerationPorts) = mailbox.nativeGenerationPorts(
            for: startingNativeLifetime
        )
    else {
        throw ConfigurationIntentTestError.expectedNativeGenerationPorts
    }
    guard
        case .published(let publication) = nativeGenerationPorts.lifecyclePort.publishAccepting(
            startingNativeLifetime
        )
    else {
        throw ConfigurationIntentTestError.expectedAcceptingPublication
    }
    return AcceptingConfigurationIntentFixture(
        mailbox: mailbox,
        registration: configuration.registration,
        startingNativeLifetime: startingNativeLifetime,
        acceptingNativeLifetime: publication.acceptingNativeLifetime
    )
}

private func makeConfigurationIntentSourceID(
    sourceKind: FilesystemSourceKind = .registeredWorktreeContent,
    sourceOrdinal: Int
) -> FilesystemSourceID {
    FilesystemSourceID(
        kind: sourceKind,
        rootID: UUID(
            uuidString: String(
                format: "10000000-0000-0000-0000-%012d",
                sourceOrdinal
            )
        )!
    )
}

private func makeConfigurationIntentConfiguration(
    sourceKind: FilesystemSourceKind = .registeredWorktreeContent,
    sourceOrdinal: Int,
    generation: UInt64
) -> FilesystemObservationSourceConfiguration {
    let sourceID = makeConfigurationIntentSourceID(
        sourceKind: sourceKind,
        sourceOrdinal: sourceOrdinal
    )
    return FilesystemObservationSourceConfiguration(
        registration: FSEventRegistrationToken(
            sourceID: sourceID,
            registrationGeneration: generation,
            rootGeneration: generation
        ),
        canonicalResolvedRootIdentity: FilesystemCanonicalResolvedRootIdentity(
            path: "/private/test/configuration-intent/\(sourceID.rootID.uuidString)"
        ),
        authorizationScopeIdentity: FilesystemAuthorizationScopeIdentity(
            value: sourceID.rootID
        ),
        eventCoverage: .recursiveFileEvents
    )
}

private func expectConfigurationIntentMailboxIsVacant(
    _ mailbox: FilesystemObservationMailbox
) {
    for physicalSlotID in mailbox.physicalSlotIDs {
        #expect(mailbox.physicalSlotState(of: physicalSlotID) == .vacant)
    }
    #expect(mailbox.selectNextDesiredSource() == .noDeferredDesiredSource)
}

private func requireConfigurationIntentAdmission(
    _ result: FilesystemConfigurationIntentBatchAdmissionResult
) throws -> FilesystemConfigurationIntentBatchAdmission {
    guard case .admitted(let admission) = result else {
        throw ConfigurationIntentTestError.expectedIntentAdmission
    }
    return admission
}

private func requireReplacementDesiredRegistration(
    _ disposition: FilesystemConfigurationIntentAdmission?
) throws -> FilesystemObservationDesiredRegistration {
    guard
        case .replacement(.admitted(.enqueued(let desiredRegistration))) = disposition
    else {
        throw ConfigurationIntentTestError.expectedReplacementAdmission
    }
    return desiredRegistration
}

private func requireInstalledDesiredRegistration(
    _ disposition: FilesystemConfigurationIntentAdmission?
) throws -> FilesystemObservationDesiredRegistration {
    guard case .installation(.enqueued(let desiredRegistration)) = disposition else {
        throw ConfigurationIntentTestError.expectedInstallationAdmission
    }
    return desiredRegistration
}

private func requireAcceptingRemovalCloseObligation(
    _ disposition: FilesystemConfigurationIntentAdmission?
) throws -> FilesystemAcceptingRemovalCloseObligation {
    guard case .removal(.closeAccepting(let closeObligation)) = disposition else {
        throw ConfigurationIntentTestError.expectedRemovalCloseObligation
    }
    return closeObligation
}
