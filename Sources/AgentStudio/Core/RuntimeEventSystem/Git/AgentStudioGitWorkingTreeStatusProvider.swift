import AgentStudioGit
import Dispatch
import Foundation
import os

typealias AgentStudioGitStatusReader =
    @Sendable (
        URL,
        AgentStudioGit.GitStatusOptions
    ) async throws -> AgentStudioGit.GitStatusSnapshot

struct AgentStudioGitWorkingTreeStatusProvider: GitWorkingTreeStatusProvider {
    private static let logger = Logger(subsystem: "com.agentstudio", category: "AgentStudioGitWorkingTree")

    private let statusReader: AgentStudioGitStatusReader
    private let timeout: Duration
    private let timeoutScheduler: any AgentStudioGitStatusTimeoutScheduler

    init(
        client: any AgentStudioGit.AgentStudioGitLocalClient = AgentStudioGit.LibGit2AgentStudioGitLocalClient(),
        timeout: Duration = AppPolicies.GitRefresh.defaultSDKReadTimeout,
        timeoutScheduler: any AgentStudioGitStatusTimeoutScheduler = DispatchAgentStudioGitStatusTimeoutScheduler()
    ) {
        self.init(timeout: timeout, timeoutScheduler: timeoutScheduler) { worktreePath, options in
            try await client.status(for: worktreePath, options: options)
        }
    }

    init(
        timeout: Duration = AppPolicies.GitRefresh.defaultSDKReadTimeout,
        timeoutScheduler: any AgentStudioGitStatusTimeoutScheduler = DispatchAgentStudioGitStatusTimeoutScheduler(),
        statusReader: @escaping AgentStudioGitStatusReader
    ) {
        self.statusReader = statusReader
        self.timeout = timeout
        self.timeoutScheduler = timeoutScheduler
    }

    func statusResult(for rootPath: URL) async -> GitWorkingTreeStatusResult {
        await Self.computeStatusResult(
            rootPath: rootPath,
            timeout: timeout,
            timeoutScheduler: timeoutScheduler,
            statusReader: statusReader
        )
    }

    @concurrent
    nonisolated private static func computeStatusResult(
        rootPath: URL,
        timeout: Duration,
        timeoutScheduler: any AgentStudioGitStatusTimeoutScheduler,
        statusReader: @escaping AgentStudioGitStatusReader
    ) async -> GitWorkingTreeStatusResult {
        do {
            let snapshot = try await readWithHardTimeout(timeout, timeoutScheduler: timeoutScheduler) {
                try await statusReader(
                    rootPath,
                    AgentStudioGit.GitStatusOptions(includeIgnored: false, includeUntracked: true)
                )
            }
            return .available(map(snapshot))
        } catch is CancellationError {
            return .unavailable(GitWorkingTreeStatusUnavailable(reason: .cancelled))
        } catch AgentStudioGitSDKTimeoutError.timedOut {
            logger.error(
                "AgentStudioGit status timed out for \(rootPath.path, privacy: .public)"
            )
            return .unavailable(GitWorkingTreeStatusUnavailable(reason: .timeout))
        } catch {
            logger.error(
                """
                AgentStudioGit status failed for \(rootPath.path, privacy: .public): \
                \(String(describing: error), privacy: .public)
                """
            )
            return .unavailable(GitWorkingTreeStatusUnavailable(reason: .sdkError))
        }
    }

