import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import os.log

private let bridgeDiffCommandLogger = Logger(subsystem: "com.agentstudio", category: "BridgeDiffCommands")

@MainActor
extension BridgePaneController: BridgeRuntimeCommandHandling {
    package func scheduleInitialReviewPackageLoadIfPossible() {
        guard paneState.diff.status != .error else {
            scheduleRetainedReviewPackageBuildIfPossible()
            return
        }
        scheduleInitialReviewPackageLoadIfPossible(reason: .initialIntake)
    }

    func scheduleInitialReviewPackageLoadIfPossible(reason: BridgeReviewPackageBuildReason) {
        guard case .workspace = bridgePaneState.source,
            runtime.metadata.worktreeId != nil,
            paneState.diff.status == .idle || paneState.diff.status == .loading
                || paneState.diff.status == .error,
            paneState.diff.packageMetadata == nil
        else { return }
        guard refreshAdmissionCoordinator.acquireForegroundWork() != nil else {
            pendingReviewPackageBuildReasons.insert(reason)
            return
        }
        guard activeReviewRefreshTask == nil else { return }
        pendingReviewPackageBuildReasons.insert(reason)
        scheduleRetainedReviewPackageBuildIfPossible()
    }

    /// Full reload for a typed product resync request on an already-loaded pane.
    func scheduleReviewPackageReloadForProductResync() {
        scheduleReviewPackageReloadForProductResync(reason: .productResync)
    }

    func scheduleReviewPackageReloadForProductResync(reason: BridgeReviewPackageBuildReason) {
        pendingReviewPackageBuildReasons.insert(reason)
        guard refreshAdmissionCoordinator.acquireForegroundWork() != nil else {
            refreshAdmissionCoordinator.recordInvalidation(
                fileChangeset: nil,
                requiresReviewRefresh: true
            )
            return
        }
        scheduleRetainedReviewPackageBuildIfPossible()
    }

