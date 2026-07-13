import Foundation
import Testing
import os

@testable import AgentStudio

enum GatherTestKey: String, Hashable, Sendable {
    case alpha
    case beta
    case gamma
}

struct GatherTestPayload: Equatable, Sendable {
    let label: String
}

final class GatherHashProbe: @unchecked Sendable {
    private struct State {
        var hashCount = 0
        var equalityCount = 0
        var onKeyOperation: (@Sendable () -> Void)?
    }

    private let lock = OSAllocatedUnfairLock(initialState: State())

    func recordHash() {
        let callback = lock.withLock { state in
            state.hashCount += 1
            return state.onKeyOperation
        }
        callback?()
    }

    func recordEquality() {
        let callback = lock.withLock { state in
            state.equalityCount += 1
            return state.onKeyOperation
        }
        callback?()
    }

    func reset(onKeyOperation: (@Sendable () -> Void)? = nil) {
        lock.withLock { state in
            state.hashCount = 0
            state.equalityCount = 0
            state.onKeyOperation = onKeyOperation
        }
    }

    var operationCount: Int {
        lock.withLock { $0.hashCount + $0.equalityCount }
    }

    var operationVector: GatherKeyOperationVector {
        lock.withLock {
            GatherKeyOperationVector(
                hashCount: $0.hashCount,
                equalityCount: $0.equalityCount
            )
        }
    }
}

struct GatherKeyOperationVector: Equatable, Hashable, Sendable {
    let hashCount: Int
    let equalityCount: Int

    static let untouched = Self(hashCount: 0, equalityCount: 0)
}

struct GatherHashProbeKey: Hashable, Sendable {
    let identifier: Int
    let probe: GatherHashProbe

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.probe.recordEquality()
        return lhs.identifier == rhs.identifier
    }

    func hash(into hasher: inout Hasher) {
        probe.recordHash()
        hasher.combine(identifier)
    }
}

final class ReentrantGatherPayload: @unchecked Sendable {
    let identifier: String
    private let onDeinitialize: @Sendable () -> Void

    init(identifier: String, onDeinitialize: @escaping @Sendable () -> Void) {
        self.identifier = identifier
        self.onDeinitialize = onDeinitialize
    }

    deinit {
        onDeinitialize()
    }
}

final class WeakGatherPayloadMailboxBox: @unchecked Sendable {
    weak var mailbox: BoundedGatherMailbox<GatherTestKey, ReentrantGatherPayload>?
}

final class GatherPayloadReleaseRecorder: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: [String]())

    func record(_ identifier: String) {
        lock.withLock { $0.append(identifier) }
    }

    var identifiers: [String] {
        lock.withLock { $0 }
    }
}

final class GatherReentrantClockProbe: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: 0)

    weak var mailbox: BoundedGatherMailbox<GatherTestKey, GatherTestPayload>?

    func reenterMailbox() {
        guard let mailbox else { return }
        _ = mailbox.lifecyclePort.authoritySnapshot
        lock.withLock { $0 += 1 }
    }

    var reentryCount: Int {
        lock.withLock { $0 }
    }
}

struct GatherReentrantClock: Clock {
    typealias Duration = Swift.Duration
    typealias Instant = ContinuousClock.Instant

    let probe: GatherReentrantClockProbe

    var now: Instant {
        probe.reenterMailbox()
        return ContinuousClock.now
    }

    var minimumResolution: Duration {
        ContinuousClock().minimumResolution
    }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        try await ContinuousClock().sleep(until: deadline, tolerance: tolerance)
    }
}

struct GatherMetadataIdentity: Hashable, Sendable {
    let key: Int
    let version: Int
}

final class GatherMetadataReleaseRecorder: @unchecked Sendable {
    private struct State {
        var releasedIdentities: [GatherMetadataIdentity] = []
        var reentrantCleanupResult: AdmissionCleanupTurnResult?
    }

    private let lock = OSAllocatedUnfairLock(initialState: State())

    func recordReleased(_ identity: GatherMetadataIdentity) {
        lock.withLock { $0.releasedIdentities.append(identity) }
    }

    func recordReentrantCleanup(_ result: AdmissionCleanupTurnResult) {
        lock.withLock { $0.reentrantCleanupResult = result }
    }

    var identities: [GatherMetadataIdentity] {
        lock.withLock { $0.releasedIdentities }
    }

    var reentrantResult: AdmissionCleanupTurnResult? {
        lock.withLock { $0.reentrantCleanupResult }
    }
}

final class GatherMetadataCleanupGate: @unchecked Sendable {
    let destructorEntered = DispatchSemaphore(value: 0)
    let releaseDestructor = DispatchSemaphore(value: 0)
    let cleanupCompleted = DispatchSemaphore(value: 0)
}

