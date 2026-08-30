import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioRepoExplorer

private final class RepoExplorerActivityExecutionRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedExecutionCount = 0
    private var storedDeltaExecutionCount = 0

    var executionCount: Int {
        lock.withLock { storedExecutionCount }
    }

    var deltaExecutionCount: Int {
        lock.withLock { storedDeltaExecutionCount }
    }

    func recordExecution(_ work: RepoExplorerProjectionWork) {
        lock.withLock {
            storedExecutionCount += 1
            if case .delta = work {
                storedDeltaExecutionCount += 1
            }
        }
    }
}

@MainActor
private final class RepoExplorerActivityReferenceDate {
    var now: Date

    init(now: Date) {
        self.now = now
    }
}

@MainActor
private final class RepoExplorerLocalActivityProjectionFixture {
    let store: WorkspaceStore
    let repo: Repo
    let worktree: Worktree
    let repositoryStableKey: String
    let worktreeStableKey: String
    let unrelatedRepo: Repo
    let unrelatedRepositoryStableKey: String
    let referenceDate: Date
    let inactiveActivity: RepositoryLocalActivity
    let unrelatedInactiveActivity: RepositoryLocalActivity
    let capture: RepoExplorerProjectionInputCapture
    let executionRecorder: RepoExplorerActivityExecutionRecorder
    let referenceDateClock: RepoExplorerActivityReferenceDate
    let adapter: RepoExplorerProjectionAdapter
    let host: RepoExplorerMaterializationHost

