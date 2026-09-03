import AgentStudioGit
import AgentStudioInfrastructure
import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioCore

@Suite("GitWorkingDirectoryProjector admission")
struct GitWorkingDirectoryProjectorAdmissionTests {
    @Test("quarantine discards orphaned capacity rearm state")
    func quarantineDiscardsOrphanedCapacityRearmState() async {
        let worktreeId = UUIDv7.generate()
        let rootPath = URL(fileURLWithPath: "/tmp/admission-rearm-quarantine-\(worktreeId)")
        let pathProbe = RootPathProbeRecorder(missingRootPaths: [rootPath])
        let actor = GitWorkingDirectoryProjector(
            bus: EventBus<RuntimeEnvelope>(),
            gitWorkingTreeProvider: StubGitWorkingTreeStatusProvider { _ in nil },
            coalescingWindow: .zero,
            pathExistenceProbe: { probedRootPath in
                pathProbe.recordExistence(probedRootPath)
            }
        )
        await actor.scheduleCapacityRetry(
            for: admissionFilesystemChangeset(worktreeId: worktreeId, rootPath: rootPath, batchSeq: 1),
            reason: .readCapacityExceeded,
            afterPhysicalCompletionGeneration: nil
        )
        #expect(await actor.capacityRearmedWorktreeIds == Set([worktreeId]))

        await actor.expireCapacityRetry(worktreeId: worktreeId)

        #expect(await actor.quarantinedWorktreeIds == Set([worktreeId]))
        #expect(await actor.capacityRearmedWorktreeIds.isEmpty)
        #expect(await actor.pendingByWorktreeId[worktreeId] == nil)
        #expect(pathProbe.recordedRootPaths == [rootPath])

        await actor.shutdown()
    }

    @Test("capacity completion resumes the paid attempt and paces the next invalidation")
    func capacityCompletionResumesPaidAttemptAndPacesNextInvalidation() async {
        let clock = TestPushClock()
        let physicalGate = AgentStudioGitStatusPhysicalGate(maxActiveReadCount: 1)
        let blockingReadStarted = AdmissionAsyncReceipt()
        let blockingReadGate = AdmissionAsyncGate()
        let statusSnapshot = admissionCompleteStatusSnapshot()
        let blockingProvider = AgentStudioGitWorkingTreeStatusProvider(
            slowObservationScheduler: PassiveAdmissionGitStatusSlowObservationScheduler(),
            physicalGate: physicalGate
        ) { _, _ in
            await blockingReadStarted.signal()
            await blockingReadGate.waitUntilOpen()
            return statusSnapshot
        }
        let projectorProvider = AgentStudioGitWorkingTreeStatusProvider(
            slowObservationScheduler: PassiveAdmissionGitStatusSlowObservationScheduler(),
            physicalGate: physicalGate
        ) { _, _ in statusSnapshot }
        let policy = AppPolicies.GitRefresh.Policy(
            maxConcurrentStatusComputes: 1,
            backgroundMaxConcurrent: 1,
            capacityRetryJitterMaxDelay: .zero,
            minimumAutomaticStartInterval: .milliseconds(300)
        )
        let actor = GitWorkingDirectoryProjector(
            bus: EventBus<RuntimeEnvelope>(),
            gitWorkingTreeProvider: projectorProvider,
            coalescingWindow: .zero,
            sleepClock: clock,
            refreshPolicy: policy
        )
        await actor.start()

        let blockingRead = Task {
            await blockingProvider.statusResult(
                for: URL(fileURLWithPath: "/tmp/admission-capacity-pacing-blocker")
            )
        }
        await blockingReadStarted.wait()

        let worktreeId = UUIDv7.generate()
        let rootPath = URL(fileURLWithPath: "/tmp/admission-capacity-pacing-\(worktreeId)")
        await actor.enqueueImmediateRefresh(
            admissionFilesystemChangeset(worktreeId: worktreeId, rootPath: rootPath, batchSeq: 1),
            triggerSource: .filesystemChange
        )
        #expect(
            await admissionWaitUntil {
                await actor.capacityRetryWorktreeIds == Set([worktreeId])
            }
        )
        let originalRequestSequence = await actor.refreshAttribution.requestSequenceByWorktreeId[worktreeId]
        #expect(originalRequestSequence != nil)
        #expect(await actor.refreshAttribution.triggerSourceByWorktreeId[worktreeId] == .filesystemChange)
        #expect(await actor.refreshAttribution.admittedTriggerSourceByWorktreeId[worktreeId] == .filesystemChange)
        #expect(await actor.refreshAttribution.admittedDemandClassByWorktreeId[worktreeId] == "background")
        #expect(await actor.refreshAttribution.admittedCadenceTierByWorktreeId[worktreeId] == "background")
        #expect(await actor.admittedDemandTierByWorktreeId[worktreeId] == .background)

