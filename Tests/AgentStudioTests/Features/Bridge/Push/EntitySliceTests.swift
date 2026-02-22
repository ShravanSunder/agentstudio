import Foundation
import Observation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
final class EntitySliceTests {

    // MARK: - Test Types

    @Observable
    class TestState {
        var items: [UUID: TestEntity] = [:]
    }

    struct TestEntity: Encodable {
        let name: String
        let version: Int
    }

    // MARK: - EntityDelta Tests

    @Test
    func test_entityDelta_isEmpty_when_both_fields_nil() {
        let empty = EntityDelta<TestEntity>(changed: nil, removed: nil)
        #expect(empty.isEmpty)
    }

    @Test
    func test_entityDelta_isEmpty_when_both_fields_empty() {
        let emptyCollections = EntityDelta<TestEntity>(changed: [:], removed: [])
        #expect(emptyCollections.isEmpty)
    }

    @Test
    func test_entityDelta_not_empty_with_changed() {
        let withChanged = EntityDelta<TestEntity>(
            changed: ["k": TestEntity(name: "x", version: 1)],
            removed: nil
        )
        #expect(!(withChanged.isEmpty))
    }

    @Test
    func test_entityDelta_not_empty_with_removed() {
        let withRemoved = EntityDelta<TestEntity>(
            changed: nil,
            removed: ["k"]
        )
        #expect(!(withRemoved.isEmpty))
    }

    @Test
    func test_entityDelta_keys_are_strings_in_wire_format() {
        let delta = EntityDelta<TestEntity>(
            changed: ["key1": TestEntity(name: "test", version: 1)],
            removed: nil
        )
        let data = try! JSONEncoder().encode(delta)
        let json = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        let changed = json["changed"] as? [String: Any]
        #expect(changed?["key1"] != nil, "EntityDelta keys must be String in wire format")
    }

    @Test
    func test_entityDelta_omits_nil_fields() {
        // changed only — removed should be absent from JSON
        let changedOnly = EntityDelta<TestEntity>(
            changed: ["k": TestEntity(name: "a", version: 1)],
            removed: nil
        )
        let data = try! JSONEncoder().encode(changedOnly)
        let json = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["changed"] != nil)
        #expect(json["removed"] == nil, "nil removed field should be omitted from JSON")
    }

    // MARK: - EntitySlice Push Tests

    @Test
    func test_entitySlice_only_pushes_changed_entities() async throws {
        let state = TestState()
        let transport = MockPushTransport()
        let clock = RevisionClock()

        let id1 = UUID()
        let id2 = UUID()
        state.items[id1] = TestEntity(name: "first", version: 1)
        state.items[id2] = TestEntity(name: "second", version: 1)

        let slice = EntitySlice<TestState, UUID, TestEntity>(
            "testItems",
            store: .review,
            level: .hot,
            capture: { state in state.items },
            version: { entity in entity.version },
            keyToString: { $0.uuidString }
        )

        let task = slice.erased().makeTask(state, transport, clock) { 1 }
        #expect(await transport.waitForPushCount(atLeast: 1))

        let initialCount = transport.pushCount

        // Mutate only id1 — bump its version
        state.items[id1] = TestEntity(name: "first-updated", version: 2)
        #expect(await transport.waitForPushCount(atLeast: initialCount + 1))

        #expect(transport.pushCount > initialCount, "Transport should receive a push after entity mutation")

        if let json = transport.lastJSON {
            let delta = try JSONDecoder().decode(EntityDeltaTestShape.self, from: json)
            #expect(delta.changed?[id1.uuidString] != nil, "Changed entity should be in delta")
            #expect(delta.changed?[id2.uuidString] == nil, "Unchanged entity should NOT be in delta")
        }

        task.cancel()
    }

    // MARK: - Version Contract Tests

    /// Documents that EntitySlice relies on `version` for change detection.
    /// If a field mutates but version doesn't increment, the change is NOT pushed.
    /// This is by design — callers are responsible for bumping version.
    @Test
    func test_entitySlice_skips_entity_when_version_unchanged() async throws {
        // Arrange
        let state = TestState()
        let transport = MockPushTransport()
        let clock = RevisionClock()

        let id1 = UUID()
        state.items[id1] = TestEntity(name: "original", version: 1)

        let slice = EntitySlice<TestState, UUID, TestEntity>(
            "testItems", store: .review, level: .hot,
            capture: { state in state.items },
            version: { entity in entity.version },
            keyToString: { $0.uuidString }
        )

        let task = slice.erased().makeTask(state, transport, clock) { 1 }
        #expect(await transport.waitForPushCount(atLeast: 1))

        let countAfterInitial = transport.pushCount

        // Act — mutate name but DON'T bump version
        state.items[id1] = TestEntity(name: "changed-name", version: 1)
        await Task.yield()

        // Assert — EntitySlice should NOT push because version is unchanged
        // This documents the version contract: callers must bump version for changes to propagate
        #expect(
            transport.pushCount == countAfterInitial,
            "EntitySlice should skip push when version is unchanged despite field mutation")

        task.cancel()
    }

    // MARK: - Encoder Determinism Tests

    /// Verifies that JSONEncoder produces deterministic output for identical values.
    /// The transport content guard relies on byte-equality of encoded JSON.
    @Test
    func test_jsonEncoder_determinism_for_content_guard() throws {
        let encoder = JSONEncoder()
        // Use sorted keys to ensure determinism (JSONEncoder's default key ordering is implementation-defined)
        encoder.outputFormatting = .sortedKeys

        let manifest = FileManifest(
            id: "test-file",
            version: 1,
            path: "src/app.tsx",
            oldPath: nil,
            changeType: .modified,
            additions: 10,
            deletions: 5,
            size: 1024,
            contextHash: "abc123"
        )

        let data1 = try encoder.encode(manifest)
        let data2 = try encoder.encode(manifest)

        #expect(data1 == data2, "JSONEncoder must produce identical bytes for identical values")
    }
}

// MARK: - Test Helpers

/// Decodable shape matching EntityDelta wire format for test assertions.
struct EntityDeltaTestShape: Decodable {
    let changed: [String: AnyCodableValue]?
    let removed: [String]?
}
