import Foundation
import Testing
import os

@testable import AgentStudio

enum JournalFact: Sendable, Equatable {
    case started
    case command(String)
    case finished(Int32)
    case closed
}

struct JournalSnapshot: Sendable, Equatable {
    let value: String
}

struct AdmittedResult {
    let sequence: UInt64
    let wake: AdmissionWakeDirective
}

struct FactDrainResult {
    let token: AdmissionDrainToken
    let facts: [SequencedFact<JournalFact>]
}

struct PersistentGapDrainResult {
    let token: AdmissionDrainToken
    let gap: FactGap
}

struct ExactReplayResult {
    let facts: [SequencedFact<JournalFact>]
    let nextSequence: UInt64
}

struct SnapshotReplayResult {
    let snapshot: SequencedSnapshot<JournalSnapshot>
    let followingFacts: [SequencedFact<JournalFact>]
    let nextSequence: UInt64
}

struct CurrentStateResult {
    let snapshot: SequencedSnapshot<JournalSnapshot>?
    let latestSequence: UInt64
    let isSealed: Bool
}

struct SequencedFactOracle: Equatable {
    let sequence: UInt64
    let fact: JournalFact
}

struct JournalTestHarness<Fact: Sendable, Snapshot: Sendable>: Sendable {
    let journal: OrderedFactJournal<Fact, Snapshot>
    let producer: OrderedFactProducerPort<Fact, Snapshot>
    let consumer: OrderedFactConsumerPort<Fact, Snapshot>
    let lifecycle: OrderedFactLifecyclePort<Fact, Snapshot>
    let binding: AdmissionConsumerBinding

    init(journal: OrderedFactJournal<Fact, Snapshot>) {
        self.journal = journal
        producer = journal.producerPort
        consumer = journal.consumerPort
        lifecycle = journal.lifecyclePort
        binding = consumer.bindConsumer().binding
    }
}

final class ReentrantJournalFact: @unchecked Sendable {
    let identifier: String
    private let onDeinitialize: @Sendable () -> Void

    init(
        identifier: String,
        onDeinitialize: @escaping @Sendable () -> Void
    ) {
        self.identifier = identifier
        self.onDeinitialize = onDeinitialize
    }

    deinit {
        onDeinitialize()
    }
}

struct ReentrantJournalSnapshot: Sendable {
    let payload: ReentrantJournalFact
}

final class ReentrantJournalBox: @unchecked Sendable {
    weak var journal: OrderedFactJournal<ReentrantJournalFact, ReentrantJournalSnapshot>?
}

final class JournalReleaseRecorder: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: [String]())

    func record(_ identifier: String) {
        lock.withLock { identifiers in
            identifiers.append(identifier)
        }
    }

    var identifiers: [String] {
        lock.withLock { $0 }
    }
}

final class JournalClockReentryBox: @unchecked Sendable {
    weak var journal: OrderedFactJournal<JournalFact, JournalSnapshot>?
}

final class JournalClockRecorder: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: UInt64.zero)

    func recordSample() -> Duration {
        lock.withLock { count in
            incrementAdmissionCounter(&count)
            return .seconds(Int64(clamping: count))
        }
    }

    var sampleCount: UInt64 {
        lock.withLock { $0 }
    }
}

final class JournalCleanupGate: @unchecked Sendable {
    let entered = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)
    let completed = DispatchSemaphore(value: 0)
}

final class JournalCleanupResultBox<Result: Sendable>: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock<Result?>(initialState: nil)

    func store(_ result: Result) {
        lock.withLock { $0 = result }
    }

    var value: Result? {
        lock.withLock { $0 }
    }
}

func makeGeneration(_ value: UInt64) -> AdmissionGeneration {
    AdmissionGeneration(
        owner: .runtimeFacts,
        value: value
    )
}

func makeJournal(
    generation: AdmissionGeneration,
    maximumRetainedFacts: Int = 16,
    maximumRetainedBytes: Int = 1024,
    maximumSnapshotBytes: Int = 1024,
    snapshotLimits: OrderedFactSnapshotLimits? = nil,
    maximumDrainFacts: Int = 16,
    cleanupQuantum: AdmissionCleanupQuantum? = nil,
    initialSequence: UInt64 = 0,
    initialSnapshot: JournalSnapshot? = nil,
    initialSnapshotBytes: Int = 16,
    authoritySeeds: OrderedFactJournalAuthoritySeeds = .initial
) -> JournalTestHarness<JournalFact, JournalSnapshot> {
    let effectiveSnapshotLimits =
        snapshotLimits
        ?? OrderedFactSnapshotLimits(
            maximumSnapshotBytes: maximumSnapshotBytes,
            maximumPhysicalSnapshotCount: Int.max,
            maximumPhysicalSnapshotBytes: Int.max
        )
    return JournalTestHarness(
        journal: try! OrderedFactJournal(
            generation: generation,
            maximumRetainedFacts: maximumRetainedFacts,
            maximumRetainedBytes: maximumRetainedBytes,
            snapshotLimits: effectiveSnapshotLimits,
            maximumDrainFacts: maximumDrainFacts,
            cleanupQuantum: cleanupQuantum
                ?? AdmissionCleanupQuantum(
                    maximumEntries: 17,
                    maximumBytes: Swift.max(maximumRetainedBytes, maximumSnapshotBytes)
                ),
            initialSequence: initialSequence,
            initialSnapshot: initialSnapshot,
            initialSnapshotBytes: initialSnapshot == nil ? 0 : initialSnapshotBytes,
            authoritySeeds: authoritySeeds
        ))
}

