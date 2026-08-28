import AgentStudioInfrastructure
import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioCore

@Suite("GitWorkingDirectoryProjector visible tier")
struct GitWorkingDirectoryProjectorVisibleTierTests {
    @Test("automatic registration wave waits for process start pacing")
    func automaticRegistrationWaveWaitsForProcessStartPacing() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let clock = TestPushClock()
        let calls = VisibleTierCallRecorder()
        let gate = VisibleTierStatusGate()
        let policy = AppPolicies.GitRefresh.Policy(
            activePaneCadence: .milliseconds(20),
            visibleSidebarCadence: .milliseconds(40),
            openPaneCadence: .milliseconds(80),
            backgroundCadence: .milliseconds(100),
            backgroundStripeCount: 1,
            maxConcurrentStatusComputes: 4,
            backgroundMaxConcurrent: 4,
            minimumAutomaticStartInterval: .milliseconds(10)
        )
        let provider = StubGitWorkingTreeStatusProvider { rootPath in
            _ = await calls.record(rootPath.lastPathComponent)
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

        for offset in 0..<3 {
            let worktreeID = UUID(
                uuidString: String(format: "00000000-0000-0000-0000-%012X", offset + 1)
            )!
            await bus.post(
                visibleTierRegistrationEnvelope(
                    seq: UInt64(offset + 1),
                    worktreeId: worktreeID,
                    rootPath: URL(fileURLWithPath: "/tmp/paced-registration-\(offset)")
                )
            )
        }
        #expect(await visibleTierWaitUntil { await actor.rootPathByWorktreeId.count == 3 })

        clock.advance(by: policy.backgroundCadence)
        #expect(await visibleTierWaitUntil { await calls.count == 1 })
        await clock.waitForPendingSleepCount(atLeast: 1)
        clock.advance(by: .milliseconds(9))
        #expect(await calls.count == 1)

        let thirdStartSleepGeneration = clock.scheduledSleepGeneration
        clock.advance(by: .milliseconds(1))
        #expect(await visibleTierWaitUntil { await calls.count == 2 })
        await clock.waitForPendingSleepCount(
            atLeast: 1,
            fromGeneration: thirdStartSleepGeneration
        )
        let thirdStartDeadline = try #require(clock.pendingSleepDeadlines.min())
        clock.advance(to: thirdStartDeadline)
        #expect(await visibleTierWaitUntil { await calls.count == 3 })

        await gate.releaseAllAndRemainOpen()
        await actor.shutdown()
    }

    @Test("large hidden registration fleet owns one phased deadline waiter")
    func largeHiddenRegistrationFleetOwnsOneDeadlineWaiter() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let clock = TestPushClock()
        let calls = VisibleTierCallRecorder()
        let policy = AppPolicies.GitRefresh.Policy(
            activePaneCadence: .milliseconds(20),
            visibleSidebarCadence: .milliseconds(40),
            openPaneCadence: .milliseconds(80),
            backgroundCadence: .milliseconds(160),
            backgroundStripeCount: 16,
            maxConcurrentStatusComputes: 4,
            backgroundMaxConcurrent: 4
        )
        let provider = StubGitWorkingTreeStatusProvider { rootPath in
            _ = await calls.record(rootPath.lastPathComponent)
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
            refreshPolicy: policy,
            subscriptionBufferLimit: 512
        )
        await actor.start()

        let worktreeIds = (0..<160).map { offset in
            UUID(uuidString: String(format: "00000000-0000-0000-0000-%012X", offset + 1))!
        }
        for (offset, worktreeId) in worktreeIds.enumerated() {
            await bus.post(
                visibleTierRegistrationEnvelope(
                    seq: UInt64(offset + 1),
                    worktreeId: worktreeId,
                    rootPath: URL(fileURLWithPath: "/tmp/deadline-fleet-\(offset)")
                )
            )
        }
        #expect(await visibleTierWaitUntil { await actor.rootPathByWorktreeId.count == 160 })
        await clock.waitForPendingSleepCount(exactly: 1)
        #expect(await calls.isEmpty)
        #expect(await actor.automaticRefreshDeadlineByWorktreeId.count == 160)

        clock.advance(by: policy.backgroundCadence)
        await calls.waitForCount(160)
        await clock.waitForPendingSleepCount(exactly: 1)

