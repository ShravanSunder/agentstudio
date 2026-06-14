import Foundation
import Observation
import Testing

@testable import AgentStudio

private final class AtomEntityMapObservationCounter: @unchecked Sendable {
    private(set) var count = 0
    private(set) var didFire = false

    func record() {
        didFire = true
        count += 1
    }
}

@MainActor
struct AtomEntityMapObservationTests {
    @Test
    func missingKeyReadWakesWhenThatKeyIsInserted() {
        let aggregateRevision = AtomRevision()
        let map = AtomEntityMap<String, Int>(isContentEqual: ==)
        let missingKeyCounter = AtomEntityMapObservationCounter()

        withObservationTracking {
            _ = map.value(for: "repo-a")
        } onChange: {
            missingKeyCounter.record()
        }

        let mutation = AtomMutationContext(aggregateRevision: aggregateRevision)
        map.setValue(1, for: "repo-a", mutation: mutation)
        mutation.commit()

        #expect(missingKeyCounter.count == 1)
        #expect(map.value(for: "repo-a") == 1)
        #expect(aggregateRevision.value == 1)
    }

    @Test
    func keyedReadersWakeOnlyForTouchedKey() {
        let aggregateRevision = AtomRevision()
        let map = AtomEntityMap<String, Int>(isContentEqual: ==)
        let keyACounter = AtomEntityMapObservationCounter()
        let keyBCounter = AtomEntityMapObservationCounter()

        withObservationTracking {
            _ = map.value(for: "repo-a")
        } onChange: {
            keyACounter.record()
        }
        withObservationTracking {
            _ = map.value(for: "repo-b")
        } onChange: {
            keyBCounter.record()
        }

        let mutation = AtomMutationContext(aggregateRevision: aggregateRevision)
        map.setValue(2, for: "repo-b", mutation: mutation)
        mutation.commit()

        #expect(!keyACounter.didFire)
        #expect(keyBCounter.count == 1)
        #expect(aggregateRevision.value == 1)
    }

    @Test
    func membershipRevisionWakesOnlyForAddOrRemove() {
        let aggregateRevision = AtomRevision()
        let map = AtomEntityMap<String, Int>(isContentEqual: ==)
        let membershipCounter = AtomEntityMapObservationCounter()

        withObservationTracking {
            _ = map.membershipRevision.value
        } onChange: {
            membershipCounter.record()
        }

        let addMutation = AtomMutationContext(aggregateRevision: aggregateRevision)
        map.setValue(1, for: "repo-a", mutation: addMutation)
        addMutation.commit()

        #expect(membershipCounter.count == 1)

        let valueOnlyCounter = AtomEntityMapObservationCounter()
        withObservationTracking {
            _ = map.membershipRevision.value
        } onChange: {
            valueOnlyCounter.record()
        }

        let updateMutation = AtomMutationContext(aggregateRevision: aggregateRevision)
        map.setValue(2, for: "repo-a", mutation: updateMutation)
        updateMutation.commit()

        #expect(!valueOnlyCounter.didFire)

        let removeCounter = AtomEntityMapObservationCounter()
        withObservationTracking {
            _ = map.membershipRevision.value
        } onChange: {
            removeCounter.record()
        }

        let removeMutation = AtomMutationContext(aggregateRevision: aggregateRevision)
        map.removeValue(for: "repo-a", mutation: removeMutation)
        removeMutation.commit()

        #expect(removeCounter.count == 1)
        #expect(aggregateRevision.value == 3)
    }

    @Test
    func topologyExitPrunesRemovedSlotAndAllowsReSubscription() {
        let aggregateRevision = AtomRevision()
        let map = AtomEntityMap<String, Int>(isContentEqual: ==)
        let removalCounter = AtomEntityMapObservationCounter()

        let addMutation = AtomMutationContext(aggregateRevision: aggregateRevision)
        map.setValue(1, for: "repo-a", mutation: addMutation)
        addMutation.commit()

        withObservationTracking {
            _ = map.value(for: "repo-a")
        } onChange: {
            removalCounter.record()
        }

        let removeMutation = AtomMutationContext(aggregateRevision: aggregateRevision)
        map.removeValue(for: "repo-a", mutation: removeMutation)
        removeMutation.commit()

        #expect(removalCounter.count == 1)
        #expect(map.storageSlotCount == 0)

        let reinsertionCounter = AtomEntityMapObservationCounter()
        withObservationTracking {
            _ = map.value(for: "repo-a")
        } onChange: {
            reinsertionCounter.record()
        }

        #expect(map.storageSlotCount == 1)

        let reinsertMutation = AtomMutationContext(aggregateRevision: aggregateRevision)
        map.setValue(2, for: "repo-a", mutation: reinsertMutation)
        reinsertMutation.commit()

        #expect(reinsertionCounter.count == 1)
        #expect(map.value(for: "repo-a") == 2)
    }

