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
        @MainActor (
            State, PushTransport, RevisionClock, @escaping EpochProvider
        ) -> Task<Void, Never>
}

/// Value-level observation slice. Captures a snapshot from @Observable state,
/// compares with previous via Equatable, and pushes when changed.
///
/// Hot slices push immediately. Warm/cold slices debounce by PushLevel duration.
/// Cold payloads encode off-main-actor. Hot/warm encode on-main-actor.
///
/// Design doc section 6.5.
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

    func erased() -> AnyPushSlice<State> {
        let capture = self.capture
        let level = self.level
        let op = self.op
        let store = self.store
        let name = self.name

        return AnyPushSlice(name: name) { state, transport, revisions, epochProvider in
            Task { @MainActor in
                var prev: Snapshot?
                let encoder = JSONEncoder()

                let stream = Observations { capture(state) }

                if level == .hot {
                    for await snapshot in stream {
                        guard snapshot != prev else { continue }
                        prev = snapshot
                        let revision = revisions.next(for: store)
                        let epoch = epochProvider()
                        let data: Data
                        do {
                            data = try encoder.encode(snapshot)
                        } catch {
                            logger.error("[PushEngine] encode failed slice=\(name) store=\(store.rawValue): \(error)")
                            continue
                        }
                        await transport.pushJSON(
                            store: store, op: op, level: level,
                            revision: revision, epoch: epoch, json: data
                        )
                    }
                } else {
                    for await snapshot in stream.debounce(for: level.debounce) {
                        guard snapshot != prev else { continue }
                        prev = snapshot
                        let revision = revisions.next(for: store)
                        let epoch = epochProvider()

                        let data: Data
                        if level == .cold {
                            do {
                                data = try await Task.detached(priority: .utility) {
                                    try encoder.encode(snapshot)
                                }.value
                            } catch {
                                logger.error(
                                    "[PushEngine] encode failed slice=\(name) store=\(store.rawValue): \(error)")
                                continue
                            }
                        } else {
                            do {
                                data = try encoder.encode(snapshot)
                            } catch {
                                logger.error(
                                    "[PushEngine] encode failed slice=\(name) store=\(store.rawValue): \(error)")
                                continue
                            }
                        }

                        await transport.pushJSON(
                            store: store, op: op, level: level,
                            revision: revision, epoch: epoch, json: data
                        )
                    }
                }
            }
        }
    }
}
