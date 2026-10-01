import AgentStudioCore
import AgentStudioGit
import AgentStudioTestHarness
import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioBridge

@Suite("Bridge pane hidden Review build admission", .serialized)
@MainActor
struct BridgePaneControllerHiddenReviewBuildTests {
    init() {
        installTestCoreAtomsIfNeeded()
    }

    @Test("hidden Review retains initial intake and builds once on show")
    func hiddenReviewRetainsInitialIntakeUntilShown() async throws {
        // Arrange
        let facts = try BridgePaneReviewBuildAdmissionTrace()
        let fixture = try await makeRefreshAdmissionIntegrationFixture(
            reviewBuildAdmissionFactSink: facts.source.sink
        )
        await bringPaneToForeground(fixture)
        await acceptFileViewerMode(fixture, sequence: 1)
        await setLatestComparison(fixture, fileId: "latest-initial")

        // Act: worker warm-up can arrive while File is visible and Review is hidden.
        let hiddenInput = BridgePaneReviewBuildAdmissionInput.initialIntake
        let hiddenOpening = await facts.recorder.mark(.hiddenInput(hiddenInput))
        await fixture.controller.handleCommittedProductReviewIntakeReady(
            BridgeProductReviewIntakeReadyRequest(
                reason: "background-warmup",
                streamId: nil
            ),
            productAdmission: fixture.productAdmission
        )
        let hiddenAdmissionStayedClosed = await facts.expectNoAdmission(
            for: hiddenInput,
            from: hiddenOpening
        )
        #expect(hiddenAdmissionStayedClosed)
        guard hiddenAdmissionStayedClosed else {
            await fixture.finish()
            try await facts.finish()
            return
        }

        // Assert: no package was built while hidden; its initial-intake reason remains pending.
        #expect(await fixture.reviewProvider.recordedComparisonRequestsCount() == 0)
        #expect(fixture.controller.activeReviewRefreshTask == nil)
        #expect(fixture.controller.pendingReviewPackageBuildReasons.contains(.initialIntake))

        // Act: the accepted Review-mode signal releases one build at the latest input.
        await acceptReviewViewerMode(fixture, sequence: 2, requiresCommittedSource: false)
        #expect(try await facts.nextAttemptOutcome() == .succeeded)

        // Assert
        #expect(await fixture.reviewProvider.recordedComparisonRequestsCount() == 1)
        #expect(
            fixture.controller.paneState.diff.packageMetadata?.orderedItemIds
                == ["item-latest-initial"]
        )
        await fixture.finish()
        try await facts.finish()
    }

    @Test("hidden Review retains product resync and builds once on show")
    func hiddenReviewRetainsProductResyncUntilShown() async throws {
        // Arrange
        let facts = try BridgePaneReviewBuildAdmissionTrace()
        let fixture = try await makeRefreshAdmissionIntegrationFixture(
            reviewBuildAdmissionFactSink: facts.source.sink
        )
        await bringPaneToForeground(fixture)
        await acceptReviewViewerMode(fixture, sequence: 1, requiresCommittedSource: false)
        #expect(try await facts.nextAttemptOutcome() == .succeeded)
        #expect(await fixture.reviewProvider.recordedComparisonRequestsCount() == 1)
        await acceptReviewViewerMode(fixture, sequence: 2, requiresCommittedSource: true)

        await acceptFileViewerMode(fixture, sequence: 3)
        await setLatestComparison(fixture, fileId: "latest-resync")

        // Act: a real controller resync request retains the reason while Review is hidden.
        let hiddenInput = BridgePaneReviewBuildAdmissionInput.productResync
        let hiddenOpening = await facts.recorder.mark(.hiddenInput(hiddenInput))
        await fixture.controller.handleCommittedProductReviewIntakeReady(
            BridgeProductReviewIntakeReadyRequest(
                reason: "sequence_gap",
                streamId: fixture.controller.reviewProtocolStreamId()
            ),
            productAdmission: fixture.productAdmission
        )
        let hiddenAdmissionStayedClosed = await facts.expectNoAdmission(
            for: hiddenInput,
            from: hiddenOpening
        )
        #expect(hiddenAdmissionStayedClosed)
        guard hiddenAdmissionStayedClosed else {
            await fixture.finish()
            try await facts.finish()
            return
        }

        // Assert: resync did not build in the hidden interval.
        #expect(await fixture.reviewProvider.recordedComparisonRequestsCount() == 1)
        #expect(fixture.controller.activeReviewRefreshTask == nil)
        #expect(fixture.controller.pendingReviewPackageBuildReasons.contains(.productResync))

        // Act: select the visible Review source that matches the committed package.
        await acceptReviewViewerMode(fixture, sequence: 4, requiresCommittedSource: true)
        #expect(try await facts.nextAttemptOutcome() == .succeeded)

        // Assert
        #expect(await fixture.reviewProvider.recordedComparisonRequestsCount() == 2)
        #expect(
            fixture.controller.paneState.diff.packageMetadata?.orderedItemIds
                == ["item-latest-resync"]
        )
        await fixture.finish()
        try await facts.finish()
    }

    @Test("hidden Review retains an explicit target and builds its latest target on show")
    func hiddenReviewRetainsExplicitTargetUntilShown() async throws {
        // Arrange
        let target = WorkspaceReviewContributionTarget.branch(name: "topic/review-target")
        let canonicalState = BridgePaneState(
            panelKind: .diffViewer,
            source: .workspace(
                rootPath: "/tmp/bridge-refresh-admission",
                baseline: WorkspaceBaseline(contributionTarget: target)
            )
        )
        let facts = try BridgePaneReviewBuildAdmissionTrace()
        let fixture = try await makeRefreshAdmissionIntegrationFixture(
            reviewBuildAdmissionFactSink: facts.source.sink,
            contributionTargetCommit: { _ in .applied(canonicalState) }
        )
        await bringPaneToForeground(fixture)
        await acceptFileViewerMode(fixture, sequence: 1)
        await setLatestContributionCapture(fixture, fileId: "hidden-target")

        // Act: an explicit target update is committed while File is the desired viewer.
        let hiddenInput = BridgePaneReviewBuildAdmissionInput.explicitTarget
        let hiddenOpening = await facts.recorder.mark(.hiddenInput(hiddenInput))
        _ = fixture.productAdmission.withValidAdmission {
            fixture.controller.refreshAdmissionCoordinator.workAdmissionSource
                .admitReviewComparisonIntent(
                    workerDerivationEpoch: 1,
                    productAdmission: fixture.productAdmission
                )
        }
        let didAdopt = await fixture.controller.handleCommittedProductReviewComparisonUpdate(
            BridgeProductReviewComparisonUpdateRequest(target: target),
            workerDerivationEpoch: 1,
            productAdmission: fixture.productAdmission
        )
        let hiddenAdmissionStayedClosed = await facts.expectNoAdmission(
            for: hiddenInput,
            from: hiddenOpening
        )
        #expect(hiddenAdmissionStayedClosed)
        guard hiddenAdmissionStayedClosed else {
            await fixture.finish()
            try await facts.finish()
            return
        }

        // Assert: target truth is retained without building Review while hidden.
        #expect(didAdopt == .applied)
        #expect(fixture.controller.bridgePaneState == canonicalState)
        #expect(await fixture.reviewProvider.recordedContributionRequests().isEmpty)
        #expect(fixture.controller.activeReviewRefreshTask == nil)
        #expect(fixture.controller.pendingReviewPackageBuildReasons.contains(.productResync))

        // Act: a newer target input arrives before Review becomes visible.
        await setLatestContributionCapture(fixture, fileId: "latest-target")
        await acceptReviewViewerMode(fixture, sequence: 2, requiresCommittedSource: false)
        #expect(try await facts.nextAttemptOutcome() == .succeeded)

        // Assert
        #expect(await fixture.reviewProvider.recordedContributionRequests().count == 1)
        #expect(
            fixture.controller.paneState.diff.packageMetadata?.orderedItemIds
                == ["item-latest-target"]
        )
        await fixture.finish()
        try await facts.finish()
    }

    @Test("hidden Review keeps filesystem catch-up pending while File work completes")
    func hiddenReviewDefersFilesystemCatchUpUntilShown() async throws {
        // Arrange
        let facts = try BridgePaneReviewBuildAdmissionTrace()
        let fixture = try await makeRefreshAdmissionIntegrationFixture(
            reviewBuildAdmissionFactSink: facts.source.sink
        )
        await bringPaneToForeground(fixture)
        await acceptReviewViewerMode(fixture, sequence: 1, requiresCommittedSource: false)
        #expect(try await facts.nextAttemptOutcome() == .succeeded)
        #expect(await fixture.reviewProvider.recordedComparisonRequestsCount() == 1)
        await acceptReviewViewerMode(fixture, sequence: 2, requiresCommittedSource: true)

        await acceptFileViewerMode(fixture, sequence: 3)
        await setLatestComparison(fixture, fileId: "intermediate-catch-up")

        // Act: real pane filesystem ingress records File and Review invalidation.
        let firstCatchUpInput = BridgePaneReviewBuildAdmissionInput.filesystemCatchUp(
            batchSequence: 41
        )
        let firstCatchUpOpening = await facts.recorder.mark(.hiddenInput(firstCatchUpInput))
        await postFilesystemEvent(
            fixture,
            path: "Sources/App/Intermediate.swift",
            batchSequence: 41
        )
        let firstCatchUpStayedHidden = await facts.expectNoAdmission(
            for: firstCatchUpInput,
            from: firstCatchUpOpening
        )
        #expect(firstCatchUpStayedHidden)
        guard firstCatchUpStayedHidden else {
            await fixture.finish()
            try await facts.finish()
            return
        }
        await setLatestComparison(fixture, fileId: "latest-catch-up")
        let latestCatchUpInput = BridgePaneReviewBuildAdmissionInput.filesystemCatchUp(
            batchSequence: 42
        )
        let latestCatchUpOpening = await facts.recorder.mark(.hiddenInput(latestCatchUpInput))
        await postFilesystemEvent(fixture, path: "Sources/App/Latest.swift", batchSequence: 42)
        let latestCatchUpStayedHidden = await facts.expectNoAdmission(
            for: latestCatchUpInput,
            from: latestCatchUpOpening
        )
        #expect(latestCatchUpStayedHidden)
        guard latestCatchUpStayedHidden else {
            await fixture.finish()
            try await facts.finish()
            return
        }

        // Assert: File published the churn, while Review retained its dirty fact without a build.
        #expect(await fixture.fileMetadataSource.changesetPublishCount == 2)
        #expect(await fixture.reviewProvider.recordedComparisonRequestsCount() == 1)
        #expect(fixture.controller.activeReviewRefreshTask == nil)
        #expect(
            fixture.controller.refreshAdmissionCoordinator.diagnosticSnapshot.dirtyFact?
                .requiresReviewRefresh == true
        )

        // Act: showing Review admits the retained catch-up at the latest provider input.
        await acceptReviewViewerMode(fixture, sequence: 4, requiresCommittedSource: true)
        #expect(try await facts.nextAttemptOutcome() == .succeeded)

        // Assert
        #expect(await fixture.reviewProvider.recordedComparisonRequestsCount() == 2)
        #expect(
            fixture.controller.paneState.diff.packageMetadata?.orderedItemIds
                == ["item-latest-catch-up"]
        )
        #expect(
            fixture.controller.refreshAdmissionCoordinator.diagnosticSnapshot.dirtyFact?
                .requiresReviewRefresh != true
        )
        await fixture.finish()
        try await facts.finish()
    }

    @Test("hiding fences a building Review attempt and blocks its refresh tail")
    func hidingReviewFencesActiveBuildAndRefreshTail() async throws {
        // Arrange
        let facts = try BridgePaneReviewBuildAdmissionTrace()
        let fixture = try await makeRefreshAdmissionIntegrationFixture(
            reviewBuildAdmissionFactSink: facts.source.sink
        )
        await bringPaneToForeground(fixture)
        let heldBuildInput = HeldStep<Void>(
            "initial Review build held through viewer hide",
            cancellation: .holdThroughCancellation
        )
        await fixture.reviewProvider.setComparisonStep(heldBuildInput)
        await setLatestComparison(fixture, fileId: "captured-before-hide")
        await acceptReviewViewerMode(fixture, sequence: 1, requiresCommittedSource: false)
        let activeBuildAttempt = try await facts.nextAdmittedAttempt()
        let buildingReviewTask = fixture.controller.activeReviewRefreshTask
        #expect(buildingReviewTask != nil)
        _ = try await heldBuildInput.firstArrival()

        // Act: retain a second initial intent while the first build is still active.
        await fixture.controller.handleCommittedProductReviewIntakeReady(
            BridgeProductReviewIntakeReadyRequest(
                reason: "background-warmup",
                streamId: nil
            ),
            productAdmission: fixture.productAdmission
        )

        // Act: hide Review and advance to a newer comparison while the old build is held.
        await acceptFileViewerMode(fixture, sequence: 2)
        await setLatestComparison(fixture, fileId: "latest-hidden")
        await fixture.controller.handleCommittedProductReviewIntakeReady(
            BridgeProductReviewIntakeReadyRequest(
                reason: "background-warmup",
                streamId: nil
            ),
            productAdmission: fixture.productAdmission
        )
        let retainedInput = BridgePaneReviewBuildAdmissionInput.retainedPackageBuild
        let retainedOpening = await facts.recorder.mark(.hiddenInput(retainedInput))
        heldBuildInput.release()
        await buildingReviewTask?.value
        let hiddenBuildOutcome = try await facts.attemptOutcome(for: activeBuildAttempt)
        #expect(hiddenBuildOutcome == .stale)
        guard hiddenBuildOutcome == .stale else {
            await fixture.finish()
            try await facts.finish()
            return
        }
        let retainedAdmissionStayedClosed = await facts.expectNoAdmission(
            for: retainedInput,
            from: retainedOpening
        )
        #expect(retainedAdmissionStayedClosed)
        guard retainedAdmissionStayedClosed else {
            await fixture.finish()
            try await facts.finish()
            return
        }

        // Assert: neither the stale build nor its refresh tail publishes or starts hidden Review work.
        #expect(await fixture.reviewProvider.recordedComparisonRequestsCount() == 1)
        #expect(fixture.controller.activeReviewRefreshTask == nil)
        #expect(fixture.controller.paneState.diff.packageMetadata == nil)
        #expect(fixture.controller.pendingReviewPackageBuildReasons.contains(.initialIntake))
        #expect(
            fixture.controller.refreshAdmissionCoordinator.diagnosticSnapshot.dirtyFact?
                .requiresReviewRefresh != true
        )

        // Act: showing Review starts one build against the latest desired input.
        await acceptReviewViewerMode(fixture, sequence: 3, requiresCommittedSource: false)
        #expect(try await facts.nextAttemptOutcome() == .succeeded)

        // Assert
        #expect(await fixture.reviewProvider.recordedComparisonRequestsCount() == 2)
        #expect(
            fixture.controller.paneState.diff.packageMetadata?.orderedItemIds
                == ["item-latest-hidden"]
        )
        await fixture.finish()
        try await facts.finish()
    }
}

