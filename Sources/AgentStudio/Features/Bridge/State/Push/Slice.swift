import AsyncAlgorithms
import Foundation
import Observation
import os.log

private let logger = Logger(subsystem: "com.agentstudio", category: "PushEngine")

/// Reads the current epoch from domain state at push time.
typealias EpochProvider = @MainActor () -> Int

/// Type-erased push slice. Holds a closure that creates the observation
/// task for this slice when the engine starts.
struct AnyPushSlice<State: Observable & AnyObject> {
    let name: String
    let makeTask:
        @Sendable @MainActor (
            State, PushTransport, RevisionClock, @escaping EpochProvider
        ) -> Task<Void, Never>
}

/// Value-level observation slice. Captures a snapshot from @Observable state,
/// compares with previous via Equatable, and pushes when changed.
///
/// Hot slices push immediately. Warm/cold slices debounce by PushLevel duration.
/// Cold payloads encode off-main-actor. Hot/warm encode on-main-actor.
///
/// See bridge push architecture docs for slice semantics.
struct Slice<State: Observable & AnyObject, Snapshot: Encodable & Equatable & Sendable> {
    let name: String
    let store: StoreKey
    let level: PushLevel
    let op: PushOp
    let capture: @MainActor @Sendable (State) -> Snapshot

    init(
        _ name: String,
        store: StoreKey,
        level: PushLevel,
        op: PushOp = .replace,
        capture: @escaping @MainActor @Sendable (State) -> Snapshot
    ) {
        self.name = name
        self.store = store
        self.level = level
        self.op = op
        self.capture = capture
    }

    /// Encode cold payloads off MainActor on cooperative pool (Swift 6.2, SE-0461).
    /// Preserves priority and task-locals that detached tasks would strip.
    @concurrent
    private static func encodeColdPayload(_ snapshot: Snapshot) async throws -> Data {
        let coldEncoder = JSONEncoder()
        coldEncoder.outputFormatting = .sortedKeys
        return try coldEncoder.encode(snapshot)
    }

    func erased<C: Clock & Sendable>(
        debounceClock: C = ContinuousClock()
    ) -> AnyPushSlice<State> where C.Duration == Duration {
        let capture = self.capture
        let level = self.level
        let op = self.op
        let store = self.store
        let name = self.name
        let debounceClock = debounceClock

        return AnyPushSlice(name: name) { state, transport, revisions, epochProvider in
            Task { @MainActor in
                var prev: Snapshot?
                let encoder = JSONEncoder()
                encoder.outputFormatting = .sortedKeys

                let stream = Observations { capture(state) }
                let source: any AsyncSequence<Snapshot, Never> =
                    level == .hot ? stream : stream.debounce(for: level.debounce, clock: debounceClock)

                for await snapshot in source {
                    guard snapshot != prev else { continue }
                    let revision = revisions.next(for: store)
                    let epoch = epochProvider()

                    let data: Data
                    do {
                        if level == .cold {
                            // Off-main cold snapshot encoding prevents large payload serialization
                            // from blocking MainActor. @concurrent runs on cooperative pool (SE-0461).
                            data = try await Self.encodeColdPayload(snapshot)
                        } else {
                            data = try encoder.encode(snapshot)
                        }
                    } catch {
                        logger.error("[PushEngine] encode failed slice=\(name) store=\(store.rawValue): \(error)")
                        // Advance local snapshot state even on encode failure so we do not
                        // loop forever on an unencodable payload.
                        prev = snapshot
                        continue
                    }
                    prev = snapshot

                    await transport.pushJSON(
                        store: store, op: op, level: level,
                        revision: revision, epoch: epoch, json: data
                    )
                }
            }
        }
    }
}
