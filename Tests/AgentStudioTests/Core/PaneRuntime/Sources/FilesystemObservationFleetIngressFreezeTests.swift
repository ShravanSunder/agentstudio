import Foundation
import Testing

@testable import AgentStudio

@Suite("Filesystem observation fleet ingress freeze")
struct FilesystemObservationFleetIngressFreezeTests {
    private let generation = AdmissionGeneration(owner: .filesystemObservation, value: 931)

    @Test("repeated shutdown begin retains one exact UUIDv7 shutdown identity")
    func freezeRetainsExactIdentityAndReplays() throws {
        // Arrange
        let mailbox = try makeSelectedMailbox(registrationIndex: 936)
        let lifecycle = FilesystemObservationFleetLifecycle()

        // Act
        _ = lifecycle.beginShutdown(mailbox: mailbox)
        let firstIdentity = requireFrozenShutdownIdentity(mailbox)
        _ = lifecycle.beginShutdown(mailbox: mailbox)
        let replayedIdentity = requireFrozenShutdownIdentity(mailbox)

        // Assert
        #expect(firstIdentity.isUUIDv7)
        #expect(replayedIdentity == firstIdentity)
    }

    @Test("a competing lifecycle cannot replace the retained shutdown identity")
    func competingLifecycleCannotReplaceShutdownIdentity() throws {
        // Arrange
        let mailbox = try makeSelectedMailbox(registrationIndex: 937)
        let lifecycle = FilesystemObservationFleetLifecycle()
        let competingLifecycle = FilesystemObservationFleetLifecycle()
        _ = lifecycle.beginShutdown(mailbox: mailbox)
        let retainedIdentity = requireFrozenShutdownIdentity(mailbox)

        // Act
        let firstRejection = competingLifecycle.beginShutdown(mailbox: mailbox)
        let replayedRejection = competingLifecycle.beginShutdown(mailbox: mailbox)

        // Assert
        #expect(requireFrozenShutdownIdentity(mailbox) == retainedIdentity)
        guard
            case .shutdownIdentityMismatch(
                expected: let firstExpected,
                presented: let firstPresented
            ) = firstRejection,
            case .shutdownIdentityMismatch(
                expected: let replayedExpected,
                presented: let replayedPresented
            ) = replayedRejection
        else {
            Issue.record("Competing lifecycle must replay one exact rejected identity")
            return
        }
        #expect(firstExpected == retainedIdentity)
        #expect(replayedExpected == retainedIdentity)
        #expect(firstPresented == replayedPresented)
        #expect(firstPresented != retainedIdentity)
        #expect(firstPresented.isUUIDv7)
    }