    nonisolated private static func readWithHardTimeout<ReturnValue: Sendable>(
        _ timeout: Duration,
        timeoutScheduler: any AgentStudioGitStatusTimeoutScheduler,
        operation: @Sendable @escaping () async throws -> ReturnValue
    ) async throws -> ReturnValue {
        let raceBox = AgentStudioGitTimeoutRaceBox<ReturnValue>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ReturnValue, Error>) in
                let race = AgentStudioGitTimeoutRace(continuation: continuation)
                guard raceBox.install(race) else { return }
                // Detached by design: the SDK read may ignore cooperative cancellation.
                // swiftlint:disable:next no_task_detached
                let readTask = Task.detached(priority: .utility) {
                    do {
                        try await race.succeed(operation())
                    } catch {
                        race.fail(error)
                    }
                }
                let scheduledTimeout = timeoutScheduler.scheduleTimeout(after: timeout) {
                    race.fail(AgentStudioGitSDKTimeoutError.timedOut)
                }
                race.install(readTask: readTask, scheduledTimeout: scheduledTimeout)
            }
        } onCancel: {
            raceBox.cancel()
        }
    }

    nonisolated fileprivate static func dispatchInterval(for duration: Duration) -> DispatchTimeInterval {
        let components = duration.components
        let (secondsNanoseconds, multiplicationOverflow) =
            components.seconds.multipliedReportingOverflow(by: 1_000_000_000)
        let attosecondNanoseconds = components.attoseconds / 1_000_000_000
        let (totalNanoseconds, additionOverflow) =
            secondsNanoseconds.addingReportingOverflow(attosecondNanoseconds)

        guard !multiplicationOverflow, !additionOverflow else {
            return .seconds(Int.max)
        }
        guard totalNanoseconds > 0 else {
            return .nanoseconds(0)
        }
        guard totalNanoseconds <= Int64(Int.max) else {
            return .seconds(Int.max)
        }
        return .nanoseconds(Int(totalNanoseconds))
    }

    nonisolated private static func map(_ snapshot: AgentStudioGit.GitStatusSnapshot) -> GitWorkingTreeStatus {
        GitWorkingTreeStatus(
            summary: mapSummary(snapshot.summary, headKind: snapshot.head.kind),
            branch: mapBranch(snapshot.head),
            originResolution: mapOrigin(snapshot.originResolution)
        )
    }

    nonisolated private static func mapSummary(
        _ summary: AgentStudioGit.GitStatusSummary,
        headKind: AgentStudioGit.GitHeadKind
    ) -> GitWorkingTreeSummary {
        let syncCounts = mapSyncCounts(summary, headKind: headKind)
        return GitWorkingTreeSummary(
            changed: summary.unstagedFileCount,
            staged: summary.stagedFileCount,
            untracked: summary.untrackedFileCount,
            linesAdded: summary.linesAdded,
            linesDeleted: summary.linesDeleted,
            aheadCount: syncCounts.aheadCount,
            behindCount: syncCounts.behindCount,
            hasUpstream: syncCounts.hasUpstream
        )
    }

    nonisolated private static func mapSyncCounts(
        _ summary: AgentStudioGit.GitStatusSummary,
        headKind: AgentStudioGit.GitHeadKind
    ) -> (aheadCount: Int?, behindCount: Int?, hasUpstream: Bool?) {
        guard headKind == .branch else {
            return (aheadCount: nil, behindCount: nil, hasUpstream: nil)
        }
        guard summary.hasUpstream else {
            return (aheadCount: nil, behindCount: nil, hasUpstream: false)
        }
        if summary.aheadCount == 0, summary.behindCount == 0 {
            return (aheadCount: 0, behindCount: 0, hasUpstream: true)
        }
        return (
            aheadCount: summary.aheadCount > 0 ? summary.aheadCount : nil,
            behindCount: summary.behindCount > 0 ? summary.behindCount : nil,
            hasUpstream: true
        )
    }

    nonisolated private static func mapBranch(_ head: AgentStudioGit.GitHeadSnapshot) -> String? {
        guard head.kind == .branch else { return nil }
        return head.shortName
    }

    nonisolated private static func mapOrigin(
        _ originResolution: AgentStudioGit.GitOriginResolution
    ) -> GitOriginResolution {
        switch originResolution {
        case .awaitingResolution:
            .awaitingResolution
        case .confirmedAbsent:
            .confirmedAbsent
        case .resolved(let remote):
            .resolved(remote.rawURL)
        }
    }
}