    @Test
    func replaceAllPrunesRemovedSlots() {
        let aggregateRevision = AtomRevision()
        let map = AtomEntityMap<String, Int>(isContentEqual: ==)

        let addMutation = AtomMutationContext(aggregateRevision: aggregateRevision)
        map.setValue(1, for: "repo-a", mutation: addMutation)
        map.setValue(2, for: "repo-b", mutation: addMutation)
        addMutation.commit()

        #expect(map.storageSlotCount == 2)

        let replaceMutation = AtomMutationContext(aggregateRevision: aggregateRevision)
        map.replaceAll(["repo-b": 2], mutation: replaceMutation)
        replaceMutation.commit()

        #expect(map.storageSlotCount == 1)
        #expect(map.value(for: "repo-a") == nil)
        #expect(map.storageSlotCount == 2)
    }

    @Test
    func topologyCleanupPrunesSlotsThatOnlyObservedMissingKeys() {
        let aggregateRevision = AtomRevision()
        let map = AtomEntityMap<String, Int>(isContentEqual: ==)

        #expect(map.value(for: "repo-a") == nil)
        #expect(map.value(for: "repo-b") == nil)
        #expect(map.storageSlotCount == 2)

        let removeMutation = AtomMutationContext(aggregateRevision: aggregateRevision)
        map.removeValue(for: "repo-a", mutation: removeMutation)
        removeMutation.commit()

        #expect(map.storageSlotCount == 1)
        #expect(aggregateRevision.value == 0)

        let replaceMutation = AtomMutationContext(aggregateRevision: aggregateRevision)
        map.replaceAll([:], mutation: replaceMutation)
        replaceMutation.commit()

        #expect(map.storageSlotCount == 0)
        #expect(aggregateRevision.value == 0)
    }

    @Test
    func removeAllPrunesAllSlots() {
        let aggregateRevision = AtomRevision()
        let map = AtomEntityMap<String, Int>(isContentEqual: ==)

        let addMutation = AtomMutationContext(aggregateRevision: aggregateRevision)
        map.setValue(1, for: "repo-a", mutation: addMutation)
        map.setValue(2, for: "repo-b", mutation: addMutation)
        addMutation.commit()

        let removeMutation = AtomMutationContext(aggregateRevision: aggregateRevision)
        map.removeAll(mutation: removeMutation)
        removeMutation.commit()

        #expect(map.storageSlotCount == 0)
        #expect(map.snapshot().isEmpty)
    }

    @Test
    func removeAllPrunesSlotsThatOnlyObservedMissingKeys() {
        let aggregateRevision = AtomRevision()
        let map = AtomEntityMap<String, Int>(isContentEqual: ==)

        #expect(map.value(for: "repo-a") == nil)
        #expect(map.storageSlotCount == 1)

        let removeMutation = AtomMutationContext(aggregateRevision: aggregateRevision)
        map.removeAll(mutation: removeMutation)
        removeMutation.commit()

        #expect(map.storageSlotCount == 0)
        #expect(aggregateRevision.value == 0)
    }

    @Test
    func entityMapEmitsOptInAtomPerformanceTelemetry() async throws {
        let traceDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("atom-entity-map-telemetry-\(UUID().uuidString)", isDirectory: true)
        let runtime = AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_BACKEND": "jsonl",
                "AGENTSTUDIO_TRACE_DIR": traceDirectory.path,
                "AGENTSTUDIO_TRACE_NAME": "atom-entity-map-telemetry",
                "AGENTSTUDIO_TRACE_TAGS": "atoms",
            ]),
            processIdentifier: 917,
            timeUnixNano: { 777 }
        )
        AtomPerformanceTelemetry.shared.configure(traceRuntime: runtime)
        defer { AtomPerformanceTelemetry.shared.resetForTests() }
        let aggregateRevision = AtomRevision()
        let map = AtomEntityMap<String, Int>(isContentEqual: ==)

        #expect(map.value(for: "repo-a") == nil)
        let mutation = AtomMutationContext(aggregateRevision: aggregateRevision)
        map.setValue(1, for: "repo-a", mutation: mutation)
        mutation.commit()
        try await AtomPerformanceTelemetry.shared.drainForTests()

        let outputFileURL = try #require(runtime.outputFileURL)
        let contents = try String(contentsOf: outputFileURL, encoding: .utf8)
        #expect(contents.contains("\"body\":\"performance.atom.read\""))
        #expect(contents.contains("\"body\":\"performance.atom.mutation\""))
        #expect(contents.contains("\"agentstudio.trace.tag\":\"atoms\""))
        #expect(contents.contains("\"agentstudio.performance.atom.kind\":\"entity_map\""))
        #expect(contents.contains("\"agentstudio.performance.atom.operation\":\"value\""))
        #expect(contents.contains("\"agentstudio.performance.atom.operation\":\"set\""))
        #expect(contents.contains("\"agentstudio.performance.atom.slot.count\":1"))
    }
}