    init(
        atoms: CoreAtoms,
        publishesAuthoritativeActivity: Bool = true,
        groupingMode: RepoExplorerGroupingMode = .repo
    ) throws {
        let fixedReferenceDate = Date(timeIntervalSince1970: 10_000_000)
        referenceDate = fixedReferenceDate
        referenceDateClock = RepoExplorerActivityReferenceDate(now: fixedReferenceDate)
        store = WorkspaceStore(
            catalogAtom: atoms.workspaceRepositoryTopology,
            graphAtom: atoms.workspacePane,
            interactionAtom: atoms.workspaceTabLayout
        )
        repo = store.addRepo(at: URL(filePath: "/tmp/repo-explorer-local-activity"))
        worktree = try #require(repo.worktrees.first)
        repositoryStableKey = try #require(
            store.repositoryTopologyAtom.repositoryStableKey(for: repo.id)
        )
        worktreeStableKey = try #require(
            store.repositoryTopologyAtom.worktreeStableKey(for: worktree.id)
        )
        unrelatedRepo = store.addRepo(
            at: URL(filePath: "/tmp/repo-explorer-unrelated-local-activity")
        )
        unrelatedRepositoryStableKey = try #require(
            store.repositoryTopologyAtom.repositoryStableKey(for: unrelatedRepo.id)
        )
        atoms.repoCache.setRepoEnrichment(
            .resolvedLocal(
                repoId: repo.id,
                identity: RemoteIdentityNormalizer.localIdentity(repoName: repo.name),
                updatedAt: fixedReferenceDate
            )
        )
        atoms.repoCache.setRepoEnrichment(
            .resolvedLocal(
                repoId: unrelatedRepo.id,
                identity: RemoteIdentityNormalizer.localIdentity(repoName: unrelatedRepo.name),
                updatedAt: fixedReferenceDate
            )
        )
        inactiveActivity = try Self.inactiveActivity(
            repositoryStableKey: repositoryStableKey,
            referenceDate: fixedReferenceDate
        )
        unrelatedInactiveActivity = try Self.inactiveActivity(
            repositoryStableKey: unrelatedRepositoryStableKey,
            referenceDate: fixedReferenceDate
        )
        if publishesAuthoritativeActivity {
            atoms.repositoryLocalActivity.publishAuthoritative(
                RepositoryLocalActivitySnapshot(
                    activityByRepositoryStableKey: [
                        repositoryStableKey: inactiveActivity,
                        unrelatedRepositoryStableKey: unrelatedInactiveActivity,
                    ],
                    cursorByVolumeIdentifier: [:]
                )
            )
        }
        let preferences = RepoExplorerSidebarPrefsAtom()
        preferences.setGroupingMode(groupingMode)
        capture = RepoExplorerProjectionInputCapture(
            store: store,
            preferences: preferences,
            repoCache: atoms.repoCache,
            sidebarState: atoms.workspaceSidebarState,
            sidebarCache: atoms.sidebarCache,
            coreAtoms: atoms,
            bridgeAttendanceSnapshot: { _ in nil },
            latestPaneMessageSnapshot: { _ in nil }
        )
        executionRecorder = RepoExplorerActivityExecutionRecorder()
        adapter = RepoExplorerProjectionAdapter(
            inputCapture: capture,
            recencyNow: { [referenceDateClock] in referenceDateClock.now },
            recencyDelay: AsyncDelay { _ in throw CancellationError() },
            project: { [executionRecorder] work throws(CancellationError) in
                executionRecorder.recordExecution(work)
                do {
                    return try RepoExplorerProjectionWorker.project(work)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    preconditionFailure("Unexpected projection failure: \(error)")
                }
            }
        )
        host = registerProjectionTestMaterializationHost(adapter: adapter)
    }

    func publishActivity(atoms: CoreAtoms, activity: RepositoryLocalActivity) {
        publishActivities(
            atoms: atoms,
            activityByStableKey: [
                repositoryStableKey: activity,
                unrelatedRepositoryStableKey: unrelatedInactiveActivity,
            ]
        )
    }

    func publishActivities(
        atoms: CoreAtoms,
        activityByStableKey: [String: RepositoryLocalActivity]
    ) {
        atoms.repositoryLocalActivity.publishAuthoritative(
            RepositoryLocalActivitySnapshot(
                activityByRepositoryStableKey: activityByStableKey,
                cursorByVolumeIdentifier: [:]
            )
        )
    }

    func startAndWait(for disposition: RepositoryActivityDisposition) async {
        adapter.updateDemand(isVisible: true, query: "")
        for _ in 0..<2000
        where adapter.publishedResult?.repositoryActivityDispositionByRepoId[repo.id]
            != disposition
        {
            await Task.yield()
        }
    }

    func reassociateRepository(to relocatedPath: URL) -> RepositoryReassociationResult {
        store.reassociateRepo(
            repo.id,
            to: relocatedPath,
            discoveredWorktrees: [
                Worktree(
                    repoId: repo.id,
                    name: relocatedPath.lastPathComponent,
                    path: relocatedPath,
                    isMainWorktree: true
                )
            ]
        )
    }

    func waitForStableKey(
        _ stableKey: String,
        disposition: RepositoryActivityDisposition
    ) async {
        for _ in 0..<2000
        where adapter.cachedProjectionRequest?.snapshot.repos.first(where: {
            $0.id == repo.id
        })?.stableKey != stableKey
            || adapter.publishedResult?.repositoryActivityDispositionByRepoId[repo.id]
                != disposition
        {
            await Task.yield()
        }
    }

    func observesActivity(stableKey: String) -> Bool {
        adapter.observationTokens.contains(
            .repositoryActivity(repositoryID: repo.id, stableKey: stableKey)
        )
    }

    func warmActivity(lastQualifyingActivityAt: Date) throws -> RepositoryLocalActivity {
        try warmActivity(
            repositoryStableKey: repositoryStableKey,
            lastQualifyingActivityAt: lastQualifyingActivityAt
        )
    }

    func warmActivity(
        repositoryStableKey: String,
        lastQualifyingActivityAt: Date
    ) throws -> RepositoryLocalActivity {
        try RepositoryLocalActivity(
            repositoryStableKey: repositoryStableKey,
            lastQualifyingActivityAt: lastQualifyingActivityAt,
            continuousCoverageStartedAt: inactiveActivity.continuousCoverageStartedAt,
            updatedAt: referenceDate,
            ownedPromotionAttemptID: nil,
            ownedPromotionStartedAt: nil,
            ownedPromotionUnsettled: false
        )
    }

    func stop() {
        host.detach()
        adapter.stop()
    }

    private static func inactiveActivity(
        repositoryStableKey: String,
        referenceDate: Date
    ) throws -> RepositoryLocalActivity {
        try RepositoryLocalActivity(
            repositoryStableKey: repositoryStableKey,
            lastQualifyingActivityAt: nil,
            continuousCoverageStartedAt: referenceDate.addingTimeInterval(
                -AppPolicies.EntityRecency.applicationActivityHorizon - 1
            ),
            updatedAt: referenceDate,
            ownedPromotionAttemptID: nil,
            ownedPromotionStartedAt: nil,
            ownedPromotionUnsettled: false
        )
    }

    func inactiveActivity(repositoryStableKey: String) throws -> RepositoryLocalActivity {
        try Self.inactiveActivity(
            repositoryStableKey: repositoryStableKey,
            referenceDate: referenceDate
        )
    }
}

