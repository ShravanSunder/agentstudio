import CoreServices
import Dispatch
import Foundation
import Testing
import os

@testable import AgentStudio

func makeTestFilesystemObservationSourceConfiguration(
    _ registration: FSEventRegistrationToken
) -> FilesystemObservationSourceConfiguration {
    FilesystemObservationSourceConfiguration(
        registration: registration,
        canonicalResolvedRootIdentity: FilesystemCanonicalResolvedRootIdentity(
            path: "/private/test/\(registration.sourceID.rootID.uuidString)"
        ),
        authorizationScopeIdentity: FilesystemAuthorizationScopeIdentity(
            value: registration.sourceID.rootID
        ),
        eventCoverage: .recursiveFileEvents
    )
}

extension FilesystemObservationSlotRegistry {
    func installTestConfiguration(
        _ registration: FSEventRegistrationToken
    ) -> FilesystemObservationDesiredUpdateResult {
        installDesiredConfiguration(
            makeTestFilesystemObservationSourceConfiguration(registration),
            acceptedTopologyRevision: FilesystemObservationAcceptedTopologyRevision(
                value: registration.registrationGeneration
            )
        )
    }
}

extension FilesystemObservationMailbox {
    func installTestConfiguration(
        _ registration: FSEventRegistrationToken
    ) -> FilesystemObservationDesiredUpdateResult {
        installDesiredConfiguration(
            makeTestFilesystemObservationSourceConfiguration(registration),
            acceptedTopologyRevision: FilesystemObservationAcceptedTopologyRevision(
                value: registration.registrationGeneration
            )
        )
    }
}

enum TestCredentialedTransferAcknowledgement: Equatable, Sendable {
    case transferredAuthoritative(wake: AdmissionWakeDirective)
    case transferredRecovery(
        evidence: FixedFilesystemRecoveryAcknowledgeResult,
        wake: AdmissionWakeDirective
    )
    case retried(wake: AdmissionWakeDirective)
    case rejected
}

private final class TestTransferAcknowledgementCapture: @unchecked Sendable {
    private enum Captured: Sendable {
        case vacant
        case acknowledgement(FilesystemObservationDrainAcknowledgement)
    }

    private let captured = OSAllocatedUnfairLock(initialState: Captured.vacant)
    private let underlying: FilesystemObservationActorConsumerPort

    init(underlying: FilesystemObservationActorConsumerPort) {
        self.underlying = underlying
    }

    var port: FilesystemObservationActorConsumerPort {
        FilesystemObservationActorConsumerPort(
            bind: underlying.bindConsumer,
            take: underlying.takeDrain,
            acknowledge: acknowledge,
            cleanup: underlying.performCleanup,
            preflightWholeLeaseTransfer: underlying.preflightWholeLeaseTransfer,
            completeWholeLeaseTransfer: underlying.completeWholeLeaseTransfer
        )
    }

    func projectedAcknowledgement() -> TestCredentialedTransferAcknowledgement {
        captured.withLock { state in
            switch state {
            case .vacant:
                return .rejected
            case .acknowledgement(let acknowledgement):
                switch acknowledgement {
                case .transferredAuthoritative(_, let wake):
                    return .transferredAuthoritative(wake: wake)
                case .transferredRecovery(_, let evidence, let wake):
                    return .transferredRecovery(evidence: evidence, wake: wake)
                case .retried(let wake):
                    return .retried(wake: wake)
                case .dispositionMismatch, .invalidToken, .closed:
                    return .rejected
                }
            }
        }
    }

    private func acknowledge(
        token: AdmissionDrainToken,
        disposition: FilesystemObservationDrainDisposition
    ) -> FilesystemObservationDrainAcknowledgement {
        let acknowledgement = underlying.acknowledge(
            token: token,
            disposition: disposition
        )
        captured.withLock { state in
            state = .acknowledgement(acknowledgement)
        }
        return acknowledgement
    }
}

