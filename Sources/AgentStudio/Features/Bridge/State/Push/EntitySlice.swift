import AsyncAlgorithms
import Foundation
import Observation
import os.log

private let logger = Logger(subsystem: "com.agentstudio", category: "PushEngine")

// MARK: - EntityDelta

/// Wire format for entity deltas. Keys are always String (normalized from Key type).
/// Omits empty fields to minimize payload size.
struct EntityDelta<Entity: Encodable & Sendable>: Encodable {
    let changed: [String: Entity]?
    let removed: [String]?

    var isEmpty: Bool { (changed?.isEmpty ?? true) && (removed?.isEmpty ?? true) }
}

// MARK: - EntitySlice

/// Keyed collection observation slice with per-entity diff.
///
/// Observes a dictionary from @Observable state, computes per-entity diffs using
/// version comparisons, and pushes only changed entities. Keys are normalized
/// to String for JSON wire format safety.
///
/// See bridge push architecture docs for entity-delta semantics.
struct EntitySlice<
    State: Observable & AnyObject,
    Key: Hashable & Sendable,
    Entity: Encodable & Sendable
> {
    let name: String
    let store: StoreKey
    let level: PushLevel
    let capture: @MainActor @Sendable (State) -> [Key: Entity]
    let version: @Sendable (Entity) -> Int
    let keyToString: @Sendable (Key) -> String

    init(
        _ name: String,
        store: StoreKey,
        level: PushLevel,
        capture: @escaping @MainActor @Sendable (State) -> [Key: Entity],
        version: @escaping @Sendable (Entity) -> Int,
        keyToString: @escaping @Sendable (Key) -> String = { "\($0)" }
    ) {
        self.name = name
        self.store = store
        self.level = level
        self.capture = capture
        self.version = version
        self.keyToString = keyToString
    }

    func erased<C: Clock>(
        debounceClock: C = ContinuousClock()
    ) -> AnyPushSlice<State> where C.Duration == Duration {
        let capture = self.capture
        let version = self.version
        let keyToString = self.keyToString
        let level = self.level
        let store = self.store
        let name = self.name
        let debounceClock = debounceClock

        return AnyPushSlice(name: name) { state, transport, revisions, epochProvider in
            let epochFn = epochProvider
            return Task { @MainActor in
                var lastVersions: [Key: Int] = [:]
                let encoder = JSONEncoder()
                encoder.outputFormatting = .sortedKeys

                let stream = Observations { capture(state) }
                let source: any AsyncSequence<[Key: Entity], Never> =
                    level == .hot ? stream : stream.debounce(for: level.debounce, clock: debounceClock)

                for await entities in source {
                    let deltaComputation = Self.computeDelta(
                        entities: entities,
                        lastVersions: lastVersions,
                        version: version,
                        keyToString: keyToString
                    )
                    guard !deltaComputation.delta.isEmpty else { continue }

                    let data: Data
                    do {
                        if level == .cold {
                            // Off-main cold delta encoding prevents large payload serialization
                            // from blocking MainActor. @concurrent runs on cooperative pool (SE-0461).
                            data = try await Self.encodeColdDelta(deltaComputation.delta)
                        } else {
                            data = try encoder.encode(deltaComputation.delta)
                        }
                    } catch {
                        logger.error("[PushEngine] encode failed slice=\(name) store=\(store.rawValue): \(error)")
                        // Advance local versions even on encode failure so we do not
                        // spin indefinitely on the same unencodable delta.
                        lastVersions = deltaComputation.nextVersions
                        continue
                    }
                    lastVersions = deltaComputation.nextVersions

                    let revision = revisions.next(for: store)
                    let epoch = epochFn()
                    await transport.pushJSON(
                        store: store, op: .merge, level: level,
                        revision: revision, epoch: epoch, json: data
                    )
                }
            }
        }
    }

    /// Encode cold deltas off MainActor on cooperative pool (Swift 6.2, SE-0461).
    /// Preserves priority and task-locals that detached tasks would strip.
    @concurrent
    private static func encodeColdDelta(_ delta: EntityDelta<Entity>) async throws -> Data {
        let coldEncoder = JSONEncoder()
        coldEncoder.outputFormatting = .sortedKeys
        return try coldEncoder.encode(delta)
    }

    // MARK: - Delta Computation

    private static func computeDelta(
        entities: [Key: Entity],
        lastVersions: [Key: Int],
        version: (Entity) -> Int,
        keyToString: (Key) -> String
    ) -> (delta: EntityDelta<Entity>, nextVersions: [Key: Int]) {
        var nextVersions = lastVersions
        var changed: [String: Entity] = [:]
        for (key, entity) in entities {
            let v = version(entity)
            if nextVersions[key] != v {
                changed[keyToString(key)] = entity
                nextVersions[key] = v
            }
        }
        let removedKeys = nextVersions.keys
            .filter { entities[$0] == nil }
        let removed = removedKeys.map { keyToString($0) }
        for key in removedKeys {
            nextVersions.removeValue(forKey: key)
        }
        return (
            delta: EntityDelta(
                changed: changed.isEmpty ? nil : changed,
                removed: removed.isEmpty ? nil : removed
            ),
            nextVersions: nextVersions
        )
    }
}
