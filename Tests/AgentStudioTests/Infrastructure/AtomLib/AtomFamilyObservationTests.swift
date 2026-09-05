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
private final class AtomTraceInstantBox {
    var instant: ContinuousClock.Instant

    init(instant: ContinuousClock.Instant) {
        self.instant = instant
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

@Suite(.serialized)
@MainActor
struct AtomFamilyObservationTests {
    @Test
    func missingKeyReadWakesWhenThatKeyIsInserted() {
        let aggregateRevision = AtomRevision()
        let map = AtomFamily<String, Int>(telemetryLabel: "observation_test", isContentEqual: ==)
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
        let map = AtomFamily<String, Int>(telemetryLabel: "observation_test", isContentEqual: ==)
        let mutation = AtomMutationContext(aggregateRevision: aggregateRevision)

        map.replaceAll(["repo-a": 1], mutation: mutation)
        mutation.commit()

        #expect(map.value(for: "repo-a") == 1)
        #expect(map.storageSlotCount == 1)
    }

    @Test
    func keyedReadersWakeOnlyForTouchedKey() {
        let aggregateRevision = AtomRevision()
        let map = AtomFamily<String, Int>(telemetryLabel: "observation_test", isContentEqual: ==)
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
        let map = AtomFamily<String, Int>(telemetryLabel: "observation_test", isContentEqual: ==)
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
        let map = AtomFamily<String, Int>(telemetryLabel: "observation_test", isContentEqual: ==)

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
        let map = AtomFamily<String, Int>(telemetryLabel: "observation_test", isContentEqual: ==)
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
        let map = AtomFamily<String, Int>(telemetryLabel: "observation_test", isContentEqual: ==)
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
    func removedSlotRetainsIdentityAndActiveResubscription() {
        let aggregateRevision = AtomRevision()
        let map = AtomFamily<String, Int>(telemetryLabel: "observation_test", isContentEqual: ==)
        let repoACounter = AtomFamilyObservationCounter()

        let addMutation = AtomMutationContext(aggregateRevision: aggregateRevision)
        map.setValue(1, for: "repo-a", mutation: addMutation)
        map.setValue(2, for: "repo-b", mutation: addMutation)
        addMutation.commit()
        observeRepoA(in: map, counter: repoACounter)

        let removeMutation = AtomMutationContext(aggregateRevision: aggregateRevision)
        map.removeValue(for: "repo-a", mutation: removeMutation)
        map.removeValue(for: "repo-b", mutation: removeMutation)
        removeMutation.commit()

        #expect(repoACounter.count == 1)
        #expect(map.storageSlotCount == 2)

        let reinsertMutation = AtomMutationContext(aggregateRevision: aggregateRevision)
        map.setValue(3, for: "repo-a", mutation: reinsertMutation)
        reinsertMutation.commit()

        #expect(repoACounter.count == 2)
        #expect(map.value(for: "repo-a") == 3)
    }

    @Test
    func removalAndReinsertionCannotReuseRevisionTupleOrReturnStaleDerivedValue() {
        let aggregateRevision = AtomRevision()
        let map = AtomFamily<String, Int>(telemetryLabel: "observation_test", isContentEqual: ==)

        let insertMutation = AtomMutationContext(aggregateRevision: aggregateRevision)
        map.setValue(1, for: "repo-a", mutation: insertMutation)
        insertMutation.commit()
        let insertedRevision = map.revision(for: "repo-a")

        let derived = DerivedAtom<Int?>(
            inputRevisions: { [map.revision(for: "repo-a")] },
            isContentEqual: ==,
            compute: { map.value(for: "repo-a") }
        )
        #expect(derived.value == 1)

        let removeMutation = AtomMutationContext(aggregateRevision: aggregateRevision)
        map.removeValue(for: "repo-a", mutation: removeMutation)
        removeMutation.commit()
        let removedRevision = map.revision(for: "repo-a")

        let reinsertMutation = AtomMutationContext(aggregateRevision: aggregateRevision)
        map.setValue(2, for: "repo-a", mutation: reinsertMutation)
        reinsertMutation.commit()
        let reinsertedRevision = map.revision(for: "repo-a")

        #expect(removedRevision > insertedRevision)
        #expect(reinsertedRevision > removedRevision)
        #expect(derived.value == 2)
    }

    @Test
    func missingSlotsRemainRetainedForFamilyLifetime() {
        let aggregateRevision = AtomRevision()
        let map = AtomFamily<String, Int>(telemetryLabel: "observation_test", isContentEqual: ==)
        let repoACounter = AtomFamilyObservationCounter()
        observeRepoA(in: map, counter: repoACounter)

        #expect(map.storageSlotCount == 1)

        let insertMutation = AtomMutationContext(aggregateRevision: aggregateRevision)
        map.setValue(1, for: "repo-a", mutation: insertMutation)
        insertMutation.commit()

        #expect(repoACounter.count == 1)
    }

    @Test
    func removingMissingObservedKeyIsSemanticNoOp() {
        let aggregateRevision = AtomRevision()
        let map = AtomFamily<String, Int>(telemetryLabel: "observation_test", isContentEqual: ==)
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
        let map = AtomFamily<String, Int>(telemetryLabel: "observation_test", isContentEqual: ==)

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
        let map = AtomFamily<String, Int>(telemetryLabel: "observation_test", isContentEqual: ==)

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
        let map = AtomFamily<String, Int>(telemetryLabel: "observation_test", isContentEqual: ==)

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
        let map = AtomFamily<String, Int>(telemetryLabel: "observation_test", isContentEqual: ==)

        #expect(map.value(for: "repo-a") == nil)
        let mutation = AtomMutationContext(aggregateRevision: aggregateRevision)
        map.setValue(1, for: "repo-a", mutation: mutation)
        mutation.commit()
        #expect(map.membershipKeys() == Set(["repo-a"]))
        #expect(map.snapshot() == ["repo-a": 1])
        try await AtomPerformanceTelemetry.shared.drainForTests()

        let outputFileURL = try #require(runtime.outputFileURL)
        let contents = try String(contentsOf: outputFileURL, encoding: .utf8)
        #expect(contents.contains("\"body\":\"performance.atom.read\""))
        #expect(contents.contains("\"body\":\"performance.atom.mutation\""))
        #expect(contents.contains("\"agentstudio.trace.tag\":\"atoms\""))
        #expect(contents.contains("\"agentstudio.performance.atom.kind\":\"entity_map\""))
        #expect(contents.contains("\"agentstudio.performance.atom.operation\":\"value\""))
        #expect(contents.contains("\"agentstudio.performance.atom.operation\":\"membership_keys\""))
        #expect(contents.contains("\"agentstudio.performance.atom.operation\":\"snapshot\""))
        #expect(contents.contains("\"agentstudio.performance.atom.operation\":\"set\""))
        #expect(contents.contains("\"agentstudio.performance.atom.slot.count\":1"))
    }

    @Test
    func atomFamiliesEmitControlledLabelsWithoutKeysOrValues() async throws {
        let traceDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("atom-family-label-telemetry", isDirectory: true)
        let runtime = AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_BACKEND": "jsonl",
                "AGENTSTUDIO_TRACE_DIR": traceDirectory.path,
                "AGENTSTUDIO_TRACE_NAME": "atom-family-label-telemetry",
                "AGENTSTUDIO_TRACE_TAGS": "atoms",
            ]),
            processIdentifier: 918,
            timeUnixNano: { 778 }
        )
        AtomPerformanceTelemetry.shared.configure(traceRuntime: runtime)
        defer { AtomPerformanceTelemetry.shared.resetForTests() }
        let aggregateRevision = AtomRevision()
        let canonicalFamily = AtomFamily<String, String>(
            telemetryLabel: "pane_graph_canonical",
            isContentEqual: ==
        )
        let structuralFamily = AtomFamily<String, String>(
            telemetryLabel: "pane_graph_structural",
            isContentEqual: ==
        )

        #expect(canonicalFamily.value(for: "private-pane-key") == nil)
        #expect(structuralFamily.value(for: "private-structural-key") == nil)
        let mutation = AtomMutationContext(aggregateRevision: aggregateRevision)
        canonicalFamily.setValue("private-pane-value", for: "private-pane-key", mutation: mutation)
        structuralFamily.setValue("private-structural-value", for: "private-structural-key", mutation: mutation)
        mutation.commit()
        try await AtomPerformanceTelemetry.shared.drainForTests()

        let outputFileURL = try #require(runtime.outputFileURL)
        let contents = try String(contentsOf: outputFileURL, encoding: .utf8)
        #expect(contents.contains("\"agentstudio.performance.atom.label\":\"pane_graph_canonical\""))
        #expect(contents.contains("\"agentstudio.performance.atom.label\":\"pane_graph_structural\""))
        #expect(!contents.contains("private-pane-key"))
        #expect(!contents.contains("private-pane-value"))
        #expect(!contents.contains("private-structural-key"))
        #expect(!contents.contains("private-structural-value"))
    }