private struct AcceptAllFilesystemSemanticSink: FilesystemObservationSemanticCustodySink {
    mutating func accept(
        _: FSEventObservation,
        identity _: FilesystemObservationContributionIdentity
    ) -> FilesystemObservationSemanticCustodyResult {
        .accepted
    }
}

func credentialedTransferAcknowledgement(
    for lease: FilesystemObservationDrainLease,
    consumerPort: FilesystemObservationActorConsumerPort,
    sourceGate: inout FilesystemSourceGate,
    recoveryContext: FilesystemObservationRecoveryAdmissionContext = .notRequired
) throws -> TestCredentialedTransferAcknowledgement {
    let capture = TestTransferAcknowledgementCapture(underlying: consumerPort)
    var transfer = try FilesystemObservationLeaseTransfer(
        physicalSlotIDs: [lease.binding.physicalSlotID],
        maximumContributionsPerLease: max(1, testContributionCount(in: lease))
    )
    var semanticSink = AcceptAllFilesystemSemanticSink()
    _ = transfer.transfer(
        lease,
        sourceGate: &sourceGate,
        recoveryContext: recoveryContext,
        semanticSink: &semanticSink,
        consumerPort: capture.port
    )
    return capture.projectedAcknowledgement()
}

func credentialedTransferAcknowledgement(
    for lease: FilesystemObservationDrainLease,
    consumerPort: FilesystemObservationActorConsumerPort
) throws -> TestCredentialedTransferAcknowledgement {
    var sourceGate = FilesystemSourceGate(binding: lease.binding)
    return try credentialedTransferAcknowledgement(
        for: lease,
        consumerPort: consumerPort,
        sourceGate: &sourceGate
    )
}

private func testContributionCount(in lease: FilesystemObservationDrainLease) -> Int {
    switch lease.payload {
    case .contributions(let batch), .contributionsWithRecovery(let batch, _):
        1 + batch.remaining.count
    case .recovery:
        0
    }
}

enum FixedSlotFilesystemObservationTestFailure: Error {
    case fixtureConstructionFailed
    case callbackPortUnavailable
    case callbackLeaseUnavailable
    case recoveryNotAccepted
}

struct FixedSlotFilesystemObservationMailboxFixture {
    let mailbox: FilesystemObservationMailbox
    let startingNativeLifetimesByRegistration: [FSEventRegistrationToken: FilesystemObservationStartingNativeLifetime]
    let captureLimits: FSEventCaptureLimits
    let callbackQueueLabel: String

    var binding: FilesystemObservationSlotBinding {
        guard startingNativeLifetimesByRegistration.count == 1,
            let startingNativeLifetime = startingNativeLifetimesByRegistration.values.first
        else {
            preconditionFailure("Expected exactly one fixed-slot starting native lifetime")
        }
        return startingNativeLifetime.binding
    }

    func binding(
        for registration: FSEventRegistrationToken
    ) -> FilesystemObservationSlotBinding {
        startingNativeLifetime(for: registration).binding
    }

    func admitCallback(
        _ offer: FilesystemObservationOffer
    ) throws -> DarwinFSEventObservationCaptureResult {
        guard startingNativeLifetimesByRegistration.count == 1,
            let registration = startingNativeLifetimesByRegistration.keys.first
        else {
            throw FixedSlotFilesystemObservationTestFailure.fixtureConstructionFailed
        }
        return try admitCallback(offer, for: registration)
    }