func makeJournal<C: Clock>(
    generation: AdmissionGeneration,
    maximumRetainedFacts: Int = 16,
    maximumRetainedBytes: Int = 1024,
    maximumSnapshotBytes: Int = 1024,
    maximumDrainFacts: Int = 16,
    cleanupQuantum: AdmissionCleanupQuantum? = nil,
    initialSequence: UInt64 = 0,
    initialSnapshot: JournalSnapshot? = nil,
    initialSnapshotBytes: Int = 16,
    clock: C,
    authoritySeeds: OrderedFactJournalAuthoritySeeds = .initial
) -> JournalTestHarness<JournalFact, JournalSnapshot> where C.Duration == Duration, C: Sendable {
    JournalTestHarness(
        journal: try! OrderedFactJournal(
            generation: generation,
            maximumRetainedFacts: maximumRetainedFacts,
            maximumRetainedBytes: maximumRetainedBytes,
            snapshotLimits: OrderedFactSnapshotLimits(
                maximumSnapshotBytes: maximumSnapshotBytes,
                maximumPhysicalSnapshotCount: Int.max,
                maximumPhysicalSnapshotBytes: Int.max
            ),
            maximumDrainFacts: maximumDrainFacts,
            cleanupQuantum: cleanupQuantum
                ?? AdmissionCleanupQuantum(
                    maximumEntries: 17,
                    maximumBytes: Swift.max(maximumRetainedBytes, maximumSnapshotBytes)
                ),
            initialSequence: initialSequence,
            initialSnapshot: initialSnapshot,
            initialSnapshotBytes: initialSnapshot == nil ? 0 : initialSnapshotBytes,
            admissionClock: .make(clock: clock),
            authoritySeeds: authoritySeeds
        ))
}

func makeReentrantJournal(
    generation: AdmissionGeneration,
    maximumRetainedFacts: Int = 16,
    maximumRetainedBytes: Int = 1024,
    maximumDrainFacts: Int = 16
) -> JournalTestHarness<ReentrantJournalFact, ReentrantJournalSnapshot> {
    JournalTestHarness(
        journal: try! OrderedFactJournal(
            generation: generation,
            maximumRetainedFacts: maximumRetainedFacts,
            maximumRetainedBytes: maximumRetainedBytes,
            snapshotLimits: OrderedFactSnapshotLimits(
                maximumSnapshotBytes: 1024,
                maximumPhysicalSnapshotCount: Int.max,
                maximumPhysicalSnapshotBytes: Int.max
            ),
            maximumDrainFacts: maximumDrainFacts,
            cleanupQuantum: AdmissionCleanupQuantum(maximumEntries: 17, maximumBytes: 1024),
            initialSnapshot: nil,
            initialSnapshotBytes: 0
        ))
}

func makeReentrantClockJournal(
    generation: AdmissionGeneration,
    box: JournalClockReentryBox,
    recorder: JournalClockRecorder
) -> JournalTestHarness<JournalFact, JournalSnapshot> {
    let admissionClock = AdmissionClock {
        if let journal = box.journal {
            _ = journal.consumerPort.currentState(generation: generation)
        }
        return recorder.recordSample()
    }
    let harness: JournalTestHarness<JournalFact, JournalSnapshot> = JournalTestHarness(
        journal: try! OrderedFactJournal(
            generation: generation,
            maximumRetainedFacts: 16,
            maximumRetainedBytes: 1024,
            snapshotLimits: OrderedFactSnapshotLimits(
                maximumSnapshotBytes: 1024,
                maximumPhysicalSnapshotCount: Int.max,
                maximumPhysicalSnapshotBytes: Int.max
            ),
            maximumDrainFacts: 1,
            cleanupQuantum: AdmissionCleanupQuantum(maximumEntries: 17, maximumBytes: 1024),
            initialSnapshot: nil,
            initialSnapshotBytes: 0,
            admissionClock: admissionClock
        ))
    box.journal = harness.journal
    return harness
}

