import Foundation
import Observation
import Testing

@testable import AgentStudioInfrastructure

private final class AtomFamilyObservationCounter: @unchecked Sendable {
    private(set) var count = 0
    private(set) var didFire = false

    func record() {
        didFire = true
        count += 1
    }
}

@MainActor
private func observeRepoA(
    in family: AtomFamily<String, Int>,
    counter: AtomFamilyObservationCounter
) {
    withObservationTracking {
        _ = family.value(for: "repo-a")
    } onChange: {
        MainActor.assumeIsolated {
            counter.record()
            observeRepoA(in: family, counter: counter)
        }
    }
}

@MainActor
private func observeRepoARevision(
    in family: AtomFamily<String, Int>,
    counter: AtomFamilyObservationCounter
) {
    withObservationTracking {
        _ = family.revision(for: "repo-a")
    } onChange: {
        MainActor.assumeIsolated {
            counter.record()
            observeRepoARevision(in: family, counter: counter)
        }
    }
}

@MainActor
struct AtomFamilyObservationTests {
    @Test
    func missingKeyReadWakesWhenThatKeyIsInserted() {
        let aggregateRevision = AtomRevision()
        let map = AtomFamily<String, Int>(isContentEqual: ==)
        let missingKeyCounter = AtomFamilyObservationCounter()

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
    func replaceAllInsertedValueIsReadableThroughKeyedSlot() {
        let aggregateRevision = AtomRevision()
        let map = AtomFamily<String, Int>(isContentEqual: ==)
        let mutation = AtomMutationContext(aggregateRevision: aggregateRevision)

        map.replaceAll(["repo-a": 1], mutation: mutation)
        mutation.commit()

        #expect(map.value(for: "repo-a") == 1)
        #expect(map.storageSlotCount == 1)
    }

    @Test
    func keyedReadersWakeOnlyForTouchedKey() {
        let aggregateRevision = AtomRevision()
        let map = AtomFamily<String, Int>(isContentEqual: ==)
        let keyACounter = AtomFamilyObservationCounter()
        let keyBCounter = AtomFamilyObservationCounter()

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
        let map = AtomFamily<String, Int>(isContentEqual: ==)
        let membershipCounter = AtomFamilyObservationCounter()

        withObservationTracking {
            _ = map.membershipRevision
        } onChange: {
            membershipCounter.record()
        }

        let addMutation = AtomMutationContext(aggregateRevision: aggregateRevision)
        map.setValue(1, for: "repo-a", mutation: addMutation)
        addMutation.commit()

        #expect(membershipCounter.count == 1)

        let valueOnlyCounter = AtomFamilyObservationCounter()
        withObservationTracking {
            _ = map.membershipRevision
        } onChange: {
            valueOnlyCounter.record()
        }

        let updateMutation = AtomMutationContext(aggregateRevision: aggregateRevision)
        map.setValue(2, for: "repo-a", mutation: updateMutation)
        updateMutation.commit()

        #expect(!valueOnlyCounter.didFire)

        let removeCounter = AtomFamilyObservationCounter()
        withObservationTracking {
            _ = map.membershipRevision
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
    func perKeyRevisionAdvancesOnlyForAcceptedChangesToThatKey() {
        let aggregateRevision = AtomRevision()
        let map = AtomFamily<String, Int>(isContentEqual: ==)

        #expect(map.revision(for: "repo-a") == 0)
        #expect(map.revision(for: "repo-b") == 0)

        let insertMutation = AtomMutationContext(aggregateRevision: aggregateRevision)
        map.setValue(1, for: "repo-a", mutation: insertMutation)
        insertMutation.commit()
        #expect(map.revision(for: "repo-a") == 1)
        #expect(map.revision(for: "repo-b") == 0)

        let equalMutation = AtomMutationContext(aggregateRevision: aggregateRevision)
        map.setValue(1, for: "repo-a", mutation: equalMutation)
        equalMutation.commit()
        #expect(map.revision(for: "repo-a") == 1)

        let updateMutation = AtomMutationContext(aggregateRevision: aggregateRevision)
        map.setValue(2, for: "repo-a", mutation: updateMutation)
        updateMutation.commit()
        #expect(map.revision(for: "repo-a") == 2)

        let removeMutation = AtomMutationContext(aggregateRevision: aggregateRevision)
        map.removeValue(for: "repo-a", mutation: removeMutation)
        removeMutation.commit()
        #expect(map.revision(for: "repo-a") == 3)

        let reinsertMutation = AtomMutationContext(aggregateRevision: aggregateRevision)
        map.setValue(3, for: "repo-a", mutation: reinsertMutation)
        reinsertMutation.commit()
        #expect(map.revision(for: "repo-a") == 4)
    }

    @Test
    func perKeyRevisionObservationTracksOnlyAcceptedChangesToThatKey() {
        let aggregateRevision = AtomRevision()
        let map = AtomFamily<String, Int>(isContentEqual: ==)
        let revisionCounter = AtomFamilyObservationCounter()
        observeRepoARevision(in: map, counter: revisionCounter)

        let insertMutation = AtomMutationContext(aggregateRevision: aggregateRevision)
        map.setValue(1, for: "repo-a", mutation: insertMutation)
        insertMutation.commit()
        #expect(revisionCounter.count == 1)

        let equalMutation = AtomMutationContext(aggregateRevision: aggregateRevision)
        map.setValue(1, for: "repo-a", mutation: equalMutation)
        map.setValue(2, for: "repo-b", mutation: equalMutation)
        equalMutation.commit()
        #expect(revisionCounter.count == 1)

        let removeMutation = AtomMutationContext(aggregateRevision: aggregateRevision)
        map.removeValue(for: "repo-a", mutation: removeMutation)
        removeMutation.commit()
        #expect(revisionCounter.count == 2)

        let reinsertMutation = AtomMutationContext(aggregateRevision: aggregateRevision)
        map.setValue(3, for: "repo-a", mutation: reinsertMutation)
        reinsertMutation.commit()
        #expect(revisionCounter.count == 3)
    }

    @Test
    func removalCallbackReRegistersAndWakesAgainForReinsertion() {
        let aggregateRevision = AtomRevision()
        let map = AtomFamily<String, Int>(isContentEqual: ==)
        let removalCounter = AtomFamilyObservationCounter()

        let addMutation = AtomMutationContext(aggregateRevision: aggregateRevision)
        map.setValue(1, for: "repo-a", mutation: addMutation)
        addMutation.commit()

        observeRepoA(in: map, counter: removalCounter)

        let removeMutation = AtomMutationContext(aggregateRevision: aggregateRevision)
        map.removeValue(for: "repo-a", mutation: removeMutation)
        removeMutation.commit()

        #expect(removalCounter.count == 1)
        #expect(map.storageSlotCount == 1)

        let reinsertMutation = AtomMutationContext(aggregateRevision: aggregateRevision)
        map.setValue(2, for: "repo-a", mutation: reinsertMutation)
        reinsertMutation.commit()

        #expect(removalCounter.count == 2)
        #expect(map.value(for: "repo-a") == 2)
    }

    @Test
    func removingMissingObservedKeyIsSemanticNoOp() {
        let aggregateRevision = AtomRevision()
        let map = AtomFamily<String, Int>(isContentEqual: ==)
        let removalCounter = AtomFamilyObservationCounter()

        observeRepoA(in: map, counter: removalCounter)
        let keyRevisionBeforeRemoval = map.revision(for: "repo-a")
        let membershipRevisionBeforeRemoval = map.membershipRevision

        let removeMutation = AtomMutationContext(aggregateRevision: aggregateRevision)
        map.removeValue(for: "repo-a", mutation: removeMutation)
        removeMutation.commit()

        #expect(!removalCounter.didFire)
        #expect(map.storageSlotCount == 1)
        #expect(map.revision(for: "repo-a") == keyRevisionBeforeRemoval)
        #expect(map.membershipRevision == membershipRevisionBeforeRemoval)
        #expect(aggregateRevision.value == 0)

        let insertMutation = AtomMutationContext(aggregateRevision: aggregateRevision)
        map.setValue(1, for: "repo-a", mutation: insertMutation)
        insertMutation.commit()

        #expect(removalCounter.count == 1)
    }

    @Test
    func replaceAllTombstonesRemovedSlots() {
        let aggregateRevision = AtomRevision()
        let map = AtomFamily<String, Int>(isContentEqual: ==)

        let addMutation = AtomMutationContext(aggregateRevision: aggregateRevision)
        map.setValue(1, for: "repo-a", mutation: addMutation)
        map.setValue(2, for: "repo-b", mutation: addMutation)
        addMutation.commit()

        #expect(map.storageSlotCount == 2)

        let removalCounter = AtomFamilyObservationCounter()
        observeRepoA(in: map, counter: removalCounter)
        let keyRevisionBeforeReplacement = map.revision(for: "repo-a")
        let membershipRevisionBeforeReplacement = map.membershipRevision

        let replaceMutation = AtomMutationContext(aggregateRevision: aggregateRevision)
        map.replaceAll(["repo-b": 2], mutation: replaceMutation)
        replaceMutation.commit()

        #expect(map.storageSlotCount == 2)
        #expect(map.value(for: "repo-a") == nil)
        #expect(removalCounter.count == 1)
        #expect(map.revision(for: "repo-a") == keyRevisionBeforeReplacement + 1)
        #expect(map.membershipRevision == membershipRevisionBeforeReplacement + 1)

        let reinsertMutation = AtomMutationContext(aggregateRevision: aggregateRevision)
        map.setValue(3, for: "repo-a", mutation: reinsertMutation)
        reinsertMutation.commit()
        #expect(removalCounter.count == 2)
    }

    @Test
    func removeAllTombstonesAllSlots() {
        let aggregateRevision = AtomRevision()
        let map = AtomFamily<String, Int>(isContentEqual: ==)

        let addMutation = AtomMutationContext(aggregateRevision: aggregateRevision)
        map.setValue(1, for: "repo-a", mutation: addMutation)
        map.setValue(2, for: "repo-b", mutation: addMutation)
        addMutation.commit()

        let removalCounter = AtomFamilyObservationCounter()
        observeRepoA(in: map, counter: removalCounter)
        let keyRevisionBeforeRemoval = map.revision(for: "repo-a")
        let membershipRevisionBeforeRemoval = map.membershipRevision

        let removeMutation = AtomMutationContext(aggregateRevision: aggregateRevision)
        map.removeAll(mutation: removeMutation)
        removeMutation.commit()

        #expect(map.storageSlotCount == 2)
        #expect(map.snapshot().isEmpty)
        #expect(removalCounter.count == 1)
        #expect(map.revision(for: "repo-a") == keyRevisionBeforeRemoval + 1)
        #expect(map.membershipRevision == membershipRevisionBeforeRemoval + 1)

        let reinsertMutation = AtomMutationContext(aggregateRevision: aggregateRevision)
        map.setValue(3, for: "repo-a", mutation: reinsertMutation)
        reinsertMutation.commit()
        #expect(removalCounter.count == 2)
    }

    @Test
    func removeAllRetainsSlotsThatOnlyObservedMissingKeys() {
        let aggregateRevision = AtomRevision()
        let map = AtomFamily<String, Int>(isContentEqual: ==)

        #expect(map.value(for: "repo-a") == nil)
        #expect(map.storageSlotCount == 1)

        let removeMutation = AtomMutationContext(aggregateRevision: aggregateRevision)
        map.removeAll(mutation: removeMutation)
        removeMutation.commit()

        #expect(map.storageSlotCount == 1)
        #expect(aggregateRevision.value == 0)
    }

    @Test
    func atomFamilyEmitsOptInAtomPerformanceTelemetry() async throws {
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
        let map = AtomFamily<String, Int>(isContentEqual: ==)

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
