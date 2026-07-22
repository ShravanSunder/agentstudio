import Foundation
import Testing

@testable import AgentStudio

@Suite("GitWorkingDirectoryProjector visible tier")
struct GitWorkingDirectoryProjectorVisibleTierTests {
    @Test("visible sidebar worktree refreshes on active cadence before its background stripe")
    func visibleSidebarWorktreeRefreshesOnActiveCadenceBeforeBackgroundStripe() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let clock = TestPushClock()
        let calls = VisibleTierCallRecorder()
        let policy = AppPolicies.GitRefresh.Policy(
            activeCadence: .milliseconds(120),
            backgroundStripeCount: 3,
            maxConcurrentStatusComputes: 4
        )
        let provider = StubGitWorkingTreeStatusProvider { rootPath in
            let callNumber = await calls.record(rootPath.lastPathComponent)
            return GitWorkingTreeStatus(
                summary: GitWorkingTreeSummary(changed: callNumber, staged: 0, untracked: 0),
                branch: "call-\(callNumber)",
                origin: nil
            )
        }
        let actor = GitWorkingDirectoryProjector(
            bus: bus,
            gitWorkingTreeProvider: provider,
            coalescingWindow: .zero,
            periodicRefreshInterval: policy.activeCadence,
            sleepClock: clock,
            refreshPolicy: policy
        )
        await actor.start()

        let visibleWorktreeId = visibleTierWorktreeId(forBackgroundStripe: 2, policy: policy)
        await bus.post(
            visibleTierRegistrationEnvelope(
                seq: 1,
                worktreeId: visibleWorktreeId,
                rootPath: URL(fileURLWithPath: "/tmp/visible-active-\(UUID().uuidString)")
            )
        )
        #expect(await visibleTierWaitUntil { await calls.count == 1 })

        await actor.setSidebarVisibleWorktrees([visibleWorktreeId])
        #expect(await visibleTierWaitUntil { await calls.count == 2 })

        await clock.waitForPendingSleepCount(atLeast: 1)
        clock.advance(by: policy.activeCadence)
        #expect(await visibleTierWaitUntil { await calls.count == 3 })

        await actor.shutdown()
    }

    @Test("removed sidebar visibility demotes worktree back to background stripe")
    func removedSidebarVisibilityDemotesWorktreeBackToBackgroundStripe() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let clock = TestPushClock()
        let calls = VisibleTierCallRecorder()
        let policy = AppPolicies.GitRefresh.Policy(
            activeCadence: .milliseconds(120),
            backgroundStripeCount: 3,
            maxConcurrentStatusComputes: 4
        )
        let provider = StubGitWorkingTreeStatusProvider { rootPath in
            let callNumber = await calls.record(rootPath.lastPathComponent)
            return GitWorkingTreeStatus(
                summary: GitWorkingTreeSummary(changed: callNumber, staged: 0, untracked: 0),
                branch: "call-\(callNumber)",
                origin: nil
            )
        }
        let actor = GitWorkingDirectoryProjector(
            bus: bus,
            gitWorkingTreeProvider: provider,
            coalescingWindow: .zero,
            periodicRefreshInterval: policy.activeCadence,
            sleepClock: clock,
            refreshPolicy: policy
        )
        await actor.start()

        let visibleWorktreeId = visibleTierWorktreeId(forBackgroundStripe: 2, policy: policy)
        await bus.post(
            visibleTierRegistrationEnvelope(
                seq: 1,
                worktreeId: visibleWorktreeId,
                rootPath: URL(fileURLWithPath: "/tmp/visible-demote-\(UUID().uuidString)")
            )
        )
        #expect(await visibleTierWaitUntil { await calls.count == 1 })

        await actor.setSidebarVisibleWorktrees([visibleWorktreeId])
        #expect(await visibleTierWaitUntil { await calls.count == 2 })

        await clock.waitForPendingSleepCount(atLeast: 1)
        clock.advance(by: policy.activeCadence)
        #expect(await visibleTierWaitUntil { await calls.count == 3 })

        await actor.setSidebarVisibleWorktrees([])
        await clock.waitForPendingSleepCount(atLeast: 1)
        clock.advance(by: policy.activeCadence)
        for _ in 0..<300 {
            await Task.yield()
        }
        #expect(await calls.count == 3)

        await clock.waitForPendingSleepCount(atLeast: 1)
        clock.advance(by: policy.activeCadence)
        #expect(await visibleTierWaitUntil { await calls.count == 4 })

        await actor.shutdown()
    }

    @Test("active pane reservation admits before merely visible sidebar worktree")
    func activePaneReservationAdmitsBeforeMerelyVisibleSidebarWorktree() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let gate = VisibleTierStatusGate()
        let policy = AppPolicies.GitRefresh.Policy(
            backgroundStripeCount: 1,
            maxConcurrentStatusComputes: 4,
            oldestStaleReservedSlots: 1
        )
        let provider = StubGitWorkingTreeStatusProvider { rootPath in
            await gate.recordAndWait(rootPath.lastPathComponent)
            return GitWorkingTreeStatus(
                summary: GitWorkingTreeSummary(changed: 1, staged: 0, untracked: 0),
                branch: rootPath.lastPathComponent,
                origin: nil
            )
        }
        let actor = GitWorkingDirectoryProjector(
            bus: bus,
            gitWorkingTreeProvider: provider,
            coalescingWindow: .zero,
            refreshPolicy: policy
        )
        await actor.start()

        for offset in 0..<policy.maxConcurrentStatusComputes {
            await bus.post(
                visibleTierFilesChangedEnvelope(
                    seq: UInt64(offset + 1),
                    worktreeId: UUID(),
                    rootPath: URL(fileURLWithPath: "/tmp/visible-running-\(offset)-\(UUID().uuidString)"),
                    batchSeq: 1
                )
            )
        }
        #expect(await visibleTierWaitUntil { await gate.labels.count == policy.maxConcurrentStatusComputes })

        let visibleWorktreeId = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!
        let activePaneWorktreeId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        await actor.setSidebarVisibleWorktrees([visibleWorktreeId])
        await actor.setActivePaneWorktree(worktreeId: activePaneWorktreeId)
        await bus.post(
            visibleTierFilesChangedEnvelope(
                seq: 10,
                worktreeId: visibleWorktreeId,
                rootPath: URL(fileURLWithPath: "/tmp/visible-pending-\(UUID().uuidString)"),
                batchSeq: 1
            )
        )
        await bus.post(
            visibleTierFilesChangedEnvelope(
                seq: 11,
                worktreeId: activePaneWorktreeId,
                rootPath: URL(fileURLWithPath: "/tmp/active-pane-pending-\(UUID().uuidString)"),
                batchSeq: 1
            )
        )

        await gate.releaseFirst(containing: "visible-running-0")
        #expect(
            await visibleTierWaitUntil {
                await gate.labels.count == policy.maxConcurrentStatusComputes + 1
            }
        )
        let labels = await gate.labels
        #expect(labels.dropFirst(policy.maxConcurrentStatusComputes).first?.contains("active-pane-pending") == true)

        await gate.releaseAll()
        await actor.shutdown()
    }
}

