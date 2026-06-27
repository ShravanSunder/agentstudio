import AgentStudioGit
import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
struct AgentStudioGitWorkingTreeStatusProviderTests {
    @Test("SDK status snapshot maps into AgentStudio working-tree status")
    func sdkStatusSnapshotMapsIntoAgentStudioWorkingTreeStatus() async throws {
        let provider = AgentStudioGitWorkingTreeStatusProvider(
            statusReader: { _, _ in
                makeSnapshot(
                    head: AgentStudioGit.GitHeadSnapshot(
                        kind: .branch,
                        oid: "abc123",
                        shortName: "feature/sdk"
                    ),
                    originResolution: .resolved(
                        AgentStudioGit.GitRemoteSnapshot(
                            name: "origin",
                            url: URL(string: "git@example.com:askluna/agent-studio.git")!,
                            rawURL: "git@example.com:askluna/agent-studio.git"
                        )
                    ),
                    summary: makeSummary(
                        stagedFileCount: 2,
                        unstagedFileCount: 3,
                        untrackedFileCount: 1,
                        linesAdded: 8,
                        linesDeleted: 4,
                        aheadCount: 1,
                        behindCount: 2,
                        hasUpstream: true
                    )
                )
            }
        )

        let status = try #require(await provider.status(for: URL(fileURLWithPath: "/tmp/repo")))

        #expect(status.branch == "feature/sdk")
        #expect(status.summary.changed == 3)
        #expect(status.summary.staged == 2)
        #expect(status.summary.untracked == 1)
        #expect(status.summary.linesAdded == 8)
        #expect(status.summary.linesDeleted == 4)
        #expect(status.summary.aheadCount == 1)
        #expect(status.summary.behindCount == 2)
        #expect(status.summary.hasUpstream == true)
        #expect(status.originResolution == .resolved("git@example.com:askluna/agent-studio.git"))
    }

    @Test("SDK origin states preserve AgentStudio origin-resolution semantics")
    func sdkOriginStatesPreserveAgentStudioOriginResolutionSemantics() async throws {
        let awaitingProvider = AgentStudioGitWorkingTreeStatusProvider(
            statusReader: { _, _ in makeSnapshot(originResolution: .awaitingResolution) }
        )
        let absentProvider = AgentStudioGitWorkingTreeStatusProvider(
            statusReader: { _, _ in makeSnapshot(originResolution: .confirmedAbsent) }
        )
        let credentialedRemoteProvider = AgentStudioGitWorkingTreeStatusProvider(
            statusReader: { _, _ in
                makeSnapshot(
                    originResolution: .resolved(
                        AgentStudioGit.GitRemoteSnapshot(
                            name: "origin",
                            url: URL(string: "https://example.com/org/repo.git")!,
                            rawURL: "https://example.com/org/repo.git"
                        )
                    )
                )
            }
        )

        let awaiting = try #require(await awaitingProvider.status(for: URL(fileURLWithPath: "/tmp/repo")))
        let absent = try #require(await absentProvider.status(for: URL(fileURLWithPath: "/tmp/repo")))
        let credentialed = try #require(
            await credentialedRemoteProvider.status(for: URL(fileURLWithPath: "/tmp/repo"))
        )

