import Foundation
import Testing

@testable import AgentStudio

extension WebKitSerializedTests.BridgePaneControllerTests {
    @Test("loaded-hidden presentation precedes cancellation-ignoring metadata producer drain")
    func loadedHiddenPresentationPrecedesCancellationIgnoringMetadataProducerDrain() async throws {
        // Arrange — the producer opening is already consumed by fixture installation, so the
        // foreground transition is the first queued metadata frame.
        let producerGate = RefreshAdmissionCancellationIgnoringProducerGate()
        let fixture = try await makeRefreshAdmissionIntegrationFixture(
            fileMetadataProducerGate: producerGate
        )
        let foregroundTransition = fixture.controller.applyBridgePaneActivity(.foreground)
        await foregroundTransition?.value
        guard
            case .panePresentation(let foregroundPresentation) =
                try await fixture.consumeNextMetadataFrame()
        else {
            Issue.record("Expected the foreground pane presentation")
            producerGate.releaseAll()
            await fixture.finish()
            return
        }
        #expect(foregroundPresentation.nativeActivity == .foreground)
        await waitForActiveReviewRefreshTaskToFinish(fixture.controller)
        try await fixture.openFileMetadataSubscription()
        await producerGate.waitUntilStarted()

        // Act — native admission closes synchronously. The producer observes cancellation but
        // deliberately does not return, so producer drain remains held at a known boundary.
        let hiddenTransition = fixture.controller.applyBridgePaneActivity(.loadedHidden)
        await producerGate.waitUntilCancellationRequested()
        let presentationWasQueuedBeforeProducerRelease =
            await waitForRefreshAdmissionQueuedMetadataFrame(fixture)
        let presentationBeforeProducerRelease: BridgeProductPanePresentationFrame?
        if presentationWasQueuedBeforeProducerRelease {
            guard
                case .panePresentation(let presentation) =
                    try await fixture.consumeNextMetadataFrame()
            else {
                Issue.record("Expected loaded-hidden pane presentation before producer drain")
                producerGate.releaseAll()
                await hiddenTransition?.value
                await fixture.finish()
                return
            }
            presentationBeforeProducerRelease = presentation
        } else {
            presentationBeforeProducerRelease = nil
        }

        // Assert — the comm-worker activity boundary must not wait for native producer drain.
        #expect(presentationBeforeProducerRelease?.nativeActivity == .loadedHidden)

        // Cleanup also captures the current defective ordering without leaking the held task.
        producerGate.releaseAll()
        await hiddenTransition?.value
        if presentationBeforeProducerRelease == nil {
            guard
                case .panePresentation(let delayedPresentation) =
                    try await fixture.consumeNextMetadataFrame()
            else {
                Issue.record("Expected delayed loaded-hidden presentation after producer release")
                await fixture.finish()
                return
            }
            #expect(delayedPresentation.nativeActivity == .loadedHidden)
        }
        await fixture.finish()
    }

    @Test("loaded-hidden initial Review intake waits for one foreground load")
    func loadedHiddenInitialReviewIntakeWaitsForOneForegroundLoad() async throws {
        // Arrange
        let comparisonGate = BridgeComparisonGate()
        let fixture = try await makeRefreshAdmissionIntegrationFixture(
            comparisonGate: comparisonGate
        )
        fixture.controller.applyBridgePaneActivity(.loadedHidden)

        // Act
        fixture.controller.scheduleInitialReviewPackageLoadIfPossible(reason: .initialIntake)

        // Assert — scheduling while hidden retains intent without starting provider or package work.
        #expect(fixture.controller.activeReviewRefreshTask == nil)
        #expect(await fixture.reviewProvider.recordedComparisonRequestsCount() == 0)
        #expect(fixture.controller.paneState.diff.packageMetadata == nil)

        // Act — native foreground is the only fact that may admit the retained intake.
        fixture.controller.applyBridgePaneActivity(.foreground)
        await comparisonGate.waitForStartedComparisonCount(1)
        await comparisonGate.releaseAll()
        await waitForActiveReviewRefreshTaskToFinish(fixture.controller)

        // Assert
        #expect(await fixture.reviewProvider.recordedComparisonRequestsCount() == 1)
        #expect(fixture.controller.paneState.diff.packageMetadata?.orderedItemIds == ["item-initial"])
        await fixture.finish()
    }

