import Foundation
import Testing

@testable import AgentStudio

@Suite("Filesystem observation fleet exhaustion integration")
// swiftlint:disable:next type_name
struct FilesystemObservationFleetExhaustionIntegrationTests {
    private let generation = AdmissionGeneration(owner: .filesystemObservation, value: 941)

    @Test("the flipping offer retains exact binding and terminal generic recovery revision")
    func exhaustionRetainsExactTriggeringDebt() throws {
        // Arrange
        let registration = makeFleetRegistration(index: 941)
        let fixture = try makeFleetMailboxFixture(
            generation: generation,
            registrations: [registration],
            limits: fleetMailboxLimits(global: 0, perRegistration: 1, perLease: 1),
            recoveryAuthoritySeed: .preseededSequenced(.max)
        )
        let binding = fixture.binding(for: registration)

        // Act
        let terminalRecovery = requireContractedRecovery(
            try fixture.admitCallback(
                .authoritative(
                    try makeObservation(
                        registration: registration,
                        path: "/exhaustion/trigger",
                        eventID: 941
                    )
                ),
                for: registration
            )
        )

        // Assert
        let expectedDebt = FilesystemObservationFleetAdmissionExhaustionDebt(
            triggeringBinding: binding,
            terminalGenericRecoveryRevision: terminalRecovery.revision.genericRecoveryRevision
        )
        #expect(
            fixture.mailbox.lifecyclePort.diagnostics.fleetOrdinaryAdmissionDisposition
                == .fleetAdmissionExhausted(expectedDebt)
        )
    }

    @Test("later callbacks replay exact exhaustion without capture mutation or replacement")
    func exhaustedAdmissionReplaysExactDebt() throws {
        // Arrange
        let firstRegistration = makeFleetRegistration(index: 942)
        let laterRegistration = makeFleetRegistration(index: 943)
        let fixture = try makeFleetMailboxFixture(
            generation: generation,
            registrations: [firstRegistration, laterRegistration],
            limits: fleetMailboxLimits(global: 0, perRegistration: 1, perLease: 1),
            recoveryAuthoritySeed: .preseededSequenced(.max)
        )
        let terminalRecovery = requireContractedRecovery(
            try fixture.admitCallback(
                .authoritative(
                    try makeObservation(
                        registration: firstRegistration,
                        path: "/exhaustion/first",
                        eventID: 942
                    )
                ),
                for: firstRegistration
            )
        )
        let exactDebt = FilesystemObservationFleetAdmissionExhaustionDebt(
            triggeringBinding: fixture.binding(for: firstRegistration),
            terminalGenericRecoveryRevision: terminalRecovery.revision.genericRecoveryRevision
        )
        let diagnosticsBeforeReplay = fixture.mailbox.lifecyclePort.diagnostics.gather
        let (callbackAdmissionPort, controlBlock) = try makeFleetCallbackHarness(
            fixture: fixture,
            registration: laterRegistration
        )
        let callbackLease = try #require(acquiredLease(from: controlBlock))
        defer { _ = callbackLease.release() }
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
        expectRejection(result, expected: .mailbox(.fleetAdmissionExhausted(exactDebt)))
        #expect(inspectionLedger.inspectionCount == 0)
        #expect(
            fixture.mailbox.lifecyclePort.diagnostics.fleetOrdinaryAdmissionDisposition
                == .fleetAdmissionExhausted(exactDebt)
        )
        #expect(
            fixture.mailbox.lifecyclePort.diagnostics.gather.admission.offered
                == diagnosticsBeforeReplay.admission.offered
        )
    }

    @Test("shutdown freeze and exact fleet exhaustion remain orthogonal")
    func shutdownFreezeAndExhaustionCoexist() throws {
        // Arrange
        let registration = makeFleetRegistration(index: 944)
        let fixture = try makeFleetMailboxFixture(
            generation: generation,
            registrations: [registration],
            limits: fleetMailboxLimits(global: 0, perRegistration: 1, perLease: 1),
            recoveryAuthoritySeed: .preseededSequenced(.max)
        )
        let terminalRecovery = requireContractedRecovery(
            try fixture.admitCallback(
                .authoritative(
                    try makeObservation(
                        registration: registration,
                        path: "/exhaustion/before-freeze",
                        eventID: 944
                    )
                ),
                for: registration
            )
        )
        let exactDebt = FilesystemObservationFleetAdmissionExhaustionDebt(
            triggeringBinding: fixture.binding(for: registration),
            terminalGenericRecoveryRevision: terminalRecovery.revision.genericRecoveryRevision
        )
        let lifecycle = FilesystemObservationFleetLifecycle()

        // Act
        _ = lifecycle.beginShutdown(mailbox: fixture.mailbox)
        let shutdownIdentity = requireFrozenShutdownIdentity(fixture.mailbox)

        // Assert
        #expect(
            fixture.mailbox.lifecyclePort.diagnostics.fleetIngressLifecycle
                == .shutdownFrozen(shutdownIdentity)
        )
        #expect(
            fixture.mailbox.lifecyclePort.diagnostics.fleetOrdinaryAdmissionDisposition
                == .fleetAdmissionExhausted(exactDebt)
        )
    }
}

