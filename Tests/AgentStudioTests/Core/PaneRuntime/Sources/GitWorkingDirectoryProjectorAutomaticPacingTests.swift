import AgentStudioInfrastructure
import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioCore

@Suite("GitWorkingDirectoryProjector automatic pacing")
struct GitWorkingDirectoryProjectorAutomaticPacingTests {
    @Test("inactive registration owns no automatic work and warm transition rearms")
    func inactiveRegistrationHasNoAutomaticDeadline() async {
        let worktreeID = UUIDv7.generate()
        let repositoryID = UUIDv7.generate()
        let rootPath = URL(filePath: "/tmp/inactive-registration-\(worktreeID)")
        let providerCallCount = AutomaticPacingCallCounter()
        let actor = GitWorkingDirectoryProjector(
            bus: EventBus<RuntimeEnvelope>(),
            gitWorkingTreeProvider: StubGitWorkingTreeStatusProvider { _ in
                await providerCallCount.increment()
                return GitWorkingTreeStatus(
                    summary: GitWorkingTreeSummary(changed: 0, staged: 0, untracked: 0),
                    branch: "main",
                    origin: nil
                )
            },
            coalescingWindow: .zero
        )

        await actor.setRepositoryFactAttention(
            activePaneWorktreeId: nil,
            sidebarAttendedWorktreeIds: [worktreeID],
            visibleActiveTabWorktreeIds: [],
            openWorktreeIds: [],
            warmAutomaticWorktreeIds: []
        )
        await actor.assertTopology(
            FilesystemTopologyAssertion(
                generation: 1,
                contextsByWorktreeId: [
                    worktreeID: WorktreeFilesystemContext(repoId: repositoryID, rootPath: rootPath)
                ]
            )
        )

        #expect(await providerCallCount.value == 0)
        #expect(await actor.pendingByWorktreeId[worktreeID] == nil)
        #expect(await actor.automaticRefreshDeadlineByWorktreeId[worktreeID] == nil)

        await actor.setRepositoryFactAttention(
            activePaneWorktreeId: nil,
            sidebarAttendedWorktreeIds: [worktreeID],
            visibleActiveTabWorktreeIds: [],
            openWorktreeIds: [],
            warmAutomaticWorktreeIds: [worktreeID]
        )
        #expect(await automaticPacingWaitUntil { await providerCallCount.value == 1 })
        #expect(await automaticPacingWaitUntil { await actor.worktreeTasks.isEmpty })

        await actor.setRepositoryFactAttention(
            activePaneWorktreeId: nil,
            sidebarAttendedWorktreeIds: [worktreeID],
            visibleActiveTabWorktreeIds: [],
            openWorktreeIds: [],
            warmAutomaticWorktreeIds: []
        )

        #expect(await actor.automaticRefreshDeadlineByWorktreeId[worktreeID] == nil)
        #expect(await actor.logicalDebtSnapshot().futureAutomaticCount == 0)
        await actor.shutdown()
    }