        #expect(awaiting.originResolution == .awaitingResolution)
        #expect(absent.originResolution == .confirmedAbsent)
        #expect(credentialed.originResolution == .resolved("https://example.com/org/repo.git"))
    }

    @Test("detached and unborn SDK heads map to branchless sync-unknown status")
    func detachedAndUnbornSDKHeadsMapToBranchlessSyncUnknownStatus() async throws {
        let detachedProvider = AgentStudioGitWorkingTreeStatusProvider(
            statusReader: { _, _ in
                makeSnapshot(
                    head: AgentStudioGit.GitHeadSnapshot(kind: .detached, oid: "abc123", shortName: nil),
                    summary: makeSummary(hasUpstream: false)
                )
            }
        )
        let unbornProvider = AgentStudioGitWorkingTreeStatusProvider(
            statusReader: { _, _ in
                makeSnapshot(
                    head: AgentStudioGit.GitHeadSnapshot(kind: .unborn, oid: nil, shortName: "main"),
                    summary: makeSummary(hasUpstream: false)
                )
            }
        )

        let detached = try #require(await detachedProvider.status(for: URL(fileURLWithPath: "/tmp/repo")))
        let unborn = try #require(await unbornProvider.status(for: URL(fileURLWithPath: "/tmp/repo")))

        #expect(detached.branch == nil)
        #expect(detached.summary.aheadCount == nil)
        #expect(detached.summary.behindCount == nil)
        #expect(detached.summary.hasUpstream == nil)
        #expect(unborn.branch == nil)
        #expect(unborn.summary.aheadCount == nil)
        #expect(unborn.summary.behindCount == nil)
        #expect(unborn.summary.hasUpstream == nil)
    }

    @Test("SDK status failure returns nil")
    func sdkStatusFailureReturnsNil() async {
        let provider = AgentStudioGitWorkingTreeStatusProvider(
            statusReader: { _, _ in throw AgentStudioGit.GitDataPlaneError.unsupported(message: "boom") }
        )

        let status = await provider.status(for: URL(fileURLWithPath: "/tmp/not-a-repo"))

        #expect(status == nil)
    }

    @Test("SDK status failure reports SDK error reason")
    func sdkStatusFailureReportsSDKErrorReason() async throws {
        let provider = AgentStudioGitWorkingTreeStatusProvider(
            statusReader: { _, _ in throw AgentStudioGit.GitDataPlaneError.unsupported(message: "boom") }
        )

        let result = await provider.statusResult(for: URL(fileURLWithPath: "/tmp/not-a-repo"))

        guard case .unavailable(let unavailable) = result else {
            Issue.record("expected unavailable result, got \(result)")
            return
        }
        #expect(unavailable.reason == .sdkError)
    }

    @Test("SDK status timeout returns nil")
    func sdkStatusTimeoutReturnsNil() async {
        let gate = StatusReadGate()
        let timeoutScheduler = ManualStatusTimeoutScheduler()
        let provider = AgentStudioGitWorkingTreeStatusProvider(
            timeout: .seconds(999),
            timeoutScheduler: timeoutScheduler
        ) { _, _ in
            await gate.waitUntilReleased()
            return makeSnapshot()
        }

        let statusTask = Task {
            await provider.status(for: URL(fileURLWithPath: "/tmp/slow-repo"))
        }
        await gate.waitUntilStarted()
        await timeoutScheduler.waitUntilScheduled()
        timeoutScheduler.fireScheduledTimeout()
        let status = await statusTask.value
        await gate.release()

        #expect(status == nil)
    }

    @Test("SDK status timeout reports reason")
    func sdkStatusTimeoutReportsReason() async throws {
        let gate = StatusReadGate()
        let timeoutScheduler = ManualStatusTimeoutScheduler()
        let provider = AgentStudioGitWorkingTreeStatusProvider(
            timeout: .seconds(999),
            timeoutScheduler: timeoutScheduler
        ) { _, _ in
            await gate.waitUntilReleased()
            return makeSnapshot()
        }

        let resultTask = Task {
            await provider.statusResult(for: URL(fileURLWithPath: "/tmp/slow-repo"))
        }
        await gate.waitUntilStarted()
        await timeoutScheduler.waitUntilScheduled()
        timeoutScheduler.fireScheduledTimeout()
        let result = await resultTask.value
        await gate.release()

        guard case .unavailable(let unavailable) = result else {
            Issue.record("expected unavailable result, got \(result)")
            return
        }
        #expect(unavailable.reason == .timeout)
    }

    @Test("SDK status cancellation reports cancellation reason")
    func sdkStatusCancellationReportsCancellationReason() async throws {
        let gate = StatusReadGate()
        let tracker = StatusReadTracker()
        let timeoutScheduler = ManualStatusTimeoutScheduler()
        let provider = AgentStudioGitWorkingTreeStatusProvider(
            timeout: .seconds(999),
            timeoutScheduler: timeoutScheduler
        ) { _, _ in
            await tracker.recordStarted()
            await gate.waitUntilReleased()
            await tracker.recordFinished()
            return makeSnapshot()
        }

        let resultTask = Task {
            await provider.statusResult(for: URL(fileURLWithPath: "/tmp/cancelled-repo"))
        }
        await gate.waitUntilStarted()
        resultTask.cancel()
        let result = await resultTask.value
        await gate.release()
        await tracker.waitForFinishedCount(1)

        guard case .unavailable(let unavailable) = result else {
            Issue.record("expected unavailable result, got \(result)")
            return
        }
        #expect(unavailable.reason == .cancelled)
    }

    @Test("SDK status timeout wins when SDK read ignores cancellation")
    func sdkStatusTimeoutWinsWhenSDKReadIgnoresCancellation() async throws {
        let gate = StatusReadGate()
        let timeoutScheduler = ManualStatusTimeoutScheduler()
        let provider = AgentStudioGitWorkingTreeStatusProvider(
            timeout: .seconds(999),
            timeoutScheduler: timeoutScheduler
        ) { _, _ in
            await gate.waitUntilReleased()
            return makeSnapshot()
        }

        let resultTask = Task {
            await provider.statusResult(for: URL(fileURLWithPath: "/tmp/noncooperative-slow-repo"))
        }
        await gate.waitUntilStarted()
        await timeoutScheduler.waitUntilScheduled()
        timeoutScheduler.fireScheduledTimeout()
        let result = await resultTask.value
        await gate.release()

        guard case .unavailable(let unavailable) = result else {
            Issue.record("expected unavailable result, got \(result)")
            return
        }
        #expect(unavailable.reason == .timeout)
    }

    @Test("timed out SDK read keeps same root gated until detached read exits")
    func timedOutSDKReadKeepsSameRootGatedUntilDetachedReadExits() async throws {
        let rootPath = URL(fileURLWithPath: "/tmp/noncooperative-slow-repo")
        let gate = StatusReadGate()
        let tracker = StatusReadTracker()
        let timeoutScheduler = ManualStatusTimeoutScheduler()
        let activeReadRegistry = AgentStudioGitActiveStatusReadRegistry()
        let provider = AgentStudioGitWorkingTreeStatusProvider(
            timeout: .seconds(999),
            timeoutScheduler: timeoutScheduler,
            activeReadRegistry: activeReadRegistry
        ) { _, _ in
            await tracker.recordStarted()
            await gate.waitUntilReleased()
            await tracker.recordFinished()
            return makeSnapshot()
        }

        let timedOutRead = Task {
            await provider.statusResult(for: rootPath)
        }
        await gate.waitUntilStarted()
        await timeoutScheduler.waitUntilScheduled()
        timeoutScheduler.fireScheduledTimeout()
        let timedOutResult = await timedOutRead.value

        let overlappingResult = await provider.statusResult(for: rootPath)
        let startCountWhileGated = await tracker.startedCount()

        await gate.release()
        await activeReadRegistry.waitUntilInactive(AgentStudioGitActiveStatusReadKey(rootPath))
        let recoveredResult = await provider.statusResult(for: rootPath)

        guard case .unavailable(let timedOutUnavailable) = timedOutResult else {
            Issue.record("expected first result to time out, got \(timedOutResult)")
            return
        }
        guard case .unavailable(let overlappingUnavailable) = overlappingResult else {
            Issue.record("expected overlapping result to be unavailable, got \(overlappingResult)")
            return
        }
        guard case .available = recoveredResult else {
            Issue.record("expected provider to recover after detached read exits, got \(recoveredResult)")
            return
        }
        #expect(timedOutUnavailable.reason == .timeout)
        #expect(overlappingUnavailable.reason == .readAlreadyInFlight)
        #expect(startCountWhileGated == 1)
        #expect(await tracker.startedCount() == 2)
    }

    @Test("pre-install timeout keeps same root gated until detached read exits")
    func preInstallTimeoutKeepsSameRootGatedUntilDetachedReadExits() async throws {
        let rootPath = URL(fileURLWithPath: "/tmp/pre-install-timeout-repo")
        let gate = StatusReadGate()
        let tracker = StatusReadTracker()
        let activeReadRegistry = AgentStudioGitActiveStatusReadRegistry()
        let timingOutProvider = AgentStudioGitWorkingTreeStatusProvider(
            timeout: .seconds(999),
            timeoutScheduler: ImmediateStatusTimeoutScheduler(),
            activeReadRegistry: activeReadRegistry
        ) { _, _ in
            await tracker.recordStarted()
            await gate.waitUntilReleased()
            await tracker.recordFinished()
            return makeSnapshot()
        }

        let timedOutResult = await timingOutProvider.statusResult(for: rootPath)
        let overlappingResult = await timingOutProvider.statusResult(for: rootPath)

        await gate.release()
        await activeReadRegistry.waitUntilInactive(AgentStudioGitActiveStatusReadKey(rootPath))

        let recoveredProvider = AgentStudioGitWorkingTreeStatusProvider(
            activeReadRegistry: activeReadRegistry
        ) { _, _ in
            makeSnapshot()
        }
        let recoveredResult = await recoveredProvider.statusResult(for: rootPath)

        guard case .unavailable(let timedOutUnavailable) = timedOutResult else {
            Issue.record("expected first result to time out, got \(timedOutResult)")
            return
        }
        guard case .unavailable(let overlappingUnavailable) = overlappingResult else {
            Issue.record("expected overlapping result to be unavailable, got \(overlappingResult)")
            return
        }
        guard case .available = recoveredResult else {
            Issue.record("expected provider to recover after detached read exits, got \(recoveredResult)")
            return
        }
        #expect(timedOutUnavailable.reason == .timeout)
        #expect(overlappingUnavailable.reason == .readAlreadyInFlight)
        #expect(await tracker.startedCount() == 1)
    }

    @Test("timed out SDK reads across roots respect global detached read limit")
    func timedOutSDKReadsAcrossRootsRespectGlobalDetachedReadLimit() async throws {
        let firstRootPath = URL(fileURLWithPath: "/tmp/noncooperative-slow-repo-1")
        let secondRootPath = URL(fileURLWithPath: "/tmp/noncooperative-slow-repo-2")
        let thirdRootPath = URL(fileURLWithPath: "/tmp/noncooperative-slow-repo-3")
        let gate = StatusReadGate()
        let tracker = StatusReadTracker()
        let timeoutScheduler = ManualStatusTimeoutScheduler()
        let activeReadRegistry = AgentStudioGitActiveStatusReadRegistry(maxActiveReadCount: 2)
        let provider = AgentStudioGitWorkingTreeStatusProvider(
            timeout: .seconds(999),
            timeoutScheduler: timeoutScheduler,
            activeReadRegistry: activeReadRegistry
        ) { _, _ in
            await tracker.recordStarted()
            await gate.waitUntilReleased()
            await tracker.recordFinished()
            return makeSnapshot()
        }

        let firstRead = Task {
            await provider.statusResult(for: firstRootPath)
        }
        let secondRead = Task {
            await provider.statusResult(for: secondRootPath)
        }
        await tracker.waitForStartedCount(2)
        await timeoutScheduler.waitUntilScheduledCount(2)
        timeoutScheduler.fireScheduledTimeout()
        timeoutScheduler.fireScheduledTimeout()
        let firstResult = await firstRead.value
        let secondResult = await secondRead.value

        let overCapacityResult = await provider.statusResult(for: thirdRootPath)
        let startCountWhileDetachedReadsAreGated = await tracker.startedCount()

        await gate.release()
        await tracker.waitForFinishedCount(2)

        guard case .unavailable(let firstUnavailable) = firstResult else {
            Issue.record("expected first result to time out, got \(firstResult)")
            return
        }
        guard case .unavailable(let secondUnavailable) = secondResult else {
            Issue.record("expected second result to time out, got \(secondResult)")
            return
        }
        guard case .unavailable(let overCapacityUnavailable) = overCapacityResult else {
            Issue.record("expected third result to be unavailable, got \(overCapacityResult)")
            return
        }
        #expect(firstUnavailable.reason == .timeout)
        #expect(secondUnavailable.reason == .timeout)
        #expect(overCapacityUnavailable.reason == .readCapacityExceeded)
        #expect(startCountWhileDetachedReadsAreGated == 2)
    }

    @Test("successful SDK read leaves root immediately available for another read")
    func successfulSDKReadLeavesRootImmediatelyAvailableForAnotherRead() async throws {
        let rootPath = URL(fileURLWithPath: "/tmp/successful-read-recovery-repo")
        let activeReadRegistry = AgentStudioGitActiveStatusReadRegistry()
        let provider = AgentStudioGitWorkingTreeStatusProvider(
            activeReadRegistry: activeReadRegistry
        ) { _, _ in
            makeSnapshot()
        }

        let firstResult = await provider.statusResult(for: rootPath)
        let secondResult = await provider.statusResult(for: rootPath)

        guard case .available = firstResult else {
            Issue.record("expected first result to be available, got \(firstResult)")
            return
        }
        guard case .available = secondResult else {
            Issue.record("expected second result to be available, got \(secondResult)")
            return
        }
    }

    @Test("real SDK provider matches shell provider for current status shape")
    func realSDKProviderMatchesShellProviderForCurrentStatusShape() async throws {
        let repoURL = try FilesystemTestGitRepo.create(named: "agentstudio-git-status-provider")
        defer { FilesystemTestGitRepo.destroy(repoURL) }
        try FilesystemTestGitRepo.seedTrackedAndUntrackedChanges(at: repoURL)

        let shellProvider = ShellGitWorkingTreeStatusProvider(processExecutor: DefaultProcessExecutor(timeout: 5))
        let sdkProvider = AgentStudioGitWorkingTreeStatusProvider()

        let shellStatus = try #require(await shellProvider.status(for: repoURL))
        let sdkStatus = try #require(await sdkProvider.status(for: repoURL))

        #expect(sdkStatus.branch == shellStatus.branch)
        #expect(sdkStatus.summary.changed == shellStatus.summary.changed)
        #expect(sdkStatus.summary.staged == shellStatus.summary.staged)
        #expect(sdkStatus.summary.untracked == shellStatus.summary.untracked)
        #expect(sdkStatus.summary.linesAdded == shellStatus.summary.linesAdded)
        #expect(sdkStatus.summary.linesDeleted == shellStatus.summary.linesDeleted)
        #expect(sdkStatus.summary.aheadCount == shellStatus.summary.aheadCount)
        #expect(sdkStatus.summary.behindCount == shellStatus.summary.behindCount)
        #expect(sdkStatus.summary.hasUpstream == shellStatus.summary.hasUpstream)
        #expect(sdkStatus.originResolution == shellStatus.originResolution)
    }

    @Test("real SDK provider matches shell provider for staged status shape")
    func realSDKProviderMatchesShellProviderForStagedStatusShape() async throws {
        let repoURL = try FilesystemTestGitRepo.create(named: "agentstudio-git-status-staged")
        defer { FilesystemTestGitRepo.destroy(repoURL) }
        try "base\n".write(to: repoURL.appending(path: "staged.txt"), atomically: true, encoding: .utf8)
        try FilesystemTestGitRepo.runGit(at: repoURL, args: ["add", "staged.txt"])
        try FilesystemTestGitRepo.runGit(at: repoURL, args: ["commit", "-m", "Seed staged parity"])
        try "base\nstaged\n".write(to: repoURL.appending(path: "staged.txt"), atomically: true, encoding: .utf8)
        try FilesystemTestGitRepo.runGit(at: repoURL, args: ["add", "staged.txt"])
        try "loose\n".write(to: repoURL.appending(path: "loose.txt"), atomically: true, encoding: .utf8)

        try await assertSDKMatchesShell(repoURL)
    }

    @Test("real SDK provider matches shell provider for local origin and upstream sync states")
    func realSDKProviderMatchesShellProviderForLocalOriginAndUpstreamSyncStates() async throws {
        let repoURL = try FilesystemTestGitRepo.create(named: "agentstudio-git-status-upstream")
        defer { FilesystemTestGitRepo.destroy(repoURL) }
        try "base\n".write(to: repoURL.appending(path: "tracked.txt"), atomically: true, encoding: .utf8)
        try FilesystemTestGitRepo.runGit(at: repoURL, args: ["add", "tracked.txt"])
        try FilesystemTestGitRepo.runGit(at: repoURL, args: ["commit", "-m", "Seed upstream parity"])
        let remoteURL = repoURL.deletingLastPathComponent().appending(path: "origin.git")
        defer { FilesystemTestGitRepo.destroy(remoteURL) }
        try FilesystemTestGitRepo.runGit(at: repoURL, args: ["init", "--bare", remoteURL.path])
        try FilesystemTestGitRepo.runGit(at: repoURL, args: ["remote", "add", "origin", remoteURL.path])
        try FilesystemTestGitRepo.runGit(at: repoURL, args: ["push", "-u", "origin", "main"])

        try await assertSDKMatchesShell(repoURL)

        try "ahead\n".write(to: repoURL.appending(path: "ahead.txt"), atomically: true, encoding: .utf8)
        try FilesystemTestGitRepo.runGit(at: repoURL, args: ["add", "ahead.txt"])
        try FilesystemTestGitRepo.runGit(at: repoURL, args: ["commit", "-m", "Local ahead"])

        try await assertSDKMatchesShell(repoURL)
    }

    @Test("real SDK provider returns nil for invalid worktree like shell provider")
    func realSDKProviderReturnsNilForInvalidWorktreeLikeShellProvider() async throws {
        let invalidURL = URL(fileURLWithPath: "/tmp/agentstudio-invalid-status-\(UUID().uuidString)")
        let shellProvider = ShellGitWorkingTreeStatusProvider(processExecutor: DefaultProcessExecutor(timeout: 5))
        let sdkProvider = AgentStudioGitWorkingTreeStatusProvider()

        #expect(await shellProvider.status(for: invalidURL) == nil)
        #expect(await sdkProvider.status(for: invalidURL) == nil)
    }

    @Test("real SDK provider keeps unborn worktrees branchless instead of shell placeholder branch")
    func realSDKProviderKeepsUnbornWorktreesBranchlessInsteadOfShellPlaceholderBranch() async throws {
        let repoURL = try FilesystemTestGitRepo.create(named: "agentstudio-git-status-unborn")
        defer { FilesystemTestGitRepo.destroy(repoURL) }
        let shellProvider = ShellGitWorkingTreeStatusProvider(processExecutor: DefaultProcessExecutor(timeout: 5))
        let sdkProvider = AgentStudioGitWorkingTreeStatusProvider()

        let shellStatus = try #require(await shellProvider.status(for: repoURL))
        let sdkStatus = try #require(await sdkProvider.status(for: repoURL))

        #expect(shellStatus.branch != nil)
        #expect(sdkStatus.branch == nil)
        #expect(sdkStatus.summary.hasUpstream == nil)
    }
}