final class GatherMetadataMailboxReference: @unchecked Sendable {
    let generation: AdmissionGeneration
    weak var mailbox: BoundedGatherMailbox<GatherHashProbeKey, GatherMetadataPayload>?

    init(generation: AdmissionGeneration) {
        self.generation = generation
    }
}

final class GatherMetadataPayload: @unchecked Sendable {
    let identity: GatherMetadataIdentity
    private let recorder: GatherMetadataReleaseRecorder
    private let mailboxReference: GatherMetadataMailboxReference?
    private let cleanupGate: GatherMetadataCleanupGate?

    init(
        identity: GatherMetadataIdentity,
        recorder: GatherMetadataReleaseRecorder,
        mailboxReference: GatherMetadataMailboxReference? = nil,
        cleanupGate: GatherMetadataCleanupGate? = nil
    ) {
        self.identity = identity
        self.recorder = recorder
        self.mailboxReference = mailboxReference
        self.cleanupGate = cleanupGate
    }

    deinit {
        if let mailboxReference, let cleanupGate {
            let result =
                mailboxReference.mailbox?.lifecyclePort.performCleanup(
                    generation: mailboxReference.generation
                ) ?? .empty
            recorder.recordReentrantCleanup(result)
            cleanupGate.destructorEntered.signal()
            cleanupGate.releaseDestructor.wait()
        }
        recorder.recordReleased(identity)
    }
}

final class WeakGatherMetadataPayload: @unchecked Sendable {
    weak var payload: GatherMetadataPayload?

    init(_ payload: GatherMetadataPayload) {
        self.payload = payload
    }
}

final class GatherMetadataCleanupResultBox: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock<AdmissionCleanupTurnResult?>(initialState: nil)

    func store(_ result: AdmissionCleanupTurnResult) {
        lock.withLock { $0 = result }
    }

    var result: AdmissionCleanupTurnResult? {
        lock.withLock { $0 }
    }
}

func hashProbeLimits(
    maximumDeclaredKeys: Int,
    maximumContributions: Int
) -> GatherMailboxLimits {
    GatherMailboxLimits(
        maximumDeclaredKeys: maximumDeclaredKeys,
        maximumRetainedContributions: maximumContributions,
        maximumRetainedItems: maximumContributions,
        maximumRetainedBytes: maximumContributions,
        maximumRetainedContributionsPerKey: maximumContributions,
        maximumRetainedItemsPerKey: maximumContributions,
        maximumRetainedBytesPerKey: maximumContributions,
        maximumContributionsPerLease: maximumContributions,
        maximumItemsPerLease: maximumContributions,
        maximumBytesPerLease: maximumContributions,
        cleanupQuantum: .entriesAndBytes(
            maximumEntries: max(1, maximumContributions),
            maximumBytes: max(1, maximumContributions)
        )
    )
}

func requireAdmission(
    _ result: GatherOfferResult<GatherTestKey>,
    sourceLocation: SourceLocation = #_sourceLocation
) -> GatherAdmissionDisposition<GatherTestKey> {
    guard case .admitted(let admission, _) = result else {
        Issue.record(
            "Expected admitted gather result, got \(String(reflecting: result))", sourceLocation: sourceLocation)
        preconditionFailure("Expected admitted gather result")
    }
    return admission
}

func requireLease(
    _ result: GatherTakeDrainResult<GatherTestKey, GatherTestPayload>,
    sourceLocation: SourceLocation = #_sourceLocation
) -> GatherDrainLease<GatherTestKey, GatherTestPayload> {
    guard case .lease(let lease) = result else {
        Issue.record(
            "Expected single-key gather lease, got \(String(reflecting: result))", sourceLocation: sourceLocation)
        preconditionFailure("Expected gather lease")
    }
    return lease
}

func expectInvalidFootprint(
    _ result: GatherOfferResult<GatherTestKey>,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    guard case .invalidFootprint = result else {
        Issue.record(
            "Expected invalid-footprint rejection, got \(String(reflecting: result))", sourceLocation: sourceLocation)
        return
    }
}

func requireGenericAdmission<Key: Hashable & Sendable>(
    _ result: GatherOfferResult<Key>,
    sourceLocation: SourceLocation = #_sourceLocation
) -> GatherAdmissionDisposition<Key> {
    guard case .admitted(let admission, _) = result else {
        Issue.record(
            "Expected admitted gather result, got \(String(reflecting: result))",
            sourceLocation: sourceLocation
        )
        preconditionFailure("Expected admitted gather result")
    }
    return admission
}

