import Foundation
import Testing

@testable import AgentStudioInfrastructure

typealias EagerDerivedAtomTestFamily = EagerDerivedAtomFamily<
    Int,
    EagerDerivedAtomTestRequest,
    Int,
    EagerDerivedAtomTestValue
>

enum EagerDerivedAtomFamilyTermination: Sendable {
    case removeKey
    case stopFamily
}

@MainActor
private final class EagerDerivedAtomFamilyCompletionRecorder {
    private var completions: [(key: Int, completion: EagerDerivedAtomTestNode.ProjectionCompletion)] =
        []
    private var waiters:
        [(
            key: Int,
            completion: EagerDerivedAtomTestNode.ProjectionCompletion,
            signal: EagerDerivedAtomTestSignal
        )] = []

    func record(
        key: Int,
        completion: EagerDerivedAtomTestNode.ProjectionCompletion
    ) {
        completions.append((key, completion))
        var readySignals: [EagerDerivedAtomTestSignal] = []
        waiters.removeAll { waiter in
            guard waiter.key == key, waiter.completion == completion else { return false }
            readySignals.append(waiter.signal)
            return true
        }
        for signal in readySignals {
            signal.signal()
        }
    }

    func wait(
        forKey key: Int,
        completion: EagerDerivedAtomTestNode.ProjectionCompletion
    ) async -> Bool {
        if completions.contains(where: { $0.key == key && $0.completion == completion }) {
            return true
        }
        let signal = EagerDerivedAtomTestSignal()
        waiters.append((key, completion, signal))
        return await signal.wait()
    }
}

@MainActor
private func makeEagerDerivedAtomTestFamily(
    completionRecorder: EagerDerivedAtomFamilyCompletionRecorder? = nil
) -> EagerDerivedAtomTestFamily {
    EagerDerivedAtomTestFamily(
        requestIdentity: \EagerDerivedAtomTestRequest.identity,
        isValueEqual: { lhs, rhs in lhs.content == rhs.content },
        project: projectEagerDerivedAtomTestRequest,
        onProjectionCompletion: { key, completion in
            completionRecorder?.record(key: key, completion: completion)
        }
    )
}