@MainActor
private func bringPaneToForeground(_ fixture: RefreshAdmissionIntegrationFixture) async {
    await fixture.controller.applyBridgePaneActivity(.foreground)?.value
}

@MainActor
private func acceptFileViewerMode(
    _ fixture: RefreshAdmissionIntegrationFixture,
    sequence: Int
) async {
    await retainDesiredViewerSurface(.file, for: fixture)
    await acceptViewerMode(
        fixture,
        sequence: sequence,
        mode: .file,
        activeSource: BridgeActiveViewerSource(
            protocolId: .worktreeFile,
            streamId: "file:\(fixture.controller.paneId.uuidString)",
            generation: 1
        )
    )
}

@MainActor
private func acceptReviewViewerMode(
    _ fixture: RefreshAdmissionIntegrationFixture,
    sequence: Int,
    requiresCommittedSource: Bool
) async {
    await retainDesiredViewerSurface(.review, for: fixture)
    let activeSource: BridgeActiveViewerSource?
    if requiresCommittedSource,
        let publication = fixture.controller.reviewPublicationCoordinator
            .committedPublicationForReplay(productAdmission: fixture.productAdmission)
    {
        activeSource = BridgeActiveViewerSource(
            protocolId: .review,
            streamId: fixture.controller.reviewProtocolStreamId(),
            generation: publication.package.reviewGeneration.rawValue
        )
    } else {
        activeSource = nil
    }
    #expect(!requiresCommittedSource || activeSource != nil)
    await acceptViewerMode(
        fixture,
        sequence: sequence,
        mode: .review,
        activeSource: activeSource
    )
}