    @Test("loaded-hidden product resync waits for one foreground Review reload")
    func loadedHiddenProductResyncWaitsForOneForegroundReviewReload() async throws {
        // Arrange
        let fixture = try await makeRefreshAdmissionIntegrationFixture()
        try await fixture.loadInitialReviewPackage()
        let comparisonCountBeforeResync = await fixture.reviewProvider.recordedComparisonRequestsCount()
        await fixture.reviewProvider.setComparison(fixture.refreshedComparison)
        let comparisonGate = BridgeComparisonGate()
        await fixture.reviewProvider.setComparisonGate(comparisonGate)
        fixture.controller.applyBridgePaneActivity(.loadedHidden)

        // Act
        fixture.controller.scheduleReviewPackageReloadForProductResync(reason: .productResync)

        // Assert — the retained package stays readable and no replacement build starts hidden.
        #expect(fixture.controller.activeReviewRefreshTask == nil)
        #expect(
            await fixture.reviewProvider.recordedComparisonRequestsCount()
                == comparisonCountBeforeResync
        )
        #expect(fixture.controller.paneState.diff.packageMetadata?.orderedItemIds == ["item-initial"])

        // Act
        fixture.controller.applyBridgePaneActivity(.foreground)
        await comparisonGate.waitForStartedComparisonCount(1)
        await comparisonGate.releaseAll()
        await waitForActiveReviewRefreshTaskToFinish(fixture.controller)