extension RepoExplorerProjectionDemandTests {
    @MainActor
    @Test(
        "non-repository grouping rejects repository activity and hydration before capture",
        arguments: [RepoExplorerGroupingMode.pane, .tab]
    )
    func nonRepositoryGroupingRejectsRepositoryActivityBeforeCapture(
        groupingMode: RepoExplorerGroupingMode
    ) async throws {
        try await withAsyncTestCoreAtoms { atoms in
            let fixture = try RepoExplorerLocalActivityProjectionFixture(
                atoms: atoms,
                publishesAuthoritativeActivity: false,
                groupingMode: groupingMode
            )
            defer { fixture.stop() }

            fixture.adapter.updateDemand(isVisible: true, query: "")
            for _ in 0..<2000
            where fixture.adapter.publishedResult?.snapshot.groupingMode != groupingMode
                || fixture.adapter.materializedProjection?.hasUnsettledProjectionTasks != false
            {
                await Task.yield()
            }
            let fullCaptureCount = fixture.capture.fullCaptureCount
            let scopedCaptureCount = fixture.capture.scopedCaptureCount
            let executionCount = fixture.executionRecorder.executionCount
            let publishedRevision = fixture.adapter.publishedRevision

            fixture.publishActivity(atoms: atoms, activity: fixture.inactiveActivity)
            for _ in 0..<200 { await Task.yield() }
            let warmActivity = try fixture.warmActivity(
                lastQualifyingActivityAt: fixture.referenceDate.addingTimeInterval(-100)
            )
            fixture.publishActivity(atoms: atoms, activity: warmActivity)
            for _ in 0..<200 { await Task.yield() }

            #expect(fixture.capture.fullCaptureCount == fullCaptureCount)
            #expect(fixture.capture.scopedCaptureCount == scopedCaptureCount)
            #expect(fixture.executionRecorder.executionCount == executionCount)
            #expect(fixture.adapter.publishedRevision == publishedRevision)
            #expect(fixture.adapter.cachedProjectionRequest?.repositoryLocalActivityByStableKey.isEmpty == true)
            #expect(
                fixture.adapter.publishedResult?.repositoryActivityTransitionAtByRepoId.isEmpty == true
            )
            #expect(fixture.adapter.recencyDeadlineTask == nil)
            #expect(!fixture.adapter.observationTokens.contains(.activityHydration))
            #expect(
                !fixture.adapter.observationTokens.contains {
                    if case .repositoryActivity = $0 { return true }
                    return false
                }
            )
        }
    }

    @MainActor
    @Test("repository-local activity captures one repository delta")
    func repositoryLocalActivityCapturesOneRepositoryDelta() async throws {
        try await withAsyncTestCoreAtoms { atoms in
            let fixture = try RepoExplorerLocalActivityProjectionFixture(atoms: atoms)
            defer { fixture.stop() }
            await fixture.startAndWait(for: .locallyInactive)
            let fullCaptureCount = fixture.capture.fullCaptureCount
            let scopedCaptureCount = fixture.capture.scopedCaptureCount
            let deltaExecutionCount = fixture.executionRecorder.deltaExecutionCount
            let unrelatedRequestActivity = fixture.adapter.cachedProjectionRequest?
                .repositoryLocalActivityByStableKey[fixture.unrelatedRepositoryStableKey]
            let unrelatedDisposition = fixture.adapter.publishedResult?
                .repositoryActivityDispositionByRepoId[fixture.unrelatedRepo.id]
            let unrelatedRows = fixture.adapter.publishedResult?.materializationSnapshot
                .rowIDsByRepoID[fixture.unrelatedRepo.id, default: []]
                .compactMap { fixture.adapter.publishedResult?.materializationSnapshot.row(id: $0) }
            let warmActivity = try fixture.warmActivity(
                lastQualifyingActivityAt: fixture.referenceDate.addingTimeInterval(-100)
            )

            fixture.publishActivity(atoms: atoms, activity: warmActivity)
            for _ in 0..<2000
            where fixture.adapter.publishedResult?.repositoryActivityDispositionByRepoId[fixture.repo.id]
                != .warm
            {
                await Task.yield()
            }

            #expect(fixture.capture.fullCaptureCount == fullCaptureCount)
            #expect(fixture.capture.scopedCaptureCount == scopedCaptureCount + 1)
            #expect(fixture.executionRecorder.deltaExecutionCount == deltaExecutionCount + 1)
            #expect(
                fixture.adapter.cachedProjectionRequest?
                    .repositoryLocalActivityByStableKey[fixture.repositoryStableKey] == warmActivity
            )
            #expect(
                fixture.adapter.publishedResult?.materializationSnapshot
                    .groupHeader(repoID: fixture.repo.id)?.repositoryActivityDisposition == .warm
            )
            #expect(
                fixture.adapter.cachedProjectionRequest?
                    .repositoryLocalActivityByStableKey[fixture.unrelatedRepositoryStableKey]
                    == unrelatedRequestActivity
            )
            #expect(
                fixture.adapter.publishedResult?
                    .repositoryActivityDispositionByRepoId[fixture.unrelatedRepo.id]
                    == unrelatedDisposition
            )
            #expect(
                fixture.adapter.publishedResult?.materializationSnapshot
                    .rowIDsByRepoID[fixture.unrelatedRepo.id, default: []]
                    .compactMap {
                        fixture.adapter.publishedResult?.materializationSnapshot.row(id: $0)
                    } == unrelatedRows
            )
        }
    }

    @MainActor
    @Test("repository reassociation retargets activity facts, deadline, and observation")
    func repositoryReassociationRetargetsActivityIdentity() async throws {
        try await withAsyncTestCoreAtoms { atoms in
            let fixture = try RepoExplorerLocalActivityProjectionFixture(atoms: atoms)
            defer { fixture.stop() }
            await fixture.startAndWait(for: .locallyInactive)

            let relocatedPath = URL(filePath: "/tmp/repo-explorer-relocated-local-activity")
            let relocatedStableKey = StableKey.fromPath(relocatedPath)
            let relocatedLastActivityAt = fixture.referenceDate.addingTimeInterval(-100)
            let relocatedWarmActivity = try fixture.warmActivity(
                repositoryStableKey: relocatedStableKey,
                lastQualifyingActivityAt: relocatedLastActivityAt
            )
            fixture.publishActivities(
                atoms: atoms,
                activityByStableKey: [
                    fixture.repositoryStableKey: fixture.inactiveActivity,
                    relocatedStableKey: relocatedWarmActivity,
                    fixture.unrelatedRepositoryStableKey: fixture.unrelatedInactiveActivity,
                ]
            )
            for _ in 0..<200 { await Task.yield() }
            let fullCaptureCount = fixture.capture.fullCaptureCount
            let reassociationReferenceDate = fixture.referenceDate.addingTimeInterval(1000)
            fixture.referenceDateClock.now = reassociationReferenceDate
            let reassociationResult = fixture.reassociateRepository(to: relocatedPath)
            guard case .accepted = reassociationResult else {
                Issue.record("expected repository reassociation to be accepted")
                return
            }

            await fixture.waitForStableKey(relocatedStableKey, disposition: .warm)

            #expect(fixture.capture.fullCaptureCount == fullCaptureCount)
            let expectedExpiration = relocatedLastActivityAt.addingTimeInterval(
                AppPolicies.EntityRecency.applicationActivityHorizon
            )
            let expectedTransition = Date(
                timeIntervalSinceReferenceDate: expectedExpiration.timeIntervalSinceReferenceDate.nextUp
            )
            #expect(
                fixture.adapter.cachedProjectionRequest?
                    .repositoryLocalActivityByStableKey[fixture.repositoryStableKey] == nil
            )
            #expect(
                fixture.adapter.cachedProjectionRequest?
                    .repositoryLocalActivityByStableKey[relocatedStableKey] == relocatedWarmActivity
            )
            #expect(
                fixture.adapter.cachedProjectionRequest?.activityReferenceDate
                    == reassociationReferenceDate
            )
            #expect(
                fixture.adapter.publishedResult?
                    .repositoryActivityTransitionAtByRepoId[fixture.repo.id] == expectedTransition
            )
            #expect(fixture.observesActivity(stableKey: relocatedStableKey))
            #expect(!fixture.observesActivity(stableKey: fixture.repositoryStableKey))

            let scopedCaptureCountAfterReassociation = fixture.capture.scopedCaptureCount
            let deltaExecutionCountAfterReassociation = fixture.executionRecorder.deltaExecutionCount
            let oldKeyWarmActivity = try fixture.warmActivity(
                lastQualifyingActivityAt: fixture.referenceDate
            )
            fixture.publishActivities(
                atoms: atoms,
                activityByStableKey: [
                    fixture.repositoryStableKey: oldKeyWarmActivity,
                    relocatedStableKey: relocatedWarmActivity,
                    fixture.unrelatedRepositoryStableKey: fixture.unrelatedInactiveActivity,
                ]
            )
            for _ in 0..<200 { await Task.yield() }

            #expect(fixture.capture.scopedCaptureCount == scopedCaptureCountAfterReassociation)
            #expect(
                fixture.executionRecorder.deltaExecutionCount == deltaExecutionCountAfterReassociation
            )

            let relocatedInactiveActivity = try fixture.inactiveActivity(
                repositoryStableKey: relocatedStableKey
            )
            fixture.publishActivities(
                atoms: atoms,
                activityByStableKey: [
                    fixture.repositoryStableKey: oldKeyWarmActivity,
                    relocatedStableKey: relocatedInactiveActivity,
                    fixture.unrelatedRepositoryStableKey: fixture.unrelatedInactiveActivity,
                ]
            )
            for _ in 0..<2000
            where fixture.adapter.publishedResult?
                .repositoryActivityDispositionByRepoId[fixture.repo.id] != .locallyInactive
            {
                await Task.yield()
            }

            #expect(fixture.capture.scopedCaptureCount == scopedCaptureCountAfterReassociation + 1)
            #expect(
                fixture.executionRecorder.deltaExecutionCount
                    == deltaExecutionCountAfterReassociation + 1
            )
            #expect(fixture.capture.fullCaptureCount == fullCaptureCount)
        }
    }

    @MainActor
    @Test("warm activity refresh moves its deadline through an equal-paint worker delta")
    func warmActivityRefreshMovesDeadlineThroughWorkerDelta() async throws {
        try await withAsyncTestCoreAtoms { atoms in
            let fixture = try RepoExplorerLocalActivityProjectionFixture(atoms: atoms)
            defer { fixture.stop() }
            await fixture.startAndWait(for: .locallyInactive)
            let firstWarmActivity = try fixture.warmActivity(
                lastQualifyingActivityAt: fixture.referenceDate.addingTimeInterval(-100)
            )
            fixture.publishActivity(atoms: atoms, activity: firstWarmActivity)
            for _ in 0..<2000
            where fixture.adapter.publishedResult?.repositoryActivityDispositionByRepoId[fixture.repo.id]
                != .warm
            {
                await Task.yield()
            }
            let firstTransition = try #require(
                fixture.adapter.semanticBaselineResult?
                    .repositoryActivityTransitionAtByRepoId[fixture.repo.id]
            )
            let fullCaptureCount = fixture.capture.fullCaptureCount
            let scopedCaptureCount = fixture.capture.scopedCaptureCount
            let deltaExecutionCount = fixture.executionRecorder.deltaExecutionCount
            let publishedRevision = fixture.adapter.publishedRevision
            let materialization = fixture.adapter.semanticBaselineResult?.materializationSnapshot
            let refreshedWarmActivity = try fixture.warmActivity(
                lastQualifyingActivityAt: fixture.referenceDate
            )

            fixture.publishActivity(atoms: atoms, activity: refreshedWarmActivity)
            for _ in 0..<2000
            where fixture.executionRecorder.deltaExecutionCount == deltaExecutionCount
                || fixture.adapter.semanticBaselineResult?
                    .repositoryActivityTransitionAtByRepoId[fixture.repo.id] == firstTransition
            {
                await Task.yield()
            }

            #expect(fixture.capture.fullCaptureCount == fullCaptureCount)
            #expect(fixture.capture.scopedCaptureCount == scopedCaptureCount + 1)
            #expect(fixture.executionRecorder.deltaExecutionCount == deltaExecutionCount + 1)
            #expect(fixture.adapter.publishedRevision == publishedRevision)
            #expect(
                fixture.adapter.semanticBaselineResult?
                    .repositoryActivityDispositionByRepoId[fixture.repo.id] == .warm
            )
            #expect(
                fixture.adapter.semanticBaselineResult?
                    .repositoryActivityTransitionAtByRepoId[fixture.repo.id] != firstTransition
            )
            #expect(fixture.adapter.semanticBaselineResult?.materializationSnapshot == materialization)
        }
    }

    @MainActor
    @Test("launcher recency performs zero Repo Explorer activity capture")
    func launcherRecencyPerformsZeroActivityCapture() async throws {
        try await withAsyncTestCoreAtoms { atoms in
            let fixture = try RepoExplorerLocalActivityProjectionFixture(atoms: atoms)
            defer { fixture.stop() }
            await fixture.startAndWait(for: .locallyInactive)
            let fullCaptureCount = fixture.capture.fullCaptureCount
            let scopedCaptureCount = fixture.capture.scopedCaptureCount

            try atoms.applicationEntityRecency.recordOpened(
                repositoryStableKey: fixture.repositoryStableKey,
                worktreeStableKey: fixture.worktreeStableKey,
                at: fixture.referenceDate
            )
            for _ in 0..<100 { await Task.yield() }

            #expect(fixture.capture.fullCaptureCount == fullCaptureCount)
            #expect(fixture.capture.scopedCaptureCount == scopedCaptureCount)
        }
    }

    @MainActor
    @Test("activity hydration transition retains global full classification")
    func activityHydrationTransitionRetainsGlobalClassification() async throws {
        try await withAsyncTestCoreAtoms { atoms in
            let fixture = try RepoExplorerLocalActivityProjectionFixture(
                atoms: atoms,
                publishesAuthoritativeActivity: false
            )
            defer { fixture.stop() }
            await fixture.startAndWait(for: .unclassified)
            let fullCaptureCount = fixture.capture.fullCaptureCount
            let scopedCaptureCount = fixture.capture.scopedCaptureCount

            fixture.publishActivity(atoms: atoms, activity: fixture.inactiveActivity)
            for _ in 0..<2000
            where fixture.adapter.publishedResult?
                .repositoryActivityDispositionByRepoId[fixture.repo.id] != .locallyInactive
                || fixture.adapter.publishedResult?
                    .repositoryActivityDispositionByRepoId[fixture.unrelatedRepo.id] != .locallyInactive
            {
                await Task.yield()
            }

            #expect(fixture.capture.fullCaptureCount == fullCaptureCount + 1)
            #expect(fixture.capture.scopedCaptureCount == scopedCaptureCount)
            #expect(
                fixture.adapter.publishedResult?
                    .repositoryActivityDispositionByRepoId[fixture.repo.id] == .locallyInactive
            )
            #expect(
                fixture.adapter.publishedResult?
                    .repositoryActivityDispositionByRepoId[fixture.unrelatedRepo.id] == .locallyInactive
            )
        }
    }
}