private actor VisibleTierCallRecorder {
    private var labels: [String] = []

    var count: Int {
        labels.count
    }

    func record(_ label: String) -> Int {
        labels.append(label)
        return labels.count
    }
}

private actor VisibleTierStatusGate {
    private(set) var labels: [String] = []
    private var waiters: [String: CheckedContinuation<Void, Never>] = [:]

    func recordAndWait(_ label: String) async {
        labels.append(label)
        await withCheckedContinuation { continuation in
            waiters[label] = continuation
        }
    }

    func releaseFirst(containing fragment: String) {
        guard let key = waiters.keys.sorted().first(where: { $0.contains(fragment) }) else { return }
        waiters.removeValue(forKey: key)?.resume()
    }

    func releaseAll() {
        let continuations = waiters.values
        waiters.removeAll(keepingCapacity: false)
        for continuation in continuations {
            continuation.resume()
        }
    }
}

private func visibleTierWaitUntil(
    maxTurns: Int = 2000,
    _ condition: @escaping () async -> Bool
) async -> Bool {
    for _ in 0..<maxTurns {
        if await condition() {
            return true
        }
        await Task.yield()
    }
    return await condition()
}

private func visibleTierWorktreeId(
    forBackgroundStripe targetStripe: Int,
    policy: AppPolicies.GitRefresh.Policy
) -> UUID {
    for candidateIndex in 0..<10_000 {
        let candidate = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012X", candidateIndex))!
        if policy.backgroundStripe(for: candidate) == targetStripe {
            return candidate
        }
    }
    preconditionFailure("Unable to find deterministic UUID for background stripe \(targetStripe)")
}

private func visibleTierRegistrationEnvelope(
    seq: UInt64,
    worktreeId: UUID,
    rootPath: URL
) -> RuntimeEnvelope {
    .system(
        SystemEnvelope(
            source: .builtin(.filesystemWatcher),
            seq: seq,
            timestamp: ContinuousClock().now,
            event: .topology(.worktreeRegistered(worktreeId: worktreeId, repoId: worktreeId, rootPath: rootPath))
        )
    )
}

private func visibleTierFilesChangedEnvelope(
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