    func admitCallback(
        _ offer: FilesystemObservationOffer,
        for registration: FSEventRegistrationToken,
        synchronization: any FilesystemObservationCallbackSynchronization =
            ImmediateFilesystemObservationCallbackSynchronization()
    ) throws -> DarwinFSEventObservationCaptureResult {
        let startingNativeLifetime = startingNativeLifetime(for: registration)
        guard
            case .created(let nativeGenerationPorts) = mailbox.nativeGenerationPorts(
                for: startingNativeLifetime,
                synchronization: synchronization
            )
        else {
            throw FixedSlotFilesystemObservationTestFailure.callbackPortUnavailable
        }
        let controlBlock = try makeControlBlock(
            startingNativeLifetime: startingNativeLifetime,
            captureLimits: captureLimits,
            callbackQueueLabel: callbackQueueLabel
        )
        guard case .acquired(let lease) = controlBlock.acquireCallbackLease() else {
            throw FixedSlotFilesystemObservationTestFailure.callbackLeaseUnavailable
        }
        defer { _ = lease.release() }
        return nativeGenerationPorts.callbackAdmissionPort.admit(
            using: lease,
            preflight: FilesystemObservationCallbackPreflight(captureLimits: captureLimits)
        ) { .offer(offer) }
    }

    private func startingNativeLifetime(
        for registration: FSEventRegistrationToken
    ) -> FilesystemObservationStartingNativeLifetime {
        guard let startingNativeLifetime = startingNativeLifetimesByRegistration[registration]
        else {
            preconditionFailure("Expected a starting native lifetime for the registration")
        }
        return startingNativeLifetime
    }
}

func makeFixedSlotMailboxFixture(
    generation: AdmissionGeneration,
    registrations: [FSEventRegistrationToken],
    limits: GatherMailboxLimits,
    captureLimits: FSEventCaptureLimits,
    callbackQueueLabel: String,
    recoveryAuthoritySeed: FilesystemObservationRecoveryAuthoritySeed = .initial
) throws -> FixedSlotFilesystemObservationMailboxFixture {
    let mailbox = try FilesystemObservationMailbox(
        generation: generation,
        maximumSimultaneousSourceCount: registrations.count,
        replacementReserveSlotCount: 0,
        limits: limits,
        recoveryAuthoritySeed: recoveryAuthoritySeed
    )
    var startingNativeLifetimesByRegistration: [FSEventRegistrationToken: FilesystemObservationStartingNativeLifetime] =
        [:]
    for registration in registrations {
        guard case .enqueued = mailbox.installTestConfiguration(registration) else {
            throw FixedSlotFilesystemObservationTestFailure.fixtureConstructionFailed
        }
    }
    for _ in registrations {
        guard case .selected(let selection) = mailbox.selectNextDesiredSource() else {
            throw FixedSlotFilesystemObservationTestFailure.fixtureConstructionFailed
        }
        guard
            case .committed(let startingNativeLifetime) =
                mailbox.beginNativeLifetime(selection.reservation)
        else {
            throw FixedSlotFilesystemObservationTestFailure.fixtureConstructionFailed
        }
        startingNativeLifetimesByRegistration[startingNativeLifetime.binding.registration] =
            startingNativeLifetime
    }
    return FixedSlotFilesystemObservationMailboxFixture(
        mailbox: mailbox,
        startingNativeLifetimesByRegistration: startingNativeLifetimesByRegistration,
        captureLimits: captureLimits,
        callbackQueueLabel: callbackQueueLabel
    )
}

func makeControlBlock(
    startingNativeLifetime: FilesystemObservationStartingNativeLifetime,
    captureLimits: FSEventCaptureLimits,
    callbackQueueLabel: String
) throws -> FSEventRegistrationControlBlock {
    try FSEventRegistrationControlBlock(
        startingNativeLifetime: startingNativeLifetime,
        watchRoot: WatchRoot(
            sourceID: startingNativeLifetime.binding.registration.sourceID,
            declaredPath: "/workspace/repo",
            resolvedPath: "/private/workspace/repo"
        ),
        captureLimits: captureLimits,
        callbackQueue: DispatchQueue(label: callbackQueueLabel)
    )
}