    @Test("freeze rejects configuration install batch selection and a new binding commitment")
    func freezeRejectsEveryNewIngressClass() throws {
        // Arrange
        let directInstallRegistration = makeFleetRegistration(index: 931)
        let batchInstallRegistration = makeFleetRegistration(index: 932)
        let selectedRegistration = makeFleetRegistration(index: 933)
        let mailbox = try makeVacantMailbox()
        #expect(mailbox.installTestConfiguration(selectedRegistration).isEnqueued)
        let selected = requireSelection(mailbox.selectNextDesiredSource())
        let lifecycle = FilesystemObservationFleetLifecycle()
        _ = lifecycle.beginShutdown(mailbox: mailbox)
        let shutdownIdentity = requireFrozenShutdownIdentity(mailbox)
        let batch = FilesystemSourceConfigurationIntentBatch(
            acceptedTopologyRevision: FilesystemObservationAcceptedTopologyRevision(value: 932),
            intentsBySourceID: [
                batchInstallRegistration.sourceID: .install(
                    FilesystemSourceInstallationIntent(
                        desiredConfiguration: makeTestFilesystemObservationSourceConfiguration(
                            batchInstallRegistration
                        )
                    )
                )
            ]
        )

        // Act / Assert
        #expect(
            mailbox.installTestConfiguration(directInstallRegistration)
                == .fleetShutdownInProgress(shutdownIdentity)
        )
        #expect(
            mailbox.admitConfigurationIntents(batch)
                == .rejected(.fleetShutdownInProgress(shutdownIdentity))
        )
        #expect(
            mailbox.selectNextDesiredSource()
                == .fleetShutdownInProgress(shutdownIdentity)
        )
        #expect(
            mailbox.beginNativeLifetime(selected.reservation)
                == .fleetShutdownInProgress(shutdownIdentity)
        )
    }

    @Test("freeze rejects callback admission before native capture executes")
    func freezeRejectsCallbackBeforeCapture() throws {
        // Arrange
        let registration = makeFleetRegistration(index: 934)
        let fixture = try makeFleetMailboxFixture(
            generation: generation,
            registrations: [registration]
        )
        let (callbackAdmissionPort, controlBlock) = try makeFleetCallbackHarness(
            fixture: fixture,
            registration: registration
        )
        let callbackLease = try #require(acquiredLease(from: controlBlock))
        defer { _ = callbackLease.release() }
        let lifecycle = FilesystemObservationFleetLifecycle()
        _ = lifecycle.beginShutdown(mailbox: fixture.mailbox)
        let shutdownIdentity = requireFrozenShutdownIdentity(fixture.mailbox)
        let inspectionLedger = NativeInspectionLedger()

        // Act
        let result = callbackAdmissionPort.admit(
            using: callbackLease,
            preflight: FilesystemObservationCallbackPreflight(
                captureLimits: fixture.captureLimits
            )
        ) {
            inspectionLedger.recordInspection()
            return .ignoredEmptyCallback
        }

        // Assert
        expectRejection(result, expected: .mailbox(.fleetShutdownInProgress(shutdownIdentity)))
        #expect(inspectionLedger.inspectionCount == 0)
        #expect(fixture.mailbox.lifecyclePort.diagnostics.gather.admission.offered == 0)
    }

    @Test("freeze preserves committed binding replay and admitted drain progress")
    func freezePreservesCommittedReplayAndDrainProgress() throws {
        // Arrange
        let registration = makeFleetRegistration(index: 935)
        let fixture = try makeFleetMailboxFixture(
            generation: generation,
            registrations: [registration]
        )
        let startingNativeLifetime = try #require(
            fixture.startingNativeLifetimesByRegistration[registration]
        )
        expectRetainedCallback(
            try fixture.admitCallback(
                .authoritative(
                    try makeObservation(
                        registration: registration,
                        path: "/freeze/already-admitted",
                        eventID: 935
                    )
                ),
                for: registration
            )
        )
        let consumer = fixture.mailbox.actorConsumerPort
        let consumerBinding = consumer.bindConsumer().binding
        let lifecycle = FilesystemObservationFleetLifecycle()
        _ = lifecycle.beginShutdown(mailbox: fixture.mailbox)
        _ = requireFrozenShutdownIdentity(fixture.mailbox)

        // Act
        let replay = fixture.mailbox.beginNativeLifetime(
            startingNativeLifetime.consumedReservation
        )
        let lease = requireLease(consumer.takeDrain(binding: consumerBinding))

        // Assert
        #expect(replay == .alreadyCommitted(startingNativeLifetime))
        #expect(requireObservations(lease).map(\.registration) == [registration])
    }

    private func makeVacantMailbox() throws -> FilesystemObservationMailbox {
        try FilesystemObservationMailbox(
            generation: generation,
            maximumSimultaneousSourceCount: 2,
            replacementReserveSlotCount: 0,
            limits: fleetMailboxLimits(global: 4, perRegistration: 2, perLease: 2)
        )
    }

    private func makeSelectedMailbox(
        registrationIndex: Int
    ) throws -> FilesystemObservationMailbox {
        let mailbox = try makeVacantMailbox()
        #expect(
            mailbox.installTestConfiguration(
                makeFleetRegistration(index: registrationIndex)
            ).isEnqueued
        )
        _ = requireSelection(mailbox.selectNextDesiredSource())
        return mailbox
    }
}

private func requireSelection(
    _ result: FilesystemObservationDesiredSelectionResult,
    sourceLocation: SourceLocation = #_sourceLocation
) -> FilesystemObservationDesiredSelection {
    guard case .selected(let selection) = result else {
        Issue.record("Expected selected desired source, got \(result)", sourceLocation: sourceLocation)
        preconditionFailure("Expected selected filesystem desired source")
    }
    return selection
}

extension FilesystemObservationDesiredUpdateResult {
    fileprivate var isEnqueued: Bool {
        guard case .enqueued = self else { return false }
        return true
    }
}

func requireFrozenShutdownIdentity(
    _ mailbox: FilesystemObservationMailbox,
    sourceLocation: SourceLocation = #_sourceLocation
) -> FilesystemObservationFleetShutdownIdentity {
    guard
        case .shutdownFrozen(let shutdownIdentity) =
            mailbox.lifecyclePort.diagnostics.fleetIngressLifecycle
    else {
        Issue.record("Expected shutdown-frozen fleet ingress", sourceLocation: sourceLocation)
        preconditionFailure("Expected shutdown-frozen filesystem fleet ingress")
    }
    return shutdownIdentity
}