        await blockingReadGate.open()
        _ = await blockingRead.value
        let completedWithoutGovernorAdvance = await admissionWaitUntil {
            await actor.lastAcceptedStatusAtByWorktreeId[worktreeId] != nil
        }
        #expect(completedWithoutGovernorAdvance)
        guard completedWithoutGovernorAdvance, let originalRequestSequence else {
            await actor.shutdown()
            return
        }
        #expect(await actor.refreshAttribution.requestSequenceByWorktreeId[worktreeId] == originalRequestSequence)
        #expect(await actor.capacityRearmedWorktreeIds.isEmpty)
        #expect(await admissionWaitUntil { await actor.worktreeTasks.isEmpty })

        let sleepGeneration = clock.scheduledSleepGeneration
        await actor.enqueueImmediateRefresh(
            admissionFilesystemChangeset(worktreeId: worktreeId, rootPath: rootPath, batchSeq: 2),
            triggerSource: .filesystemChange
        )
        #expect(await actor.refreshAttribution.requestSequenceByWorktreeId[worktreeId] == originalRequestSequence)
        await clock.waitForPendingSleepCount(atLeast: 1, fromGeneration: sleepGeneration)
        clock.advance(by: policy.minimumAutomaticStartInterval - .milliseconds(1))
        #expect(await actor.refreshAttribution.requestSequenceByWorktreeId[worktreeId] == originalRequestSequence)
        clock.advance(by: .milliseconds(1))
        #expect(
            await admissionWaitUntil {
                await actor.refreshAttribution.requestSequenceByWorktreeId[worktreeId]
                    == originalRequestSequence + 1
            }
        )
        #expect(await admissionWaitUntil { await actor.worktreeTasks.isEmpty })

        await actor.shutdown()
    }

    @Test("same-root contention does not pause admission for a distinct active root")
    func sameRootContentionDoesNotPauseDistinctActiveRoot() async {
        let physicalGate = AgentStudioGitStatusPhysicalGate(maxActiveReadCount: 4)
        let blockingReadStarted = AdmissionAsyncReceipt()
        let blockingReadGate = AdmissionAsyncGate()
        let activeReadGate = AdmissionAsyncGate()
        let statusSnapshot = admissionCompleteStatusSnapshot()
        let contendedWorktreeId = UUIDv7.generate()
        let activeWorktreeId = UUIDv7.generate()
        let contendedRootPath = URL(fileURLWithPath: "/tmp/admission-same-root-\(contendedWorktreeId)")
        let activeRootPath = URL(fileURLWithPath: "/tmp/admission-distinct-active-\(activeWorktreeId)")
        let blockingProvider = AgentStudioGitWorkingTreeStatusProvider(
            slowObservationScheduler: PassiveAdmissionGitStatusSlowObservationScheduler(),
            physicalGate: physicalGate
        ) { _, _ in
            await blockingReadStarted.signal()
            await blockingReadGate.waitUntilOpen()
            return statusSnapshot
        }
        let projectorStatusCalls = StatusCallRecorder()
        let projectorProvider = AgentStudioGitWorkingTreeStatusProvider(
            slowObservationScheduler: PassiveAdmissionGitStatusSlowObservationScheduler(),
            physicalGate: physicalGate
        ) { rootPath, _ in
            await projectorStatusCalls.record(rootPath)
            if rootPath == activeRootPath {
                await activeReadGate.waitUntilOpen()
            }
            return statusSnapshot
        }
        let pathProbe = RootPathProbeRecorder()
        let actor = GitWorkingDirectoryProjector(
            bus: EventBus<RuntimeEnvelope>(),
            gitWorkingTreeProvider: projectorProvider,
            coalescingWindow: .zero,
            refreshPolicy: AppPolicies.GitRefresh.Policy(
                maxConcurrentStatusComputes: 2,
                activePaneMaxConcurrent: 1,
                openPaneMaxConcurrent: 1
            ),
            pathExistenceProbe: { rootPath in
                pathProbe.recordExistence(rootPath)
            }
        )

        let blockingRead = Task {
            await blockingProvider.statusResult(for: contendedRootPath)
        }
        await blockingReadStarted.wait()

        await actor.setActivity(worktreeId: contendedWorktreeId, isActiveInApp: true)
        await actor.assertTopology(
            admissionTopologyAssertion(
                generation: 1,
                rootPathsByWorktreeId: [contendedWorktreeId: contendedRootPath]
            )
        )
        #expect(
            await admissionWaitUntil {
                await actor.capacityRetryWorktreeIds == Set([contendedWorktreeId])
            }
        )
        #expect(
            await actor.capacityRetryReasonByWorktreeId[contendedWorktreeId]
                == .readAlreadyInFlight
        )

        await actor.setActivePaneWorktree(worktreeId: activeWorktreeId)
        await actor.assertTopology(
            admissionTopologyAssertion(
                generation: 2,
                rootPathsByWorktreeId: [
                    contendedWorktreeId: contendedRootPath,
                    activeWorktreeId: activeRootPath,
                ]
            )
        )

        let activeStatusRootPaths = await projectorStatusCalls.waitForCallCount(1)
        #expect(activeStatusRootPaths == [activeRootPath])
        #expect(await actor.capacityRetryWorktreeIds == Set([contendedWorktreeId]))
        #expect(pathProbe.recordedRootPaths.filter { $0 == contendedRootPath }.count == 1)

        await activeReadGate.open()
        await blockingReadGate.open()
        _ = await blockingRead.value
        #expect(
            await admissionWaitUntil {
                await actor.lastAcceptedStatusAtByWorktreeId.count == 2
            }
        )
        #expect(await admissionWaitUntil { await actor.worktreeTasks.isEmpty })
        let recordedStatusRootPaths = await projectorStatusCalls.rootPaths
        #expect(Set(recordedStatusRootPaths) == Set([contendedRootPath, activeRootPath]))
        #expect(pathProbe.recordedRootPaths.count == 2)
        #expect(Set(pathProbe.recordedRootPaths) == Set([contendedRootPath, activeRootPath]))

        await actor.shutdown()
    }

    @Test("removing the final capacity pause owner re-admits unrelated pending work")
    func removingFinalCapacityPauseOwnerReadmitsPendingWork() async {
        let physicalGate = AgentStudioGitStatusPhysicalGate(maxActiveReadCount: 1)
        let blockingReadStarted = AdmissionAsyncReceipt()
        let blockingReadGate = AdmissionAsyncGate()
        let statusSnapshot = admissionCompleteStatusSnapshot()
        let capacityWorktreeId = UUIDv7.generate()
        let pendingWorktreeId = UUIDv7.generate()
        let blockerRootPath = URL(fileURLWithPath: "/tmp/admission-capacity-owner-blocker-\(UUIDv7.generate())")
        let capacityRootPath = URL(fileURLWithPath: "/tmp/admission-capacity-owner-\(capacityWorktreeId)")
        let pendingRootPath = URL(fileURLWithPath: "/tmp/admission-capacity-pending-\(pendingWorktreeId)")
        let blockingProvider = AgentStudioGitWorkingTreeStatusProvider(
            slowObservationScheduler: PassiveAdmissionGitStatusSlowObservationScheduler(),
            physicalGate: physicalGate
        ) { _, _ in
            await blockingReadStarted.signal()
            await blockingReadGate.waitUntilOpen()
            return statusSnapshot
        }
        let projectorStatusCalls = StatusCallRecorder()
        let projectorProvider = AgentStudioGitWorkingTreeStatusProvider(
            slowObservationScheduler: PassiveAdmissionGitStatusSlowObservationScheduler(),
            physicalGate: physicalGate
        ) { rootPath, _ in
            await projectorStatusCalls.record(rootPath)
            return statusSnapshot
        }
        let pathProbe = RootPathProbeRecorder()
        let actor = GitWorkingDirectoryProjector(
            bus: EventBus<RuntimeEnvelope>(),
            gitWorkingTreeProvider: projectorProvider,
            coalescingWindow: .zero,
            refreshPolicy: AppPolicies.GitRefresh.Policy(
                maxConcurrentStatusComputes: 1,
                activePaneMaxConcurrent: 1,
                openPaneMaxConcurrent: 1
            ),
            pathExistenceProbe: { rootPath in
                pathProbe.recordExistence(rootPath)
            }
        )

        let blockingRead = Task {
            await blockingProvider.statusResult(for: blockerRootPath)
        }
        await blockingReadStarted.wait()

        await actor.setActivity(worktreeId: capacityWorktreeId, isActiveInApp: true)
        await actor.assertTopology(
            admissionTopologyAssertion(
                generation: 1,
                rootPathsByWorktreeId: [capacityWorktreeId: capacityRootPath]
            )
        )
        #expect(
            await admissionWaitUntil {
                await actor.capacityRetryWorktreeIds == Set([capacityWorktreeId])
            }
        )
        let capacityRetryReason = await actor.capacityRetryReasonByWorktreeId[capacityWorktreeId]
        #expect(capacityRetryReason == .readCapacityExceeded)

        await actor.setActivePaneWorktree(worktreeId: pendingWorktreeId)
        await actor.assertTopology(
            admissionTopologyAssertion(
                generation: 2,
                rootPathsByWorktreeId: [
                    capacityWorktreeId: capacityRootPath,
                    pendingWorktreeId: pendingRootPath,
                ]
            )
        )
        await actor.enqueueImmediateRefreshIfRegistered(
            worktreeId: pendingWorktreeId,
            isExplicit: true
        )
        #expect(await actor.pendingByWorktreeId[pendingWorktreeId] != nil)

        await actor.assertTopology(
            admissionTopologyAssertion(
                generation: 3,
                rootPathsByWorktreeId: [pendingWorktreeId: pendingRootPath]
            )
        )

        #expect(
            await admissionWaitUntil {
                await actor.capacityRetryWorktreeIds == Set([pendingWorktreeId])
            }
        )
        let pendingRetryReason = await actor.capacityRetryReasonByWorktreeId[pendingWorktreeId]
        #expect(pendingRetryReason == .readCapacityExceeded)
        #expect(await projectorStatusCalls.rootPaths.isEmpty)
        #expect(pathProbe.recordedRootPaths.count == 2)
        #expect(Set(pathProbe.recordedRootPaths) == Set([capacityRootPath, pendingRootPath]))

        await blockingReadGate.open()
        _ = await blockingRead.value
        let pendingStatusRootPaths = await projectorStatusCalls.waitForCallCount(1)
        #expect(pendingStatusRootPaths == [pendingRootPath])
        #expect(await admissionWaitUntil { await actor.worktreeTasks.isEmpty })
        #expect(await actor.capacityRetryWorktreeIds.isEmpty)
        #expect(await actor.capacityRetryReasonByWorktreeId.isEmpty)
        #expect(pathProbe.recordedRootPaths.filter { $0 == pendingRootPath }.count == 1)

        await actor.shutdown()
    }

    @Test("shared physical capacity rejection retains validation and pauses later admission")
    func sharedPhysicalCapacityRejectionRetainsValidationAndPausesLaterAdmission() async {
        let physicalGate = AgentStudioGitStatusPhysicalGate(maxActiveReadCount: 1)
        let blockingReadStarted = AdmissionAsyncReceipt()
        let blockingReadGate = AdmissionAsyncGate()
        let statusSnapshot = admissionCompleteStatusSnapshot()
        let blockingProvider = AgentStudioGitWorkingTreeStatusProvider(
            slowObservationScheduler: PassiveAdmissionGitStatusSlowObservationScheduler(),
            physicalGate: physicalGate
        ) { _, _ in
            await blockingReadStarted.signal()
            await blockingReadGate.waitUntilOpen()
            return statusSnapshot
        }
        let projectorProvider = AgentStudioGitWorkingTreeStatusProvider(
            slowObservationScheduler: PassiveAdmissionGitStatusSlowObservationScheduler(),
            physicalGate: physicalGate
        ) { _, _ in
            statusSnapshot
        }
        let pathProbe = RootPathProbeRecorder()
        let actor = GitWorkingDirectoryProjector(
            bus: EventBus<RuntimeEnvelope>(),
            gitWorkingTreeProvider: projectorProvider,
            coalescingWindow: .zero,
            refreshPolicy: AppPolicies.GitRefresh.Policy(
                maxConcurrentStatusComputes: 1,
                openPaneMaxConcurrent: 1
            ),
            pathExistenceProbe: { rootPath in
                pathProbe.recordExistence(rootPath)
            }
        )

        let blockingRead = Task {
            await blockingProvider.statusResult(
                for: URL(fileURLWithPath: "/tmp/admission-capacity-blocker-\(UUIDv7.generate())")
            )
        }
        await blockingReadStarted.wait()

        let worktreeIds = [UUIDv7.generate(), UUIDv7.generate()]
        let rootPaths = worktreeIds.map { worktreeId in
            URL(fileURLWithPath: "/tmp/admission-capacity-pending-\(worktreeId)")
        }
        for worktreeId in worktreeIds {
            await actor.setActivity(worktreeId: worktreeId, isActiveInApp: true)
        }
        await actor.assertTopology(
            FilesystemTopologyAssertion(
                generation: 1,
                contextsByWorktreeId: Dictionary(
                    uniqueKeysWithValues: zip(worktreeIds, rootPaths).map { worktreeId, rootPath in
                        (
                            worktreeId,
                            WorktreeFilesystemContext(repoId: worktreeId, rootPath: rootPath)
                        )
                    }
                )
            )
        )

        #expect(
            await admissionWaitUntil {
                await !actor.capacityRetryWorktreeIds.isEmpty
            }
        )
        for _ in 0..<300 {
            await Task.yield()
        }
        let firstProbedRootPath = pathProbe.recordedRootPaths.first
        #expect(pathProbe.recordedRootPaths == firstProbedRootPath.map { [$0] } ?? [])
        #expect(await actor.capacityRetryWorktreeIds.count == 1)
        #expect(await actor.validatedRootPathByWorktreeId.count == 1)

        await blockingReadGate.open()
        _ = await blockingRead.value
        #expect(
            await admissionWaitUntil {
                await actor.lastAcceptedStatusAtByWorktreeId.count == worktreeIds.count
            }
        )
        #expect(
            await admissionWaitUntil {
                await actor.worktreeTasks.isEmpty
            }
        )
        #expect(pathProbe.recordedRootPaths.count == rootPaths.count)
        #expect(Set(pathProbe.recordedRootPaths) == Set(rootPaths))
        #expect(await actor.validatedRootPathByWorktreeId.isEmpty)
        if let firstProbedRootPath {
            #expect(pathProbe.recordedRootPaths.filter { $0 == firstProbedRootPath }.count == 1)
        }

        await actor.shutdown()
    }

    @Test("root existence is probed only when pending work can consume an admission slot")
    func rootExistenceIsProbedOnlyForAdmissiblePendingWork() async {
        let statusGate = FirstStatusCallGate()
        let pathProbe = RootPathProbeRecorder()
        let provider = StubGitWorkingTreeStatusProvider { rootPath in
            await statusGate.recordAndWaitIfFirst(rootPath)
            return GitWorkingTreeStatus(
                summary: GitWorkingTreeSummary(changed: 0, staged: 0, untracked: 0),
                branch: "main",
                origin: nil
            )
        }
        let actor = GitWorkingDirectoryProjector(
            bus: EventBus<RuntimeEnvelope>(),
            gitWorkingTreeProvider: provider,
            coalescingWindow: .zero,
            refreshPolicy: AppPolicies.GitRefresh.Policy(
                maxConcurrentStatusComputes: 1,
                openPaneMaxConcurrent: 1
            ),
            pathExistenceProbe: { rootPath in
                pathProbe.recordExistence(rootPath)
            }
        )

        let worktreeIds = [UUIDv7.generate(), UUIDv7.generate()]
        let rootPaths = worktreeIds.map { worktreeId in
            URL(fileURLWithPath: "/tmp/admission-path-probe-\(worktreeId)")
        }
        for worktreeId in worktreeIds {
            await actor.setActivity(worktreeId: worktreeId, isActiveInApp: true)
        }
        await actor.assertTopology(
            FilesystemTopologyAssertion(
                generation: 1,
                contextsByWorktreeId: Dictionary(
                    uniqueKeysWithValues: zip(worktreeIds, rootPaths).map { worktreeId, rootPath in
                        (
                            worktreeId,
                            WorktreeFilesystemContext(repoId: worktreeId, rootPath: rootPath)
                        )
                    }
                )
            )
        )

        #expect(await admissionWaitUntil { await statusGate.callCount == 1 })
        let firstAdmittedRootPath = await statusGate.firstRootPath
        #expect(pathProbe.recordedRootPaths == firstAdmittedRootPath.map { [$0] } ?? [])

        await statusGate.releaseFirst()
        #expect(await admissionWaitUntil { await statusGate.callCount == 2 })
        #expect(
            await admissionWaitUntil {
                await actor.worktreeTasks.isEmpty
            }
        )
        #expect(pathProbe.recordedRootPaths.count == 2)
        #expect(Set(pathProbe.recordedRootPaths) == Set(rootPaths))

        await actor.shutdown()
    }

    @Test("inactive contraction preserves filesystem scope after visibility attribution")
    func inactiveContractionPreservesFilesystemScopeAfterVisibilityAttribution() async {
        let statusGate = FirstStatusCallGate()
        let blockingWorktreeId = UUIDv7.generate()
        let targetWorktreeId = UUIDv7.generate()
        let blockingRootPath = URL(fileURLWithPath: "/tmp/admission-required-blocker-\(blockingWorktreeId)")
        let targetRootPath = URL(fileURLWithPath: "/tmp/admission-required-intent-\(targetWorktreeId)")
        let actor = GitWorkingDirectoryProjector(
            bus: EventBus<RuntimeEnvelope>(),
            gitWorkingTreeProvider: StubGitWorkingTreeStatusProvider { rootPath in
                await statusGate.recordAndWaitIfFirst(rootPath)
                return GitWorkingTreeStatus(
                    summary: GitWorkingTreeSummary(changed: 0, staged: 0, untracked: 0),
                    branch: "main",
                    origin: nil
                )
            },
            coalescingWindow: .zero,
            refreshPolicy: AppPolicies.GitRefresh.Policy(
                maxConcurrentStatusComputes: 1,
                backgroundMaxConcurrent: 1,
                minimumAutomaticStartInterval: .zero
            ),
            pathExistenceProbe: { _ in true }
        )

        await actor.assertTopology(
            admissionTopologyAssertion(
                generation: 1,
                rootPathsByWorktreeId: [
                    blockingWorktreeId: blockingRootPath,
                    targetWorktreeId: targetRootPath,
                ]
            )
        )
        await actor.setRepositoryFactAttention(
            activePaneWorktreeId: nil,
            sidebarAttendedWorktreeIds: [],
            visibleActiveTabWorktreeIds: [],
            openWorktreeIds: [],
            warmAutomaticWorktreeIds: [blockingWorktreeId, targetWorktreeId],
            backgroundOnlyAutomaticWorktreeIds: [targetWorktreeId]
        )
        #expect(await actor.logicalDebtSnapshot().backgroundOnlyAutomaticCount == 1)
        await actor.enqueueImmediateRefresh(
            admissionFilesystemChangeset(
                worktreeId: blockingWorktreeId,
                rootPath: blockingRootPath,
                batchSeq: 1
            ),
            triggerSource: .filesystemChange
        )
        #expect(await admissionWaitUntil { await statusGate.callCount == 1 })

        await actor.enqueueImmediateRefresh(
            admissionFilesystemChangeset(
                worktreeId: targetWorktreeId,
                rootPath: targetRootPath,
                batchSeq: 41
            ),
            triggerSource: .filesystemChange
        )
        await actor.enqueueImmediateRefreshIfRegistered(
            worktreeId: targetWorktreeId,
            triggerSource: .visibilityChange
        )

        #expect(await actor.pendingByWorktreeId[targetWorktreeId]?.paths == ["tracked-41.txt"])
        #expect(
            await actor.refreshAttribution.triggerSourceByWorktreeId[targetWorktreeId]
                == .visibilityChange
        )
        #expect(await actor.hasRequiredIntent(worktreeId: targetWorktreeId))

        await actor.setRepositoryFactAttention(
            activePaneWorktreeId: nil,
            sidebarAttendedWorktreeIds: [],
            visibleActiveTabWorktreeIds: [],
            openWorktreeIds: [],
            warmAutomaticWorktreeIds: [blockingWorktreeId],
            backgroundOnlyAutomaticWorktreeIds: []
        )

        #expect(await actor.pendingByWorktreeId[targetWorktreeId]?.paths == ["tracked-41.txt"])
        #expect(await actor.hasRequiredIntent(worktreeId: targetWorktreeId))
        #expect(await actor.automaticRefreshDeadlineByWorktreeId[targetWorktreeId] == nil)

        await statusGate.releaseFirst()
        #expect(await admissionWaitUntil { await statusGate.callCount == 2 })
        #expect(await admissionWaitUntil { await actor.worktreeTasks.isEmpty })
        #expect(await actor.pendingByWorktreeId[targetWorktreeId] == nil)
        #expect(await !actor.hasRequiredIntent(worktreeId: targetWorktreeId))
        #expect(await actor.automaticRefreshDeadlineByWorktreeId[targetWorktreeId] == nil)

        await actor.shutdown()
    }

    @Test("inactive contraction drops an automatic follower after required work settles")
    func inactiveContractionDropsAutomaticFollowerAfterRequiredWorkSettles() async {
        let statusGate = FirstStatusCallGate()
        let worktreeId = UUIDv7.generate()
        let rootPath = URL(fileURLWithPath: "/tmp/admission-required-active-\(worktreeId)")
        let actor = GitWorkingDirectoryProjector(
            bus: EventBus<RuntimeEnvelope>(),
            gitWorkingTreeProvider: StubGitWorkingTreeStatusProvider { rootPath in
                await statusGate.recordAndWaitIfFirst(rootPath)
                return GitWorkingTreeStatus(
                    summary: GitWorkingTreeSummary(changed: 0, staged: 0, untracked: 0),
                    branch: "main",
                    origin: nil
                )
            },
            coalescingWindow: .zero,
            pathExistenceProbe: { _ in true }
        )

        await actor.assertTopology(
            admissionTopologyAssertion(
                generation: 1,
                rootPathsByWorktreeId: [worktreeId: rootPath]
            )
        )
        await actor.setAutomaticEligibleWorktrees([worktreeId])
        await actor.enqueueImmediateRefresh(
            admissionFilesystemChangeset(
                worktreeId: worktreeId,
                rootPath: rootPath,
                batchSeq: 99
            ),
            triggerSource: .filesystemChange
        )
        #expect(await admissionWaitUntil { await statusGate.callCount == 1 })
        #expect(
            await actor.refreshAttribution.admittedRequiredIntentGenerationByWorktreeId[worktreeId]
                != nil
        )

        await actor.enqueueImmediateRefreshIfRegistered(
            worktreeId: worktreeId,
            triggerSource: .visibilityChange
        )
        #expect(await actor.pendingByWorktreeId[worktreeId] != nil)
        #expect(
            await actor.refreshAttribution.pendingRequiredIntentGenerationByWorktreeId[worktreeId]
                == nil
        )

        await actor.setAutomaticEligibleWorktrees([])
        #expect(await actor.pendingByWorktreeId[worktreeId] != nil)

        await statusGate.releaseFirst()
        #expect(await admissionWaitUntil { await actor.worktreeTasks.isEmpty })
        let debt = await actor.logicalDebtSnapshot()
        #expect(await statusGate.callCount == 1)
        #expect(await actor.pendingByWorktreeId[worktreeId] == nil)
        #expect(await !actor.hasRequiredIntent(worktreeId: worktreeId))
        #expect(await actor.automaticRefreshDeadlineByWorktreeId[worktreeId] == nil)
        #expect(await actor.statusFailureDeadlineByWorktreeId[worktreeId] == nil)
        #expect(await actor.capacityFallbackDeadlineByWorktreeId[worktreeId] == nil)
        #expect(debt.logicalDebtCount == 0)
        #expect(debt.unclassifiedPendingCount == 0)

        await actor.shutdown()
    }

    @Test("missing selected root is quarantined without consuming the admission slot")
    func missingSelectedRootDoesNotConsumeAdmissionSlot() async {
        let bus = EventBus<RuntimeEnvelope>()
        let clock = TestPushClock()
        let missingWorktreeId = UUIDv7.generate()
        let healthyWorktreeId = UUIDv7.generate()
        let missingRootPath = URL(fileURLWithPath: "/tmp/admission-missing-\(missingWorktreeId)")
        let healthyRootPath = URL(fileURLWithPath: "/tmp/admission-healthy-\(healthyWorktreeId)")
        let pathProbe = RootPathProbeRecorder(missingRootPaths: [missingRootPath])
        let statusCalls = StatusCallRecorder()
        let provider = StubGitWorkingTreeStatusProvider { rootPath in
            await statusCalls.record(rootPath)
            return GitWorkingTreeStatus(
                summary: GitWorkingTreeSummary(changed: 0, staged: 0, untracked: 0),
                branch: "main",
                origin: nil
            )
        }
        let policy = AppPolicies.GitRefresh.Policy(
            activePaneCadence: .milliseconds(25),
            visibleSidebarCadence: .milliseconds(50),
            openPaneCadence: .milliseconds(75),
            backgroundCadence: .milliseconds(100),
            backgroundStripeCount: 1,
            maxConcurrentStatusComputes: 1,
            backgroundMaxConcurrent: 1
        )
        let actor = GitWorkingDirectoryProjector(
            bus: bus,
            gitWorkingTreeProvider: provider,
            coalescingWindow: .zero,
            sleepClock: clock,
            refreshPolicy: policy,
            pathExistenceProbe: { rootPath in
                pathProbe.recordExistence(rootPath)
            }
        )
        await actor.start()

        let registrationTimestamp = ContinuousClock().now
        await bus.post(
            admissionRegistrationEnvelope(
                seq: 1,
                timestamp: registrationTimestamp,
                worktreeId: missingWorktreeId,
                rootPath: missingRootPath
            )
        )
        await bus.post(
            admissionRegistrationEnvelope(
                seq: 2,
                timestamp: registrationTimestamp.advanced(by: .milliseconds(1)),
                worktreeId: healthyWorktreeId,
                rootPath: healthyRootPath
            )
        )

        #expect(
            await admissionWaitUntil {
                await actor.pendingByWorktreeId.count == 2
            }
        )
        await clock.waitForPendingSleepCount(atLeast: 1)
        clock.advance(by: policy.backgroundCadence)

        #expect(await admissionWaitUntil { await statusCalls.rootPaths == [healthyRootPath] })
        #expect(await actor.quarantinedWorktreeIds == Set([missingWorktreeId]))
        #expect(
            await actor.automaticRefreshDeadlineByWorktreeId[missingWorktreeId]
                == policy.backgroundCadence + policy.backgroundCadence
        )
        #expect(pathProbe.recordedRootPaths == [missingRootPath, healthyRootPath])

        await actor.shutdown()
    }
}