func makeObservation(
    registration: FSEventRegistrationToken,
    path: String,
    flags: FSEventFlags = [.itemModified],
    eventID: UInt64
) throws -> FSEventObservation {
    try FSEventObservation(
        registration: registration,
        capturedAt: ContinuousClock.now,
        totalRecordCount: .exact(1),
        inspectedNativeRecordCount: 1,
        records: [FSEventRecord(path: path, flags: flags, eventID: eventID)],
        unionedInspectedFlags: flags,
        eventIDWatermark: .inspected(first: eventID, last: eventID),
        completeness: .complete
    )
}

func requireOfferReceipt(
    _ result: FilesystemObservationOfferResult,
    sourceLocation: SourceLocation = #_sourceLocation
) -> FilesystemObservationOfferReceipt {
    guard case .admitted(let receipt) = result else {
        Issue.record("Expected admitted observation, got \(result)", sourceLocation: sourceLocation)
        preconditionFailure("Expected admitted filesystem observation")
    }
    return receipt
}

func requireRetainedRecovery(
    _ result: FilesystemObservationOfferResult,
    sourceLocation: SourceLocation = #_sourceLocation
) -> FixedFilesystemRecoveryEvidenceSnapshot {
    let receipt = requireOfferReceipt(result, sourceLocation: sourceLocation)
    guard case .retainedWithRecovery(let recovery) = receipt.disposition else {
        Issue.record("Expected retained recovery, got \(result)", sourceLocation: sourceLocation)
        preconditionFailure("Expected retained filesystem recovery")
    }
    return recovery
}

func requireContractedRecovery(
    _ result: FilesystemObservationOfferResult,
    sourceLocation: SourceLocation = #_sourceLocation
) -> FixedFilesystemRecoveryEvidenceSnapshot {
    let receipt = requireOfferReceipt(result, sourceLocation: sourceLocation)
    guard case .contractedToRecovery(let recovery) = receipt.disposition else {
        Issue.record("Expected contracted recovery, got \(result)", sourceLocation: sourceLocation)
        preconditionFailure("Expected contracted filesystem recovery")
    }
    return recovery
}

func requireCallbackDisposition(
    _ result: DarwinFSEventObservationCaptureResult,
    sourceLocation: SourceLocation = #_sourceLocation
) -> FilesystemObservationOfferDisposition {
    guard case .admitted(_, let admission) = result,
        case .admitted(let disposition, _) = admission
    else {
        Issue.record("Expected admitted callback, got \(result)", sourceLocation: sourceLocation)
        preconditionFailure("Expected admitted callback")
    }
    return disposition
}

func requireRetainedRecovery(
    _ result: DarwinFSEventObservationCaptureResult,
    sourceLocation: SourceLocation = #_sourceLocation
) -> FixedFilesystemRecoveryEvidenceSnapshot {
    let disposition = requireCallbackDisposition(result, sourceLocation: sourceLocation)
    guard case .retainedWithRecovery(let recovery) = disposition else {
        Issue.record("Expected retained callback recovery, got \(result)", sourceLocation: sourceLocation)
        preconditionFailure("Expected retained callback recovery")
    }
    return recovery
}

func requireContractedRecovery(
    _ result: DarwinFSEventObservationCaptureResult,
    sourceLocation: SourceLocation = #_sourceLocation
) -> FixedFilesystemRecoveryEvidenceSnapshot {
    let disposition = requireCallbackDisposition(result, sourceLocation: sourceLocation)
    guard case .contractedToRecovery(let recovery) = disposition else {
        Issue.record("Expected contracted callback recovery, got \(result)", sourceLocation: sourceLocation)
        preconditionFailure("Expected contracted callback recovery")
    }
    return recovery
}

func requireCallbackWake(
    _ result: DarwinFSEventObservationCaptureResult,
    sourceLocation: SourceLocation = #_sourceLocation
) -> FilesystemObservationCallbackWakeApplication {
    guard case .admitted(_, let admission) = result,
        case .admitted(_, let wake) = admission
    else {
        Issue.record("Expected admitted callback, got \(result)", sourceLocation: sourceLocation)
        preconditionFailure("Expected admitted callback")
    }
    return wake
}

