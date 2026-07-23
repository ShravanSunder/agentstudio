import Foundation
import os.log

private let bridgeDiffCommandLogger = Logger(subsystem: "com.agentstudio", category: "BridgeDiffCommands")

@MainActor
extension BridgePaneController: BridgeRuntimeCommandHandling {
    func scheduleInitialReviewPackageLoadIfPossible() {
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

    func handleDiffCommand(
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

    private struct ReviewPackageLoadReset {
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
        var reviewLoadStage = "request"
        let buildReason = consumePendingReviewPackageBuildReason(default: .initialIntake)
        do {
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

    private func isReviewPackageLoadCurrent(
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
                    let reviewGeneration = nextReviewGeneration.next()
                    nextReviewGeneration = reviewGeneration
                    return ReviewPackageLoadReset(
                        reviewGeneration: reviewGeneration
                    )
                }
            }).flatMap({ $0 })
        else {
            return nil
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
        let request = makeReviewPipelineRequest(artifact: artifact, reviewGeneration: reviewGeneration)
        let packageBuildStart = ContinuousClock.now
        let constructionResult: BridgeReviewPackageConstructionResult
        var telemetryReason = buildReason
        do {
            reviewLoadStage = "package"
            constructionResult = try await acquireReviewPackage(request)
        } catch {
            guard shouldRetryUnresolvedHeadBaseline(after: error) else {
                throw error
            }
            bridgeDiffCommandLogger.warning(
                "Retrying Bridge review package load with unstaged baseline after unresolved HEAD"
            )
            let fallbackRequest = makeReviewPipelineRequest(
                artifact: artifact,
                reviewGeneration: reviewGeneration,
                baselineOverride: .unstaged
            )
            reviewLoadStage = "packageFallback"
            constructionResult = try await acquireReviewPackage(fallbackRequest)
            telemetryReason = .fallbackUnresolvedHead
        }
        await recordSwiftTelemetry(
            name: "performance.bridge.swift.package_build",
            phase: "package_build",
            priorityHint: .cold,
            traceContext: packageTraceContext,
            stringAttributes: [
                "agentstudio.bridge.package_build.reason": telemetryReason.rawValue
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
            return .succeeded
        }
        let currentPackage = currentPublication.package
        do {
            let (constructionResult, packageTraceContext) = try await loadReviewPackageForRefresh(
                currentPackage
            )
            let result = constructionResult.result
            guard
                !Task.isCancelled,
                foregroundWorkAdmission.withValidAdmission({ true }) == true,
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
            return .failed
        } catch is CancellationError {
            return .stale
        } catch {
            bridgeDiffCommandLogger.debug(
                "Skipped bridge review refresh: \(String(describing: error), privacy: .private)"
            )
            return foregroundWorkAdmission.withValidAdmission({ true }) == nil
                ? .stale
                : .failed
        }
    }

    private func loadReviewPackageForRefresh(
        _ currentPackage: BridgeReviewPackage
    ) async throws -> (
        result: BridgeReviewPackageConstructionResult,
        traceContext: BridgeTraceContext?
    ) {
        let packageTraceContext = makeRootTraceContext()
        let packageBuildStart = ContinuousClock.now
        let buildReason = consumePendingReviewPackageBuildReason(default: .filesystemRefresh)
        let result = try await acquireReviewPackage(
            BridgeReviewPipelineRequest(
                packageId: currentPackage.packageId,
                query: currentPackage.query,
                baseEndpoint: currentPackage.baseEndpoint,
                headEndpoint: currentPackage.headEndpoint,
                checkpointIds: currentPackage.groups.map(\.groupId),
                reviewGeneration: currentPackage.reviewGeneration,
                generatedAtUnixMilliseconds: Int64(Date().timeIntervalSince1970 * 1000)
            )
        )
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
        reviewGeneration: BridgeReviewGeneration,
        baselineOverride: WorkspaceBaseline? = nil
    ) -> BridgeReviewPipelineRequest {
        let repoId = reviewRepoId(for: artifact)
        let endpoints = makeReviewEndpoints(for: artifact, repoId: repoId, baselineOverride: baselineOverride)
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
            viewFilter: BridgeViewFilter(),
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

    private func makeReviewEndpoints(
        for artifact: DiffArtifact,
        repoId: UUID,
        baselineOverride: WorkspaceBaseline? = nil
    ) -> ReviewEndpointSelection {
        guard case .workspace(_, let baseline) = bridgePaneState.source else {
            return makeFallbackReviewEndpoints(for: artifact, repoId: repoId)
        }

        let selection = makeWorkspaceEndpointSelection(
            baseline: baselineOverride ?? baseline,
            worktreeId: artifact.worktreeId,
            repoId: repoId
        )
        return ReviewEndpointSelection(
            base: selection.base,
            head: selection.head,
            comparisonSemantics: selection.comparisonSemantics,
            pathScope: []
        )
    }

    private func makeFallbackReviewEndpoints(for artifact: DiffArtifact, repoId: UUID) -> ReviewEndpointSelection {
        ReviewEndpointSelection(
            base: makeSourceEndpoint(
                endpointId: "base-\(artifact.diffId.uuidString)",
                kind: .gitRef,
                repoId: repoId,
                worktreeId: artifact.worktreeId,
                label: "Base",
                providerIdentity: "base:\(artifact.diffId.uuidString)"
            ),
            head: makeSourceEndpoint(
                endpointId: "head-\(artifact.diffId.uuidString)",
                kind: .workingTree,
                repoId: repoId,
                worktreeId: artifact.worktreeId,
                label: "Working tree",
                providerIdentity: "working-tree:\(artifact.diffId.uuidString)"
            ),
            comparisonSemantics: .workingTreeDelta,
            pathScope: []
        )
    }

    private func reviewRepoId(for artifact: DiffArtifact) -> UUID {
        runtime.metadata.facets.repoId ?? artifact.worktreeId
    }

    private func shouldRetryUnresolvedHeadBaseline(after error: Error) -> Bool {
        guard case .workspace(_, .ref(let name)) = bridgePaneState.source,
            name == "HEAD",
            case BridgeProviderFailure.unavailableEndpoint = error
        else {
            return false
        }
        return true
    }

    private func makeWorkspaceEndpointSelection(
        baseline: WorkspaceBaseline,
        worktreeId: UUID,
        repoId: UUID
    ) -> (
        base: BridgeSourceEndpoint,
        head: BridgeSourceEndpoint,
        comparisonSemantics: BridgeReviewQuery.ComparisonSemantics
    ) {
        switch baseline {
        case .localDefaultBranch(let branchName):
            return makeGitRefAgainstWorkingTreeSelection(
                endpointId: "baseline-local-default",
                refName: branchName,
                worktreeId: worktreeId,
                repoId: repoId
            )
        case .originDefaultBranch(let remoteName, let branchName):
            let providerIdentity = "\(remoteName)/\(branchName)"
            return makeGitRefAgainstWorkingTreeSelection(
                endpointId: "baseline-origin-default",
                refName: providerIdentity,
                worktreeId: worktreeId,
                repoId: repoId
            )
        case .branch(let name):
            return makeGitRefAgainstWorkingTreeSelection(
                endpointId: "baseline-branch-\(Self.endpointComponent(from: name))",
                refName: name,
                worktreeId: worktreeId,
                repoId: repoId
            )
        case .ref(let name):
            return makeGitRefAgainstWorkingTreeSelection(
                endpointId: "baseline-ref-\(Self.endpointComponent(from: name))",
                refName: name,
                worktreeId: worktreeId,
                repoId: repoId
            )
        case .headMinusOne:
            return makeGitRefAgainstWorkingTreeSelection(
                endpointId: "baseline-headMinusOne",
                refName: "HEAD~1",
                worktreeId: worktreeId,
                repoId: repoId
            )
        case .staged:
            return (
                base: makeGitRefEndpoint(
                    endpointId: "baseline-head", refName: "HEAD", worktreeId: worktreeId, repoId: repoId),
                head: makeIndexEndpoint(worktreeId: worktreeId, repoId: repoId),
                comparisonSemantics: .indexDelta
            )
        case .unstaged:
            return (
                base: makeIndexEndpoint(worktreeId: worktreeId, repoId: repoId),
                head: makeWorkingTreeEndpoint(worktreeId: worktreeId, repoId: repoId),
                comparisonSemantics: .workingTreeDelta
            )
        }
    }

    private func makeGitRefAgainstWorkingTreeSelection(
        endpointId: String,
        refName: String,
        worktreeId: UUID,
        repoId: UUID
    ) -> (
        base: BridgeSourceEndpoint,
        head: BridgeSourceEndpoint,
        comparisonSemantics: BridgeReviewQuery.ComparisonSemantics
    ) {
        (
            base: makeGitRefEndpoint(endpointId: endpointId, refName: refName, worktreeId: worktreeId, repoId: repoId),
            head: makeWorkingTreeEndpoint(worktreeId: worktreeId, repoId: repoId),
            comparisonSemantics: .workingTreeDelta
        )
    }

    private func makeGitRefEndpoint(
        endpointId: String,
        refName: String,
        worktreeId: UUID,
        repoId: UUID
    ) -> BridgeSourceEndpoint {
        makeSourceEndpoint(
            endpointId: endpointId,
            kind: .gitRef,
            repoId: repoId,
            worktreeId: worktreeId,
            label: refName,
            providerIdentity: refName
        )
    }

    private func makeIndexEndpoint(worktreeId: UUID, repoId: UUID) -> BridgeSourceEndpoint {
        makeSourceEndpoint(
            endpointId: "index",
            kind: .index,
            repoId: repoId,
            worktreeId: worktreeId,
            label: "Index",
            providerIdentity: "index:\(worktreeId.uuidString)"
        )
    }

    private func makeWorkingTreeEndpoint(worktreeId: UUID, repoId: UUID) -> BridgeSourceEndpoint {
        makeSourceEndpoint(
            endpointId: "working-tree",
            kind: .workingTree,
            repoId: repoId,
            worktreeId: worktreeId,
            label: "Working tree",
            providerIdentity: "working-tree:\(worktreeId.uuidString)"
        )
    }

    private static func endpointComponent(from value: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        return String(value.map { allowed.contains($0) ? $0 : "-" })
    }

    private func makeSourceEndpoint(
        endpointId: String,
        kind: BridgeSourceEndpoint.Kind,
        repoId: UUID,
        worktreeId: UUID,
        label: String,
        providerIdentity: String
    ) -> BridgeSourceEndpoint {
        BridgeSourceEndpoint(
            endpointId: endpointId,
            kind: kind,
            repoId: repoId,
            worktreeId: worktreeId,
            label: label,
            createdAtUnixMilliseconds: Int64(Date().timeIntervalSince1970 * 1000),
            contentSetHash: nil,
            providerIdentity: providerIdentity
        )
    }
}