private final class RootPathProbeRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private let missingRootPaths: Set<URL>
    private var rootPaths: [URL] = []

    init(missingRootPaths: Set<URL> = []) {
        self.missingRootPaths = missingRootPaths
    }

    var recordedRootPaths: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return rootPaths
    }

    func recordExistence(_ rootPath: URL) -> Bool {
        lock.lock()
        rootPaths.append(rootPath)
        lock.unlock()
        return !missingRootPaths.contains(rootPath)
    }
}

private actor StatusCallRecorder {
    private(set) var rootPaths: [URL] = []
    private var callCountWaiter:
        (
            minimumCallCount: Int,
            continuation: CheckedContinuation<[URL], Never>
        )?

    func record(_ rootPath: URL) {
        rootPaths.append(rootPath)
        guard let callCountWaiter, rootPaths.count >= callCountWaiter.minimumCallCount else {
            return
        }
        self.callCountWaiter = nil
        callCountWaiter.continuation.resume(returning: rootPaths)
    }

    func waitForCallCount(_ minimumCallCount: Int) async -> [URL] {
        guard rootPaths.count < minimumCallCount else { return rootPaths }
        return await withCheckedContinuation { continuation in
            precondition(callCountWaiter == nil)
            callCountWaiter = (minimumCallCount, continuation)
        }
    }
}

