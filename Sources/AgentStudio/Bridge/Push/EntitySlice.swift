import AsyncAlgorithms
import Foundation
import Observation
import os.log

private let logger = Logger(subsystem: "com.agentstudio", category: "PushEngine")

// MARK: - EntityDelta

/// Wire format for entity deltas. Keys are always String (normalized from Key type).
/// Omits empty fields to minimize payload size.
struct EntityDelta<Entity: Encodable>: Encodable {
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
/// Design doc §6.6.
struct EntitySlice<
    State: Observable & AnyObject,
    Key: Hashable,
    Entity: Encodable
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

    func erased() -> AnyPushSlice<State> {
        let capture = self.capture
        let version = self.version
        let keyToString = self.keyToString
        let level = self.level
        let store = self.store
        let name = self.name

        return AnyPushSlice(name: name) { state, transport, revisions, epochProvider in
            let epochFn = epochProvider
            return Task { @MainActor in
                var lastVersions: [Key: Int] = [:]
                let encoder = JSONEncoder()

                let stream = Observations { capture(state) }
                let source: any AsyncSequence<[Key: Entity], Never> =
                    level == .hot ? stream : stream.debounce(for: level.debounce)

                for await entities in source {
                    let delta = Self.computeDelta(
                        entities: entities,
                        lastVersions: &lastVersions,
                        version: version,
                        keyToString: keyToString
                    )
                    guard !delta.isEmpty else { continue }
                    guard let data = try? encoder.encode(delta) else {
                        logger.error("[PushEngine] encode failed slice=\(name) store=\(store.rawValue)")
                        continue
                    }
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

    // MARK: - Delta Computation

    private static func computeDelta(
        entities: [Key: Entity],
        lastVersions: inout [Key: Int],
        version: (Entity) -> Int,
        keyToString: (Key) -> String
    ) -> EntityDelta<Entity> {
        var changed: [String: Entity] = [:]
        for (key, entity) in entities {
            let v = version(entity)
            if lastVersions[key] != v {
                changed[keyToString(key)] = entity
                lastVersions[key] = v
            }
        }
        let removed = lastVersions.keys
            .filter { entities[$0] == nil }
            .map { keyToString($0) }
        for key in lastVersions.keys where entities[key] == nil {
            lastVersions.removeValue(forKey: key)
        }
        return EntityDelta(
            changed: changed.isEmpty ? nil : changed,
            removed: removed.isEmpty ? nil : removed
        )
    }
}