        await actor.shutdown()
        #expect(clock.pendingSleepCount == 0)
    }

    @Test("rapid visibility changes retain only the latest pending delta")
    func rapidVisibilityChangesRetainOnlyLatestPendingDelta() async {
        let clock = TestPushClock()
        let actor = GitWorkingDirectoryProjector(
            bus: EventBus<RuntimeEnvelope>(),
            gitWorkingTreeProvider: StubGitWorkingTreeStatusProvider { _ in nil },
            coalescingWindow: .zero,
            sleepClock: clock
        )
        let firstWorktreeId = UUID()
        let latestWorktreeId = UUID()

        await actor.setSidebarVisibleWorktrees([firstWorktreeId])
        await clock.waitForPendingSleepCount(exactly: 1)
        await actor.setSidebarVisibleWorktrees([latestWorktreeId])
        await clock.waitForPendingSleepCount(exactly: 1)

        #expect(await actor.pendingVisibilityDeltaWorktreeIds == [latestWorktreeId])
        #expect(await actor.sidebarVisibleWorktreeIds == [latestWorktreeId])

        await actor.shutdown()
    }

    @Test("covered worktree visibility change waits for its tier cadence")
    func coveredWorktreeVisibilityChangeWaitsForTierCadence() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let clock = TestPushClock()
        let calls = VisibleTierCallRecorder()
        let policy = AppPolicies.GitRefresh.Policy(
            activePaneCadence: .milliseconds(100),
            visibleSidebarCadence: .milliseconds(200),
            openPaneCadence: .milliseconds(600),
            backgroundCadence: .milliseconds(800)
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
            sleepClock: clock,
            refreshPolicy: policy
        )
        await actor.start()

        let worktreeId = UUID()
        let rootPath = URL(fileURLWithPath: "/tmp/covered-visibility-\(UUID().uuidString)")
        await actor.setActivity(worktreeId: worktreeId, isActiveInApp: true)
        await bus.post(visibleTierRegistrationEnvelope(seq: 1, worktreeId: worktreeId, rootPath: rootPath))
        #expect(await visibleTierWaitUntil { await calls.count == 1 })
        #expect(await visibleTierWaitUntil { await actor.worktreeTasks[worktreeId] == nil })
        await actor.setActivity(worktreeId: worktreeId, isActiveInApp: false)

        await actor.setSidebarVisibleWorktrees([worktreeId])

        #expect(await actor.worktreeTasks[worktreeId] == nil)
        #expect(await calls.count == 1)

        await actor.shutdown()
    }

    @Test("160 visible worktrees stay within the visible share and make rolling progress")
    func hugeVisibleFleetUsesBoundedShareWithRollingProgress() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let clock = TestPushClock()
        let gate = VisibleTierStatusGate()
        let policy = AppPolicies.GitRefresh.Policy(
            activePaneCadence: .milliseconds(100),
            visibleSidebarCadence: .milliseconds(200),
            openPaneCadence: .milliseconds(600),
            backgroundCadence: .milliseconds(800),
            maxConcurrentStatusComputes: 4,
            activePaneMaxConcurrent: 1,
            visibleSidebarMaxConcurrent: 2,
            openPaneMaxConcurrent: 1,
            backgroundMaxConcurrent: 1,
            visibleSidebarStripeSize: 8
        )
        let provider = StubGitWorkingTreeStatusProvider { rootPath in
            await gate.recordAndWait(rootPath.lastPathComponent)
            return GitWorkingTreeStatus(
                summary: GitWorkingTreeSummary(changed: 1, staged: 0, untracked: 0),
                branch: "main",
                origin: nil
            )
        }
        let actor = GitWorkingDirectoryProjector(
            bus: bus,
            gitWorkingTreeProvider: provider,
            coalescingWindow: .zero,
            sleepClock: clock,
            refreshPolicy: policy,
            subscriptionBufferLimit: 512
        )
        await actor.start()

        let worktreeIds = (0..<160).map { offset in
            UUID(uuidString: String(format: "00000000-0000-0000-0000-%012X", offset + 1))!
        }
        for (offset, worktreeId) in worktreeIds.enumerated() {
            await bus.post(
                visibleTierRegistrationEnvelope(
                    seq: UInt64(offset + 1),
                    worktreeId: worktreeId,
                    rootPath: URL(fileURLWithPath: "/tmp/visible-fleet-\(offset)")
                )
            )
        }
        #expect(
            await visibleTierWaitUntil {
                await actor.rootPathByWorktreeId.count == worktreeIds.count
            }
        )
        await actor.setSidebarVisibleWorktrees(Set(worktreeIds))
        await clock.waitForPendingSleepCount(atLeast: 2)
        clock.advance(by: AppPolicies.GitRefresh.visibilityChangeCoalescingWindow)

        await gate.waitForLabelCount(policy.visibleSidebarMaxConcurrent)
        #expect(await gate.labels.count == policy.visibleSidebarMaxConcurrent)

        for expectedCount in stride(from: 4, through: policy.visibleSidebarStripeSize, by: 2) {
            await gate.releaseAll()
            await gate.waitForLabelCount(expectedCount)
        }
        await gate.releaseAllAndRemainOpen()
        await gate.waitForLabelCount(policy.visibleSidebarStripeSize + policy.visibleSidebarMaxConcurrent)
        let admittedLabels = await gate.labels
        #expect(Set(admittedLabels).count > policy.visibleSidebarStripeSize)
        #expect(await gate.maximumInFlightCount == policy.visibleSidebarMaxConcurrent)

        await actor.shutdown()
    }

    @Test("hidden registration retains refresh debt without starting status compute until visible")
    func hiddenRegistrationDefersStatusComputeUntilVisible() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let clock = TestPushClock()
        let calls = VisibleTierCallRecorder()
        let policy = AppPolicies.GitRefresh.Policy(
            activePaneCadence: .milliseconds(100),
            visibleSidebarCadence: .milliseconds(200),
            openPaneCadence: .milliseconds(600),
            backgroundCadence: .milliseconds(800)
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
            sleepClock: clock,
            refreshPolicy: policy
        )
        await actor.start()

        let worktreeId = UUID()
        let rootPath = URL(fileURLWithPath: "/tmp/hidden-demand-\(UUID().uuidString)")
        await bus.post(visibleTierRegistrationEnvelope(seq: 1, worktreeId: worktreeId, rootPath: rootPath))
        await clock.waitForPendingSleepCount(exactly: 1)
        #expect(await calls.isEmpty)
        #expect(await actor.pendingByWorktreeId[worktreeId] != nil)

        await actor.setSidebarVisibleWorktrees([worktreeId])
        await clock.waitForPendingSleepCount(atLeast: 2)
        clock.advance(by: AppPolicies.GitRefresh.visibilityChangeCoalescingWindow)
        #expect(await visibleTierWaitUntil { await calls.count == 1 })

        await actor.shutdown()
    }

    @Test("unchanged cadence multiplier composes with visible tier cadence")
    func unchangedResultsLengthenPeriodicCadence() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let clock = TestPushClock()
        let calls = VisibleTierCallRecorder()
        let policy = AppPolicies.GitRefresh.Policy(
            activePaneCadence: .milliseconds(120),
            visibleSidebarCadence: .milliseconds(240),
            openPaneCadence: .milliseconds(720),
            backgroundCadence: .milliseconds(960),
            backgroundStripeCount: 1,
            maxConcurrentStatusComputes: 1,
            unchangedStatusCadenceMultipliers: [1, 2]
        )
        let provider = StubGitWorkingTreeStatusProvider { rootPath in
            let callNumber = await calls.record(rootPath.lastPathComponent)
            return GitWorkingTreeStatus(
                summary: GitWorkingTreeSummary(changed: min(callNumber, 2), staged: 0, untracked: 0),
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

        let worktreeId = UUID()
        let rootPath = URL(fileURLWithPath: "/tmp/adaptive-cadence-\(UUID().uuidString)")
        await actor.setSidebarVisibleWorktrees([worktreeId])
        await bus.post(visibleTierRegistrationEnvelope(seq: 1, worktreeId: worktreeId, rootPath: rootPath))
        #expect(await visibleTierWaitUntil { await calls.count == 1 })
        #expect(await visibleTierWaitUntil { await actor.worktreeTasks[worktreeId] == nil })
        await clock.waitForPendingSleepCount(atLeast: 2)

        clock.advance(by: policy.visibleSidebarCadence - .milliseconds(1))
        #expect(await calls.count == 1)
        clock.advance(by: .milliseconds(1))
        #expect(await visibleTierWaitUntil { await calls.count == 2 })
        #expect(await visibleTierWaitUntil { await actor.worktreeTasks[worktreeId] == nil })

        await clock.waitForPendingSleepCount(atLeast: 1)
        clock.advance(by: policy.visibleSidebarCadence - .milliseconds(1))
        #expect(await calls.count == 2)
        clock.advance(by: .milliseconds(1))
        #expect(await visibleTierWaitUntil { await calls.count == 3 })
        #expect(await visibleTierWaitUntil { await actor.worktreeTasks[worktreeId] == nil })

        await clock.waitForPendingSleepCount(atLeast: 1)
        clock.advance(
            by: policy.visibleSidebarCadence + policy.visibleSidebarCadence - .milliseconds(1)
        )
        #expect(await calls.count == 3)

        clock.advance(by: .milliseconds(1))
        #expect(await visibleTierWaitUntil { await calls.count == 4 })

        await actor.shutdown()
    }

    @Test(
        "filesystem refresh updates cadence from complete result equality",
        arguments: [false, true]
    )
    func filesystemRefreshUpdatesCadenceFromCompleteResultEquality(
        completeFactsChanged: Bool
    ) async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let clock = TestPushClock()
        let calls = VisibleTierCallRecorder()
        let policy = AppPolicies.GitRefresh.Policy(
            activePaneCadence: .milliseconds(20),
            visibleSidebarCadence: .milliseconds(40),
            openPaneCadence: .milliseconds(120),
            backgroundCadence: .milliseconds(160),
            backgroundStripeCount: 1,
            maxConcurrentStatusComputes: 1,
            unchangedStatusCadenceMultipliers: [1, 2, 4]
        )
        let provider = StubGitWorkingTreeStatusProvider { rootPath in
            let callNumber = await calls.record(rootPath.lastPathComponent)
            let entryPath = completeFactsChanged && callNumber >= 4 ? "b.txt" : "a.txt"
            return GitWorkingTreeStatus(
                summary: GitWorkingTreeSummary(changed: 1, staged: 0, untracked: 0),
                branch: "main",
                originResolution: .confirmedAbsent,
                entries: [
                    GitWorkingTreeStatusEntry(
                        path: entryPath,
                        hasStagedChange: false,
                        hasUnstagedChange: true,
                        isUntracked: false
                    )
                ]
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

        let worktreeId = UUIDv7.generate()
        let rootPath = URL(fileURLWithPath: "/tmp/adapted-filesystem-\(UUIDv7.generate())")
        await actor.setSidebarVisibleWorktrees([worktreeId])
        await bus.post(
            visibleTierRegistrationEnvelope(
                seq: 1,
                worktreeId: worktreeId,
                rootPath: rootPath
            )
        )
        #expect(await visibleTierWaitUntil { await calls.count == 1 })
        #expect(await visibleTierWaitUntil { await actor.worktreeTasks[worktreeId] == nil })

        await clock.waitForPendingSleepCount(atLeast: 1)
        clock.advance(by: policy.visibleSidebarCadence)
        #expect(await visibleTierWaitUntil { await calls.count == 2 })
        #expect(await visibleTierWaitUntil { await actor.worktreeTasks[worktreeId] == nil })

        await clock.waitForPendingSleepCount(atLeast: 1)
        clock.advance(by: policy.visibleSidebarCadence * 2)
        #expect(await visibleTierWaitUntil { await calls.count == 3 })
        #expect(await visibleTierWaitUntil { await actor.worktreeTasks[worktreeId] == nil })
        #expect(await actor.unchangedStatusResultCountByWorktreeId[worktreeId] == 2)

        await bus.post(
            visibleTierFilesChangedEnvelope(
                seq: 2,
                worktreeId: worktreeId,
                rootPath: rootPath,
                batchSeq: 1,
                paths: [".git/HEAD"],
                containsGitInternalChanges: true
            )
        )
        #expect(await visibleTierWaitUntil { await calls.count == 4 })
        #expect(await visibleTierWaitUntil { await actor.worktreeTasks[worktreeId] == nil })
        if completeFactsChanged {
            #expect(await actor.unchangedStatusResultCountByWorktreeId[worktreeId] == nil)
        } else {
            #expect(await actor.unchangedStatusResultCountByWorktreeId[worktreeId] == 3)
        }

        await clock.waitForPendingSleepCount(atLeast: 1)
        let expectedCadence =
            completeFactsChanged
            ? policy.visibleSidebarCadence
            : policy.visibleSidebarCadence * 4
        let lastAutomaticStart = try #require(
            await actor.lastAutomaticStartAtByWorktreeId[worktreeId]
        )
        let scheduledDeadline = try #require(
            await actor.automaticRefreshDeadlineByWorktreeId[worktreeId]
        )
        #expect(scheduledDeadline >= lastAutomaticStart + expectedCadence)
        if !completeFactsChanged {
            clock.advance(by: policy.visibleSidebarCadence * 2)
            #expect(await calls.count == 4)
        }
        let deadlineClockNow = await actor.deadlineClock.now
        clock.advance(by: max(.zero, scheduledDeadline - deadlineClockNow))
        #expect(await visibleTierWaitUntil { await calls.count == 5 })

        await actor.shutdown()
    }

    @Test("visible sidebar worktree refreshes on active cadence before its background stripe")
    func visibleSidebarWorktreeRefreshesOnActiveCadenceBeforeBackgroundStripe() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let clock = TestPushClock()
        let calls = VisibleTierCallRecorder()
        let policy = AppPolicies.GitRefresh.Policy(
            activePaneCadence: .milliseconds(120),
            visibleSidebarCadence: .milliseconds(120),
            openPaneCadence: .milliseconds(360),
            backgroundCadence: .milliseconds(480),
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
            sleepClock: clock,
            refreshPolicy: policy
        )
        await actor.start()

        let visibleWorktreeId = visibleTierWorktreeId(forBackgroundStripe: 2, policy: policy)
        await actor.setActivity(worktreeId: visibleWorktreeId, isActiveInApp: true)
        await bus.post(
            visibleTierRegistrationEnvelope(
                seq: 1,
                worktreeId: visibleWorktreeId,
                rootPath: URL(fileURLWithPath: "/tmp/visible-active-\(UUID().uuidString)")
            )
        )
        #expect(await visibleTierWaitUntil { await calls.count == 1 })

        await actor.setActivity(worktreeId: visibleWorktreeId, isActiveInApp: false)
        await actor.setSidebarVisibleWorktrees([visibleWorktreeId])
        await clock.waitForPendingSleepCount(atLeast: 2)
        clock.advance(by: AppPolicies.GitRefresh.visibilityChangeCoalescingWindow)
        #expect(await visibleTierWaitUntil { await calls.count == 2 })

        for _ in 0..<2 {
            await clock.waitForPendingSleepCount(atLeast: 1)
            clock.advance(by: policy.activePaneCadence)
        }
        #expect(await visibleTierWaitUntil { await calls.count == 3 })

        await actor.shutdown()
    }

    @Test("demotion preserves pending refresh debt until visibility returns")
    func demotionPreservesPendingRefreshDebtUntilVisibilityReturns() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let clock = TestPushClock()
        let gate = VisibleTierStatusGate()
        let policy = AppPolicies.GitRefresh.Policy(
            maxConcurrentStatusComputes: 1,
            visibleSidebarMaxConcurrent: 1
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
            sleepClock: clock,
            refreshPolicy: policy
        )
        await actor.start()

        let blockingWorktreeId = UUID()
        let pendingWorktreeId = UUID()
        await actor.setActivity(worktreeId: blockingWorktreeId, isActiveInApp: true)
        await bus.post(
            visibleTierRegistrationEnvelope(
                seq: 1,
                worktreeId: blockingWorktreeId,
                rootPath: URL(fileURLWithPath: "/tmp/demotion-blocking-\(UUID().uuidString)")
            )
        )
        #expect(await visibleTierWaitUntil { await gate.labels.count == 1 })

        await actor.setSidebarVisibleWorktrees([pendingWorktreeId])
        await bus.post(
            visibleTierRegistrationEnvelope(
                seq: 2,
                worktreeId: pendingWorktreeId,
                rootPath: URL(fileURLWithPath: "/tmp/demotion-pending-\(UUID().uuidString)")
            )
        )
        #expect(await visibleTierWaitUntil { await actor.pendingByWorktreeId[pendingWorktreeId] != nil })

        await actor.setSidebarVisibleWorktrees([])
        #expect(await actor.pendingByWorktreeId[pendingWorktreeId] != nil)

        await gate.releaseFirst(containing: "demotion-blocking")
        #expect(await visibleTierWaitUntil { await actor.worktreeTasks[blockingWorktreeId] == nil })
        for _ in 0..<300 {
            await Task.yield()
        }
        #expect(await gate.labels.count == 1)
        #expect(await actor.pendingByWorktreeId[pendingWorktreeId] != nil)

        let visibilitySleepGeneration = clock.scheduledSleepGeneration
        await actor.setSidebarVisibleWorktrees([pendingWorktreeId])
        await clock.waitForPendingSleepCount(atLeast: 1, fromGeneration: visibilitySleepGeneration)
        clock.advance(by: AppPolicies.GitRefresh.visibilityChangeCoalescingWindow)
        #expect(
            await visibleTierWaitUntil {
                await gate.labels.contains(where: { $0.contains("demotion-pending") })
            }
        )

        await gate.releaseAll()
        await actor.shutdown()
    }

    @Test("active pane reservation admits before merely visible sidebar worktree")
    func activePaneReservationAdmitsBeforeMerelyVisibleSidebarWorktree() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let gate = VisibleTierStatusGate()
        let policy = AppPolicies.GitRefresh.Policy(
            backgroundStripeCount: 1,
            maxConcurrentStatusComputes: 4,
            activePaneMaxConcurrent: 1
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

        let runningWorktreeIds = (0..<policy.maxConcurrentStatusComputes).map { _ in UUID() }
        await actor.setSidebarVisibleWorktrees(Set(runningWorktreeIds))
        for (offset, runningWorktreeId) in runningWorktreeIds.enumerated() {
            await bus.post(
                visibleTierFilesChangedEnvelope(
                    seq: UInt64(offset + 1),
                    worktreeId: runningWorktreeId,
                    rootPath: URL(fileURLWithPath: "/tmp/visible-running-\(offset)-\(UUID().uuidString)"),
                    batchSeq: 1
                )
            )
        }
        #expect(await visibleTierWaitUntil { await gate.labels.count == policy.visibleSidebarMaxConcurrent })

        let visibleWorktreeId = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!
        let activePaneWorktreeId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        await actor.setSidebarVisibleWorktrees(Set(runningWorktreeIds).union([visibleWorktreeId]))
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

        #expect(
            await visibleTierWaitUntil {
                await gate.labels.count == policy.visibleSidebarMaxConcurrent + 1
            }
        )
        let labels = await gate.labels
        #expect(labels.contains(where: { $0.contains("active-pane-pending") }))

        await gate.releaseAll()
        await actor.shutdown()
    }
}