private func assertSDKMatchesShell(_ repoURL: URL) async throws {
    let shellProvider = ShellGitWorkingTreeStatusProvider(processExecutor: DefaultProcessExecutor(timeout: 5))
    let sdkProvider = AgentStudioGitWorkingTreeStatusProvider()

    let shellStatus = try #require(await shellProvider.status(for: repoURL))
    let sdkStatus = try #require(await sdkProvider.status(for: repoURL))

    #expect(sdkStatus.branch == shellStatus.branch)
    #expect(sdkStatus.summary.changed == shellStatus.summary.changed)
    #expect(sdkStatus.summary.staged == shellStatus.summary.staged)
    #expect(sdkStatus.summary.untracked == shellStatus.summary.untracked)
    #expect(sdkStatus.summary.linesAdded == shellStatus.summary.linesAdded)
    #expect(sdkStatus.summary.linesDeleted == shellStatus.summary.linesDeleted)
    #expect(sdkStatus.summary.aheadCount == shellStatus.summary.aheadCount)
    #expect(sdkStatus.summary.behindCount == shellStatus.summary.behindCount)
    #expect(sdkStatus.summary.hasUpstream == shellStatus.summary.hasUpstream)
    #expect(sdkStatus.originResolution == shellStatus.originResolution)
}