@MainActor
private func retainDesiredViewerSurface(
    _ surface: BridgeProductSurface,
    for fixture: RefreshAdmissionIntegrationFixture
) async {
    guard fixture.controller.retainedViewerSurface != surface else { return }
    #expect(fixture.controller.requestViewerSurface(surface))
    let selectionTransition = fixture.controller.surfaceSelectionTransitionTail
    #expect(await selectionTransition?.value == true)
    #expect(fixture.controller.retainedViewerSurface == surface)
}

@MainActor
private func acceptViewerMode(
    _ fixture: RefreshAdmissionIntegrationFixture,
    sequence: Int,
    mode: BridgeActiveViewerMode,
    activeSource: BridgeActiveViewerSource?
) async {
    await fixture.controller.handleCommittedProductActiveViewerModeUpdate(
        sessionId: fixture.controller.paneId.uuidString,
        sequence: sequence,
        mode: mode,
        activeSource: activeSource,
        productAdmission: fixture.productAdmission
    )
}

@MainActor
private func setLatestComparison(
    _ fixture: RefreshAdmissionIntegrationFixture,
    fileId: String
) async {
    let latestFile = makeBridgeEndpointChangedFile(
        fileId: fileId,
        path: "Sources/App/\(fileId).swift",
        sizeBytes: 120
    )
    await fixture.reviewProvider.setComparison(
        BridgeEndpointComparison(
            baseEndpoint: fixture.baseEndpoint,
            headEndpoint: fixture.headEndpoint,
            changedFiles: [latestFile]
        )
    )
}