func requireReentrantLease(
    _ result: GatherTakeDrainResult<GatherTestKey, ReentrantGatherPayload>,
    sourceLocation: SourceLocation = #_sourceLocation
) -> GatherDrainLease<GatherTestKey, ReentrantGatherPayload> {
    guard case .lease(let lease) = result else {
        Issue.record(
            "Expected reentrant gather lease, got \(String(reflecting: result))",
            sourceLocation: sourceLocation
        )
        preconditionFailure("Expected reentrant gather lease")
    }
    return lease
}

extension NonEmptyAdmissionBatch {
    var testValues: [Element] { [first] + remaining }
}

func requireContributions<Key: Hashable & Sendable, Payload: Sendable>(
    _ lease: GatherDrainLease<Key, Payload>,
    sourceLocation: SourceLocation = #_sourceLocation
) -> NonEmptyAdmissionBatch<GatherContribution<Key, Payload>> {
    switch lease.payload {
    case .contributions(let contributions),
        .contributionsWithRecovery(let contributions, _):
        return contributions
    case .recovery:
        Issue.record("Expected contribution-bearing gather lease", sourceLocation: sourceLocation)
        preconditionFailure("Expected contribution-bearing gather lease")
    }
}

func requireRecoveryRevision<Key: Hashable & Sendable>(
    _ disposition: GatherAdmissionDisposition<Key>,
    sourceLocation: SourceLocation = #_sourceLocation
) -> GatherRecoveryRevision<Key> {
    switch disposition {
    case .retained:
        Issue.record("Expected recovery-bearing admission", sourceLocation: sourceLocation)
        preconditionFailure("Expected recovery-bearing admission")
    case .retainedWithRecovery(let revision), .contractedToRecovery(let revision, _):
        return revision
    }
}

func expectRetainedWithoutRecovery<Key: Hashable & Sendable>(
    _ disposition: GatherAdmissionDisposition<Key>,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    guard case .retained = disposition else {
        Issue.record("Expected retained admission without recovery", sourceLocation: sourceLocation)
        return
    }
}

func requireRetainedRecoveryRevision<Key: Hashable & Sendable>(
    _ disposition: GatherAdmissionDisposition<Key>,
    sourceLocation: SourceLocation = #_sourceLocation
) -> GatherRecoveryRevision<Key> {
    guard case .retainedWithRecovery(let revision) = disposition else {
        Issue.record("Expected retained admission with recovery", sourceLocation: sourceLocation)
        preconditionFailure("Expected retained admission with recovery")
    }
    return revision
}

func requireContractedRecoveryRevision<Key: Hashable & Sendable>(
    _ disposition: GatherAdmissionDisposition<Key>,
    sourceLocation: SourceLocation = #_sourceLocation
) -> GatherRecoveryRevision<Key> {
    guard case .contractedToRecovery(let revision, _) = disposition else {
        Issue.record("Expected contracted recovery admission", sourceLocation: sourceLocation)
        preconditionFailure("Expected contracted recovery admission")
    }
    return revision
}

func requireContractionCause<Key: Hashable & Sendable>(
    _ disposition: GatherAdmissionDisposition<Key>,
    sourceLocation: SourceLocation = #_sourceLocation
) -> GatherContractionCause {
    guard case .contractedToRecovery(_, let cause) = disposition else {
        Issue.record("Expected contracted recovery admission", sourceLocation: sourceLocation)
        preconditionFailure("Expected contracted recovery admission")
    }
    return cause
}

struct GatherCleanupReleaseCounts {
    let entries: Int
    let bytes: Int
}

func requireEntryAndByteRelease(
    _ turn: AdmissionCleanupTurn,
    sourceLocation: SourceLocation = #_sourceLocation
) -> GatherCleanupReleaseCounts {
    guard case .entriesAndBytes(let entries, let bytes) = turn.release else {
        Issue.record("Expected entry-and-byte gather cleanup release", sourceLocation: sourceLocation)
        preconditionFailure("Expected entry-and-byte gather cleanup release")
    }
    return GatherCleanupReleaseCounts(entries: entries, bytes: bytes)
}

func requireRecoveryRevision<Key: Hashable & Sendable, Payload: Sendable>(
    _ lease: GatherDrainLease<Key, Payload>,
    sourceLocation: SourceLocation = #_sourceLocation
) -> GatherRecoveryRevision<Key> {
    switch lease.payload {
    case .contributions:
        Issue.record("Expected recovery-bearing gather lease", sourceLocation: sourceLocation)
        preconditionFailure("Expected recovery-bearing gather lease")
    case .contributionsWithRecovery(_, let revision), .recovery(let revision):
        return revision
    }
}