func expectRetained(
    _ result: FilesystemObservationOfferResult,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    let receipt = requireOfferReceipt(result, sourceLocation: sourceLocation)
    guard case .retained = receipt.disposition else {
        Issue.record("Expected retained observation, got \(result)", sourceLocation: sourceLocation)
        return
    }
}

func expectRetainedCallback(
    _ result: DarwinFSEventObservationCaptureResult,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    guard case .retained = requireCallbackDisposition(result, sourceLocation: sourceLocation)
    else {
        Issue.record("Expected retained callback, got \(result)", sourceLocation: sourceLocation)
        return
    }
}

func requireLease(
    _ result: FilesystemObservationTakeDrainResult,
    sourceLocation: SourceLocation = #_sourceLocation
) -> FilesystemObservationDrainLease {
    guard case .lease(let lease) = result else {
        Issue.record("Expected filesystem observation lease, got \(result)", sourceLocation: sourceLocation)
        preconditionFailure("Expected filesystem observation lease")
    }
    return lease
}

func requireObservations(
    _ lease: FilesystemObservationDrainLease,
    sourceLocation: SourceLocation = #_sourceLocation
) -> [FSEventObservation] {
    switch lease.payload {
    case .contributions(let contributions),
        .contributionsWithRecovery(let contributions, _):
        let retainedContributions = [contributions.first] + contributions.remaining
        for contribution in retainedContributions {
            #expect(contribution.identity.binding == lease.binding)
            #expect(contribution.identity.isUUIDv7)
        }
        return retainedContributions.map { contribution in
            switch contribution {
            case .observation(_, let observation):
                return observation
            case .retirementFence:
                Issue.record(
                    "Expected observation contribution, got retirement fence",
                    sourceLocation: sourceLocation
                )
                preconditionFailure("Expected observation contribution")
            }
        }
    case .recovery:
        Issue.record("Expected observation-bearing lease", sourceLocation: sourceLocation)
        preconditionFailure("Expected observation-bearing lease")
    }
}

func requireRecovery(
    _ lease: FilesystemObservationDrainLease,
    sourceLocation: SourceLocation = #_sourceLocation
) -> FixedFilesystemRecoveryEvidenceSnapshot {
    switch lease.payload {
    case .contributionsWithRecovery(_, let recovery), .recovery(let recovery):
        return recovery
    case .contributions:
        Issue.record("Expected recovery-bearing lease", sourceLocation: sourceLocation)
        preconditionFailure("Expected recovery-bearing lease")
    }
}

func acceptRecovery(
    _ evidence: FixedFilesystemRecoveryEvidenceSnapshot,
    sourceLocation: SourceLocation = #_sourceLocation
) throws -> FilesystemSourceGateRecoveryAcceptance {
    var sourceGate = FilesystemSourceGate(binding: evidence.revision.binding)
    guard
        case .admitted(let acceptance) = sourceGate.acceptMailboxRecovery(
            evidence,
            trigger: .continuityLoss,
            watermark: .recoveryRevision(1),
            participants: makeRequiredParticipants()
        )
    else {
        Issue.record("source gate rejected recovery evidence", sourceLocation: sourceLocation)
        throw FixedSlotFilesystemObservationTestFailure.recoveryNotAccepted
    }
    return acceptance
}

func requiredRecoveryAdmissionContext() -> FilesystemObservationRecoveryAdmissionContext {
    .required(
        trigger: .continuityLoss,
        watermark: .recoveryRevision(1),
        participants: makeRequiredParticipants()
    )
}

func makeRequiredParticipants() -> Set<FilesystemRepairParticipantToken> {
    Set(
        [
            FilesystemRepairParticipantKind.contentRepairProjector,
            .gitWorkingDirectoryProjector,
            .paneFilesystemProjection,
        ].map {
            FilesystemRepairParticipantToken(
                kind: $0,
                participantID: UUID(),
                participantGeneration: 1
            )
        }
    )
}