    @Test(
        "active-pane invalidation bypasses automatic pacing",
        arguments: [false, true]
    )
    func activePaneInvalidationBypassesAutomaticPacing(
        usesRemoteReferenceRefresh: Bool
    ) async {
        let worktreeId = UUIDv7.generate()
        let rootPath = URL(fileURLWithPath: "/tmp/active-pacing-\(UUIDv7.generate())")
        let actor = GitWorkingDirectoryProjector(
            bus: EventBus<RuntimeEnvelope>(),
            gitWorkingTreeProvider: StubGitWorkingTreeStatusProvider { _ in nil },
            coalescingWindow: .zero,
            refreshPolicy: AppPolicies.GitRefresh.Policy(
                minimumAutomaticStartInterval: .milliseconds(10)
            )
        )
        await actor.setActivePaneWorktree(worktreeId: worktreeId)
        await actor.enqueueImmediateRefresh(
            FileChangeset(
                worktreeId: worktreeId,
                rootPath: rootPath,
                paths: ["tracked.txt"],
                timestamp: ContinuousClock().now,
                batchSeq: 1
            ),
            triggerSource: usesRemoteReferenceRefresh
                ? .remoteReferenceRefresh
                : .filesystemChange
        )

        #expect(
            await !actor.requiresAutomaticStartPacing(
                worktreeId: worktreeId,
                isExplicit: false
            )
        )
        await actor.shutdown()
    }

    @Test(
        "lower-tier invalidation starts obey process pacing",
        arguments: [false, true]
    )
    func lowerTierInvalidationStartsObeyProcessPacing(
        usesRemoteReferenceRefresh: Bool
    ) async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let clock = TestPushClock()
        let gate = AutomaticPacingStatusGate()
        let policy = automaticPacingPolicy()
        let provider = StubGitWorkingTreeStatusProvider { rootPath in
            await gate.recordAndWait(rootPath.lastPathComponent)
            return GitWorkingTreeStatus(
                summary: GitWorkingTreeSummary(changed: 0, staged: 0, untracked: 0),
                branch: "main",
                origin: nil
            )
        }
        let actor = GitWorkingDirectoryProjector(
            bus: bus,
            gitWorkingTreeProvider: provider,
            coalescingWindow: .zero,
            sleepClock: clock,
            refreshPolicy: policy
        )
        await actor.start()

        let worktreeIds = [UUIDv7.generate(), UUIDv7.generate()]
        let rootPaths = [
            URL(fileURLWithPath: "/tmp/lower-tier-pacing-a-\(UUIDv7.generate())"),
            URL(fileURLWithPath: "/tmp/lower-tier-pacing-b-\(UUIDv7.generate())"),
        ]
        await actor.setSidebarVisibleWorktrees(Set(worktreeIds))
        for index in worktreeIds.indices {
            await bus.post(
                automaticPacingRegistrationEnvelope(
                    seq: UInt64(index + 1),
                    worktreeId: worktreeIds[index],
                    rootPath: rootPaths[index]
                )
            )
        }
        #expect(await automaticPacingWaitUntil { await gate.count == 1 })
        await clock.waitForPendingSleepCount(atLeast: 1)
        clock.advance(by: policy.minimumAutomaticStartInterval)
        #expect(await automaticPacingWaitUntil { await gate.count == 2 })
        #expect(await automaticPacingWaitUntil { await gate.waitingCount == 2 })
        await gate.releaseAll()
        #expect(
            await automaticPacingWaitUntil {
                await actor.worktreeTasks.isEmpty
            }
        )

        if usesRemoteReferenceRefresh {
            await actor.enqueueImmediateRefreshIfRegistered(
                worktreeId: worktreeIds[0],
                triggerSource: .remoteReferenceRefresh
            )
            #expect(
                await actor.requiresAutomaticStartPacing(
                    worktreeId: worktreeIds[0],
                    isExplicit: false
                )
            )
            await actor.shutdown()
            return
        }

        let sleepGeneration = clock.scheduledSleepGeneration
        for index in worktreeIds.indices {
            await bus.post(
                automaticPacingFilesChangedEnvelope(
                    seq: UInt64(index + 3),
                    worktreeId: worktreeIds[index],
                    rootPath: rootPaths[index],
                    batchSeq: UInt64(index + 1)
                )
            )
        }

        #expect(await gate.count == 2)
        guard await gate.count == 2 else {
            await gate.releaseAll()
            await actor.shutdown()
            return
        }
        await clock.waitForPendingSleepCount(atLeast: 1, fromGeneration: sleepGeneration)
        let secondStartSleepGeneration = clock.scheduledSleepGeneration
        let nextAutomaticStartAt = await actor.nextAutomaticStartAt
        let deadlineClockNow = await actor.deadlineClock.now
        clock.advance(by: max(.zero, nextAutomaticStartAt - deadlineClockNow))
        #expect(await automaticPacingWaitUntil { await gate.count == 3 })
        await clock.waitForPendingSleepCount(
            atLeast: 1,
            fromGeneration: secondStartSleepGeneration
        )
        clock.advance(by: policy.minimumAutomaticStartInterval - .milliseconds(1))
        #expect(await gate.count == 3)
        clock.advance(by: .milliseconds(1))
        #expect(await automaticPacingWaitUntil { await gate.count == 4 })

        #expect(await automaticPacingWaitUntil { await gate.waitingCount == 2 })
        await gate.releaseAll()
        await actor.shutdown()
    }
}

private actor AutomaticPacingCallCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}

private func automaticPacingPolicy() -> AppPolicies.GitRefresh.Policy {
    AppPolicies.GitRefresh.Policy(
        activePaneCadence: .milliseconds(500),
        visibleSidebarCadence: .seconds(1),
        openPaneCadence: .seconds(2),
        backgroundCadence: .seconds(4),
        backgroundStripeCount: 1,
        maxConcurrentStatusComputes: 4,
        visibleSidebarMaxConcurrent: 2,
        minimumAutomaticStartInterval: .milliseconds(10)
    )
}

private actor AutomaticPacingStatusGate {
    private var labels: [String] = []
    private var waiters: [String: CheckedContinuation<Void, Never>] = [:]

    var count: Int { labels.count }
    var waitingCount: Int { waiters.count }

    func recordAndWait(_ label: String) async {
        labels.append(label)
        await withCheckedContinuation { continuation in
            waiters[label] = continuation
        }
    }

    func releaseAll() {
        let continuations = Array(waiters.values)
        waiters.removeAll(keepingCapacity: true)
        for continuation in continuations {
            continuation.resume()
        }
    }
}

private func automaticPacingWaitUntil(
    maxTurns: Int = 20_000,
    _ condition: @escaping () async -> Bool
) async -> Bool {
    for _ in 0..<maxTurns {
        if await condition() { return true }
        await Task.yield()
    }
    return await condition()
}

private func automaticPacingRegistrationEnvelope(
    seq: UInt64,
    worktreeId: UUID,
    rootPath: URL
) -> RuntimeEnvelope {
    .system(
        SystemEnvelope(
            source: .builtin(.filesystemWatcher),
            seq: seq,
            timestamp: ContinuousClock().now,
            event: .topology(
                .worktreeRegistered(
                    worktreeId: worktreeId,
                    repoId: worktreeId,
                    rootPath: rootPath
                )
            )
        )
    )
}

private func automaticPacingFilesChangedEnvelope(
    seq: UInt64,
    worktreeId: UUID,
    rootPath: URL,
    batchSeq: UInt64
) -> RuntimeEnvelope {
    .worktree(
        WorktreeEnvelope(
            source: .system(.builtin(.filesystemWatcher)),
            seq: seq,
            timestamp: ContinuousClock().now,
            repoId: worktreeId,
            worktreeId: worktreeId,
            event: .filesystem(
                .filesChanged(
                    changeset: FileChangeset(
                        worktreeId: worktreeId,
                        rootPath: rootPath,
                        paths: ["tracked-\(batchSeq).txt"],
                        timestamp: ContinuousClock().now,
                        batchSeq: batchSeq
                    )
                )
            )
        )
    )
}