func makeReentrantFact(
    identifier: String,
    box: ReentrantJournalBox,
    recorder: JournalReleaseRecorder
) -> ReentrantJournalFact {
    ReentrantJournalFact(identifier: identifier) {
        if let journal = box.journal {
            _ = journal.lifecyclePort.diagnostics
        }
        recorder.record(identifier)
    }
}

func reentrantFactDrainToken(
    _ result: OrderedFactTakeDrainResult<ReentrantJournalFact>
) -> AdmissionDrainToken? {
    guard case .drain(let drain) = result else { return nil }
    guard case .facts = drain.payload else { return nil }
    return drain.token
}

func makeJournalValidatingInitialSnapshot(
    generation: AdmissionGeneration,
    maximumRetainedFacts: Int = 16,
    maximumRetainedBytes: Int = 1024,
    maximumSnapshotBytes: Int,
    maximumDrainFacts: Int = 16,
    initialSequence: UInt64 = 0,
    initialSnapshot: JournalSnapshot?,
    initialSnapshotBytes: Int
) throws -> OrderedFactJournal<JournalFact, JournalSnapshot> {
    try OrderedFactJournal(
        generation: generation,
        maximumRetainedFacts: maximumRetainedFacts,
        maximumRetainedBytes: maximumRetainedBytes,
        snapshotLimits: OrderedFactSnapshotLimits(
            maximumSnapshotBytes: maximumSnapshotBytes,
            maximumPhysicalSnapshotCount: Int.max,
            maximumPhysicalSnapshotBytes: Int.max
        ),
        maximumDrainFacts: maximumDrainFacts,
        cleanupQuantum: AdmissionCleanupQuantum(
            maximumEntries: 17,
            maximumBytes: Swift.max(maximumRetainedBytes, maximumSnapshotBytes)
        ),
        initialSequence: initialSequence,
        initialSnapshot: initialSnapshot,
        initialSnapshotBytes: initialSnapshot == nil ? 0 : initialSnapshotBytes
    )
}

func makeGappedJournal(
    generation: AdmissionGeneration
) -> JournalTestHarness<JournalFact, JournalSnapshot> {
    let journal = makeJournal(
        generation: generation,
        maximumRetainedFacts: 2,
        maximumRetainedBytes: 1024,
        maximumDrainFacts: 2,
        initialSnapshot: JournalSnapshot(value: "idle")
    )
    _ = journal.producer.offer(
        generation: generation,
        fact: .started,
        estimatedFactBytes: 8,
        snapshotReplacement: snapshotReplacement("running", bytes: 16)
    )
    _ = journal.producer.offer(
        generation: generation,
        fact: .command("build"),
        estimatedFactBytes: 8,
        snapshotReplacement: nil
    )
    _ = journal.producer.offer(
        generation: generation,
        fact: .finished(0),
        estimatedFactBytes: 8,
        snapshotReplacement: nil
    )
    performJournalCleanupToQuiescence(journal.lifecycle, generation: generation)
    return journal
}

func performJournalCleanupToQuiescence<Fact: Sendable, Snapshot: Sendable>(
    _ lifecycle: OrderedFactLifecyclePort<Fact, Snapshot>,
    generation: AdmissionGeneration
) {
    while case .performed = lifecycle.performCleanup(generation: generation) {}
}

func admitAndTransferThreeFacts(
    _ journal: JournalTestHarness<JournalFact, JournalSnapshot>,
    generation: AdmissionGeneration,
    finalSnapshot: String
) {
    _ = journal.producer.offer(
        generation: generation,
        fact: .started,
        estimatedFactBytes: 8,
        snapshotReplacement: snapshotReplacement("running", bytes: 16)
    )
    _ = journal.producer.offer(
        generation: generation,
        fact: .command("build"),
        estimatedFactBytes: 8,
        snapshotReplacement: nil
    )
    if let drain = factDrain(journal.consumer.takeDrain(binding: journal.binding, generation: generation)) {
        _ = journal.consumer.acknowledge(drain.token, disposition: .transferred)
    }
    _ = journal.producer.offer(
        generation: generation,
        fact: .finished(0),
        estimatedFactBytes: 8,
        snapshotReplacement: snapshotReplacement(finalSnapshot, bytes: 16)
    )
}

func snapshotReplacement(
    _ value: String,
    bytes: Int
) -> OrderedFactSnapshotReplacement<JournalSnapshot> {
    OrderedFactSnapshotReplacement(
        snapshot: JournalSnapshot(value: value),
        estimatedBytes: bytes
    )
}

func sequenceOracle(
    _ facts: [SequencedFact<JournalFact>]
) -> [SequencedFactOracle] {
    facts.map { SequencedFactOracle(sequence: $0.sequence, fact: $0.fact) }
}