private actor VisibleTierCallRecorder {
    private var labels: [String] = []
    private var countWaiters: [Int: [CheckedContinuation<Void, Never>]] = [:]

    var count: Int {
        labels.count
    }

    var isEmpty: Bool {
        labels.isEmpty
    }

    func record(_ label: String) -> Int {
        labels.append(label)
        resumeSatisfiedCountWaiters()
        return labels.count
    }

    func waitForCount(_ expectedCount: Int) async {
        guard labels.count < expectedCount else { return }
        await withCheckedContinuation { continuation in
            countWaiters[expectedCount, default: []].append(continuation)
        }
    }

    private func resumeSatisfiedCountWaiters() {
        let satisfiedCounts = countWaiters.keys.filter { $0 <= labels.count }
        for satisfiedCount in satisfiedCounts {
            let continuations = countWaiters.removeValue(forKey: satisfiedCount) ?? []
            for continuation in continuations {
                continuation.resume()
            }
        }
    }
}

private actor VisibleTierStatusGate {
    private(set) var labels: [String] = []
    private var waiters: [String: CheckedContinuation<Void, Never>] = [:]
    private var countWaiters: [Int: [CheckedContinuation<Void, Never>]] = [:]
    private(set) var maximumInFlightCount = 0
    private var remainsOpen = false

    func recordAndWait(_ label: String) async {
        labels.append(label)
        resumeSatisfiedCountWaiters()
        guard !remainsOpen else { return }
        await withCheckedContinuation { continuation in
            waiters[label] = continuation
            maximumInFlightCount = max(maximumInFlightCount, waiters.count)
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

    func releaseAllAndRemainOpen() {
        remainsOpen = true
        releaseAll()
    }

    func waitForLabelCount(_ expectedCount: Int) async {
        guard labels.count < expectedCount else { return }
        await withCheckedContinuation { continuation in
            countWaiters[expectedCount, default: []].append(continuation)
        }
    }

    private func resumeSatisfiedCountWaiters() {
        let satisfiedCounts = countWaiters.keys.filter { $0 <= labels.count }
        for satisfiedCount in satisfiedCounts {
            let continuations = countWaiters.removeValue(forKey: satisfiedCount) ?? []
            for continuation in continuations {
                continuation.resume()
            }
        }
    }
}

private func visibleTierWaitUntil(
    maxTurns: Int = 20_000,
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
    batchSeq: UInt64,
    paths: [String]? = nil,
    containsGitInternalChanges: Bool = false
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
                        paths: paths ?? ["tracked-\(batchSeq).txt"],
                        containsGitInternalChanges: containsGitInternalChanges,
                        timestamp: ContinuousClock().now,
                        batchSeq: batchSeq
                    )
                )
            )
        )
    )
}
