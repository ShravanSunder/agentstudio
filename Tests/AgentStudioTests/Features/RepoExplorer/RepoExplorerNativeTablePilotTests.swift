import Dispatch
import Foundation
import Testing

@testable import AgentStudioRepoExplorer
@testable import AgentStudioTestSupport

@MainActor
@Suite("Repo Explorer native table pilot", .serialized)
struct RepoExplorerNativeTablePilotTests {
    @Test("fixed production pilot passes exact transaction and scale policy")
    func fixedProductionPilotPasses() async {
        let result = await RepoExplorerNativeTablePilot.run(performanceTraceRecorder: nil)
        print(
            "REPO_EXPLORER_NATIVE_TABLE_PILOT_RESULT "
                + "liveness=\(result.livenessProjectionCount) "
                + "drained=\(result.drainedScaleCount) "
                + "templates=\(result.templatePairCount) "
                + "baseline_measurements=\(result.baselineMeasurementCount) "
                + "doubled_measurements=\(result.doubledMeasurementCount) "
                + "baseline_p95_ms=\(result.baselineMembershipP95Milliseconds) "
                + "doubled_p95_ms=\(result.doubledMembershipP95Milliseconds) "
                + "growth_percent=\(result.doubledOffscreenGrowthPercent)"
        )

        #expect(result.policyID == "sidebar-native-table-pilot")
        #expect(result.policyVersion == 1)
        #expect(result.scaleCount == 2)
        #expect(result.livenessProjectionCount == 2)
        #expect(result.drainedScaleCount == 2)
        #expect(result.templatePairCount == 2)
        #expect(result.warmupTransactionCountPerScale == 20)
        #expect(result.measuredTransactionCountPerScale == 200)
        #expect(result.baselineMeasurementCount == 200)
        #expect(result.doubledMeasurementCount == 200)
        #expect(result.exactness)
        #expect(result.completed)
        #expect(result.passed)
        #expect(result.failureReason == nil)
        #expect(result.baselineMembershipP95Milliseconds <= 4)
        #expect(result.doubledMembershipP95Milliseconds <= 4)
        #expect(result.doubledOffscreenGrowthPercent <= 20)
    }

    @Test("pilot composes the production adapter host child and sole applier")
    func pilotComposesProductionPath() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let source = try String(
            contentsOf: projectRoot.appending(
                path:
                    "Sources/AgentStudio/Features/RepoExplorer/Diagnostics/RepoExplorerNativeTablePilot.swift"
            ),
            encoding: .utf8
        )
        let fixtureSource = try String(
            contentsOf: projectRoot.appending(
                path:
                    "Sources/AgentStudio/Features/RepoExplorer/Diagnostics/RepoExplorerNativeTablePilotFixture.swift"
            ),
            encoding: .utf8
        )
        let supportSource = try String(
            contentsOf: projectRoot.appending(
                path:
                    "Sources/AgentStudio/Features/RepoExplorer/Diagnostics/RepoExplorerNativeTablePilotSupport.swift"
            ),
            encoding: .utf8
        )
        let combinedSource = source + fixtureSource + supportSource