func makeFleetMailboxFixture(
    generation: AdmissionGeneration,
    registrations: [FSEventRegistrationToken],
    limits: GatherMailboxLimits? = nil,
    recoveryAuthoritySeed: FilesystemObservationRecoveryAuthoritySeed = .initial
) throws -> FixedSlotFilesystemObservationMailboxFixture {
    try makeFixedSlotMailboxFixture(
        generation: generation,
        registrations: registrations,
        limits: limits ?? fleetMailboxLimits(global: 8, perRegistration: 4, perLease: 2),
        captureLimits: FSEventCaptureLimits(
            maximumInspectedNativeRecords: 32,
            maximumCopiedRecords: 16,
            maximumCopiedUTF8Bytes: 4096,
            maximumSinglePathUTF8Bytes: 1024
        ),
        callbackQueueLabel: "test.filesystem-observation-fleet",
        recoveryAuthoritySeed: recoveryAuthoritySeed
    )
}

func makeFleetCallbackHarness(
    fixture: FixedSlotFilesystemObservationMailboxFixture,
    registration: FSEventRegistrationToken
) throws -> (FilesystemObservationCallbackAdmissionPort, FSEventRegistrationControlBlock) {
    let startingNativeLifetime = try #require(
        fixture.startingNativeLifetimesByRegistration[registration]
    )
    let callbackAdmissionPort: FilesystemObservationCallbackAdmissionPort
    switch fixture.mailbox.nativeGenerationPorts(for: startingNativeLifetime) {
    case .created(let ports):
        callbackAdmissionPort = ports.callbackAdmissionPort
    case .foreignFleet, .undeclaredPhysicalSlot, .bindingNotCurrent:
        throw FixedSlotFilesystemObservationTestFailure.callbackPortUnavailable
    }
    return (
        callbackAdmissionPort,
        try makeControlBlock(
            startingNativeLifetime: startingNativeLifetime,
            captureLimits: fixture.captureLimits,
            callbackQueueLabel: fixture.callbackQueueLabel
        )
    )
}

func fleetMailboxLimits(
    global: Int,
    perRegistration: Int,
    perLease: Int
) -> GatherMailboxLimits {
    GatherMailboxLimits(
        maximumDeclaredKeys: 32,
        maximumRetainedContributions: global,
        maximumRetainedItems: global,
        maximumRetainedBytes: global * 64,
        maximumRetainedContributionsPerKey: perRegistration,
        maximumRetainedItemsPerKey: perRegistration,
        maximumRetainedBytesPerKey: perRegistration * 64,
        maximumContributionsPerLease: perLease,
        maximumItemsPerLease: perLease,
        maximumBytesPerLease: perLease * 64,
        cleanupQuantum: .entriesAndBytes(
            maximumEntries: max(1, perLease),
            maximumBytes: max(64, perLease * 64)
        )
    )
}

func makeFleetRegistration(index: Int) -> FSEventRegistrationToken {
    let suffix = String(format: "%012d", index)
    return FSEventRegistrationToken(
        sourceID: FilesystemSourceID(
            kind: .registeredWorktreeContent,
            rootID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-\(suffix)")!
        ),
        registrationGeneration: UInt64(index),
        rootGeneration: 1
    )
}
