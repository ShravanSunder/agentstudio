import AgentStudioCore
import AgentStudioInfrastructure
import AppKit
import Foundation

@MainActor
package enum RepoExplorerNativeTablePilot {
    package static func run(
        performanceTraceRecorder: AgentStudioPerformanceTraceRecorder?
    ) async -> RepoExplorerNativeTablePilotResult {
        await run(
            performanceTraceRecorder: performanceTraceRecorder,
            clock: ContinuousClock()
        )
    }

    static func run<C: Clock>(
        performanceTraceRecorder: AgentStudioPerformanceTraceRecorder?,
        clock: C
    ) async -> RepoExplorerNativeTablePilotResult where C.Duration == Duration {
        await run(
            performanceTraceRecorder: performanceTraceRecorder,
            clock: clock,
            project: projectWork
        )
    }

    static func run<C: Clock>(
        performanceTraceRecorder: AgentStudioPerformanceTraceRecorder?,
        clock: C,
        project:
            @escaping @Sendable (RepoExplorerProjectionWork) throws(CancellationError)
            -> RepoExplorerProjectionResult
    ) async -> RepoExplorerNativeTablePilotResult where C.Duration == Duration {
        let policy = AppPolicies.SidebarPerformanceProof.self
        let completionDeadline = clock.now.advanced(
            by: policy.nativeTablePilotCompletionTimeout
        )

        let baselinePreparation = await prepareScale(
            worktreeCount: policy.worktreeCount,
            scale: .baseline,
            completionDeadline: completionDeadline,
            clock: clock,
            performanceTraceRecorder: performanceTraceRecorder,
            project: project
        )
        guard case .ready(let baselineScale) = baselinePreparation else {
            guard case .failed(let baseline) = baselinePreparation else {
                preconditionFailure("Unhandled native table baseline preparation")
            }
            return failedResult(
                reason: baseline.failureReason ?? .transactionInvalid,
                baseline: baseline,
                doubled: nil,
                performanceTraceRecorder: performanceTraceRecorder
            )
        }

        guard !Task.isCancelled else {
            await baselineScale.runtime.cleanup()
            return failedResult(
                reason: .cancelled,
                baseline: preparedScaleFailure(.cancelled),
                doubled: nil,
                performanceTraceRecorder: performanceTraceRecorder
            )
        }

        let doubledPreparation = await prepareScale(
            worktreeCount: policy.doubledWorktreeCount,
            scale: .doubled,
            completionDeadline: completionDeadline,
            clock: clock,
            performanceTraceRecorder: performanceTraceRecorder,
            project: project
        )
        guard case .ready(let doubledScale) = doubledPreparation else {
            await baselineScale.runtime.cleanup()
            guard case .failed(let doubled) = doubledPreparation else {
                preconditionFailure("Unhandled native table doubled preparation")
            }
            return failedResult(
                reason: doubled.failureReason ?? .transactionInvalid,
                baseline: preparedScaleFailure(doubled.failureReason ?? .transactionInvalid),
                doubled: doubled,
                performanceTraceRecorder: performanceTraceRecorder
            )
        }

        let replayOutcome = replayPairedTransactions(
            baseline: baselineScale,
            doubled: doubledScale,
            completionDeadline: completionDeadline,
            clock: clock
        )
        await baselineScale.runtime.cleanup()
        await doubledScale.runtime.cleanup()

        guard case .completed(let pairedResult) = replayOutcome else {
            guard case .failed(let reason) = replayOutcome else {
                preconditionFailure("Unhandled native table paired replay outcome")
            }
            return failedResult(
                reason: reason,
                baseline: preparedScaleFailure(reason),
                doubled: preparedScaleFailure(reason),
                performanceTraceRecorder: performanceTraceRecorder
            )
        }
        return completedResult(
            pairedResult,
            performanceTraceRecorder: performanceTraceRecorder
        )
    }

    private static func completedResult(
        _ pairedResult: PairedScaleResult,
        performanceTraceRecorder: AgentStudioPerformanceTraceRecorder?
    ) -> RepoExplorerNativeTablePilotResult {
        let policy = AppPolicies.SidebarPerformanceProof.self
        let baseline = pairedResult.baseline
        let doubled = pairedResult.doubled
        recordScaleResults(
            baseline: baseline,
            doubled: doubled,
            performanceTraceRecorder: performanceTraceRecorder
        )
        let growthPercent = growthPercent(
            baseline: baseline.p95Milliseconds,
            doubled: doubled.p95Milliseconds
        )
        let failureReason: RepoExplorerNativeTablePilotResult.FailureReason?
        if baseline.p95Milliseconds > policy.maximumMembershipP95Milliseconds
            || doubled.p95Milliseconds > policy.maximumMembershipP95Milliseconds
        {
            failureReason = .membershipP95Exceeded
        } else if growthPercent > policy.maximumDoubledOffscreenGrowthPercent {
            failureReason = .doubledGrowthExceeded
        } else {
            failureReason = nil
        }

        let result = RepoExplorerNativeTablePilotResult(
            policyID: policy.nativeTablePilotPolicyID,
            policyVersion: policy.nativeTablePilotPolicyVersion,
            scaleCount: policy.scaleWorktreeCounts.count,
            livenessProjectionCount: baseline.livenessProjectionCount
                + doubled.livenessProjectionCount,
            drainedScaleCount: (baseline.drainCompleted ? 1 : 0)
                + (doubled.drainCompleted ? 1 : 0),
            templatePairCount: baseline.templatePairCount + doubled.templatePairCount,
            warmupTransactionCountPerScale: policy.warmupTransactionCountPerScale,
            measuredTransactionCountPerScale: policy.measuredTransactionCountPerScale,
            baselineMeasurementCount: baseline.measurements.count,
            doubledMeasurementCount: doubled.measurements.count,
            baselineMembershipP95Milliseconds: baseline.p95Milliseconds,
            doubledMembershipP95Milliseconds: doubled.p95Milliseconds,
            doubledOffscreenGrowthPercent: growthPercent,
            exactness: baseline.exactness && doubled.exactness,
            completed: true,
            passed: failureReason == nil,
            failureReason: failureReason
        )
        recordSummary(result, performanceTraceRecorder: performanceTraceRecorder)
        return result
    }

    private static func prepareScale<C: Clock>(
        worktreeCount: Int,
        scale: PilotScale,
        completionDeadline: C.Instant,
        clock: C,
        performanceTraceRecorder: AgentStudioPerformanceTraceRecorder?,
        project:
            @escaping @Sendable (RepoExplorerProjectionWork) throws(CancellationError)
            -> RepoExplorerProjectionResult
    ) async -> PilotScalePreparationOutcome where C.Duration == Duration {
        let topology = await PilotTopology.build(
            repositoryCount: AppPolicies.SidebarPerformanceProof.repositoryCount,
            worktreeCount: worktreeCount,
            tabCount: AppPolicies.SidebarPerformanceProof.tabCount,
            paneCount: AppPolicies.SidebarPerformanceProof.paneCount
        )
        let runtime = PilotScaleRuntime(
            topology: topology,
            representedRowCount: AppPolicies.SidebarPerformanceProof.representedRowCount,
            performanceTraceRecorder: performanceTraceRecorder,
            project: project
        )
        guard runtime.projectionAdapter.registerMaterializationHost(runtime.host) else {
            await runtime.cleanup()
            return .failed(.failed(.fixtureInvalid))
        }

        let preparation = await prepareReplay(
            runtime: runtime,
            completionDeadline: completionDeadline,
            clock: clock
        )
        switch preparation {
        case .ready(let replayState):
            return .ready(
                PreparedPilotScale(
                    runtime: runtime,
                    replayState: replayState,
                    scale: scale
                )
            )
        case .failed(let failure):
            await runtime.cleanup()
            performanceTraceRecorder?.record(
                .repoExplorerNativeTablePilot,
                attributes: scaleTraceAttributes(scale: scale, result: failure)
            )
            return .failed(failure)
        }
    }

    private static func prepareReplay<C: Clock>(
        runtime: PilotScaleRuntime,
        completionDeadline: C.Instant,
        clock: C
    ) async -> PilotReplayPreparationOutcome where C.Duration == Duration {
        let generation = 1
        runtime.projectionAdapter.admit(
            runtime.fixture.request(generation: generation, favoriteTarget: false)
        )
        let seedOutcome = await awaitAcceptedEvent(
            stream: runtime.eventChannel.stream,
            expectedGeneration: UInt64(generation),
            expectedCandidateID: UInt64(generation),
            clock: clock,
            completionDeadline: completionDeadline
        )
        guard case .accepted(let seedEvent) = seedOutcome else {
            return await failedPreparation(
                failureReason(for: seedOutcome),
                adapter: runtime.projectionAdapter
            )
        }

        await runtime.projectionAdapter.stopAndDrain()
        let replayDemandEpoch = runtime.projectionAdapter.materializationDemandEpoch
        guard
            let sourceBaseline = runtime.host.reacknowledgeRetainedPresentation(
                demandEpoch: replayDemandEpoch
            ),
            runtime.fixture.contentChild.isExact
        else {
            return .failed(
                .failed(.fixtureInvalid, livenessProjectionCount: 1, drainCompleted: true)
            )
        }
        runtime.fixture.contentChild.discardMeasurements()
        guard !Task.isCancelled, clock.now < completionDeadline else {
            return .failed(
                .failed(
                    Task.isCancelled ? .cancelled : .completionTimeout,
                    livenessProjectionCount: 1,
                    drainCompleted: true
                )
            )
        }

        let scenarioResult = await PilotReplayScenario.prepare(
            source: sourceBaseline.presentation
        )
        guard case .success(let scenario) = scenarioResult else {
            return .failed(
                .failed(.transactionInvalid, livenessProjectionCount: 1, drainCompleted: true)
            )
        }
        guard !Task.isCancelled, clock.now < completionDeadline else {
            return .failed(
                .failed(
                    Task.isCancelled ? .cancelled : .completionTimeout,
                    livenessProjectionCount: 1,
                    drainCompleted: true,
                    templatePairCount: 1
                )
            )
        }
        return .ready(PilotReplayState(seedEvent: seedEvent, scenario: scenario))
    }

    private static func failedPreparation(
        _ reason: RepoExplorerNativeTablePilotResult.FailureReason,
        adapter: RepoExplorerProjectionAdapter
    ) async -> PilotReplayPreparationOutcome {
        await adapter.stopAndDrain()
        return .failed(
            .failed(reason, livenessProjectionCount: 1, drainCompleted: true)
        )
    }

    private static func recordScaleResults(
        baseline: ScaleResult,
        doubled: ScaleResult,
        performanceTraceRecorder: AgentStudioPerformanceTraceRecorder?
    ) {
        performanceTraceRecorder?.record(
            .repoExplorerNativeTablePilot,
            attributes: scaleTraceAttributes(scale: .baseline, result: baseline)
        )
        performanceTraceRecorder?.record(
            .repoExplorerNativeTablePilot,
            attributes: scaleTraceAttributes(scale: .doubled, result: doubled)
        )
    }

    nonisolated private static func projectWork(
        _ work: RepoExplorerProjectionWork
    ) throws(CancellationError) -> RepoExplorerProjectionResult {
        do {
            return try RepoExplorerProjectionWorker.project(work)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            preconditionFailure("Native table pilot projection failed: \(error)")
        }
    }

    private static func awaitAcceptedEvent<C: Clock>(
        stream: AsyncStream<PilotHostEvent>,
        expectedGeneration: UInt64,
        expectedCandidateID: UInt64,
        clock: C,
        completionDeadline: C.Instant
    ) async -> PilotEventWaitOutcome where C.Duration == Duration {
        guard !Task.isCancelled else { return .cancelled }
        let outcome = await withTaskGroup(of: PilotEventWaitOutcome.self) { group in
            group.addTask {
                for await event in stream {
                    guard !Task.isCancelled else { return .cancelled }
                    if event.visibleGeneration == expectedGeneration,
                        event.candidateID == expectedCandidateID
                    {
                        return .accepted(event)
                    }
                    if event.visibleGeneration > expectedGeneration
                        || event.candidateID > expectedCandidateID
                    {
                        return .invalidEvent
                    }
                }
                return Task.isCancelled ? .cancelled : .streamClosed
            }
            group.addTask {
                do {
                    try await clock.sleep(until: completionDeadline, tolerance: nil)
                    return .timedOut
                } catch is CancellationError {
                    return .cancelled
                } catch {
                    return .timedOut
                }
            }
            let first = await group.next() ?? .cancelled
            group.cancelAll()
            while await group.next() != nil {}
            return first
        }
        return Task.isCancelled ? .cancelled : outcome
    }

    private static func failureReason(
        for outcome: PilotEventWaitOutcome
    ) -> RepoExplorerNativeTablePilotResult.FailureReason {
        switch outcome {
        case .timedOut:
            .completionTimeout
        case .cancelled:
            .cancelled
        case .accepted, .invalidEvent, .streamClosed:
            .transactionInvalid
        }
    }

    private static func growthPercent(baseline: Double, doubled: Double) -> Double {
        guard baseline > 0 else { return doubled == 0 ? 0 : .infinity }
        return ((doubled / baseline) - 1) * 100
    }

    private static func failedResult(
        reason: RepoExplorerNativeTablePilotResult.FailureReason,
        baseline: ScaleResult,
        doubled: ScaleResult?,
        performanceTraceRecorder: AgentStudioPerformanceTraceRecorder?
    ) -> RepoExplorerNativeTablePilotResult {
        let policy = AppPolicies.SidebarPerformanceProof.self
        let result = RepoExplorerNativeTablePilotResult(
            policyID: policy.nativeTablePilotPolicyID,
            policyVersion: policy.nativeTablePilotPolicyVersion,
            scaleCount: policy.scaleWorktreeCounts.count,
            livenessProjectionCount: baseline.livenessProjectionCount
                + (doubled?.livenessProjectionCount ?? 0),
            drainedScaleCount: (baseline.drainCompleted ? 1 : 0)
                + ((doubled?.drainCompleted ?? false) ? 1 : 0),
            templatePairCount: baseline.templatePairCount + (doubled?.templatePairCount ?? 0),
            warmupTransactionCountPerScale: policy.warmupTransactionCountPerScale,
            measuredTransactionCountPerScale: policy.measuredTransactionCountPerScale,
            baselineMeasurementCount: baseline.measurements.count,
            doubledMeasurementCount: doubled?.measurements.count ?? 0,
            baselineMembershipP95Milliseconds: baseline.p95Milliseconds,
            doubledMembershipP95Milliseconds: doubled?.p95Milliseconds ?? 0,
            doubledOffscreenGrowthPercent: doubled.map {
                growthPercent(baseline: baseline.p95Milliseconds, doubled: $0.p95Milliseconds)
            } ?? 0,
            exactness: false,
            completed: reason != .completionTimeout && reason != .cancelled,
            passed: false,
            failureReason: reason
        )
        recordSummary(result, performanceTraceRecorder: performanceTraceRecorder)
        return result
    }

    private static func recordSummary(
        _ result: RepoExplorerNativeTablePilotResult,
        performanceTraceRecorder: AgentStudioPerformanceTraceRecorder?
    ) {
        performanceTraceRecorder?.record(
            .repoExplorerNativeTablePilot,
            attributes: [
                "agentstudio.performance.repo_explorer.native_table_pilot.policy_id": .string(
                    result.policyID
                ),
                "agentstudio.performance.repo_explorer.native_table_pilot.policy_version": .int(
                    result.policyVersion
                ),
                "agentstudio.performance.repo_explorer.native_table_pilot.result_version": .int(
                    RepoExplorerNativeTablePilotResult.resultVersion
                ),
                "agentstudio.performance.repo_explorer.native_table_pilot.scale": .string("summary"),
                "agentstudio.performance.repo_explorer.native_table_pilot.outcome": .string(
                    result.passed ? "passed" : "failed"
                ),
                "agentstudio.performance.repo_explorer.native_table_pilot.failure_reason": .string(
                    result.failureReason?.rawValue ?? "none"
                ),
                "agentstudio.performance.repo_explorer.native_table_pilot.warmup.count": .int(
                    result.warmupTransactionCountPerScale
                ),
                "agentstudio.performance.repo_explorer.native_table_pilot.liveness_projection.count": .int(
                    result.livenessProjectionCount
                ),
                "agentstudio.performance.repo_explorer.native_table_pilot.drain_completed.count": .int(
                    result.drainedScaleCount
                ),
                "agentstudio.performance.repo_explorer.native_table_pilot.template_pair.count": .int(
                    result.templatePairCount
                ),
                "agentstudio.performance.repo_explorer.native_table_pilot.measured.count": .int(
                    result.measuredTransactionCountPerScale
                ),
                "agentstudio.performance.repo_explorer.native_table_pilot.baseline_measurement.count": .int(
                    result.baselineMeasurementCount
                ),
                "agentstudio.performance.repo_explorer.native_table_pilot.doubled_measurement.count": .int(
                    result.doubledMeasurementCount
                ),
                "agentstudio.performance.repo_explorer.native_table_pilot.baseline_p95_ms": .double(
                    result.baselineMembershipP95Milliseconds
                ),
                "agentstudio.performance.repo_explorer.native_table_pilot.doubled_p95_ms": .double(
                    result.doubledMembershipP95Milliseconds
                ),
                "agentstudio.performance.repo_explorer.native_table_pilot.growth_percent": .double(
                    result.doubledOffscreenGrowthPercent
                ),
                "agentstudio.performance.repo_explorer.native_table_pilot.exactness": .int(
                    result.exactness ? 1 : 0
                ),
                "agentstudio.performance.repo_explorer.native_table_pilot.completed": .int(
                    result.completed ? 1 : 0
                ),
                "agentstudio.performance.repo_explorer.native_table_pilot.passed": .int(
                    result.passed ? 1 : 0
                ),
            ]
        )
    }

    private static func scaleTraceAttributes(
        scale: PilotScale,
        result: ScaleResult
    ) -> [String: AgentStudioTraceValue] {
        [
            "agentstudio.performance.repo_explorer.native_table_pilot.policy_id": .string(
                AppPolicies.SidebarPerformanceProof.nativeTablePilotPolicyID
            ),
            "agentstudio.performance.repo_explorer.native_table_pilot.policy_version": .int(
                AppPolicies.SidebarPerformanceProof.nativeTablePilotPolicyVersion
            ),
            "agentstudio.performance.repo_explorer.native_table_pilot.result_version": .int(
                RepoExplorerNativeTablePilotResult.resultVersion
            ),
            "agentstudio.performance.repo_explorer.native_table_pilot.scale": .string(scale.rawValue),
            "agentstudio.performance.repo_explorer.native_table_pilot.outcome": .string("completed"),
            "agentstudio.performance.repo_explorer.native_table_pilot.measured.count": .int(
                result.measurements.count
            ),
            "agentstudio.performance.repo_explorer.native_table_pilot.liveness_projection.count": .int(
                result.livenessProjectionCount
            ),
            "agentstudio.performance.repo_explorer.native_table_pilot.drain_completed.count": .int(
                result.drainCompleted ? 1 : 0
            ),
            "agentstudio.performance.repo_explorer.native_table_pilot.template_pair.count": .int(
                result.templatePairCount
            ),
            "agentstudio.performance.repo_explorer.native_table_pilot.membership_p95_ms": .double(
                result.p95Milliseconds
            ),
            "agentstudio.performance.repo_explorer.native_table_pilot.exactness": .int(
                result.exactness ? 1 : 0
            ),
        ]
    }
}
