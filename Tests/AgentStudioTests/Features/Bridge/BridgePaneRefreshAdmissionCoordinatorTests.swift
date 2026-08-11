import AgentStudioCore
import Foundation
import Testing

@testable import AgentStudioBridge

@Suite("Bridge pane refresh admission coordinator")
@MainActor
struct BridgePaneRefreshAdmissionCoordinatorTests {
    @Test("only the pending comparison attempt is current for publication")
    func onlyPendingComparisonAttemptIsCurrentForPublication() {
        // Arrange
        let coordinator = BridgePaneRefreshAdmissionCoordinator(initialActivity: .foreground)

        // Act
        coordinator.beginReviewComparisonAttempt(
            activeTarget: .branch(name: "stack/first"),
            reviewGeneration: 8
        )
        let firstAttemptWasPending = coordinator.isReviewComparisonAttemptPending(
            reviewGeneration: 8
        )
        coordinator.beginReviewComparisonAttempt(
            activeTarget: .branch(name: "stack/second"),
            reviewGeneration: 9
        )

        // Assert
        #expect(firstAttemptWasPending)
        #expect(!coordinator.isReviewComparisonAttemptPending(reviewGeneration: 8))
        #expect(coordinator.isReviewComparisonAttemptPending(reviewGeneration: 9))
    }

    @Test("successor comparison keeps the displayed predecessor stale until settlement")
    func successorComparisonKeepsDisplayedPredecessorStaleUntilSettlement() throws {
        // Arrange
        let predecessor = BridgePaneReviewDisplayedSnapshotIdentity(
            packageId: "package-7",
            reviewGeneration: 7,
            revision: 11
        )
        let successor = BridgePaneReviewDisplayedSnapshotIdentity(
            packageId: "package-8",
            reviewGeneration: 8,
            revision: 12
        )
        let coordinator = BridgePaneRefreshAdmissionCoordinator(
            initialActivity: .foreground,
            initialReviewComparison: BridgePaneReviewComparisonPresentation(
                activeTarget: .branch(name: "main"),
                attempt: .settled(reviewGeneration: 7),
                displayedSnapshot: .current(predecessor)
            )
        )
        let initialRevision = coordinator.productPresentationSnapshot.presentationRevision

        // Act
        coordinator.beginReviewComparisonAttempt(
            activeTarget: .branch(name: "stack/base"),
            reviewGeneration: 8
        )
        let pending = coordinator.productPresentationSnapshot
        coordinator.settleReviewComparisonAttempt(
            reviewGeneration: 8,
            displayedSnapshotIdentity: successor
        )
        let settled = coordinator.productPresentationSnapshot

        // Assert
        #expect(pending.presentationRevision == initialRevision + 1)
        #expect(pending.reviewComparison?.activeTarget == .branch(name: "stack/base"))
        #expect(pending.reviewComparison?.attempt == .pending(reviewGeneration: 8))
        #expect(pending.reviewComparison?.displayedSnapshot == .stale(predecessor))
        #expect(settled.presentationRevision == initialRevision + 2)
        #expect(settled.reviewComparison?.attempt == .settled(reviewGeneration: 8))
        #expect(settled.reviewComparison?.displayedSnapshot == .current(successor))
    }