func admittedResult(
    _ result: OrderedFactOfferResult
) -> AdmittedResult? {
    guard case .admitted(let sequence, let wake) = result else { return nil }
    return AdmittedResult(sequence: sequence, wake: wake)
}

func admittedSequence(_ result: OrderedFactOfferResult) -> UInt64? {
    admittedResult(result)?.sequence
}

func admittedWake(_ result: OrderedFactOfferResult) -> AdmissionWakeDirective? {
    admittedResult(result)?.wake
}

func gapCommittedResult(
    _ result: OrderedFactOfferResult
) -> (gap: FactGap, wake: AdmissionWakeDirective)? {
    guard case .gapCommitted(let gap, let wake) = result else { return nil }
    return (gap, wake)
}

func isStaleGeneration(_ result: OrderedFactOfferResult) -> Bool {
    guard case .staleGeneration = result else { return false }
    return true
}

func isClosedOffer(_ result: OrderedFactOfferResult) -> Bool {
    guard case .closed = result else { return false }
    return true
}

func isTypedSnapshotOfferRejection(_ result: OrderedFactOfferResult) -> Bool {
    guard case .snapshotTooLarge = result else { return false }
    return true
}

func isAuthorityExhaustedOffer(_ result: OrderedFactOfferResult) -> Bool {
    guard case .authorityExhausted = result else { return false }
    return true
}

func factDrain(
    _ result: OrderedFactTakeDrainResult<JournalFact>
) -> FactDrainResult? {
    guard case .drain(let drain) = result else { return nil }
    guard case .facts(let facts) = drain.payload else { return nil }
    return FactDrainResult(token: drain.token, facts: facts)
}

func persistentGapDrain(
    _ result: OrderedFactTakeDrainResult<JournalFact>
) -> PersistentGapDrainResult? {
    guard case .drain(let drain) = result else { return nil }
    guard case .gap(let gap) = drain.payload else { return nil }
    return PersistentGapDrainResult(token: drain.token, gap: gap)
}

func isEmptyDrain(_ result: OrderedFactTakeDrainResult<JournalFact>) -> Bool {
    guard case .empty = result else { return false }
    return true
}

func isAlreadyDraining(_ result: OrderedFactTakeDrainResult<JournalFact>) -> Bool {
    guard case .alreadyDraining = result else { return false }
    return true
}

func isClosedDrain(_ result: OrderedFactTakeDrainResult<JournalFact>) -> Bool {
    guard case .closed = result else { return false }
    return true
}

func exactReplay(
    _ completion: OrderedFactReplayCompletion<JournalFact, JournalSnapshot>
) -> ExactReplayResult? {
    guard case .facts(let facts, let nextSequence) = completion.result else { return nil }
    return ExactReplayResult(facts: facts, nextSequence: nextSequence)
}

func replayHistoryGap(
    _ completion: OrderedFactReplayCompletion<JournalFact, JournalSnapshot>
) -> ReplayHistoryGap<JournalFact>? {
    guard case .historyGap(let gap) = completion.result else { return nil }
    return gap
}

func snapshotReplayResult(
    _ completion: OrderedFactReplayCompletion<JournalFact, JournalSnapshot>
) -> SnapshotReplayResult? {
    guard case .snapshot(let snapshot, let followingFacts, let nextSequence) = completion.result else {
        return nil
    }
    return SnapshotReplayResult(
        snapshot: snapshot,
        followingFacts: followingFacts,
        nextSequence: nextSequence
    )
}

func persistentReplayGap(
    _ completion: OrderedFactReplayCompletion<JournalFact, JournalSnapshot>
) -> FactGap? {
    guard case .factGap(let gap) = completion.result else { return nil }
    return gap
}

func currentState(
    _ result: OrderedFactCurrentStateResult<JournalSnapshot>
) -> CurrentStateResult? {
    guard case .current(let snapshot, let latestSequence, let isSealed) = result else { return nil }
    return CurrentStateResult(
        snapshot: snapshot,
        latestSequence: latestSequence,
        isSealed: isSealed
    )
}

func nonCurrentGap(
    _ result: OrderedFactCurrentStateResult<JournalSnapshot>
) -> FactGap? {
    guard case .nonCurrent(let gap) = result else { return nil }
    return gap
}

func isInvalidatedState(
    _ result: OrderedFactCurrentStateResult<JournalSnapshot>
) -> Bool {
    guard case .invalidated = result else { return false }
    return true
}

func isInvalidatedReplay(
    _ completion: OrderedFactReplayCompletion<JournalFact, JournalSnapshot>
) -> Bool {
    guard case .invalidated = completion.result else { return false }
    return true
}
