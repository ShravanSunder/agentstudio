import Dispatch
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

    @Test("one lifecycle rejects a second fleet mailbox without freezing it")
    func lifecycleRejectsSequentialCrossMailboxReuse() throws {
        // Arrange
        let retainedMailbox = try makeSelectedMailbox(registrationIndex: 938)
        let presentedMailbox = try makeSelectedMailbox(registrationIndex: 939)
        let lifecycle = FilesystemObservationFleetLifecycle()
        let firstResult = lifecycle.beginShutdownAndSnapshot(mailbox: retainedMailbox)

        // Act
        let mismatch = lifecycle.beginShutdownAndSnapshot(mailbox: presentedMailbox)
        let replayedMismatch = lifecycle.beginShutdownAndSnapshot(mailbox: presentedMailbox)

        // Assert
        guard case .applied(let firstSnapshot) = firstResult else {
            Issue.record("Expected the first fleet mailbox shutdown to apply")
            return
        }
        #expect(firstSnapshot.fleetMailboxIdentity == retainedMailbox.fleetMailboxIdentity)
        expectFleetMailboxMismatch(
            mismatch,
            expected: retainedMailbox.fleetMailboxIdentity,
            presented: presentedMailbox.fleetMailboxIdentity
        )
        expectFleetMailboxMismatch(
            replayedMismatch,
            expected: retainedMailbox.fleetMailboxIdentity,
            presented: presentedMailbox.fleetMailboxIdentity
        )
        #expect(isFleetIngressAccepting(presentedMailbox))
    }

    @Test("concurrent cross-mailbox shutdown binds exactly one fleet")
    func concurrentCrossMailboxShutdownBindsExactlyOneFleet() async throws {
        // Arrange
        let firstMailbox = try makeSelectedMailbox(registrationIndex: 940)
        let secondMailbox = try makeSelectedMailbox(registrationIndex: 941)
        let lifecycle = FilesystemObservationFleetLifecycle()

        // Act
        async let firstResult = lifecycle.beginShutdownAndSnapshot(mailbox: firstMailbox)
        async let secondResult = lifecycle.beginShutdownAndSnapshot(mailbox: secondMailbox)
        let results = await [firstResult, secondResult]

        // Assert
        let projection = ConcurrentFleetShutdownResultProjection(results[0], results[1])
        let frozenMailboxCount = [firstMailbox, secondMailbox].count(where: {
            !isFleetIngressAccepting($0)
        })

        #expect(frozenMailboxCount == 1)
        switch projection {
        case .success(let appliedSnapshot, let expected, let presented):
            #expect(expected == appliedSnapshot.fleetMailboxIdentity)
            #expect(presented != appliedSnapshot.fleetMailboxIdentity)
            #expect(appliedSnapshot.fleetMailboxIdentity.isUUIDv7)
            #expect(appliedSnapshot.shutdownIdentity.isUUIDv7)
        case .invalid(let first, let second):
            Issue.record("Expected one applied freeze and one mailbox mismatch, got \(first), \(second)")
        }
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

    @Test("callback admitted under the core lock is present in the atomic freeze snapshot")
    func callbackAdmissionOrderedBeforeFreezeAppearsInSnapshot() throws {
        // Arrange
        let registration = makeFleetRegistration(index: 942)
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
        let observation = try makeObservation(
            registration: registration,
            path: "/freeze/callback-before-freeze",
            eventID: 942
        )
        let captureLockGate = CaptureAdmissionGate(pause: .afterAuthorityConsumption)

        DispatchQueue(label: "test.filesystem-freeze.capture-first").async {
            let result = callbackAdmissionPort.admit(
                using: callbackLease,
                preflight: FilesystemObservationCallbackPreflight(
                    captureLimits: fixture.captureLimits
                )
            ) {
                captureLockGate.afterAuthorityConsumedBeforeMailboxOffer()
                return .offer(.authoritative(observation))
            }
            captureLockGate.finish(with: result)
        }
        #expect(captureLockGate.waitForAdmissionEntry())
        let lifecycle = FilesystemObservationFleetLifecycle()
        DispatchQueue(label: "test.filesystem-freeze.release-capture").async {
            captureLockGate.releaseAdmission.signal()
        }

        // Act
        let freezeResult = lifecycle.beginShutdownAndSnapshot(mailbox: fixture.mailbox)
        let callbackResult = try #require(captureLockGate.waitForCompletion())

        // Assert
        _ = requireAuthoritative(callbackResult)
        guard case .applied(let snapshot) = freezeResult else {
            Issue.record("Expected freeze after callback admission to apply")
            return
        }
        #expect(snapshot.fleetMailboxIdentity == fixture.mailbox.fleetMailboxIdentity)
        #expect(snapshot.slots.map(\.generic.queuedContributionCount).reduce(0, +) == 1)
        #expect(!snapshot.isQuiescent)
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

private enum ConcurrentFleetShutdownResultProjection {
    case success(
        applied: FilesystemObservationFleetShutdownMailboxDebtSnapshot,
        mismatchExpected: FilesystemObservationFleetMailboxIdentity,
        mismatchPresented: FilesystemObservationFleetMailboxIdentity
    )
    case invalid(
        FilesystemObservationFleetShutdownBeginResult,
        FilesystemObservationFleetShutdownBeginResult
    )

    init(
        _ first: FilesystemObservationFleetShutdownBeginResult,
        _ second: FilesystemObservationFleetShutdownBeginResult
    ) {
        switch (first, second) {
        case (.applied(let snapshot), .fleetMailboxMismatch(let expected, let presented)),
            (.fleetMailboxMismatch(let expected, let presented), .applied(let snapshot)):
            self = .success(
                applied: snapshot,
                mismatchExpected: expected,
                mismatchPresented: presented
            )
        default:
            self = .invalid(first, second)
        }
    }
}

private func expectFleetMailboxMismatch(
    _ result: FilesystemObservationFleetShutdownBeginResult,
    expected: FilesystemObservationFleetMailboxIdentity,
    presented: FilesystemObservationFleetMailboxIdentity,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    guard
        case .fleetMailboxMismatch(
            expected: let actualExpected,
            presented: let actualPresented
        ) = result
    else {
        Issue.record("Expected fleet mailbox mismatch, got \(result)", sourceLocation: sourceLocation)
        return
    }
    #expect(actualExpected == expected, sourceLocation: sourceLocation)
    #expect(actualPresented == presented, sourceLocation: sourceLocation)
}

private func isFleetIngressAccepting(_ mailbox: FilesystemObservationMailbox) -> Bool {
    guard case .accepting = mailbox.lifecyclePort.diagnostics.fleetIngressLifecycle else {
        return false
    }
    return true
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