@Suite(.serialized)
@MainActor
struct EagerDerivedAtomFamilyTests {
    @Test
    func eagerFamilyEmitsAdmissionAndCompletionTelemetryWithoutKeysOrValues() async throws {
        let traceDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("eager-derived-family-telemetry", isDirectory: true)
        try? FileManager.default.removeItem(at: traceDirectory)
        let runtime = AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_BACKEND": "jsonl",
                "AGENTSTUDIO_TRACE_DIR": traceDirectory.path,
                "AGENTSTUDIO_TRACE_NAME": "eager-derived-family-telemetry",
                "AGENTSTUDIO_TRACE_TAGS": "atoms",
            ]),
            processIdentifier: 919,
            timeUnixNano: { 779 }
        )
        AtomPerformanceTelemetry.shared.configure(traceRuntime: runtime)
        defer {
            AtomPerformanceTelemetry.shared.resetForTests()
            try? FileManager.default.removeItem(at: traceDirectory)
        }
        let completionRecorder = EagerDerivedAtomFamilyCompletionRecorder()
        let family = EagerDerivedAtomTestFamily(
            telemetryLabel: "repo_explorer_projection",
            requestIdentity: \EagerDerivedAtomTestRequest.identity,
            isValueEqual: { lhs, rhs in lhs.content == rhs.content },
            project: projectEagerDerivedAtomTestRequest,
            onProjectionCompletion: { key, completion in
                completionRecorder.record(key: key, completion: completion)
            }
        )
        defer { family.stop() }

        let projectionCount = EagerDerivedAtomTestCounter()
        family.admit(
            makeEagerDerivedAtomTestRequest(
                identity: 1,
                outputContent: 7,
                projectionCount: projectionCount
            ),
            for: 41
        )
        #expect(await completionRecorder.wait(forKey: 41, completion: .published(1)))
        try await AtomPerformanceTelemetry.shared.drainForTests()

        let outputFileURL = try #require(runtime.outputFileURL)
        let contents = try String(contentsOf: outputFileURL, encoding: .utf8)
        #expect(contents.contains("\"body\":\"performance.atom.derived\""))
        #expect(contents.contains("\"agentstudio.performance.atom.kind\":\"eager_derived_family\""))
        #expect(contents.contains("\"agentstudio.performance.atom.label\":\"repo_explorer_projection\""))
        #expect(contents.contains("\"agentstudio.performance.atom.operation\":\"admit\""))
        #expect(contents.contains("\"agentstudio.performance.atom.operation\":\"completion\""))
        #expect(contents.contains("\"agentstudio.performance.atom.outcome\":\"published\""))
        #expect(!contents.contains("private-request-value"))
    }

    @Test
    func materializationReusesOneChildPerKeyAndKeepsKeysIsolated() {
        let family = makeEagerDerivedAtomTestFamily()
        defer { family.stop() }

        let first = family.materialize(for: 1)
        let repeatedFirst = family.materialize(for: 1)
        let second = family.materialize(for: 2)

        #expect(first != nil)
        #expect(first === repeatedFirst)
        #expect(first !== second)
        #expect(family.atom(for: 1) === first)
        #expect(family.atom(for: 2) === second)
        #expect(family.atoms.count == 2)
    }

    @Test
    func admissionClearsOnlyThatKeysReadinessAndPublicationRestoresIt() async {
        let recorder = EagerDerivedAtomFamilyCompletionRecorder()
        let family = makeEagerDerivedAtomTestFamily(completionRecorder: recorder)
        defer { family.stop() }
        let firstProjectionCount = EagerDerivedAtomTestCounter()
        let secondProjectionCount = EagerDerivedAtomTestCounter()
        let successorGate = EagerDerivedAtomProjectionGate()
        defer { successorGate.release() }

        _ = family.materialize(for: 1)
        _ = family.materialize(for: 2)
        family.admit(
            makeEagerDerivedAtomTestRequest(
                identity: 1,
                outputContent: 10,
                projectionCount: firstProjectionCount
            ),
            for: 1
        )
        family.admit(
            makeEagerDerivedAtomTestRequest(
                identity: 1,
                outputContent: 20,
                projectionCount: secondProjectionCount
            ),
            for: 2
        )
        guard
            await requireEagerDerivedAtomTestEvent(
                "first-key publication",
                wait: { await recorder.wait(forKey: 1, completion: .published(1)) }
            ),
            await requireEagerDerivedAtomTestEvent(
                "second-key publication",
                wait: { await recorder.wait(forKey: 2, completion: .published(1)) }
            )
        else { return }

        #expect(family.currentValue(for: 1)?.content == 10)
        #expect(family.currentValue(for: 2)?.content == 20)

        family.admit(
            makeEagerDerivedAtomTestRequest(
                identity: 2,
                outputContent: 11,
                gate: successorGate,
                projectionCount: firstProjectionCount
            ),
            for: 1
        )
        guard
            await requireEagerDerivedAtomTestEvent(
                "first-key successor start",
                wait: { await successorGate.waitUntilStarted() }
            )
        else { return }

        #expect(family.currentValue(for: 1) == nil)
        #expect(family.currentValue(for: 2)?.content == 20)

        successorGate.release()
        guard
            await requireEagerDerivedAtomTestEvent(
                "first-key successor publication",
                wait: { await recorder.wait(forKey: 1, completion: .published(2)) }
            )
        else { return }

        #expect(family.currentValue(for: 1)?.content == 11)
        #expect(family.currentValue(for: 2)?.content == 20)
    }

    @Test
    func equalCompletionMakesLatestAdmissionReadyWithoutReplacingValue() async {
        let recorder = EagerDerivedAtomFamilyCompletionRecorder()
        let family = makeEagerDerivedAtomTestFamily(completionRecorder: recorder)
        defer { family.stop() }
        let projectionCount = EagerDerivedAtomTestCounter()

        _ = family.materialize(for: 1)
        family.admit(
            makeEagerDerivedAtomTestRequest(
                identity: 1,
                outputContent: 10,
                projectionCount: projectionCount
            ),
            for: 1
        )
        guard
            await requireEagerDerivedAtomTestEvent(
                "initial family publication",
                wait: { await recorder.wait(forKey: 1, completion: .published(1)) }
            )
        else { return }
        let firstValue = family.currentValue(for: 1)

        family.admit(
            makeEagerDerivedAtomTestRequest(
                identity: 2,
                outputContent: 10,
                projectionCount: projectionCount
            ),
            for: 1
        )
        guard
            await requireEagerDerivedAtomTestEvent(
                "equal family completion",
                wait: { await recorder.wait(forKey: 1, completion: .equal(2)) }
            )
        else { return }

        #expect(family.currentValue(for: 1) === firstValue)
        #expect(projectionCount.count == 2)
    }

    @Test
    func supersededCompletionCannotMakeLatestAdmissionReady() async {
        let recorder = EagerDerivedAtomFamilyCompletionRecorder()
        let family = makeEagerDerivedAtomTestFamily(completionRecorder: recorder)
        defer { family.stop() }
        let predecessorGate = EagerDerivedAtomProjectionGate()
        let successorGate = EagerDerivedAtomProjectionGate()
        defer {
            predecessorGate.release()
            successorGate.release()
        }
        let projectionCount = EagerDerivedAtomTestCounter()

        _ = family.materialize(for: 1)
        family.admit(
            makeEagerDerivedAtomTestRequest(
                identity: 1,
                outputContent: 10,
                gate: predecessorGate,
                projectionCount: projectionCount
            ),
            for: 1
        )
        guard
            await requireEagerDerivedAtomTestEvent(
                "family predecessor start",
                wait: { await predecessorGate.waitUntilStarted() }
            )
        else { return }

        family.admit(
            makeEagerDerivedAtomTestRequest(
                identity: 2,
                outputContent: 20,
                gate: successorGate,
                projectionCount: projectionCount
            ),
            for: 1
        )
        guard
            await requireEagerDerivedAtomTestEvent(
                "family successor start",
                wait: { await successorGate.waitUntilStarted() }
            )
        else { return }

        predecessorGate.release()
        guard
            await requireEagerDerivedAtomTestEvent(
                "keyed superseded completion",
                wait: { await recorder.wait(forKey: 1, completion: .superseded(1)) }
            )
        else { return }

        #expect(family.currentValue(for: 1) == nil)

        successorGate.release()
        guard
            await requireEagerDerivedAtomTestEvent(
                "family successor publication",
                wait: { await recorder.wait(forKey: 1, completion: .published(2)) }
            )
        else { return }
        #expect(family.currentValue(for: 1)?.content == 20)
    }

    @Test
    func removalStopsOnlyThatChildAndLateCancellationCannotReadyRematerialization() async {
        let recorder = EagerDerivedAtomFamilyCompletionRecorder()
        let family = makeEagerDerivedAtomTestFamily(completionRecorder: recorder)
        defer { family.stop() }
        let removedGate = EagerDerivedAtomProjectionGate()
        defer { removedGate.release() }
        let projectionCount = EagerDerivedAtomTestCounter()
        let removedChild = family.materialize(for: 1)
        let retainedChild = family.materialize(for: 2)

        family.admit(
            makeEagerDerivedAtomTestRequest(
                identity: 1,
                outputContent: 10,
                gate: removedGate,
                projectionCount: projectionCount
            ),
            for: 1
        )
        guard
            await requireEagerDerivedAtomTestEvent(
                "removed child projection start",
                wait: { await removedGate.waitUntilStarted() }
            )
        else { return }

        family.remove(for: 1)

        #expect(removedChild?.freshness == .stopped)
        #expect(family.atom(for: 1) == nil)
        #expect(family.atom(for: 2) === retainedChild)
        #expect(retainedChild?.freshness == .idle)

        let replacementChild = family.materialize(for: 1)
        #expect(replacementChild != nil)
        #expect(replacementChild !== removedChild)

        removedGate.release()
        guard
            await requireEagerDerivedAtomTestEvent(
                "removed child cancellation",
                wait: { await recorder.wait(forKey: 1, completion: .cancelled(1)) }
            )
        else { return }

        #expect(family.atom(for: 1) === replacementChild)
        #expect(replacementChild?.freshness == .idle)
        #expect(family.currentValue(for: 1) == nil)
    }

    @Test(arguments: [
        EagerDerivedAtomFamilyTermination.removeKey,
        .stopFamily,
    ])
    func terminationRetainsStoppedChildUntilEveryOverlappingProjectionSettles(
        _ termination: EagerDerivedAtomFamilyTermination
    ) async {
        let recorder = EagerDerivedAtomFamilyCompletionRecorder()
        let family = makeEagerDerivedAtomTestFamily(completionRecorder: recorder)
        defer { family.stop() }
        let predecessorGate = EagerDerivedAtomProjectionGate()
        let successorGate = EagerDerivedAtomProjectionGate()
        defer {
            predecessorGate.release()
            successorGate.release()
        }
        let projectionCount = EagerDerivedAtomTestCounter()

        family.admit(
            makeEagerDerivedAtomTestRequest(
                identity: 1,
                outputContent: 10,
                gate: predecessorGate,
                projectionCount: projectionCount
            ),
            for: 1
        )
        guard
            await requireEagerDerivedAtomTestEvent(
                "overlapping predecessor start",
                wait: { await predecessorGate.waitUntilStarted() }
            )
        else { return }

        family.admit(
            makeEagerDerivedAtomTestRequest(
                identity: 2,
                outputContent: 20,
                gate: successorGate,
                projectionCount: projectionCount
            ),
            for: 1
        )
        guard
            await requireEagerDerivedAtomTestEvent(
                "overlapping successor start",
                wait: { await successorGate.waitUntilStarted() }
            )
        else { return }

        switch termination {
        case .removeKey:
            family.remove(for: 1)
        case .stopFamily:
            family.stop()
        }
        predecessorGate.release()
        guard
            await requireEagerDerivedAtomTestEvent(
                "removed predecessor cancellation",
                wait: { await recorder.wait(forKey: 1, completion: .cancelled(1)) }
            )
        else { return }

        successorGate.release()
        guard
            await requireEagerDerivedAtomTestEvent(
                "removed successor cancellation",
                wait: { await recorder.wait(forKey: 1, completion: .cancelled(2)) }
            )
        else { return }

        #expect(projectionCount.count == 2)
        #expect(family.atom(for: 1) == nil)
    }

    @Test
    func ownerReleaseRetainsStoppedChildUntilEveryOverlappingProjectionSettles() async {
        let predecessorGate = EagerDerivedAtomProjectionGate()
        let successorGate = EagerDerivedAtomProjectionGate()
        defer {
            predecessorGate.release()
            successorGate.release()
        }
        let predecessorCancellation = EagerDerivedAtomTestSignal()
        let successorCancellation = EagerDerivedAtomTestSignal()
        let projectionCount = EagerDerivedAtomTestCounter()
        var family: EagerDerivedAtomTestFamily? = makeEagerDerivedAtomTestFamily()
        weak let stoppedChild = family?.materialize(for: 1)

        family?.admit(
            makeEagerDerivedAtomTestRequest(
                identity: 1,
                outputContent: 10,
                gate: predecessorGate,
                projectionCount: projectionCount,
                observesCancellation: true,
                cancellationSignal: predecessorCancellation
            ),
            for: 1
        )
        guard
            await requireEagerDerivedAtomTestEvent(
                "owner-release predecessor start",
                wait: { await predecessorGate.waitUntilStarted() }
            )
        else { return }

        family?.admit(
            makeEagerDerivedAtomTestRequest(
                identity: 2,
                outputContent: 20,
                gate: successorGate,
                projectionCount: projectionCount,
                observesCancellation: true,
                cancellationSignal: successorCancellation
            ),
            for: 1
        )
        guard
            await requireEagerDerivedAtomTestEvent(
                "owner-release successor start",
                wait: { await successorGate.waitUntilStarted() }
            )
        else { return }

        family?.stop()
        family = nil

        #expect(stoppedChild?.freshness == .stopped)
        #expect(stoppedChild?.value == nil)
        #expect(stoppedChild?.hasUnsettledProjectionTasks == true)

        predecessorGate.release()
        guard
            await requireEagerDerivedAtomTestEvent(
                "owner-release predecessor cancellation",
                wait: { await predecessorCancellation.wait() }
            )
        else { return }
        #expect(stoppedChild != nil)
        #expect(stoppedChild?.freshness == .stopped)
        #expect(stoppedChild?.value == nil)

        successorGate.release()
        guard
            await requireEagerDerivedAtomTestEvent(
                "owner-release successor cancellation",
                wait: { await successorCancellation.wait() }
            )
        else { return }

        for _ in 0..<1000 where stoppedChild != nil {
            await Task.yield()
        }
        #expect(stoppedChild == nil)
        #expect(projectionCount.count == 2)
    }

    @Test
    func stopAllIsIdempotentAndRejectsLaterMaterializationAndAdmission() async {
        let recorder = EagerDerivedAtomFamilyCompletionRecorder()
        let family = makeEagerDerivedAtomTestFamily(completionRecorder: recorder)
        let gate = EagerDerivedAtomProjectionGate()
        defer { gate.release() }
        let runningProjectionCount = EagerDerivedAtomTestCounter()
        let rejectedProjectionCount = EagerDerivedAtomTestCounter()
        let first = family.materialize(for: 1)
        let second = family.materialize(for: 2)

        family.admit(
            makeEagerDerivedAtomTestRequest(
                identity: 1,
                outputContent: 10,
                gate: gate,
                projectionCount: runningProjectionCount
            ),
            for: 1
        )
        guard
            await requireEagerDerivedAtomTestEvent(
                "family stop projection start",
                wait: { await gate.waitUntilStarted() }
            )
        else { return }

        family.stop()
        family.stop()

        #expect(first?.freshness == .stopped)
        #expect(second?.freshness == .stopped)
        #expect(family.atoms.isEmpty)
        #expect(family.materialize(for: 1) == nil)
        #expect(family.atom(for: 1) == nil)

        family.admit(
            makeEagerDerivedAtomTestRequest(
                identity: 2,
                outputContent: 20,
                projectionCount: rejectedProjectionCount
            ),
            for: 1
        )

        #expect(rejectedProjectionCount.isEmpty)
        #expect(family.currentValue(for: 1) == nil)

        gate.release()
        guard
            await requireEagerDerivedAtomTestEvent(
                "stopped family cancellation",
                wait: { await recorder.wait(forKey: 1, completion: .cancelled(1)) }
            )
        else { return }
        #expect(family.currentValue(for: 1) == nil)
    }
}