    @Test("comparison transitions retain the published repository default target")
    func comparisonTransitionsRetainPublishedRepositoryDefaultTarget() throws {
        let repositoryDefaultTarget = BridgeReviewComparisonDefaultTargetIdentity(
            remoteName: "origin",
            branchName: "main"
        )
        let coordinator = BridgePaneRefreshAdmissionCoordinator(
            initialActivity: .foreground,
            initialReviewComparison: BridgePaneReviewComparisonPresentation(
                activeTarget: nil,
                attempt: .selectionRequired,
                displayedSnapshot: .absent
            )
        )

        coordinator.publishReviewComparisonDefaultTarget(repositoryDefaultTarget)
        coordinator.beginReviewComparisonAttempt(
            activeTarget: .originDefaultBranch(remoteName: "origin", branchName: "main"),
            reviewGeneration: 8
        )
        coordinator.failReviewComparisonAttempt(
            reviewGeneration: 8,
            failureKind: "git.unresolvedTarget",
            retryable: true
        )

        #expect(
            coordinator.productPresentationSnapshot.reviewComparison?.repositoryDefaultTarget
                == repositoryDefaultTarget
        )
    }

    @Test("current comparison failure retains the displayed predecessor as stale")
    func currentComparisonFailureRetainsDisplayedPredecessorAsStale() {
        // Arrange
        let predecessor = BridgePaneReviewDisplayedSnapshotIdentity(
            packageId: "package-7",
            reviewGeneration: 7,
            revision: 11
        )
        let coordinator = BridgePaneRefreshAdmissionCoordinator(
            initialActivity: .foreground,
            initialReviewComparison: BridgePaneReviewComparisonPresentation(
                activeTarget: .branch(name: "main"),
                attempt: .settled(reviewGeneration: 7),
                displayedSnapshot: .current(predecessor)
            )
        )
        coordinator.beginReviewComparisonAttempt(
            activeTarget: .branch(name: "stack/base"),
            reviewGeneration: 8
        )

        // Act
        coordinator.failReviewComparisonAttempt(
            reviewGeneration: 8,
            failureKind: "git.unresolvedTarget",
            retryable: true
        )

        // Assert
        #expect(
            coordinator.productPresentationSnapshot.reviewComparison
                == BridgePaneReviewComparisonPresentation(
                    activeTarget: .branch(name: "stack/base"),
                    attempt: .unavailable(
                        failureKind: "git.unresolvedTarget",
                        retryable: true
                    ),
                    displayedSnapshot: .stale(predecessor)
                )
        )
    }

    @Test("loaded-hidden invalidation storms accumulate in one pane-wide dirty fact")
    func loadedHiddenInvalidationStormAccumulatesOneDirtyFact() throws {
        // Arrange
        let coordinator = BridgePaneRefreshAdmissionCoordinator()
        coordinator.applyActivity(.loadedHidden)

        // Act
        coordinator.recordInvalidation(
            fileChangeset: makeFileChangeset(
                paths: ["Sources/App/First.swift"],
                batchSequence: 41
            ),
            requiresReviewRefresh: true
        )
        let firstDirtyFact = try #require(coordinator.diagnosticSnapshot.dirtyFact)
        coordinator.recordInvalidation(
            fileChangeset: makeFileChangeset(
                paths: ["Sources/App/Second.swift", "Sources/App/First.swift"],
                batchSequence: 42
            ),
            requiresReviewRefresh: true
        )
        coordinator.recordInvalidation(
            fileChangeset: makeFileChangeset(
                paths: ["Tests/App/FirstTests.swift"],
                batchSequence: 43
            ),
            requiresReviewRefresh: true
        )

        // Assert
        let accumulatedDirtyFact = try #require(coordinator.diagnosticSnapshot.dirtyFact)
        #expect(accumulatedDirtyFact.generation == firstDirtyFact.generation)
        #expect(
            accumulatedDirtyFact.filePaths
                == [
                    "Sources/App/First.swift",
                    "Sources/App/Second.swift",
                    "Tests/App/FirstTests.swift",
                ]
        )
        #expect(accumulatedDirtyFact.latestBatchSequence == 43)
        #expect(accumulatedDirtyFact.requiresReviewRefresh)
        #expect(coordinator.diagnosticSnapshot.activeRefreshPass == nil)
        #expect(coordinator.diagnosticSnapshot.refreshPassCount == 0)
    }

    @Test("foreground transition reserves one latest catch-up covering File and Review")
    func foregroundTransitionReservesOneLatestCatchUpForBothLanes() throws {
        // Arrange
        let coordinator = BridgePaneRefreshAdmissionCoordinator()
        coordinator.applyActivity(.loadedHidden)
        coordinator.recordInvalidation(
            fileChangeset: makeFileChangeset(
                paths: ["Sources/App/First.swift"],
                batchSequence: 51
            ),
            requiresReviewRefresh: true
        )
        coordinator.recordInvalidation(
            fileChangeset: makeFileChangeset(
                paths: ["Sources/App/Latest.swift"],
                batchSequence: 52
            ),
            requiresReviewRefresh: true
        )

        // Act
        coordinator.applyActivity(.foreground)
        let reservation = try #require(coordinator.reserveForegroundRefreshPass())
        coordinator.applyActivity(.foreground)
        let repeatedForegroundReservation = coordinator.reserveForegroundRefreshPass()
        coordinator.applyActivity(.foreground)
        let thirdForegroundReservation = coordinator.reserveForegroundRefreshPass()

        // Assert
        #expect(
            reservation.filePaths
                == [
                    "Sources/App/First.swift",
                    "Sources/App/Latest.swift",
                ]
        )
        #expect(reservation.latestBatchSequence == 52)
        #expect(reservation.requiresReviewRefresh)
        #expect(repeatedForegroundReservation == nil)
        #expect(thirdForegroundReservation == nil)
        #expect(coordinator.diagnosticSnapshot.activeRefreshPass?.id == reservation.id)
        #expect(coordinator.diagnosticSnapshot.refreshPassCount == 1)
    }

    @Test("loaded-hidden coalescing retains only the latest File status snapshot")
    func loadedHiddenCoalescingRetainsLatestFileStatusSnapshot() throws {
        // Arrange
        let coordinator = BridgePaneRefreshAdmissionCoordinator()
        coordinator.applyActivity(.loadedHidden)
        let earlierStatus = makeGitWorkingTreeStatus(
            branch: "feature/earlier",
            changed: 1,
            staged: 0,
            untracked: 0
        )
        let latestStatus = makeGitWorkingTreeStatus(
            branch: "feature/latest",
            changed: 2,
            staged: 1,
            untracked: 3
        )

        // Act
        coordinator.recordInvalidation(
            fileChangeset: nil,
            latestFileStatus: earlierStatus,
            requiresReviewRefresh: true
        )
        coordinator.recordInvalidation(
            fileChangeset: nil,
            latestFileStatus: latestStatus,
            requiresReviewRefresh: true
        )
        coordinator.applyActivity(.foreground)
        let reservation = try #require(coordinator.reserveForegroundRefreshPass())

        // Assert
        #expect(reservation.fileChangeset == nil)
        #expect(reservation.latestFileStatus == latestStatus)
        #expect(reservation.lanes == [.file, .review])
        #expect(coordinator.diagnosticSnapshot.refreshPassCount == 1)
    }

    @Test("successful completion clears dirty while failure retains it for explicit retry")
    func catchUpCompletionControlsDirtyRetentionWithoutSpinning() throws {
        // Arrange
        let coordinator = BridgePaneRefreshAdmissionCoordinator()
        coordinator.applyActivity(.loadedHidden)
        coordinator.recordInvalidation(
            fileChangeset: makeFileChangeset(
                paths: ["Sources/App/Retry.swift"],
                batchSequence: 61
            ),
            requiresReviewRefresh: true
        )
        coordinator.applyActivity(.foreground)
        let failedReservation = try #require(coordinator.reserveForegroundRefreshPass())

        // Act — a failed pass releases its reservation but retains the pane dirty fact.
        coordinator.completeRefreshPass(failedReservation, outcome: .failed)

        // Assert
        #expect(coordinator.diagnosticSnapshot.dirtyFact != nil)
        #expect(coordinator.diagnosticSnapshot.activeRefreshPass == nil)
        #expect(coordinator.diagnosticSnapshot.refreshPassCount == 1)
        coordinator.applyActivity(.foreground)
        #expect(coordinator.diagnosticSnapshot.refreshPassCount == 1)

        // Act — only an explicit retry can reserve the retained fact.
        let retryReservation = try #require(coordinator.reserveForegroundRefreshPass())
        coordinator.completeRefreshPass(retryReservation, outcome: .succeeded)

        // Assert
        #expect(retryReservation.dirtyGeneration == failedReservation.dirtyGeneration)
        #expect(coordinator.diagnosticSnapshot.dirtyFact == nil)
        #expect(coordinator.diagnosticSnapshot.activeRefreshPass == nil)
        #expect(coordinator.diagnosticSnapshot.refreshPassCount == 2)
        #expect(coordinator.reserveForegroundRefreshPass() == nil)
    }

    @Test("foreground to loaded-hidden invalidates the admitted activity epoch")
    func loadedHiddenTransitionRejectsLateReviewAndFileOutput() throws {
        // Arrange
        let coordinator = BridgePaneRefreshAdmissionCoordinator()
        coordinator.applyActivity(.foreground)
        let admittedActivityEpoch = try #require(coordinator.acquireForegroundWork())
        let admittedEpoch = coordinator.diagnosticSnapshot.foregroundWorkEpoch
        var reviewPublicationCount = 0
        var fileMetadataPublicationCount = 0
        var fileBodyPublicationCount = 0

        // Act
        coordinator.applyActivity(.loadedHidden)
        let lateReviewPublication = admittedActivityEpoch.withValidAdmission {
            reviewPublicationCount += 1
            return true
        }
        let lateFileMetadataPublication = admittedActivityEpoch.withValidAdmission {
            fileMetadataPublicationCount += 1
            return true
        }
        let lateFileBodyPublication = admittedActivityEpoch.withValidAdmission {
            fileBodyPublicationCount += 1
            return true
        }

        // Assert
        #expect(coordinator.diagnosticSnapshot.activity == .loadedHidden)
        #expect(coordinator.diagnosticSnapshot.foregroundWorkEpoch == admittedEpoch + 1)
        #expect(lateReviewPublication == nil)
        #expect(lateFileMetadataPublication == nil)
        #expect(lateFileBodyPublication == nil)
        #expect(reviewPublicationCount == 0)
        #expect(fileMetadataPublicationCount == 0)
        #expect(fileBodyPublicationCount == 0)
        #expect(coordinator.acquireForegroundWork() == nil)
    }

    @Test("started Review continuation remains valid while hidden and invalidates on close")
    func startedReviewContinuationSurvivesLoadedHiddenOnly() throws {
        // Arrange
        let coordinator = BridgePaneRefreshAdmissionCoordinator(initialActivity: .foreground)
        let reviewContinuation = try #require(coordinator.acquireReviewContentContinuation())
        let invalidationCounter = BridgePaneRefreshInvalidationCounter()
        let handlerId = try #require(
            reviewContinuation.registerInvalidationHandler {
                invalidationCounter.record()
            }
        )

        // Act
        coordinator.applyActivity(.loadedHidden)
        let hiddenMutation = reviewContinuation.withValidAdmission { true }

        // Assert
        #expect(hiddenMutation == true)
        #expect(invalidationCounter.isEmpty)

        // Act
        coordinator.close()
        let closedMutation = reviewContinuation.withValidAdmission { true }

        // Assert
        #expect(closedMutation == nil)
        #expect(invalidationCounter.count == 1)
        reviewContinuation.removeInvalidationHandler(handlerId)
    }

    @Test("stale completion retains dirty after its activity epoch is invalidated")
    func staleCompletionRetainsDirtyForLaterExplicitRetry() throws {
        // Arrange
        let coordinator = BridgePaneRefreshAdmissionCoordinator()
        coordinator.applyActivity(.loadedHidden)
        coordinator.recordInvalidation(
            fileChangeset: makeFileChangeset(
                paths: ["Sources/App/Stale.swift"],
                batchSequence: 71
            ),
            requiresReviewRefresh: true
        )
        coordinator.applyActivity(.foreground)
        let staleReservation = try #require(coordinator.reserveForegroundRefreshPass())

        // Act
        coordinator.applyActivity(.loadedHidden)
        coordinator.completeRefreshPass(staleReservation, outcome: .stale)

        // Assert
        #expect(coordinator.diagnosticSnapshot.activity == .loadedHidden)
        #expect(coordinator.diagnosticSnapshot.dirtyFact?.generation == staleReservation.dirtyGeneration)
        #expect(coordinator.diagnosticSnapshot.activeRefreshPass == nil)
        #expect(coordinator.diagnosticSnapshot.refreshPassCount == 1)
    }

    @Test("close is synchronous terminal and discards pending dirty work")
    func closeSynchronouslyInvalidatesPendingWorkAndClearsDirty() throws {
        // Arrange
        let coordinator = BridgePaneRefreshAdmissionCoordinator()
        coordinator.applyActivity(.loadedHidden)
        coordinator.recordInvalidation(
            fileChangeset: makeFileChangeset(
                paths: ["Sources/App/Close.swift"],
                batchSequence: 81
            ),
            requiresReviewRefresh: true
        )
        coordinator.applyActivity(.foreground)
        let reservation = try #require(coordinator.reserveForegroundRefreshPass())
        let activityEpochBeforeClose = coordinator.diagnosticSnapshot.foregroundWorkEpoch
        var lateMutationCount = 0

        // Act
        coordinator.close()
        let lateMutation = reservation.foregroundWorkAdmission.withValidAdmission {
            lateMutationCount += 1
            return true
        }
        coordinator.completeRefreshPass(reservation, outcome: .succeeded)
        let firstClosedSnapshot = coordinator.diagnosticSnapshot
        coordinator.close()

        // Assert
        #expect(lateMutation == nil)
        #expect(lateMutationCount == 0)
        #expect(firstClosedSnapshot.activity == .closed)
        #expect(firstClosedSnapshot.foregroundWorkEpoch == activityEpochBeforeClose + 1)
        #expect(firstClosedSnapshot.dirtyFact == nil)
        #expect(firstClosedSnapshot.activeRefreshPass == nil)
        #expect(coordinator.diagnosticSnapshot.foregroundWorkEpoch == firstClosedSnapshot.foregroundWorkEpoch)
        #expect(coordinator.diagnosticSnapshot.dirtyFact == nil)
        coordinator.applyActivity(.foreground)
        #expect(coordinator.reserveForegroundRefreshPass() == nil)
        #expect(coordinator.acquireForegroundWork() == nil)
    }
}

private final class BridgePaneRefreshInvalidationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storedCount = 0

    var isEmpty: Bool {
        lock.withLock { storedCount == 0 }
    }

    var count: Int {
        lock.withLock { storedCount }
    }

    func record() {
        lock.withLock { storedCount += 1 }
    }
}

private func makeFileChangeset(
    paths: [String],
    batchSequence: UInt64
) -> FileChangeset {
    FileChangeset(
        worktreeId: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        repoId: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
        rootPath: URL(fileURLWithPath: "/tmp/bridge-pane-refresh-admission"),
        paths: paths,
        timestamp: .now,
        batchSeq: batchSequence
    )
}

private func makeGitWorkingTreeStatus(
    branch: String,
    changed: Int,
    staged: Int,
    untracked: Int
) -> GitWorkingTreeStatus {
    GitWorkingTreeStatus(
        summary: GitWorkingTreeSummary(
            changed: changed,
            staged: staged,
            untracked: untracked
        ),
        branch: branch,
        origin: nil
    )
}
