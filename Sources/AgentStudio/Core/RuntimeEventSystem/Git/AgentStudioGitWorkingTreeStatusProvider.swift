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
    private let activeReadRegistry: AgentStudioGitActiveStatusReadRegistry

    init(
        client: any AgentStudioGit.AgentStudioGitLocalClient = AgentStudioGit.LibGit2AgentStudioGitLocalClient(),
        timeout: Duration = AppPolicies.GitRefresh.defaultStatusReadTimeout,
        timeoutScheduler: any AgentStudioGitStatusTimeoutScheduler = DispatchAgentStudioGitStatusTimeoutScheduler(),
        activeReadRegistry: AgentStudioGitActiveStatusReadRegistry = AgentStudioGitActiveStatusReadRegistry()
    ) {
        self.init(
            timeout: timeout,
            timeoutScheduler: timeoutScheduler,
            activeReadRegistry: activeReadRegistry,
            statusReader: { worktreePath, options in
                try await client.status(for: worktreePath, options: options)
            }
        )
    }

    init(
        timeout: Duration = AppPolicies.GitRefresh.defaultStatusReadTimeout,
        timeoutScheduler: any AgentStudioGitStatusTimeoutScheduler = DispatchAgentStudioGitStatusTimeoutScheduler(),
        activeReadRegistry: AgentStudioGitActiveStatusReadRegistry = AgentStudioGitActiveStatusReadRegistry(),
        statusReader: @escaping AgentStudioGitStatusReader
    ) {
        self.statusReader = statusReader
        self.timeout = timeout
        self.timeoutScheduler = timeoutScheduler
        self.activeReadRegistry = activeReadRegistry
    }

    func statusResult(for rootPath: URL, pathspecs: [String]?) async -> GitWorkingTreeStatusResult {
        await Self.computeStatusResult(
            rootPath: rootPath,
            pathspecs: pathspecs,
            timeout: timeout,
            timeoutScheduler: timeoutScheduler,
            activeReadRegistry: activeReadRegistry,
            statusReader: statusReader
        )
    }

    @concurrent
    nonisolated private static func computeStatusResult(
        rootPath: URL,
        pathspecs: [String]?,
        timeout: Duration,
        timeoutScheduler: any AgentStudioGitStatusTimeoutScheduler,
        activeReadRegistry: AgentStudioGitActiveStatusReadRegistry,
        statusReader: @escaping AgentStudioGitStatusReader
    ) async -> GitWorkingTreeStatusResult {
        let readKey = AgentStudioGitActiveStatusReadKey(rootPath)
        switch activeReadRegistry.start(readKey) {
        case .started:
            break
        case .sameRootAlreadyInFlight:
            return .unavailable(GitWorkingTreeStatusUnavailable(reason: .readAlreadyInFlight))
        case .capacityExceeded:
            return .unavailable(GitWorkingTreeStatusUnavailable(reason: .readCapacityExceeded))
        }
        do {
            let snapshot = try await readWithHardTimeout(timeout, timeoutScheduler: timeoutScheduler) {
                try await statusReader(
                    rootPath,
                    AgentStudioGit.GitStatusOptions(
                        includeIgnored: false,
                        includeUntracked: true,
                        pathspecs: pathspecs
                    )
                )
            } onOperationFinished: {
                activeReadRegistry.finish(readKey)
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
        operation: @Sendable @escaping () async throws -> ReturnValue,
        onOperationFinished: @escaping @Sendable () -> Void
    ) async throws -> ReturnValue {
        let raceBox = AgentStudioGitTimeoutRaceBox<ReturnValue>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ReturnValue, Error>) in
                let race = AgentStudioGitTimeoutRace(continuation: continuation)
                guard raceBox.install(race) else {
                    onOperationFinished()
                    return
                }
                // Detached by design: the SDK read may ignore cooperative cancellation.
                let operationFinish = AgentStudioGitOperationFinish(onOperationFinished)
                // swiftlint:disable:next no_task_detached
                let readTask = Task.detached(priority: .utility) {
                    defer {
                        operationFinish.finish()
                    }
                    do {
                        let value = try await operation()
                        operationFinish.finish()
                        race.succeed(value)
                    } catch {
                        operationFinish.finish()
                        race.fail(error)
                    }
                }
                let scheduledTimeout = timeoutScheduler.scheduleTimeout(after: timeout) {
                    race.fail(AgentStudioGitSDKTimeoutError.timedOut)
                }
                _ = race.install(readTask: readTask, scheduledTimeout: scheduledTimeout)
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
            originResolution: mapOrigin(snapshot.originResolution),
            entries: snapshot.entries.map(mapEntry)
        )
    }

    nonisolated private static func mapEntry(
        _ entry: AgentStudioGit.GitStatusEntry
    ) -> GitWorkingTreeStatusEntry {
        GitWorkingTreeStatusEntry(
            path: entry.path,
            previousPath: entry.previousPath,
            hasStagedChange: entry.indexState != nil,
            hasUnstagedChange: entry.worktreeState != nil,
            isUntracked: entry.untracked,
            isRename: entry.indexState == .renamed || entry.worktreeState == .renamed
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

private final class AgentStudioGitOperationFinish: @unchecked Sendable {
    private let lock = NSLock()
    private let handler: @Sendable () -> Void
    private var didFinish = false

    init(_ handler: @escaping @Sendable () -> Void) {
        self.handler = handler
    }

    func finish() {
        lock.lock()
        guard !didFinish else {
            lock.unlock()
            return
        }
        didFinish = true
        lock.unlock()

        handler()
    }
}

struct AgentStudioGitActiveStatusReadKey: Hashable, Sendable {
    private let path: String

    init(_ rootPath: URL) {
        self.path = rootPath.standardizedFileURL.resolvingSymlinksInPath().path
    }
}

final class AgentStudioGitActiveStatusReadRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private let maxActiveReadCount: Int
    /// Root in-flight marker. Prevents a duplicate concurrent read of the same root.
    /// Cleared only on true completion of the detached read (`finish`), even after the
    /// caller has abandoned the wait — so an orphaned libgit2 read is never double-started.
    private var activeReadKeys: Set<AgentStudioGitActiveStatusReadKey> = []
    /// Physical-operation slot accounting. Bounds the number of detached native reads that
    /// are still running, including reads whose caller timed out or cancelled. Released only
    /// on true completion of the detached read (`finish`).
    private var capacityHeldKeys: Set<AgentStudioGitActiveStatusReadKey> = []
    private var inactiveWaiters: [AgentStudioGitActiveStatusReadKey: [CheckedContinuation<Void, Never>]] = [:]

    init(maxActiveReadCount: Int = AppPolicies.GitRefresh.defaultDetachedStatusReadLimit) {
        precondition(maxActiveReadCount > 0)
        self.maxActiveReadCount = maxActiveReadCount
    }

    func start(_ key: AgentStudioGitActiveStatusReadKey) -> AgentStudioGitActiveStatusReadStartResult {
        lock.lock()
        if activeReadKeys.contains(key) {
            lock.unlock()
            return .sameRootAlreadyInFlight
        }
        guard capacityHeldKeys.count < maxActiveReadCount else {
            lock.unlock()
            return .capacityExceeded
        }
        activeReadKeys.insert(key)
        capacityHeldKeys.insert(key)
        lock.unlock()
        return .started
    }

    func finish(_ key: AgentStudioGitActiveStatusReadKey) {
        let waiters: [CheckedContinuation<Void, Never>]
        lock.lock()
        activeReadKeys.remove(key)
        capacityHeldKeys.remove(key)
        waiters = inactiveWaiters.removeValue(forKey: key) ?? []
        lock.unlock()

        for waiter in waiters {
            waiter.resume()
        }
    }

    func waitUntilInactive(_ key: AgentStudioGitActiveStatusReadKey) async {
        await withCheckedContinuation { continuation in
            lock.lock()
            guard activeReadKeys.contains(key) else {
                lock.unlock()
                continuation.resume()
                return
            }
            inactiveWaiters[key, default: []].append(continuation)
            lock.unlock()
        }
    }
}

enum AgentStudioGitActiveStatusReadStartResult: Equatable, Sendable {
    case started
    case sameRootAlreadyInFlight
    case capacityExceeded
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

    func install(readTask: Task<Void, Never>, scheduledTimeout: AgentStudioGitScheduledTimeout) -> Bool {
        lock.lock()
        if didResume {
            lock.unlock()
            readTask.cancel()
            scheduledTimeout.cancel()
            return false
        }
        self.readTask = readTask
        self.scheduledTimeout = scheduledTimeout
        lock.unlock()
        return true
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