        // Assert
        #expect(
            await fixture.reviewProvider.recordedComparisonRequestsCount()
                == comparisonCountBeforeResync + 1
        )
        #expect(fixture.controller.paneState.diff.packageMetadata?.orderedItemIds == ["item-refreshed"])
        await fixture.finish()
    }

    @Test("loaded-hidden worktree invalidations coalesce and foreground catches up both surfaces once")
    func loadedHiddenWorktreeInvalidationsCoalesceIntoOneBothSurfaceCatchUp() async throws {
        // Arrange
        let fixture = try await makeRefreshAdmissionIntegrationFixture()
        try await fixture.loadInitialReviewPackage()
        let comparisonCountBeforeInvalidation = await fixture.reviewProvider.recordedComparisonRequestsCount()
        let firstStatus = makeRefreshAdmissionStatus(branch: "feature/first", changed: 2)
        let latestStatus = makeRefreshAdmissionStatus(branch: "feature/latest", changed: 4)
        fixture.controller.applyBridgePaneActivity(.loadedHidden)

        // Act
        await fixture.controller.handleWorktreeProductInvalidation(
            .filesChanged(
                fixture.makeChangeset(
                    paths: ["Sources/App/First.swift"],
                    batchSequence: 41
                )
            )
        )
        await fixture.controller.handleWorktreeProductInvalidation(.statusChanged(firstStatus))
        await fixture.controller.handleWorktreeProductInvalidation(
            .filesChanged(
                fixture.makeChangeset(
                    paths: ["Sources/App/Second.swift", "Sources/App/First.swift"],
                    batchSequence: 42
                )
            )
        )
        await fixture.controller.handleWorktreeProductInvalidation(.statusChanged(latestStatus))

        // Assert — loaded-hidden retains one pane-wide fact and starts no product work.
        let hiddenSnapshot = fixture.controller.refreshAdmissionCoordinator.diagnosticSnapshot
        let hiddenDirtyFact = try #require(hiddenSnapshot.dirtyFact)
        #expect(hiddenSnapshot.activity == .loadedHidden)
        #expect(hiddenSnapshot.refreshPassCount == 0)
        #expect(hiddenSnapshot.activeRefreshPass == nil)
        #expect(
            hiddenDirtyFact.filePaths
                == [
                    "Sources/App/First.swift",
                    "Sources/App/Second.swift",
                ]
        )
        #expect(hiddenDirtyFact.latestBatchSequence == 42)
        #expect(hiddenDirtyFact.latestFileStatus == latestStatus)
        #expect(hiddenDirtyFact.requiresReviewRefresh)
        #expect(await fixture.reviewProvider.recordedComparisonRequestsCount() == comparisonCountBeforeInvalidation)
        #expect(await fixture.fileMetadataSource.changesetPublishCount == 0)
        #expect(await fixture.fileMetadataSource.statusPublishCount == 0)

        // Act — foreground return starts one catch-up. Hold Review so repeated foreground
        // inputs cannot accidentally start another pass.
        await fixture.reviewProvider.setComparison(fixture.refreshedComparison)
        let comparisonGate = BridgeComparisonGate()
        await fixture.reviewProvider.setComparisonGate(comparisonGate)
        fixture.controller.applyBridgePaneActivity(.foreground)
        fixture.controller.applyBridgePaneActivity(.foreground)
        await comparisonGate.waitForStartedComparisonCount(1)
        await comparisonGate.releaseAll()
        await fixture.fileMetadataSource.waitForChangesetPublishCount(1)
        await fixture.fileMetadataSource.waitForStatusPublishCount(1)
        await waitForRefreshAdmissionIdle(fixture.controller)

        // Assert
        #expect(
            await fixture.reviewProvider.recordedComparisonRequestsCount()
                == comparisonCountBeforeInvalidation + 1
        )
        #expect(await fixture.fileMetadataSource.publishedChangesets().count == 1)
        #expect(await fixture.fileMetadataSource.publishedStatuses() == [latestStatus])
        #expect(fixture.controller.paneState.diff.packageMetadata?.orderedItemIds == ["item-refreshed"])
        let foregroundSnapshot = fixture.controller.refreshAdmissionCoordinator.diagnosticSnapshot
        #expect(foregroundSnapshot.activity == .foreground)
        #expect(foregroundSnapshot.refreshPassCount == 1)
        #expect(foregroundSnapshot.activeRefreshPass == nil)
        #expect(foregroundSnapshot.dirtyFact == nil)
        await fixture.finish()
    }

    @Test("foreground to loaded-hidden suppresses a late admitted Review publication")
    func foregroundToLoadedHiddenSuppressesLateReviewPublication() async throws {
        // Arrange
        let fixture = try await makeRefreshAdmissionIntegrationFixture()
        try await fixture.loadInitialReviewPackage()
        let committedBeforeRefresh = try fixture.currentCommittedReviewPublication()
        let panePackageBeforeRefresh = try #require(fixture.controller.paneState.diff.packageMetadata)
        await fixture.reviewProvider.setComparison(fixture.refreshedComparison)
        let comparisonGate = BridgeComparisonGate()
        await fixture.reviewProvider.setComparisonGate(comparisonGate)

        // Act
        await fixture.controller.handleWorktreeProductInvalidation(
            .filesChanged(
                fixture.makeChangeset(
                    paths: ["Sources/App/Refreshed.swift"],
                    batchSequence: 51
                )
            )
        )
        await comparisonGate.waitForStartedComparisonCount(1)
        fixture.controller.applyBridgePaneActivity(.loadedHidden)
        await comparisonGate.releaseAll()
        await waitForRefreshAdmissionSettledWhileHidden(fixture.controller)

        // Assert
        let committedAfterLateCompletion = try fixture.currentCommittedReviewPublication()
        #expect(committedAfterLateCompletion.publicationId == committedBeforeRefresh.publicationId)
        #expect(committedAfterLateCompletion.package == committedBeforeRefresh.package)
        #expect(fixture.controller.paneState.diff.packageMetadata == panePackageBeforeRefresh)
        let hiddenSnapshot = fixture.controller.refreshAdmissionCoordinator.diagnosticSnapshot
        #expect(hiddenSnapshot.activity == .loadedHidden)
        #expect(hiddenSnapshot.activeRefreshPass == nil)
        #expect(hiddenSnapshot.dirtyFact != nil)
        await fixture.finish()
    }

    @Test("foreground return before canceled refresh unwinds starts one replacement catch-up")
    func foregroundReturnBeforeCanceledRefreshUnwindsStartsOneReplacementCatchUp() async throws {
        // Arrange
        let fixture = try await makeRefreshAdmissionIntegrationFixture()
        try await fixture.loadInitialReviewPackage()
        let comparisonCountBeforeInvalidation = await fixture.reviewProvider.recordedComparisonRequestsCount()
        await fixture.reviewProvider.setComparison(fixture.refreshedComparison)
        let comparisonGate = BridgeComparisonGate()
        await fixture.reviewProvider.setComparisonGate(comparisonGate)

        // Act — block the first pass, invalidate its foreground epoch, then return before
        // its canceled task has had a chance to unwind.
        await fixture.controller.handleWorktreeProductInvalidation(
            .filesChanged(
                fixture.makeChangeset(
                    paths: ["Sources/App/Replacement.swift"],
                    batchSequence: 61
                )
            )
        )
        await comparisonGate.waitForStartedComparisonCount(1)
        fixture.controller.applyBridgePaneActivity(.loadedHidden)
        fixture.controller.applyBridgePaneActivity(.foreground)
        await comparisonGate.releaseAll()
        await waitForRefreshAdmissionIdle(fixture.controller)

        // Assert — the canceled attempt is not the catch-up. Exactly one replacement pass
        // consumes the restored dirty fact after the old task relinquishes ownership.
        #expect(
            await fixture.reviewProvider.recordedComparisonRequestsCount()
                == comparisonCountBeforeInvalidation + 2
        )
        #expect(await fixture.fileMetadataSource.changesetPublishAttemptCount == 2)
        #expect(await fixture.fileMetadataSource.publishedChangesets().count == 2)
        let snapshot = fixture.controller.refreshAdmissionCoordinator.diagnosticSnapshot
        #expect(snapshot.refreshPassCount == 2)
        #expect(snapshot.activeRefreshPass == nil)
        #expect(snapshot.dirtyFact == nil)
        #expect(fixture.controller.paneState.diff.packageMetadata?.orderedItemIds == ["item-refreshed"])
        await fixture.finish()
    }

    @Test("stale Review commit after rapid foreground return schedules one replacement catch-up")
    func staleReviewCommitAfterRapidForegroundReturnSchedulesOneReplacementCatchUp() async throws {
        // Arrange — initial Review authority commits before the reservation boundary is armed.
        let reservationGate = RefreshAdmissionReviewReservationGate()
        let fixture = try await makeRefreshAdmissionIntegrationFixture(
            reviewMetadataReservationGate: reservationGate
        )
        try await fixture.loadInitialReviewPackage()
        let comparisonCountBeforeInvalidation = await fixture.reviewProvider.recordedComparisonRequestsCount()
        await fixture.reviewProvider.setComparison(fixture.refreshedComparison)
        await reservationGate.enable()

        // Act — hold the first replacement immediately before commit, invalidate its original
        // foreground token, and return foreground before that old transaction unwinds.
        await fixture.controller.handleWorktreeProductInvalidation(
            .filesChanged(
                fixture.makeChangeset(
                    paths: ["Sources/App/StaleCommit.swift"],
                    batchSequence: 63
                )
            )
        )
        await reservationGate.waitForHeldReservationCount(1)
        let hiddenTransition = fixture.controller.applyBridgePaneActivity(.loadedHidden)
        let foregroundTransition = fixture.controller.applyBridgePaneActivity(.foreground)
        await hiddenTransition?.value
        await foregroundTransition?.value
        await reservationGate.releaseAll()
        await waitForActiveReviewRefreshTaskToFinish(fixture.controller)

        // Assert — the rejected old transaction is stale, not failed. Exactly one replacement
        // pass consumes the one restored dirty fact under the new foreground epoch.
        #expect(
            await fixture.reviewProvider.recordedComparisonRequestsCount()
                == comparisonCountBeforeInvalidation + 2
        )
        #expect(await fixture.fileMetadataSource.changesetPublishAttemptCount == 2)
        #expect(await fixture.fileMetadataSource.publishedChangesets().count == 2)
        let snapshot = fixture.controller.refreshAdmissionCoordinator.diagnosticSnapshot
        #expect(snapshot.refreshPassCount == 2)
        #expect(snapshot.activeRefreshPass == nil)
        #expect(snapshot.dirtyFact == nil)
        #expect(fixture.controller.paneState.diff.packageMetadata?.orderedItemIds == ["item-refreshed"])
        await fixture.finish()
    }

    @Test("File publication failure retains dirty state after successful Review refresh")
    func filePublicationFailureRetainsDirtyStateAfterSuccessfulReviewRefresh() async throws {
        // Arrange
        let fixture = try await makeRefreshAdmissionIntegrationFixture(
            failsChangesetPublication: true
        )
        try await fixture.loadInitialReviewPackage()
        await fixture.reviewProvider.setComparison(fixture.refreshedComparison)

        // Act
        await fixture.controller.handleWorktreeProductInvalidation(
            .filesChanged(
                fixture.makeChangeset(
                    paths: ["Sources/App/FileFailure.swift"],
                    batchSequence: 62
                )
            )
        )
        await waitForActiveReviewRefreshTaskToFinish(fixture.controller)

        // Assert — Review may advance, but the pane-wide catch-up cannot report success
        // when the File half failed. The exact worktree fact remains retryable.
        #expect(fixture.controller.paneState.diff.packageMetadata?.orderedItemIds == ["item-refreshed"])
        #expect(await fixture.fileMetadataSource.changesetPublishAttemptCount == 1)
        #expect(await fixture.fileMetadataSource.publishedChangesets().isEmpty)
        let snapshot = fixture.controller.refreshAdmissionCoordinator.diagnosticSnapshot
        let retainedDirtyFact = snapshot.dirtyFact
        #expect(retainedDirtyFact?.filePaths == ["Sources/App/FileFailure.swift"])
        #expect(retainedDirtyFact?.latestBatchSequence == 62)
        #expect(retainedDirtyFact?.requiresReviewRefresh == true)
        #expect(snapshot.activeRefreshPass == nil)
        await fixture.finish()
    }

    @Test("controller teardown synchronously closes the refresh work gate")
    func controllerTeardownSynchronouslyClosesRefreshWorkGate() async throws {
        // Arrange
        let controller = makeController(
            state: BridgePaneState(
                panelKind: .diffViewer,
                source: .workspace(rootPath: "/tmp/bridge-refresh-teardown", baseline: .headMinusOne)
            )
        )
        controller.applyBridgePaneActivity(.foreground)
        let admittedWork = try #require(
            controller.refreshAdmissionCoordinator.acquireForegroundWork()
        )
        var latePublicationCount = 0

        // Act
        let retirementTask = controller.teardown()
        let latePublication = admittedWork.withValidAdmission {
            latePublicationCount += 1
            return true
        }

        // Assert
        #expect(latePublication == nil)
        #expect(latePublicationCount == 0)
        #expect(controller.refreshAdmissionCoordinator.diagnosticSnapshot.activity == .closed)
        #expect(controller.refreshAdmissionCoordinator.acquireForegroundWork() == nil)
        #expect(await retirementTask.value)
    }
}