private actor FirstStatusCallGate {
    private var rootPaths: [URL] = []
    private var firstCallWaiter: CheckedContinuation<Void, Never>?
    private var isFirstCallReleased = false

    var callCount: Int { rootPaths.count }
    var firstRootPath: URL? { rootPaths.first }

    func recordAndWaitIfFirst(_ rootPath: URL) async {
        rootPaths.append(rootPath)
        guard rootPaths.count == 1 else { return }
        await withCheckedContinuation { continuation in
            if isFirstCallReleased {
                continuation.resume()
            } else {
                firstCallWaiter = continuation
            }
        }
    }

    func releaseFirst() {
        isFirstCallReleased = true
        firstCallWaiter?.resume()
        firstCallWaiter = nil
    }
}

private actor AdmissionAsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func waitUntilOpen() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let pendingWaiters = waiters
        waiters.removeAll(keepingCapacity: false)
        for waiter in pendingWaiters {
            waiter.resume()
        }
    }
}

private actor AdmissionAsyncReceipt {
    private var isSignalled = false
    private var waiter: CheckedContinuation<Void, Never>?

    func signal() {
        isSignalled = true
        waiter?.resume()
        waiter = nil
    }

    func wait() async {
        guard !isSignalled else { return }
        await withCheckedContinuation { continuation in
            waiter = continuation
        }
    }
}