private enum AgentStudioGitSDKTimeoutError: Error {
    case timedOut
}

protocol AgentStudioGitStatusTimeoutScheduler: Sendable {
    func scheduleTimeout(
        after timeout: Duration,
        _ handler: @escaping @Sendable () -> Void
    ) -> AgentStudioGitScheduledTimeout
}

struct AgentStudioGitScheduledTimeout: Sendable {
    private let box: AgentStudioGitScheduledTimeoutBox

    init(cancel: @escaping () -> Void) {
        box = AgentStudioGitScheduledTimeoutBox(cancel: cancel)
    }

    func cancel() {
        box.cancel()
    }
}

private final class AgentStudioGitScheduledTimeoutBox: @unchecked Sendable {
    private let cancelHandler: () -> Void

    init(cancel: @escaping () -> Void) {
        cancelHandler = cancel
    }

    func cancel() {
        cancelHandler()
    }
}

struct DispatchAgentStudioGitStatusTimeoutScheduler: AgentStudioGitStatusTimeoutScheduler {
    private static let timeoutQueue = DispatchQueue(
        label: "com.agentstudio.git-status-timeout",
        qos: .userInitiated
    )

    func scheduleTimeout(
        after timeout: Duration,
        _ handler: @escaping @Sendable () -> Void
    ) -> AgentStudioGitScheduledTimeout {
        let workItem = DispatchWorkItem(block: handler)
        Self.timeoutQueue.asyncAfter(
            deadline: .now() + AgentStudioGitWorkingTreeStatusProvider.dispatchInterval(for: timeout),
            execute: workItem
        )
        return AgentStudioGitScheduledTimeout {
            workItem.cancel()
        }
    }
}

private final class AgentStudioGitTimeoutRaceBox<ReturnValue: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var race: AgentStudioGitTimeoutRace<ReturnValue>?
    private var didCancel = false

    func install(_ race: AgentStudioGitTimeoutRace<ReturnValue>) -> Bool {
        lock.lock()
        if didCancel {
            lock.unlock()
            race.fail(CancellationError())
            return false
        }
        self.race = race
        lock.unlock()
        return true
    }

    func cancel() {
        let raceToCancel: AgentStudioGitTimeoutRace<ReturnValue>?
        lock.lock()
        didCancel = true
        raceToCancel = race
        race = nil
        lock.unlock()

        raceToCancel?.fail(CancellationError())
    }
}

private final class AgentStudioGitTimeoutRace<ReturnValue: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private let continuation: CheckedContinuation<ReturnValue, Error>
    private var didResume = false
    private var readTask: Task<Void, Never>?
    private var scheduledTimeout: AgentStudioGitScheduledTimeout?

    init(continuation: CheckedContinuation<ReturnValue, Error>) {
        self.continuation = continuation
    }

    func install(readTask: Task<Void, Never>, scheduledTimeout: AgentStudioGitScheduledTimeout) {
        lock.lock()
        if didResume {
            lock.unlock()
            readTask.cancel()
            scheduledTimeout.cancel()
            return
        }
        self.readTask = readTask
        self.scheduledTimeout = scheduledTimeout
        lock.unlock()
    }

    func succeed(_ value: ReturnValue) {
        resume(.success(value))
    }

    func fail(_ error: Error) {
        resume(.failure(error))
    }

    private func resume(_ result: Result<ReturnValue, Error>) {
        let workToCancel: (Task<Void, Never>?, AgentStudioGitScheduledTimeout?)
        lock.lock()
        guard !didResume else {
            lock.unlock()
            return
        }
        didResume = true
        workToCancel = (readTask, scheduledTimeout)
        readTask = nil
        scheduledTimeout = nil
        lock.unlock()

        workToCancel.0?.cancel()
        workToCancel.1?.cancel()
        continuation.resume(with: result)
    }
}