func requireRecoveryAcceptance(
    _ result: FilesystemSourceGateRecoveryAdmissionResult,
    sourceLocation: SourceLocation = #_sourceLocation
) -> FilesystemSourceGateRecoveryAcceptance {
    guard case .admitted(let acceptance) = result else {
        Issue.record("mailbox recovery was not accepted: \(result)", sourceLocation: sourceLocation)
        preconditionFailure("Expected accepted mailbox recovery")
    }
    return acceptance
}

func expectAlreadyLeased(
    _ result: FilesystemObservationTakeDrainResult,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    guard case .alreadyLeased = result else {
        Issue.record("Expected outstanding-lease rejection", sourceLocation: sourceLocation)
        return
    }
}

func expectClosed(
    _ result: FilesystemObservationTakeDrainResult,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    guard case .closed = result else {
        Issue.record("expected closed drain result: \(result)", sourceLocation: sourceLocation)
        return
    }
}

final class CallbackPreWakeProbe:
    @unchecked Sendable, FilesystemObservationCallbackSynchronization
{
    private let mailbox: FilesystemObservationMailbox
    private let lock = NSLock()
    private var storedDoorbellState: AdmissionDoorbellStateSnapshot?

    init(mailbox: FilesystemObservationMailbox) {
        self.mailbox = mailbox
    }

    var observedDoorbellState: AdmissionDoorbellStateSnapshot? {
        lock.withLock { storedDoorbellState }
    }

    func afterAuthorityConsumedBeforeMailboxOffer() {}

    func afterMailboxOfferBeforeWakeApplication() {
        let doorbellState = mailbox.lifecyclePort.diagnostics.doorbellState
        lock.withLock { storedDoorbellState = doorbellState }
    }
}

struct AdapterFixture: Sendable {
    let registration: FSEventRegistrationToken
    let startingNativeLifetime: FilesystemObservationStartingNativeLifetime
    let mailbox: FilesystemObservationMailbox
    let controlBlock: FSEventRegistrationControlBlock
    let callbackAdmissionPort: FilesystemObservationCallbackAdmissionPort
    let adapter: DarwinFSEventObservationAdapter
}

func capture(
    fixture: AdapterFixture,
    reportedEventCount: Int? = nil,
    paths: CFArray,
    flags: [FSEventStreamEventFlags],
    eventIDs: [FSEventStreamEventId]
) -> DarwinFSEventObservationCaptureResult {
    capture(
        adapter: fixture.adapter,
        reportedEventCount: reportedEventCount ?? flags.count,
        eventPaths: Unmanaged.passUnretained(paths).toOpaque(),
        flags: flags,
        eventIDs: eventIDs
    )
}

func capture(
    adapter: DarwinFSEventObservationAdapter,
    paths: CFArray,
    flags: [FSEventStreamEventFlags],
    eventIDs: [FSEventStreamEventId]
) -> DarwinFSEventObservationCaptureResult {
    capture(
        adapter: adapter,
        reportedEventCount: flags.count,
        eventPaths: Unmanaged.passUnretained(paths).toOpaque(),
        flags: flags,
        eventIDs: eventIDs
    )
}

func capture(
    adapter: DarwinFSEventObservationAdapter,
    reportedEventCount: Int,
    eventPaths: UnsafeMutableRawPointer,
    flags: [FSEventStreamEventFlags],
    eventIDs: [FSEventStreamEventId]
) -> DarwinFSEventObservationCaptureResult {
    flags.withUnsafeBufferPointer { flagBuffer in
        eventIDs.withUnsafeBufferPointer { eventIDBuffer in
            adapter.capture(
                input: DarwinFSEventNativeCallbackInput(
                    capturedAt: ContinuousClock.now,
                    reportedEventCount: reportedEventCount,
                    eventPaths: eventPaths,
                    eventFlags: flagBuffer,
                    eventIDs: eventIDBuffer
                )
            )
        }
    }
}