private struct PassiveAdmissionGitStatusSlowObservationScheduler: AgentStudioGitStatusSlowObservationScheduler {
    func scheduleObservation(
        after _: Duration,
        _: @escaping @Sendable () -> Void
    ) -> AgentStudioGitScheduledSlowObservation {
        AgentStudioGitScheduledSlowObservation {}
    }
}

private func admissionWaitUntil(
    maxTurns: Int = 20_000,
    _ condition: @escaping () async -> Bool
) async -> Bool {
    for _ in 0..<maxTurns {
        if await condition() { return true }
        await Task.yield()
    }
    return await condition()
}

private func admissionRegistrationEnvelope(
    seq: UInt64,
    timestamp: ContinuousClock.Instant,
    worktreeId: UUID,
    rootPath: URL
) -> RuntimeEnvelope {
    .system(
        SystemEnvelope(
            source: .builtin(.filesystemWatcher),
            seq: seq,
            timestamp: timestamp,
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

private func admissionTopologyAssertion(
    generation: UInt64,
    rootPathsByWorktreeId: [UUID: URL]
) -> FilesystemTopologyAssertion {
    FilesystemTopologyAssertion(
        generation: generation,
        contextsByWorktreeId: Dictionary(
            uniqueKeysWithValues: rootPathsByWorktreeId.map { worktreeId, rootPath in
                (
                    worktreeId,
                    WorktreeFilesystemContext(repoId: worktreeId, rootPath: rootPath)
                )
            }
        )
    )
}

private func admissionFilesystemChangeset(
    worktreeId: UUID,
    rootPath: URL,
    batchSeq: UInt64
) -> FileChangeset {
    FileChangeset(
        worktreeId: worktreeId,
        rootPath: rootPath,
        paths: ["tracked-\(batchSeq).txt"],
        timestamp: ContinuousClock().now,
        batchSeq: batchSeq
    )
}

private func admissionCompleteStatusSnapshot() -> AgentStudioGit.GitCompleteStatusSnapshot {
    let rootPath = URL(fileURLWithPath: "/tmp/admission-status-snapshot")
    return AgentStudioGit.GitCompleteStatusSnapshot(
        facts: AgentStudioGit.GitStatusFactsSnapshot(
            repositoryRoot: rootPath,
            worktreePath: rootPath,
            generatedAtUnixMilliseconds: 1,
            head: AgentStudioGit.GitHeadSnapshot(kind: .branch, oid: "abc123", shortName: "main"),
            originResolution: .confirmedAbsent,
            summary: AgentStudioGit.GitStatusFactSummary(
                changedFileCount: 0,
                stagedFileCount: 0,
                unstagedFileCount: 0,
                untrackedFileCount: 0,
                ignoredFileCount: 0,
                aheadCount: 0,
                behindCount: 0,
                hasUpstream: false
            ),
            entries: []
        ),
        lineCountDetail: AgentStudioGit.GitStatusLineCountDetail(
            repositoryRoot: rootPath,
            worktreePath: rootPath,
            generatedAtUnixMilliseconds: 1,
            linesAdded: 0,
            linesDeleted: 0
        )
    )
}