@MainActor
private func setLatestContributionCapture(
    _ fixture: RefreshAdmissionIntegrationFixture,
    fileId: String
) async {
    let changedFile = makeBridgeEndpointChangedFile(
        fileId: fileId,
        path: "Sources/App/\(fileId).swift",
        sizeBytes: 120
    )
    await fixture.reviewProvider.setContributionCapture(
        BridgeContributionComparisonCapture(
            resolvedTargetOID: "resolved-\(fileId)",
            reviewedHeadOID: "head-\(fileId)",
            baseRole: .commonCommit,
            baseOID: "base-\(fileId)",
            comparison: BridgeEndpointComparison(
                baseEndpoint: fixture.baseEndpoint,
                headEndpoint: fixture.headEndpoint,
                changedFiles: [changedFile]
            )
        )
    )
}

@MainActor
private func postFilesystemEvent(
    _ fixture: RefreshAdmissionIntegrationFixture,
    path: String,
    batchSequence: UInt64
) async {
    await fixture.controller.handlePaneFilesystemContextEvent(
        .cwdSubtreeChanged(
            context: PaneFilesystemContext(
                paneId: PaneId(existingUUID: fixture.controller.paneId),
                repoId: fixture.headEndpoint.repoId,
                cwd: URL(fileURLWithPath: "/tmp/bridge-refresh-admission"),
                worktreeId: fixture.headEndpoint.worktreeId
            ),
            paths: [path],
            batchSeq: batchSequence
        )
    )
    await fixture.controller.worktreeRefreshDriver.awaitActiveFileOperations()
    await fixture.controller.worktreeRefreshDriver.awaitRetiringFileOperations()
}