func makeFixture(
    registrationGeneration: UInt64 = 19,
    captureLimits: FSEventCaptureLimits? = nil,
    synchronization: any FilesystemObservationCallbackSynchronization =
        ImmediateFilesystemObservationCallbackSynchronization()
) throws -> AdapterFixture {
    let registration = makeRegistration(registrationGeneration: registrationGeneration)
    let mailbox = try FilesystemObservationMailbox(
        generation: AdmissionGeneration(owner: .filesystemObservation, value: registrationGeneration),
        maximumSimultaneousSourceCount: 1,
        replacementReserveSlotCount: 0,
        limits: mailboxLimits()
    )
    guard case .enqueued = mailbox.installTestConfiguration(registration) else {
        throw AdapterFixtureError.fixtureConstructionFailed
    }
    guard case .selected(let selection) = mailbox.selectNextDesiredSource() else {
        throw AdapterFixtureError.fixtureConstructionFailed
    }
    guard
        case .committed(let startingNativeLifetime) =
            mailbox.beginNativeLifetime(selection.reservation)
    else {
        throw AdapterFixtureError.fixtureConstructionFailed
    }
    let controlBlock = try makeControlBlock(
        startingNativeLifetime: startingNativeLifetime,
        captureLimits: captureLimits ?? makeCaptureLimits(),
        callbackQueueLabel: "test.fsevent.observation.capture"
    )
    guard
        case .created(let nativeGenerationPorts) = mailbox.nativeGenerationPorts(
            for: startingNativeLifetime,
            synchronization: synchronization
        )
    else {
        throw AdapterFixtureError.fixtureConstructionFailed
    }
    return AdapterFixture(
        registration: registration,
        startingNativeLifetime: startingNativeLifetime,
        mailbox: mailbox,
        controlBlock: controlBlock,
        callbackAdmissionPort: nativeGenerationPorts.callbackAdmissionPort,
        adapter: DarwinFSEventObservationAdapter(
            controlBlock: controlBlock,
            callbackAdmissionPort: nativeGenerationPorts.callbackAdmissionPort
        )
    )
}

func makeRegistration(registrationGeneration: UInt64) -> FSEventRegistrationToken {
    FSEventRegistrationToken(
        sourceID: FilesystemSourceID(
            kind: .registeredWorktreeContent,
            rootID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        ),
        registrationGeneration: registrationGeneration,
        rootGeneration: 5
    )
}

func makeCaptureLimits(
    maximumInspected: Int = 8,
    maximumCopied: Int = 8,
    maximumBytes: Int = 4096,
    maximumSinglePathBytes: Int = 1024
) throws -> FSEventCaptureLimits {
    try FSEventCaptureLimits(
        maximumInspectedNativeRecords: maximumInspected,
        maximumCopiedRecords: maximumCopied,
        maximumCopiedUTF8Bytes: maximumBytes,
        maximumSinglePathUTF8Bytes: maximumSinglePathBytes
    )
}

func mailboxLimits() -> GatherMailboxLimits {
    GatherMailboxLimits(
        maximumDeclaredKeys: 1,
        maximumRetainedContributions: 8,
        maximumRetainedItems: 64,
        maximumRetainedBytes: 65_536,
        maximumRetainedContributionsPerKey: 8,
        maximumRetainedItemsPerKey: 64,
        maximumRetainedBytesPerKey: 65_536,
        maximumContributionsPerLease: 8,
        maximumItemsPerLease: 64,
        maximumBytesPerLease: 65_536,
        cleanupQuantum: .entriesAndBytes(maximumEntries: 8, maximumBytes: 65_536)
    )
}

func ordinaryFlags(count: Int) -> [FSEventStreamEventFlags] {
    Array(
        repeating: FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified),
        count: count
    )
}