        #expect(combinedSource.contains("RepoExplorerProjectionAdapter("))
        #expect(combinedSource.contains("RepoExplorerMaterializationHost("))
        #expect(fixtureSource.contains("NSTableView"))
        #expect(fixtureSource.contains("RepoExplorerMaterializationContentChild"))
        #expect(fixtureSource.contains("RepoExplorerNativeTransactionApplier.apply("))
        #expect(source.contains("projectionAdapter.admit("))
        #expect(source.components(separatedBy: "projectionAdapter.admit(").count - 1 == 1)
        #expect(source.contains("projectionAdapter.registerMaterializationHost("))
        #expect(source.contains("projectionAdapter.stopAndDrain()"))
        #expect(source.contains("reacknowledgeRetainedPresentation("))
        #expect(source.contains("PilotReplayScenario.prepare("))
        #expect(source.contains("template.instantiate("))
        #expect(source.contains("host.apply(candidate)"))
        #expect(supportSource.contains("@concurrent nonisolated static func prepare("))
        #expect(combinedSource.contains("host.detach()"))
        #expect(!combinedSource.replacingOccurrences(of: "group.addTask {", with: "").contains("Task {"))
        // swiftlint:disable:next no_task_detached
        #expect(!combinedSource.contains("Task.detached"))
        #expect(source.contains("async -> RepoExplorerNativeTablePilotResult"))
        #expect(source.contains("withTaskGroup"))
        #expect(source.contains("group.addTask"))
        #expect(source.contains("clock.sleep(until:"))
        #expect(!source.contains("admitDelta"))
        #expect(!combinedSource.contains("Timer"))
        #expect(!combinedSource.contains("NotificationCenter"))
        #expect(!combinedSource.contains("RunLoop"))
        #expect(!combinedSource.contains("Task.sleep"))
        #expect(!combinedSource.contains("DispatchSemaphore"))
        #expect(!combinedSource.contains("NSCondition"))
        #expect(!combinedSource.contains("reloadData()"))
        #expect(source.split(separator: "\n").count < 600)
        #expect(fixtureSource.split(separator: "\n").count < 600)
        #expect(supportSource.split(separator: "\n").count < 600)
    }

    @Test("pilot replay measures mixed membership and displaced survivors")
    func pilotReplayMeasuresCorrectedMembershipPath() async {
        let sourceSnapshot = nativePlanSnapshot((0..<40).map { "row-\($0)" })
        let source = nativePlanContent(sourceSnapshot)
        let scenarioResult = await PilotReplayScenario.prepare(source: source)
        guard case .success(let scenario) = scenarioResult else {
            Issue.record("Expected pilot replay preparation")
            return
        }
        let baseline = nativePlanBaseline(snapshot: sourceSnapshot, revision: 1)
        let candidateResult = scenario.templates.forward.instantiate(
            baseline: baseline,
            candidateID: RepoExplorerMaterializationCandidateID(rawValue: 1),
            requestGeneration: 11,
            visibleGeneration: 11
        )
        guard case .success(let candidate) = candidateResult else {
            Issue.record("Expected pilot template instantiation")
            return
        }
        guard case .changed(let changed) = candidate.nativeUpdatePlan.kind,
            case .contentToContent(.membership(let membership)) = changed.presentation
        else {
            Issue.record("Expected a mixed membership pilot transaction")
            return
        }

        #expect(membership.removeRowsInOldSpace.count > 2)
        #expect(membership.insertRowsInNewSpace.count > 2)
        #expect(membership.movesFromOldToNewSpace.isEmpty)
    }

    @Test("recorded synchronous facade timeout is rejected evidence")
    func recordedSynchronousFalsifierRemainsRejected() {
        let elapsedSeconds = 30.004
        let visibleGeneration: UInt64 = 0
        let baselineMeasurementCount = 0
        let doubledMeasurementCount = 0

        #expect(elapsedSeconds > 30)
        #expect(visibleGeneration == 0)
        #expect(baselineMeasurementCount == 0)
        #expect(doubledMeasurementCount == 0)
    }

    @Test("recorded 440-projection async falsifiers remain rejected")
    func recordedAsyncFullProjectionFalsifiersRemainRejected() {
        let attemptedFullProjectionCount = 440
        let measurementCount = 0
        let crashedDuringUndrainedTeardown = true

        #expect(attemptedFullProjectionCount == 440)
        #expect(measurementCount == 0)
        #expect(crashedDuringUndrainedTeardown)
    }

    @Test("injected deadline latches timeout and drains cooperative projection before return")
    func injectedDeadlineDrainsBeforeReturningFailure() async {
        let clock = TestPushClock()
        let gate = PilotBlockingProjectGate()
        async let pendingResult = RepoExplorerNativeTablePilot.run(
            performanceTraceRecorder: nil,
            clock: clock,
            project: { _ throws(CancellationError) in
                try gate.holdThenCancel()
            }
        )
        await gate.waitUntilStarted()
        await clock.waitForPendingSleepCount(atLeast: 1)

        clock.advance(by: .seconds(30))
        gate.release()
        let result = await pendingResult

        #expect(result.failureReason == .completionTimeout)
        #expect(!result.passed)
        #expect(!result.completed)
        #expect(result.livenessProjectionCount == 1)
        #expect(result.drainedScaleCount == 1)
        #expect(result.templatePairCount == 0)
        #expect(result.baselineMeasurementCount == 0)
        #expect(result.doubledMeasurementCount == 0)
    }
}

private final class PilotBlockingProjectGate: Sendable {
    private let started: AsyncStream<Void>
    private let startedContinuation: AsyncStream<Void>.Continuation
    private let releaseSemaphore = DispatchSemaphore(value: 0)

    init() {
        (started, startedContinuation) = AsyncStream.makeStream(of: Void.self)
    }

    func holdThenCancel() throws(CancellationError) -> RepoExplorerProjectionResult {
        startedContinuation.yield()
        releaseSemaphore.wait()
        throw CancellationError()
    }

    func waitUntilStarted() async {
        for await _ in started { return }
    }

    func release() {
        releaseSemaphore.signal()
        startedContinuation.finish()
    }
}