private struct BridgePaneReviewBuildAdmissionTrace {
    let source:
        LocalFactSource<
            BridgePaneReviewBuildAdmissionScope,
            BridgePaneReviewBuildAdmissionFact
        >
    let recorder:
        FactRecorder<
            BridgePaneReviewBuildAdmissionScope,
            BridgePaneReviewBuildAdmissionFact
        >

    init() throws {
        let vocabulary = FactVocabulary<
            BridgePaneReviewBuildAdmissionScope,
            BridgePaneReviewBuildAdmissionFact
        >(
            describeScope: { String(describing: $0) },
            describeFact: { String(describing: $0) },
            isClosing: isReviewBuildAdmissionFactClosing
        )
        let source = LocalFactSource<
            BridgePaneReviewBuildAdmissionScope,
            BridgePaneReviewBuildAdmissionFact
        >(vocabulary: vocabulary)
        self.source = source
        recorder = try source.attach()
    }

    func expectNoAdmission(
        for input: BridgePaneReviewBuildAdmissionInput,
        from opening: OpeningPosition<BridgePaneReviewBuildAdmissionScope>
    ) async -> Bool {
        do {
            try await recorder.expectNone(
                of: { fact in
                    if case .admitted = fact { true } else { false }
                },
                "Review build admission while hidden",
                from: opening,
                closedBy: { $0 == .deferredHidden(input: input) }
            )
            return true
        } catch {
            return false
        }
    }