private final class ManualStatusTimeoutScheduler: AgentStudioGitStatusTimeoutScheduler, @unchecked Sendable {
    private struct ScheduledTimeout {
        let id: Int
        let handler: @Sendable () -> Void
    }

    private let lock = NSLock()
    private var nextId = 0
    private var scheduledTimeouts: [ScheduledTimeout] = []
    private var scheduleWaiters: [(minimumCount: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func scheduleTimeout(
        after _: Duration,
        _ handler: @escaping @Sendable () -> Void
    ) -> AgentStudioGitScheduledTimeout {
        let id: Int
        let waiters: [CheckedContinuation<Void, Never>]
        lock.lock()
        id = nextId
        nextId += 1
        scheduledTimeouts.append(ScheduledTimeout(id: id, handler: handler))
        waiters =
            scheduleWaiters
            .filter { $0.minimumCount <= scheduledTimeouts.count }
            .map(\.continuation)
        scheduleWaiters.removeAll { $0.minimumCount <= scheduledTimeouts.count }
        lock.unlock()

        for waiter in waiters {
            waiter.resume()
        }

        return AgentStudioGitScheduledTimeout { [weak self] in
            self?.cancelScheduledTimeout(id: id)
        }
    }

    func waitUntilScheduled() async {
        guard !hasScheduledTimeouts() else { return }

        await withCheckedContinuation { continuation in
            if !appendScheduleWaiterIfNeeded(continuation) {
                continuation.resume()
            }
        }
    }

    func waitUntilScheduledCount(_ count: Int) async {
        guard scheduledTimeoutCount() < count else { return }

        await withCheckedContinuation { continuation in
            if !appendScheduleWaiterIfNeeded(continuation, minimumCount: count) {
                continuation.resume()
            }
        }
    }

    func fireScheduledTimeout() {
        let scheduledTimeout: ScheduledTimeout?
        lock.lock()
        scheduledTimeout = scheduledTimeouts.isEmpty ? nil : scheduledTimeouts.removeFirst()
        lock.unlock()

        scheduledTimeout?.handler()
    }

    private func cancelScheduledTimeout(id: Int) {
        lock.lock()
        scheduledTimeouts.removeAll { $0.id == id }
        lock.unlock()
    }

    private func hasScheduledTimeouts() -> Bool {
        scheduledTimeoutCount() > 0
    }

    private func scheduledTimeoutCount() -> Int {
        lock.lock()
        let result = scheduledTimeouts.count
        lock.unlock()
        return result
    }

    private func appendScheduleWaiterIfNeeded(
        _ waiter: CheckedContinuation<Void, Never>,
        minimumCount: Int = 1
    ) -> Bool {
        lock.lock()
        guard scheduledTimeouts.count < minimumCount else {
            lock.unlock()
            return false
        }
        scheduleWaiters.append((minimumCount: minimumCount, continuation: waiter))
        lock.unlock()
        return true
    }
}

private struct ImmediateStatusTimeoutScheduler: AgentStudioGitStatusTimeoutScheduler {
    func scheduleTimeout(
        after _: Duration,
        _ handler: @escaping @Sendable () -> Void
    ) -> AgentStudioGitScheduledTimeout {
        handler()
        return AgentStudioGitScheduledTimeout {}
    }
}

private actor StatusReadGate {
    private var didStart = false
    private var didRelease = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func waitUntilStarted() async {
        guard !didStart else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func waitUntilReleased() async {
        markStarted()
        guard !didRelease else { return }
        await withCheckedContinuation { continuation in
            releaseWaiters.append(continuation)
        }
    }

    func release() {
        guard !didRelease else { return }
        didRelease = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll(keepingCapacity: false)
        for waiter in waiters {
            waiter.resume()
        }
    }

    private func markStarted() {
        guard !didStart else { return }
        didStart = true
        let waiters = startWaiters
        startWaiters.removeAll(keepingCapacity: false)
        for waiter in waiters {
            waiter.resume()
        }
    }
}

private actor StatusReadTracker {
    private var startCount = 0
    private var finishCount = 0
    private var startWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private var finishWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func recordStarted() {
        startCount += 1
        let readyWaiters = startWaiters.filter { $0.count <= startCount }
        startWaiters.removeAll { $0.count <= startCount }
        for waiter in readyWaiters {
            waiter.continuation.resume()
        }
    }

    func recordFinished() {
        finishCount += 1
        let readyWaiters = finishWaiters.filter { $0.count <= finishCount }
        finishWaiters.removeAll { $0.count <= finishCount }
        for waiter in readyWaiters {
            waiter.continuation.resume()
        }
    }

    func startedCount() -> Int {
        startCount
    }

    func waitForStartedCount(_ count: Int) async {
        guard startCount < count else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append((count: count, continuation: continuation))
        }
    }

    func waitForFinishedCount(_ count: Int) async {
        guard finishCount < count else { return }
        await withCheckedContinuation { continuation in
            finishWaiters.append((count: count, continuation: continuation))
        }
    }
}

private func makeSnapshot(
    head: AgentStudioGit.GitHeadSnapshot = AgentStudioGit.GitHeadSnapshot(
        kind: .branch,
        oid: "abc123",
        shortName: "main"
    ),
    originResolution: AgentStudioGit.GitOriginResolution = .confirmedAbsent,
    summary: AgentStudioGit.GitStatusSummary = makeSummary()
) -> AgentStudioGit.GitStatusSnapshot {
    AgentStudioGit.GitStatusSnapshot(
        repositoryRoot: URL(fileURLWithPath: "/tmp/repo"),
        worktreePath: URL(fileURLWithPath: "/tmp/repo"),
        generatedAtUnixMilliseconds: 1,
        head: head,
        originResolution: originResolution,
        summary: summary,
        entries: []
    )
}

private func makeSummary(
    changedFileCount: Int = 0,
    stagedFileCount: Int = 0,
    unstagedFileCount: Int = 0,
    untrackedFileCount: Int = 0,
    ignoredFileCount: Int = 0,
    linesAdded: Int = 0,
    linesDeleted: Int = 0,
    aheadCount: Int = 0,
    behindCount: Int = 0,
    hasUpstream: Bool = false
) -> AgentStudioGit.GitStatusSummary {
    AgentStudioGit.GitStatusSummary(
        changedFileCount: changedFileCount,
        stagedFileCount: stagedFileCount,
        unstagedFileCount: unstagedFileCount,
        untrackedFileCount: untrackedFileCount,
        ignoredFileCount: ignoredFileCount,
        linesAdded: linesAdded,
        linesDeleted: linesDeleted,
        aheadCount: aheadCount,
        behindCount: behindCount,
        hasUpstream: hasUpstream
    )
}
