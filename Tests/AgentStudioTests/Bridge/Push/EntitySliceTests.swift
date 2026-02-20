import Observation
import XCTest

@testable import AgentStudio

@MainActor
final class EntitySliceTests: XCTestCase {

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

    func test_entityDelta_isEmpty_when_both_fields_nil() {
        let empty = EntityDelta<TestEntity>(changed: nil, removed: nil)
        XCTAssertTrue(empty.isEmpty)
    }

    func test_entityDelta_isEmpty_when_both_fields_empty() {
        let emptyCollections = EntityDelta<TestEntity>(changed: [:], removed: [])
        XCTAssertTrue(emptyCollections.isEmpty)
    }

    func test_entityDelta_not_empty_with_changed() {
        let withChanged = EntityDelta<TestEntity>(
            changed: ["k": TestEntity(name: "x", version: 1)],
            removed: nil
        )
        XCTAssertFalse(withChanged.isEmpty)
    }

    func test_entityDelta_not_empty_with_removed() {
        let withRemoved = EntityDelta<TestEntity>(
            changed: nil,
            removed: ["k"]
        )
        XCTAssertFalse(withRemoved.isEmpty)
    }

    func test_entityDelta_keys_are_strings_in_wire_format() {
        let delta = EntityDelta<TestEntity>(
            changed: ["key1": TestEntity(name: "test", version: 1)],
            removed: nil
        )
        let data = try! JSONEncoder().encode(delta)
        let json = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        let changed = json["changed"] as? [String: Any]
        XCTAssertNotNil(
            changed?["key1"],
            "EntityDelta keys must be String in wire format")
    }

    func test_entityDelta_omits_nil_fields() {
        // changed only — removed should be absent from JSON
        let changedOnly = EntityDelta<TestEntity>(
            changed: ["k": TestEntity(name: "a", version: 1)],
            removed: nil
        )
        let data = try! JSONEncoder().encode(changedOnly)
        let json = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertNotNil(json["changed"])
        XCTAssertNil(
            json["removed"],
            "nil removed field should be omitted from JSON")
    }

    // MARK: - EntitySlice Push Tests

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
            level: .warm,
            capture: { state in state.items },
            version: { entity in entity.version },
            keyToString: { $0.uuidString }
        )

        let task = slice.erased().makeTask(state, transport, clock) { 1 }
        try await Task.sleep(for: .milliseconds(100))

        let initialCount = transport.pushCount

        // Mutate only id1 — bump its version
        state.items[id1] = TestEntity(name: "first-updated", version: 2)
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertGreaterThan(
            transport.pushCount, initialCount,
            "Transport should receive a push after entity mutation")

        if let json = transport.lastJSON {
            let delta = try JSONDecoder().decode(EntityDeltaTestShape.self, from: json)
            XCTAssertNotNil(
                delta.changed?[id1.uuidString],
                "Changed entity should be in delta")
            XCTAssertNil(
                delta.changed?[id2.uuidString],
                "Unchanged entity should NOT be in delta")
        }

        task.cancel()
    }
}

// MARK: - Test Helpers

/// Decodable shape matching EntityDelta wire format for test assertions.
struct EntityDeltaTestShape: Decodable {
    let changed: [String: AnyCodableValue]?
    let removed: [String]?
}