    func scheduleRetainedReviewPackageBuildIfPossible() {
        guard !pendingReviewPackageBuildReasons.isEmpty,
            activeReviewRefreshTask == nil,
            refreshAdmissionCoordinator.acquireForegroundWork() != nil,
            case .workspace = bridgePaneState.source,
            let worktreeId = runtime.metadata.worktreeId
        else { return }

        let shouldLoadInitialPackage =
            paneState.diff.packageMetadata == nil
            && (paneState.diff.status == .idle || paneState.diff.status == .loading
                || paneState.diff.status == .error)
        guard
            shouldLoadInitialPackage || paneState.diff.packageMetadata != nil
                || pendingReviewPackageBuildReasons.contains(.productResync)
        else { return }

        activeReviewRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if shouldLoadInitialPackage {
                _ = await self.loadInitialReviewPackageIfPossible(correlationId: nil)
            } else {
                _ = await self.loadReviewPackage(worktreeId: worktreeId, correlationId: nil)
            }
            self.activeReviewRefreshTask = nil
            self.scheduleRetainedReviewPackageBuildIfPossible()
            self.scheduleWorktreeProductCatchUpIfPossible()
        }
    }

    /// Bootstraps the review package for any workspace-backed Bridge pane, not
    /// only `.diffViewer` panes. A pane hosts both viewer modes in one webview
    /// and the browser can switch into review mode regardless of the pane's
    /// fixed `panelKind`; the review viewer is intake-only and never requests
    /// the package itself, so a `.fileViewer` pane that skipped this load would
    /// show a blank review surface on switch.
    func loadInitialReviewPackageIfPossible(correlationId: UUID?) async -> ActionResult? {
        guard case .workspace = bridgePaneState.source,
            let worktreeId = runtime.metadata.worktreeId,
            paneState.diff.status == .idle || paneState.diff.status == .loading
                || paneState.diff.status == .error,
            paneState.diff.packageMetadata == nil
        else {
            return nil
        }

        return await loadReviewPackage(worktreeId: worktreeId, correlationId: correlationId)
    }

    package func handleDiffCommand(
        _ command: DiffCommand,
        commandId: UUID,
        correlationId: UUID?
    ) async -> ActionResult {
        guard let foregroundWorkAdmission = refreshAdmissionCoordinator.acquireForegroundWork(),
            let productAdmission = productAdmissionGate.acquire()
        else {
            return .failure(.invalidPayload(description: "Bridge pane is closed"))
        }
        switch command {
        case .loadDiff(let artifact):
            return await handleLoadDiffCommand(
                artifact: artifact,
                commandId: commandId,
                correlationId: correlationId,
                productAdmission: productAdmission,
                foregroundWorkAdmission: foregroundWorkAdmission
            )
        }
    }

    struct ReviewPackageLoadReset {
        let reviewGeneration: BridgeReviewGeneration
    }

    private struct ReviewPackageLoadCommit {
        let reset: ReviewPackageLoadReset
        let load: BridgeReviewPackageLoadData
        let summary: BridgeReviewPackageSummary
        let commandId: UUID
        let correlationId: UUID?
        let productAdmission: BridgeProductAdmissionContext
        let foregroundWorkAdmission: BridgePaneRefreshWorkAdmission
        let traceContext: BridgeTraceContext?
    }

    private func handleLoadDiffCommand(
        artifact: DiffArtifact,
        commandId: UUID,
        correlationId: UUID?,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission
    ) async -> ActionResult {
        let packageTraceContext = makeRootTraceContext()
        guard
            let reset = await beginReviewPackageLoad(
                artifact: artifact,
                productAdmission: productAdmission,
                foregroundWorkAdmission: foregroundWorkAdmission
            )
        else {
            return .failure(.invalidPayload(description: "Bridge pane is closed"))
        }
        var reviewLoadStage = "designation"
        let buildReason = consumePendingReviewPackageBuildReason(default: .initialIntake)
        do {
            try await adoptInitialContributionTargetIfEligible(
                reset: reset,
                productAdmission: productAdmission,
                foregroundWorkAdmission: foregroundWorkAdmission
            )
            let constructionResult = try await loadReviewPackageResult(
                artifact: artifact,
                reviewGeneration: reset.reviewGeneration,
                buildReason: buildReason,
                reviewLoadStage: &reviewLoadStage,
                packageTraceContext: packageTraceContext
            )
            let result = constructionResult.result
            guard
                acceptReviewPackageLoadResult(
                    reset: reset,
                    productAdmission: productAdmission,
                    foregroundWorkAdmission: foregroundWorkAdmission,
                    packageTraceContext: packageTraceContext
                )
            else {
                await constructionResult.releaseArtifactPin()
                pendingReviewPackageBuildReasons.insert(buildReason)
                return .failure(.invalidPayload(description: "Stale bridge review load"))
            }
            let load = try await makeReviewPackageLoadData(
                constructionResult: constructionResult,
                contentHandles: result.registeredContentHandles,
                productAdmission: productAdmission,
                reviewLoadStage: &reviewLoadStage,
                packageTraceContext: packageTraceContext
            )
            let contentRegisterStart = ContinuousClock.now
            await recordReviewContentRegisterTelemetry(
                traceContext: packageTraceContext,
                contentRegisterStart: contentRegisterStart
            )
            guard
                isReviewPackageLoadCurrent(
                    reset: reset,
                    productAdmission: productAdmission,
                    foregroundWorkAdmission: foregroundWorkAdmission
                )
            else {
                await load.releaseArtifactPin()
                pendingReviewPackageBuildReasons.insert(buildReason)
                return .failure(.invalidPayload(description: "Stale bridge review load"))
            }
            return await completeReviewPackageLoad(
                ReviewPackageLoadCommit(
                    reset: reset,
                    load: load,
                    summary: result.package.summary,
                    commandId: commandId,
                    correlationId: correlationId,
                    productAdmission: productAdmission,
                    foregroundWorkAdmission: foregroundWorkAdmission,
                    traceContext: packageTraceContext
                ),
                buildReason: buildReason
            )
        } catch BridgeProviderFailure.providerUnavailable {
            guard foregroundWorkAdmission.withValidAdmission({ true }) == true else {
                pendingReviewPackageBuildReasons.insert(buildReason)
                return .failure(.invalidPayload(description: "Stale bridge review load"))
            }
            guard
                await retainCommittedReviewOrSetInitialFailure(
                    "providerUnavailable",
                    reset: reset,
                    productAdmission: productAdmission,
                    foregroundWorkAdmission: foregroundWorkAdmission
                )
            else {
                return .failure(.invalidPayload(description: "Bridge pane is closed"))
            }
            return .failure(.backendUnavailable(backend: "BridgeReviewSourceProvider"))
        } catch {
            return await reviewPackageLoadFailureResult(
                for: error,
                reset: reset,
                reviewLoadStage: reviewLoadStage,
                productAdmission: productAdmission,
                foregroundWorkAdmission: foregroundWorkAdmission,
                buildReason: buildReason
            )
        }
    }

    private func completeReviewPackageLoad(
        _ commit: ReviewPackageLoadCommit,
        buildReason: BridgeReviewPackageBuildReason
    ) async -> ActionResult {
        guard
            case .committed(let deliveryDisposition) =
                await commitReviewPackageLoadAndPublishDiffLoaded(commit)
        else {
            if commit.foregroundWorkAdmission.withValidAdmission({ true }) == nil {
                pendingReviewPackageBuildReasons.insert(buildReason)
            }
            guard
                await retainCommittedReviewOrSetInitialFailure(
                    "loadFailed:publication",
                    reset: commit.reset,
                    productAdmission: commit.productAdmission,
                    foregroundWorkAdmission: commit.foregroundWorkAdmission
                )
            else {
                return .failure(.invalidPayload(description: "Bridge pane is closed"))
            }
            return .failure(.invalidPayload(description: "Failed to load bridge review package"))
        }
        if deliveryDisposition == .failed {
            await productSchemeProvider?.resetCurrentReviewSubscriptionsForUnavailableSource(
                productAdmission: commit.productAdmission,
                foregroundWorkAdmission: commit.foregroundWorkAdmission
            )
        }
        return .success(commandId: commit.commandId)
    }

    private func reviewPackageLoadFailureResult(
        for error: any Error,
        reset: ReviewPackageLoadReset,
        reviewLoadStage: String,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission,
        buildReason: BridgeReviewPackageBuildReason
    ) async -> ActionResult {
        guard foregroundWorkAdmission.withValidAdmission({ true }) == true else {
            pendingReviewPackageBuildReasons.insert(buildReason)
            return .failure(.invalidPayload(description: "Stale bridge review load"))
        }
        let failureSummary = Self.reviewPackageLoadFailureSummary(for: error, stage: reviewLoadStage)
        bridgeDiffCommandLogger.error(
            "Bridge review package load failed: \(failureSummary, privacy: .public)"
        )
        guard
            await retainCommittedReviewOrSetInitialFailure(
                failureSummary,
                reset: reset,
                productAdmission: productAdmission,
                foregroundWorkAdmission: foregroundWorkAdmission
            )
        else {
            return .failure(.invalidPayload(description: "Bridge pane is closed"))
        }
        return .failure(.invalidPayload(description: "Failed to load bridge review package"))
    }

    private func acceptReviewPackageLoadResult(
        reset: ReviewPackageLoadReset,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission,
        packageTraceContext: BridgeTraceContext?
    ) -> Bool {
        foregroundWorkAdmission.withValidAdmission {
            productAdmission.withValidAdmission {
                guard reset.reviewGeneration == nextReviewGeneration else { return false }
                lastReviewPackageTraceContext = packageTraceContext
                return true
            }
        }.flatMap { $0 } == true
    }

    func isReviewPackageLoadCurrent(
        reset: ReviewPackageLoadReset,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission
    ) -> Bool {
        foregroundWorkAdmission.withValidAdmission {
            productAdmission.withValidAdmission {
                reset.reviewGeneration == nextReviewGeneration
            }
        }.flatMap { $0 } == true
    }

    private func commitReviewPackageLoadAndPublishDiffLoaded(
        _ request: ReviewPackageLoadCommit
    ) async -> BridgeReviewPackageLoadCommitDisposition {
        let commitDisposition = await commitReviewPackageLoad(
            request.load,
            expectedReviewGeneration: request.reset.reviewGeneration,
            productAdmission: request.productAdmission,
            traceContext: request.traceContext,
            foregroundWorkAdmission: request.foregroundWorkAdmission
        )
        guard case .committed = commitDisposition else { return .rejected }
        let didPublishDiffLoaded =
            request.foregroundWorkAdmission.withValidAdmission {
                request.productAdmission.withValidAdmission {
                    ingestRuntimeEvent(
                        .diff(.diffLoaded(stats: Self.diffStats(from: request.summary))),
                        commandId: request.commandId,
                        correlationId: request.correlationId
                    )
                    return true
                }
            }.flatMap { $0 } == true
        return didPublishDiffLoaded ? commitDisposition : .rejected
    }

    private func beginReviewPackageLoad(
        artifact: DiffArtifact,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission
    ) async -> ReviewPackageLoadReset? {
        guard
            let reset = foregroundWorkAdmission.withValidAdmission({
                productAdmission.withValidAdmission {
                    if reviewPublicationCoordinator.diagnosticSnapshot.active == nil {
                        paneState.diff.setStatus(.loading)
                    }
                    paneState.diff.advanceEpoch()
                    let reviewGeneration =
                        pendingComparisonReviewGeneration
                        ?? nextReviewGeneration.next()
                    pendingComparisonReviewGeneration = nil
                    nextReviewGeneration = reviewGeneration
                    return ReviewPackageLoadReset(
                        reviewGeneration: reviewGeneration
                    )
                }
            }).flatMap({ $0 })
        else {
            return nil
        }
        if case .workspace(_, let baseline) = bridgePaneState.source,
            let activeTarget = baseline?.contributionTarget
        {
            refreshAdmissionCoordinator.beginReviewComparisonAttempt(
                activeTarget: activeTarget,
                reviewGeneration: reset.reviewGeneration.rawValue
            )
            _ = scheduleProductPresentationPublication()
        }
        return reset
    }

    private func loadReviewPackageResult(
        artifact: DiffArtifact,
        reviewGeneration: BridgeReviewGeneration,
        buildReason: BridgeReviewPackageBuildReason,
        reviewLoadStage: inout String,
        packageTraceContext: BridgeTraceContext?
    ) async throws -> BridgeReviewPackageConstructionResult {
        let unresolvedRequest = makeReviewPipelineRequest(
            artifact: artifact,
            reviewGeneration: reviewGeneration
        )
        let packageBuildStart = ContinuousClock.now
        let constructionResult: BridgeReviewPackageConstructionResult
        reviewLoadStage = "package"
        let request = try await resolveContributionRequestIfNeeded(unresolvedRequest)
        constructionResult = try await acquireReviewPackage(request)
        await recordSwiftTelemetry(
            name: "performance.bridge.swift.package_build",
            phase: "package_build",
            priorityHint: .cold,
            traceContext: packageTraceContext,
            stringAttributes: [
                "agentstudio.bridge.package_build.reason": buildReason.rawValue
            ],
            durationMilliseconds: AgentStudioPerformanceTraceRecorder.milliseconds(
                from: packageBuildStart.duration(to: ContinuousClock.now)
            )
        )
        return constructionResult
    }

    private func makeReviewPackageLoadData(
        constructionResult: BridgeReviewPackageConstructionResult,
        contentHandles: [BridgeContentHandle],
        productAdmission: BridgeProductAdmissionContext,
        fallbackRevision: Int? = nil,
        reviewLoadStage: inout String,
        packageTraceContext: BridgeTraceContext?
    ) async throws -> BridgeReviewPackageLoadData {
        let result = constructionResult.result
        let deltaBuildStart = ContinuousClock.now
        reviewLoadStage = "delta"
        let changeIndexLoad: BridgeChangeIndexPreparedLoad
        do {
            changeIndexLoad = try await reviewChangeIndex.prepareExplicitLoad(
                result.package,
                fallbackRevision: fallbackRevision,
                productAdmission: productAdmission
            )
        } catch {
            await constructionResult.releaseArtifactPin()
            throw error
        }
        await recordSwiftTelemetry(
            name: "performance.bridge.swift.delta_build",
            phase: "delta_build",
            priorityHint: .warm,
            traceContext: makeChildTraceContext(parent: packageTraceContext),
            durationMilliseconds: AgentStudioPerformanceTraceRecorder.milliseconds(
                from: deltaBuildStart.duration(to: ContinuousClock.now)
            )
        )
        reviewLoadStage = "publicationPrepare"
        guard
            let preparedPublication = await BridgeReviewPreparedPublication.prepare(
                BridgeReviewPublicationCandidate(
                    package: changeIndexLoad.package,
                    delta: changeIndexLoad.delta,
                    contentHandles: contentHandles,
                    artifactPin: constructionResult.artifactPin
                )
            )
        else {
            await constructionResult.releaseArtifactPin()
            throw BridgeProviderFailure.providerFailed(
                message: "Invalid bridge Review publication candidate"
            )
        }
        guard productAdmission.withValidAdmission({ true }) == true else {
            await constructionResult.releaseArtifactPin()
            throw BridgeChangeIndexError.admissionClosed
        }
        return BridgeReviewPackageLoadData(
            preparedPublication: preparedPublication,
            changeIndexLoad: changeIndexLoad
        )
    }

    private func recordReviewContentRegisterTelemetry(
        traceContext: BridgeTraceContext?,
        contentRegisterStart: ContinuousClock.Instant
    ) async {
        await recordSwiftTelemetry(
            name: "performance.bridge.swift.content_register",
            phase: "content_register",
            priorityHint: .cold,
            traceContext: makeChildTraceContext(parent: traceContext),
            durationMilliseconds: AgentStudioPerformanceTraceRecorder.milliseconds(
                from: contentRegisterStart.duration(to: ContinuousClock.now)
            )
        )
    }

    private func loadReviewPackage(worktreeId: UUID, correlationId: UUID?) async -> ActionResult {
        let commandId = UUID()
        return await handleDiffCommand(
            .loadDiff(
                DiffArtifact(
                    diffId: UUIDv7.generate(),
                    worktreeId: worktreeId,
                    patchData: Data()
                )
            ),
            commandId: commandId,
            correlationId: correlationId
        )
    }

    func handlePaneFilesystemContextEvent(_ event: PaneFilesystemContextEvent) async {
        guard shouldRefreshReviewPackage(for: event) else { return }
        switch event {
        case .cwdSubtreeChanged(let context, let paths, let batchSequence):
            await handleWorktreeProductInvalidation(
                .filesChanged(
                    FileChangeset(
                        worktreeId: context.worktreeId,
                        repoId: context.repoId,
                        rootPath: context.cwd,
                        paths: Array(paths),
                        timestamp: .now,
                        batchSeq: batchSequence
                    )
                )
            )
        case .gitWorkingTreeInCwd(_, let staged, let unstaged, let untracked):
            await handleWorktreeProductInvalidation(
                .statusChanged(
                    GitWorkingTreeStatus(
                        summary: GitWorkingTreeSummary(
                            changed: unstaged,
                            staged: staged,
                            untracked: untracked
                        ),
                        branch: nil,
                        origin: nil
                    )
                )
            )
        }
    }

    func refreshCurrentReviewPackage(
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission,
        productAdmission: BridgeProductAdmissionContext
    ) async -> BridgePaneRefreshCatchUpOutcome {
        guard foregroundWorkAdmission.withValidAdmission({ true }) == true else { return .stale }
        guard
            let currentPublication = reviewPublicationCoordinator.committedPublicationForReplay(
                productAdmission: productAdmission
            )
        else {
            pendingReviewPackageBuildReasons.insert(.filesystemRefresh)
            return .succeeded
        }
        let currentPackage = currentPublication.package
        guard
            let refreshGeneration = beginReviewPackageRefresh(
                currentPackage: currentPackage,
                productAdmission: productAdmission,
                foregroundWorkAdmission: foregroundWorkAdmission
            )
        else {
            return .stale
        }
        if case .workspace(_, let baseline) = bridgePaneState.source,
            let activeTarget = baseline?.contributionTarget
        {
            refreshAdmissionCoordinator.beginReviewComparisonAttempt(
                activeTarget: activeTarget,
                reviewGeneration: refreshGeneration.rawValue
            )
            _ = scheduleProductPresentationPublication()
        }
        do {
            _ = try await resolveAndPublishReviewComparisonDefaultTargetIfCurrent(
                reset: ReviewPackageLoadReset(reviewGeneration: refreshGeneration),
                productAdmission: productAdmission,
                foregroundWorkAdmission: foregroundWorkAdmission
            )
        } catch is CancellationError {
            return .stale
        } catch {
            return .failed
        }
        return await performReviewPackageRefresh(
            currentPublication: currentPublication,
            refreshGeneration: refreshGeneration,
            foregroundWorkAdmission: foregroundWorkAdmission,
            productAdmission: productAdmission
        )
    }

    private func performReviewPackageRefresh(
        currentPublication: BridgeReviewCommittedPublication,
        refreshGeneration: BridgeReviewGeneration,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission,
        productAdmission: BridgeProductAdmissionContext
    ) async -> BridgePaneRefreshCatchUpOutcome {
        let currentPackage = currentPublication.package
        do {
            let (constructionResult, packageTraceContext) = try await loadReviewPackageForRefresh(
                currentPackage,
                reviewGeneration: refreshGeneration
            )
            let result = constructionResult.result
            guard
                !Task.isCancelled,
                foregroundWorkAdmission.withValidAdmission({ true }) == true,
                refreshGeneration == nextReviewGeneration,
                reviewPublicationCoordinator.committedPublicationForReplay(
                    productAdmission: productAdmission
                )?.publicationId == currentPublication.publicationId,
                productAdmission.withValidAdmission({
                    lastReviewPackageTraceContext = packageTraceContext
                    return true
                }) == true
            else {
                await constructionResult.releaseArtifactPin()
                return .stale
            }

            var reviewLoadStage = "delta"
            let load = try await makeReviewPackageLoadData(
                constructionResult: constructionResult,
                contentHandles: result.registeredContentHandles,
                productAdmission: productAdmission,
                fallbackRevision: currentPackage.revision,
                reviewLoadStage: &reviewLoadStage,
                packageTraceContext: packageTraceContext
            )
            guard
                !Task.isCancelled,
                foregroundWorkAdmission.withValidAdmission({ true }) == true,
                refreshGeneration == nextReviewGeneration,
                reviewPublicationCoordinator.isCurrentPublication(
                    publicationId: currentPublication.publicationId,
                    productAdmission: productAdmission
                )
            else {
                await load.releaseArtifactPin()
                return .stale
            }
            guard !Self.isUnchangedSameLineageLoad(load, currentPublication: currentPublication)
            else {
                await load.releaseArtifactPin()
                settleReviewComparisonAttempt(
                    reviewGeneration: refreshGeneration,
                    package: currentPackage
                )
                return .succeeded
            }
            let contentRegisterStart = ContinuousClock.now
            await recordSwiftTelemetry(
                name: "performance.bridge.swift.content_register",
                phase: "content_register",
                priorityHint: .cold,
                traceContext: makeChildTraceContext(parent: packageTraceContext),
                durationMilliseconds: AgentStudioPerformanceTraceRecorder.milliseconds(
                    from: contentRegisterStart.duration(to: ContinuousClock.now)
                )
            )
            let disposition = await commitReviewPackageLoad(
                load,
                expectedReviewGeneration: refreshGeneration,
                productAdmission: productAdmission,
                traceContext: packageTraceContext,
                foregroundWorkAdmission: foregroundWorkAdmission
            )
            guard case .committed = disposition else {
                return Task.isCancelled || foregroundWorkAdmission.withValidAdmission({ true }) == nil
                    ? .stale
                    : .failed
            }
            return .succeeded
        } catch BridgeProviderFailure.providerUnavailable {
            bridgeDiffCommandLogger.debug("Skipped bridge review refresh: provider unavailable")
            failReviewComparisonAttempt(
                reviewGeneration: refreshGeneration,
                failureKind: "providerUnavailable",
                retryable: true
            )
            return .failed
        } catch is CancellationError {
            return .stale
        } catch {
            bridgeDiffCommandLogger.debug(
                "Skipped bridge review refresh: \(String(describing: error), privacy: .private)"
            )
            failReviewComparisonAttempt(
                reviewGeneration: refreshGeneration,
                failureKind: Self.reviewPackageLoadFailureSummary(for: error, stage: "package"),
                retryable: true
            )
            return foregroundWorkAdmission.withValidAdmission({ true }) == nil ? .stale : .failed
        }
    }

    private func settleReviewComparisonAttempt(
        reviewGeneration: BridgeReviewGeneration,
        package: BridgeReviewPackage
    ) {
        refreshAdmissionCoordinator.settleReviewComparisonAttempt(
            reviewGeneration: reviewGeneration.rawValue,
            displayedSnapshotIdentity: BridgePaneReviewDisplayedSnapshotIdentity(
                packageId: package.packageId,
                reviewGeneration: package.reviewGeneration.rawValue,
                revision: package.revision
            )
        )
        _ = scheduleProductPresentationPublication()
    }

    private func failReviewComparisonAttempt(
        reviewGeneration: BridgeReviewGeneration,
        failureKind: String,
        retryable: Bool
    ) {
        refreshAdmissionCoordinator.failReviewComparisonAttempt(
            reviewGeneration: reviewGeneration.rawValue,
            failureKind: failureKind,
            retryable: retryable
        )
        _ = scheduleProductPresentationPublication()
    }

    private func beginReviewPackageRefresh(
        currentPackage: BridgeReviewPackage,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission
    ) -> BridgeReviewGeneration? {
        foregroundWorkAdmission.withValidAdmission {
            productAdmission.withValidAdmission {
                guard case .workspace(_, let baseline) = bridgePaneState.source,
                    baseline?.contributionTarget != nil
                else {
                    return currentPackage.reviewGeneration
                }
                let reviewGeneration =
                    pendingComparisonReviewGeneration
                    ?? nextReviewGeneration.next()
                pendingComparisonReviewGeneration = nil
                nextReviewGeneration = reviewGeneration
                return reviewGeneration
            }
        }.flatMap { $0 }
    }

    private func loadReviewPackageForRefresh(
        _ currentPackage: BridgeReviewPackage,
        reviewGeneration: BridgeReviewGeneration
    ) async throws -> (
        result: BridgeReviewPackageConstructionResult,
        traceContext: BridgeTraceContext?
    ) {
        let packageTraceContext = makeRootTraceContext()
        let packageBuildStart = ContinuousClock.now
        let buildReason = consumePendingReviewPackageBuildReason(default: .filesystemRefresh)
        let unresolvedRequest = makeReviewRefreshPipelineRequest(
            currentPackage: currentPackage,
            reviewGeneration: reviewGeneration
        )
        let request = try await resolveContributionRequestIfNeeded(unresolvedRequest)
        let result = try await acquireReviewPackage(request)
        await recordSwiftTelemetry(
            name: "performance.bridge.swift.package_build",
            phase: "package_build",
            priorityHint: .cold,
            traceContext: packageTraceContext,
            stringAttributes: [
                "agentstudio.bridge.package_build.reason": buildReason.rawValue
            ],
            durationMilliseconds: AgentStudioPerformanceTraceRecorder.milliseconds(
                from: packageBuildStart.duration(to: ContinuousClock.now)
            )
        )
        return (result, packageTraceContext)
    }

    private func makeReviewRefreshPipelineRequest(
        currentPackage: BridgeReviewPackage,
        reviewGeneration: BridgeReviewGeneration
    ) -> BridgeReviewPipelineRequest {
        guard case .workspace(_, let baseline) = bridgePaneState.source,
            baseline?.contributionTarget != nil
        else {
            return BridgeReviewPipelineRequest(
                packageId: currentPackage.packageId,
                query: currentPackage.query,
                baseEndpoint: currentPackage.baseEndpoint,
                headEndpoint: currentPackage.headEndpoint,
                checkpointIds: currentPackage.groups.map(\.groupId),
                reviewGeneration: reviewGeneration,
                generatedAtUnixMilliseconds: Int64(Date().timeIntervalSince1970 * 1000)
            )
        }

        let artifact = DiffArtifact(
            diffId: UUIDv7.generate(),
            worktreeId: currentPackage.query.worktreeId,
            patchData: Data()
        )
        let endpoints = makeReviewEndpoints(
            for: artifact,
            repoId: currentPackage.query.repoId
        )
        let query = BridgeReviewQuery(
            queryId: currentPackage.query.queryId,
            queryKind: currentPackage.query.queryKind,
            repoId: currentPackage.query.repoId,
            worktreeId: currentPackage.query.worktreeId,
            baseEndpointId: endpoints.base.endpointId,
            headEndpointId: endpoints.head.endpointId,
            comparisonSemantics: endpoints.comparisonSemantics,
            pathScope: currentPackage.query.pathScope,
            fileTarget: currentPackage.query.fileTarget,
            viewFilter: currentPackage.query.viewFilter,
            grouping: currentPackage.query.grouping,
            provenanceFilter: currentPackage.query.provenanceFilter
        )
        return BridgeReviewPipelineRequest(
            packageId: currentPackage.packageId,
            query: query,
            baseEndpoint: endpoints.base,
            headEndpoint: endpoints.head,
            checkpointIds: currentPackage.groups.map(\.groupId),
            reviewGeneration: reviewGeneration,
            generatedAtUnixMilliseconds: Int64(Date().timeIntervalSince1970 * 1000)
        )
    }

    private static func isUnchangedSameLineageLoad(
        _ load: BridgeReviewPackageLoadData,
        currentPublication: BridgeReviewCommittedPublication
    ) -> Bool {
        let currentPackage = currentPublication.package
        return load.delta == nil
            && load.package.packageId == currentPackage.packageId
            && load.package.reviewGeneration == currentPackage.reviewGeneration
            && load.package.query.queryId == currentPackage.query.queryId
            && load.package.revision == currentPackage.revision
    }

    private func retainCommittedReviewOrSetInitialFailure(
        _ failureSummary: String,
        reset: ReviewPackageLoadReset,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission
    ) async -> Bool {
        let failureDisposition =
            foregroundWorkAdmission.withValidAdmission {
                productAdmission.withValidAdmission {
                    guard reset.reviewGeneration == nextReviewGeneration else {
                        return (accepted: false, isInitial: false)
                    }
                    guard reviewPublicationCoordinator.diagnosticSnapshot.active == nil else {
                        return (accepted: true, isInitial: false)
                    }
                    paneState.diff.setStatus(.error, error: failureSummary)
                    return (accepted: true, isInitial: true)
                } ?? (accepted: false, isInitial: false)
            } ?? (accepted: false, isInitial: false)
        guard failureDisposition.accepted else { return false }
        failReviewComparisonAttempt(
            reviewGeneration: reset.reviewGeneration,
            failureKind: failureSummary,
            retryable: true
        )
        if failureDisposition.isInitial {
            await productSchemeProvider?.resetCurrentReviewSubscriptionsForUnavailableSource(
                productAdmission: productAdmission,
                foregroundWorkAdmission: foregroundWorkAdmission
            )
        }
        return true
    }

    private static func diffStats(from summary: BridgeReviewPackageSummary) -> DiffStats {
        DiffStats(
            filesChanged: summary.filesChanged,
            insertions: summary.additions,
            deletions: summary.deletions
        )
    }

    private func makeReviewPipelineRequest(
        artifact: DiffArtifact,
        reviewGeneration: BridgeReviewGeneration
    ) -> BridgeReviewPipelineRequest {
        let repoId = reviewRepoId(for: artifact)
        let endpoints = makeReviewEndpoints(
            for: artifact,
            repoId: repoId
        )
        let query = BridgeReviewQuery(
            queryId: reviewSourceIdentity(for: artifact),
            queryKind: .compare,
            repoId: repoId,
            worktreeId: artifact.worktreeId,
            baseEndpointId: endpoints.base.endpointId,
            headEndpointId: endpoints.head.endpointId,
            comparisonSemantics: endpoints.comparisonSemantics,
            pathScope: endpoints.pathScope,
            fileTarget: nil,
            viewFilter: BridgeViewFilter(
                showHiddenFiles: true,
                showBinaryFiles: true,
                showLargeFiles: true
            ),
            grouping: BridgeChangeGrouping(kind: .flat),
            provenanceFilter: BridgeProvenanceFilter()
        )
        return BridgeReviewPipelineRequest(
            packageId: "package-\(artifact.diffId.uuidString)",
            query: query,
            baseEndpoint: endpoints.base,
            headEndpoint: endpoints.head,
            checkpointIds: [],
            reviewGeneration: reviewGeneration,
            generatedAtUnixMilliseconds: Int64(Date().timeIntervalSince1970 * 1000)
        )
    }

    private func reviewSourceIdentity(for artifact: DiffArtifact) -> String {
        "query-\(artifact.diffId.uuidString)"
    }

    func reviewProtocolStreamId() -> String {
        "review:\(paneId.uuidString)"
    }

    private func shouldRefreshReviewPackage(for event: PaneFilesystemContextEvent) -> Bool {
        guard let currentPackage = paneState.diff.packageMetadata else { return false }
        let context: PaneFilesystemContext
        switch event {
        case .cwdSubtreeChanged(let eventContext, let paths, _):
            guard !paths.isEmpty else { return false }
            context = eventContext
        case .gitWorkingTreeInCwd(let eventContext, _, _, _):
            context = eventContext
        }
        return context.paneId.uuid == paneId
            && context.worktreeId == currentPackage.query.worktreeId
    }

    private func reviewRepoId(for artifact: DiffArtifact) -> UUID {
        runtime.metadata.facets.repoId ?? artifact.worktreeId
    }

}
