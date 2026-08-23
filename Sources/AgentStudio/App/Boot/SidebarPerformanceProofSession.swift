import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioRepoExplorer
import AppKit
import Foundation

#if DEBUG
    struct SidebarPerformanceProofOutstandingAction: Sendable {
        let sequence: Int
        let baselineSemanticGeneration: Int
        let baselineAcknowledgedRevision: UInt64
        let baselineVisibleGeneration: UInt64
        let expectedGrouping: RepoExplorerGroupingMode?
        let expectsFilterFocus: Bool
    }

    @MainActor
    struct SidebarPerformanceProofActionTracker {
        private(set) var outstandingAction: SidebarPerformanceProofOutstandingAction?

        mutating func begin(
            sequence: Int,
            baseline: RepoExplorerPerformanceProofReadback,
            expectedGrouping: RepoExplorerGroupingMode?,
            expectsFilterFocus: Bool
        ) -> SidebarPerformanceProofOutstandingAction? {
            guard outstandingAction == nil else { return nil }
            let action = SidebarPerformanceProofOutstandingAction(
                sequence: sequence,
                baselineSemanticGeneration: baseline.semanticGeneration,
                baselineAcknowledgedRevision: baseline.acknowledgedRevision,
                baselineVisibleGeneration: baseline.visibleGeneration,
                expectedGrouping: expectedGrouping,
                expectsFilterFocus: expectsFilterFocus
            )
            outstandingAction = action
            return action
        }

        mutating func complete(sequence: Int) -> Bool {
            guard outstandingAction?.sequence == sequence else { return false }
            outstandingAction = nil
            return true
        }

        nonisolated static func matches(
            _ readback: RepoExplorerPerformanceProofReadback,
            action: SidebarPerformanceProofOutstandingAction
        ) -> Bool {
            readback.semanticGeneration > action.baselineSemanticGeneration
                && readback.acknowledgedRevision > action.baselineAcknowledgedRevision
                && readback.visibleGeneration > action.baselineVisibleGeneration
                && readback.presentationIsReady && readback.isDemanded
                && readback.accessibilityDisposition == .ready
                && (action.expectedGrouping == nil || readback.groupingMode == action.expectedGrouping)
                && (!action.expectsFilterFocus || readback.focusDisposition == .filterFocused)
                && (!action.expectsFilterFocus || readback.queryIsEmpty)
        }
    }

    enum SidebarPerformanceProofPopulation: String, Sendable {
        case zeroPTYIdle = "zero_pty_idle"
        case quiescentPTYIdle = "quiescent_pty_idle"
        case searchClear = "search_clear"
        case grouping
        case hideShow = "hide_show"
        case tabSwitch = "tab_switch"

        init?(kind: AgentStudioStartupDiagnosticAction.Kind) {
            switch kind {
            case .sidebarCPUZeroPTYIdle: self = .zeroPTYIdle
            case .sidebarCPUQuiescentPTYIdle: self = .quiescentPTYIdle
            case .sidebarCPUSearchClear: self = .searchClear
            case .sidebarCPUGrouping: self = .grouping
            case .sidebarCPUHideShow: self = .hideShow
            case .sidebarCPUTabSwitch: self = .tabSwitch
            default: return nil
            }
        }

        var isIdle: Bool { self == .zeroPTYIdle || self == .quiescentPTYIdle }
    }

    @MainActor
    final class SidebarPerformanceProofSession {
        private let population: SidebarPerformanceProofPopulation
        private let window: NSWindow
        private let recorder: AgentStudioStartupTraceRecorder
        private let delay: AsyncDelay
        private let readbackStream: AsyncStream<RepoExplorerPerformanceProofReadback>
        private let readbackContinuation: AsyncStream<RepoExplorerPerformanceProofReadback>.Continuation
        private var latestReadback: RepoExplorerPerformanceProofReadback?
        private var actionTracker = SidebarPerformanceProofActionTracker()

        init(
            population: SidebarPerformanceProofPopulation,
            window: NSWindow,
            recorder: AgentStudioStartupTraceRecorder,
            delay: AsyncDelay = .taskSleep
        ) {
            self.population = population
            self.window = window
            self.recorder = recorder
            self.delay = delay
            (readbackStream, readbackContinuation) = AsyncStream.makeStream(
                of: RepoExplorerPerformanceProofReadback.self,
                bufferingPolicy: .bufferingNewest(1)
            )
        }

        func receive(_ readback: RepoExplorerPerformanceProofReadback) {
            latestReadback = readback
            readbackContinuation.yield(readback)
        }

        func run() async -> Bool {
            guard await waitForInitialReadback() else {
                record("performance.sidebar.proof_action.failed", sequence: 0, outcome: "missing_initial_readback")
                return false
            }
            record("performance.sidebar.proof_population.ready", sequence: 0, outcome: "settled")
            if population.isIdle {
                return true
            }
            do {
                try await delay.wait(AppPolicies.SidebarPerformanceProof.quiescenceInterval)
            } catch {
                return false
            }
            let actionCount = max(
                AppPolicies.SidebarPerformanceProof.requiredSuccessfulActionCount,
                AppPolicies.SidebarPerformanceProof.requiredActionBearingSampleCount
            )
            for sequence in 1...actionCount {
                guard await runAction(sequence: sequence) else { return false }
            }
            record("performance.sidebar.proof_population.completed", sequence: actionCount, outcome: "settled")
            return true
        }

        private func runAction(sequence: Int) async -> Bool {
            guard let baseline = latestReadback else {
                record("performance.sidebar.proof_action.failed", sequence: sequence, outcome: "overlap")
                return false
            }
            await waitForSamplerBoundary()
            let expectedGrouping = groupingExpectation(sequence: sequence)
            guard
                let outstandingAction = actionTracker.begin(
                    sequence: sequence,
                    baseline: baseline,
                    expectedGrouping: expectedGrouping,
                    expectsFilterFocus: population == .searchClear
                )
            else {
                record("performance.sidebar.proof_action.failed", sequence: sequence, outcome: "overlap")
                return false
            }
            record("performance.sidebar.proof_action.started", sequence: sequence, outcome: "started")
            guard await dispatchAction(sequence: sequence, expectedGrouping: expectedGrouping) else {
                _ = actionTracker.complete(sequence: sequence)
                record("performance.sidebar.proof_action.failed", sequence: sequence, outcome: "dispatch_failed")
                return false
            }
            let settled = await waitForSettlement(of: outstandingAction)
            guard actionTracker.complete(sequence: sequence) else {
                record("performance.sidebar.proof_action.failed", sequence: sequence, outcome: "token_mismatch")
                return false
            }
            record(
                settled ? "performance.sidebar.proof_action.settled" : "performance.sidebar.proof_action.failed",
                sequence: sequence,
                outcome: settled ? "settled" : "readback_timeout"
            )
            return settled
        }

        private func dispatchAction(
            sequence: Int,
            expectedGrouping: RepoExplorerGroupingMode?
        ) async -> Bool {
            switch population {
            case .searchClear:
                AppCommandDispatcher.shared.dispatch(.filterSidebar)
                await Task.yield()
                await Task.yield()
                return await SidebarPerformanceProofNativeInputDriver(delay: delay)
                    .typeAndClearFixtureQuery(in: window)
            case .grouping:
                guard let expectedGrouping else { return false }
                let command: AppCommand =
                    switch expectedGrouping {
                    case .repo: .setRepoSidebarGroupingRepo
                    case .pane: .setRepoSidebarGroupingPane
                    case .tab: .setRepoSidebarGroupingTab
                    }
                AppCommandDispatcher.shared.dispatch(command)
                return true
            case .hideShow:
                AppCommandDispatcher.shared.dispatch(.toggleSidebar)
                await Task.yield()
                AppCommandDispatcher.shared.dispatch(.toggleSidebar)
                return true
            case .tabSwitch:
                AppCommandDispatcher.shared.dispatch(sequence.isMultiple(of: 2) ? .selectTab1 : .selectTab2)
                return true
            case .zeroPTYIdle, .quiescentPTYIdle:
                return false
            }
        }

        private func groupingExpectation(sequence: Int) -> RepoExplorerGroupingMode? {
            guard population == .grouping else { return nil }
            return [.repo, .pane, .tab][sequence % 3]
        }

        private func waitForSettlement(
            of outstandingAction: SidebarPerformanceProofOutstandingAction
        ) async -> Bool {
            await withTaskGroup(of: Bool.self) { group in
                group.addTask { [readbackStream] in
                    for await readback in readbackStream {
                        if SidebarPerformanceProofActionTracker.matches(
                            readback,
                            action: outstandingAction
                        ) {
                            return true
                        }
                    }
                    return false
                }
                group.addTask { [delay] in
                    do {
                        try await delay.wait(AppPolicies.SidebarPerformanceProof.actionReadbackTimeout)
                    } catch {}
                    return false
                }
                let result = await group.next() ?? false
                group.cancelAll()
                return result
            }
        }

        private func waitForInitialReadback() async -> Bool {
            if latestReadback != nil { return true }
            return await withTaskGroup(of: Bool.self) { group in
                group.addTask { [readbackStream] in
                    for await _ in readbackStream { return true }
                    return false
                }
                group.addTask { [delay] in
                    do {
                        try await delay.wait(AppPolicies.SidebarPerformanceProof.actionReadbackTimeout)
                    } catch {}
                    return false
                }
                let result = await group.next() ?? false
                group.cancelAll()
                return result
            }
        }

        private func waitForSamplerBoundary() async {
            let interval = AppPolicies.SidebarPerformanceProof.sampleInterval.nanosecondsForTaskSleep
            let now = DispatchTime.now().uptimeNanoseconds
            let remainder = now % interval
            if remainder > 0 {
                try? await delay.wait(.nanoseconds(Int64(interval - remainder)))
            }
        }

        private func record(_ message: String, sequence: Int, outcome: String) {
            recorder.recordAppStartup(
                message,
                phase: "sidebar_performance_proof",
                outcome: outcome,
                attributes: [
                    "agentstudio.performance.sidebar.proof.population": .string(population.rawValue),
                    "agentstudio.performance.sidebar.proof.action.sequence": .int(sequence),
                    "agentstudio.performance.sidebar.proof.monotonic_ns": .int(
                        Int(DispatchTime.now().uptimeNanoseconds)
                    ),
                ]
            )
        }
    }
#endif