    @Test
    func atomReadTelemetryShedsBeyondTheAdmissionLimitWithinOneWindow() async throws {
        let traceDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("atom-read-admission-\(UUID().uuidString)", isDirectory: true)
        let runtime = AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_BACKEND": "jsonl",
                "AGENTSTUDIO_TRACE_DIR": traceDirectory.path,
                "AGENTSTUDIO_TRACE_NAME": "atom-read-admission",
                "AGENTSTUDIO_TRACE_TAGS": "atoms",
            ]),
            processIdentifier: 919,
            timeUnixNano: { 779 }
        )
        let clockBox = AtomTraceInstantBox(instant: ContinuousClock().now)
        AtomPerformanceTelemetry.shared.configure(
            traceRuntime: runtime,
            now: { clockBox.instant }
        )
        defer { AtomPerformanceTelemetry.shared.resetForTests() }
        let limit = AppPolicies.Diagnostics.atomReadTraceAdmissionLimit
        let family = AtomFamily<String, Int>(telemetryLabel: "read_admission", isContentEqual: ==)

        for index in 0..<(limit + 40) {
            _ = family.value(for: "repo-\(index)")
        }
        try await AtomPerformanceTelemetry.shared.drainForTests()

        let outputFileURL = try #require(runtime.outputFileURL)
        let contents = try String(contentsOf: outputFileURL, encoding: .utf8)
        let admittedReadCount =
            contents.components(
                separatedBy: "\"body\":\"performance.atom.read\""
            ).count - 1

        #expect(admittedReadCount == limit)
    }

    @Test
    func atomReadTelemetryAdmitsAgainAfterTheWindowElapses() async throws {
        let traceDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("atom-read-window-\(UUID().uuidString)", isDirectory: true)
        let runtime = AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_BACKEND": "jsonl",
                "AGENTSTUDIO_TRACE_DIR": traceDirectory.path,
                "AGENTSTUDIO_TRACE_NAME": "atom-read-window",
                "AGENTSTUDIO_TRACE_TAGS": "atoms",
            ]),
            processIdentifier: 920,
            timeUnixNano: { 780 }
        )
        let clockBox = AtomTraceInstantBox(instant: ContinuousClock().now)
        AtomPerformanceTelemetry.shared.configure(
            traceRuntime: runtime,
            now: { clockBox.instant }
        )
        defer { AtomPerformanceTelemetry.shared.resetForTests() }
        let limit = AppPolicies.Diagnostics.atomReadTraceAdmissionLimit
        let family = AtomFamily<String, Int>(telemetryLabel: "read_window", isContentEqual: ==)

        for index in 0..<(limit + 10) {
            _ = family.value(for: "first-\(index)")
        }
        clockBox.instant = clockBox.instant.advanced(
            by: AppPolicies.Diagnostics.atomReadTraceAdmissionWindow
        )
        for index in 0..<(limit + 10) {
            _ = family.value(for: "second-\(index)")
        }
        try await AtomPerformanceTelemetry.shared.drainForTests()

        let outputFileURL = try #require(runtime.outputFileURL)
        let contents = try String(contentsOf: outputFileURL, encoding: .utf8)
        let admittedReadCount =
            contents.components(
                separatedBy: "\"body\":\"performance.atom.read\""
            ).count - 1

        #expect(admittedReadCount == limit * 2)
        // The first read admitted in the second window must carry the exact
        // count shed at the tail of the first, or a sampled stream would be
        // indistinguishable from a quiet one.
        #expect(contents.contains("\"agentstudio.performance.atom.shed_read.count\":10"))
    }

    @Test
    func atomMutationTelemetryIsNotSubjectToReadAdmission() async throws {
        let traceDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("atom-mutation-unshed-\(UUID().uuidString)", isDirectory: true)
        let runtime = AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_BACKEND": "jsonl",
                "AGENTSTUDIO_TRACE_DIR": traceDirectory.path,
                "AGENTSTUDIO_TRACE_NAME": "atom-mutation-unshed",
                "AGENTSTUDIO_TRACE_TAGS": "atoms",
            ]),
            processIdentifier: 921,
            timeUnixNano: { 781 }
        )
        let clockBox = AtomTraceInstantBox(instant: ContinuousClock().now)
        AtomPerformanceTelemetry.shared.configure(
            traceRuntime: runtime,
            now: { clockBox.instant }
        )
        defer { AtomPerformanceTelemetry.shared.resetForTests() }
        let limit = AppPolicies.Diagnostics.atomReadTraceAdmissionLimit
        let aggregateRevision = AtomRevision()
        let family = AtomFamily<String, Int>(telemetryLabel: "mutation_unshed", isContentEqual: ==)

        let mutation = AtomMutationContext(aggregateRevision: aggregateRevision)
        for index in 0..<(limit + 10) {
            family.setValue(index, for: "repo-\(index)", mutation: mutation)
        }
        mutation.commit()
        try await AtomPerformanceTelemetry.shared.drainForTests()

        let outputFileURL = try #require(runtime.outputFileURL)
        let contents = try String(contentsOf: outputFileURL, encoding: .utf8)
        let mutationCount =
            contents.components(
                separatedBy: "\"body\":\"performance.atom.mutation\""
            ).count - 1

        #expect(mutationCount == limit + 10)
    }

    @Test
    func atomTelemetryQueueExistsOnlyWhenRecordingIsEnabled() {
        let traceDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("atom-queue-gate-\(UUID().uuidString)", isDirectory: true)
        let performanceOnlyRuntime = AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_BACKEND": "jsonl",
                "AGENTSTUDIO_TRACE_DIR": traceDirectory.path,
                "AGENTSTUDIO_TRACE_NAME": "atom-queue-gate",
                "AGENTSTUDIO_TRACE_TAGS": "performance",
            ]),
            processIdentifier: 922,
            timeUnixNano: { 782 }
        )
        AtomPerformanceTelemetry.shared.configure(traceRuntime: performanceOnlyRuntime)
        defer { AtomPerformanceTelemetry.shared.resetForTests() }

        #expect(AtomPerformanceTelemetry.shared.isEventQueueActive == false)
    }
}