    func nextAdmittedAttempt() async throws -> UUID {
        let scope = try await recorder.expectNextOperation(
            matching: { if case .attempt = $0 { true } else { false } },
            opening: { if case .admitted = $0 { true } else { false } },
            "Review package build admission"
        )
        guard case .attempt(let attempt) = scope else {
            throw BridgePaneReviewBuildAdmissionTraceError.expectedAttemptScope
        }
        guard
            case .admitted(attempt) = try await recorder.expectNext(
                in: scope,
                where: { $0 == .admitted(attempt: attempt) },
                "admitted Review package build"
            )
        else {
            throw BridgePaneReviewBuildAdmissionTraceError.expectedAdmission
        }
        return attempt
    }

    func nextAttemptOutcome() async throws -> BridgePaneReviewBuildAttemptOutcome {
        let attempt = try await nextAdmittedAttempt()
        return try await attemptOutcome(for: attempt)
    }

    func attemptOutcome(
        for attempt: UUID
    ) async throws -> BridgePaneReviewBuildAttemptOutcome {
        guard
            case .attemptEnded(_, let outcome) = try await recorder.expectNext(
                in: .attempt(attempt),
                where: {
                    if case .attemptEnded(let endedAttempt, _) = $0 { endedAttempt == attempt } else { false }
                },
                "Review package build attempt end"
            )
        else {
            throw BridgePaneReviewBuildAdmissionTraceError.expectedAttemptEnd
        }
        return outcome
    }

    func finish() async throws {
        source.end()
        try await recorder.finish()
    }
}

private func isReviewBuildAdmissionFactClosing(
    scope: BridgePaneReviewBuildAdmissionScope,
    fact: BridgePaneReviewBuildAdmissionFact
) -> Bool {
    switch (scope, fact) {
    case (.hiddenInput(let input), .deferredHidden(let closedInput)):
        input == closedInput
    case (.hiddenInput, .attemptEnded):
        true
    case (.attempt(let scopeAttempt), .attemptEnded(let attempt, _)):
        scopeAttempt == attempt
    default:
        false
    }
}

private enum BridgePaneReviewBuildAdmissionTraceError: Error {
    case expectedAttemptScope
    case expectedAdmission
    case expectedAttemptEnd
}
