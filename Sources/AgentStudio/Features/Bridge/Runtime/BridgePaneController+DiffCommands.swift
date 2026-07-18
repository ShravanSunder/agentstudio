import Foundation
import os.log

private let bridgeDiffCommandLogger = Logger(subsystem: "com.agentstudio", category: "BridgeDiffCommands")

private enum BridgeRefreshTelemetryOutcome {
    case failed
    case finalCommit
    case providerUnavailable
    case staleRejection

    var phase: String {
        switch self {
        case .failed:
            "failed"
        case .finalCommit:
            "final_commit"
        case .providerUnavailable:
            "provider_unavailable"
        case .staleRejection:
            "stale_rejection"
        }
    }

    var numericAttributes: [String: Double] {
        var attributes = ["agentstudio.performance.bridge.active_refresh.count": 1.0]
        switch self {
        case .failed, .providerUnavailable:
            break
        case .finalCommit:
            attributes["agentstudio.performance.bridge.final_commit.count"] = 1
        case .staleRejection:
            attributes["agentstudio.performance.bridge.stale_rejection.count"] = 1
        }
        return attributes
    }
}

@MainActor
extension BridgePaneController: BridgeRuntimeCommandHandling {
    func handleDiffCommand(
        _ command: DiffCommand,
        commandId: UUID,
        correlationId: UUID?
    ) async -> ActionResult {
        switch command {
        case .loadDiff(let artifact):
            paneState.diff.setStatus(.loading)
            paneState.diff.advanceEpoch()
            paneState.diff.setPackageMetadata(nil)
            paneState.diff.setPackageDelta(nil)
            let reviewGeneration = nextReviewGeneration.next()
            nextReviewGeneration = reviewGeneration
            do {
                let request = makeReviewPipelineRequest(
                    artifact: artifact,
                    reviewGeneration: reviewGeneration
                )
                let packageTraceContext = makeRootTraceContext()
                let packageBuildStart = ContinuousClock.now
                let result = try await reviewPipeline.loadPackage(request)
                await recordSwiftTelemetry(
                    name: "performance.bridge.swift.package_build",
                    phase: "package_build",
                    priorityHint: .cold,
                    traceContext: packageTraceContext,
                    durationMilliseconds: AgentStudioPerformanceTraceRecorder.milliseconds(
                        from: packageBuildStart.duration(to: ContinuousClock.now)
                    )
                )
                guard reviewGeneration == nextReviewGeneration else {
                    return .failure(.invalidPayload(description: "Stale bridge review load"))
                }
                lastReviewPackageTraceContext = packageTraceContext
                let deltaBuildStart = ContinuousClock.now
                let delta = try await reviewChangeIndex.ingestExplicitLoad(result.package)
                await recordSwiftTelemetry(
                    name: "performance.bridge.swift.delta_build",
                    phase: "delta_build",
                    priorityHint: .warm,
                    traceContext: makeChildTraceContext(parent: packageTraceContext),
                    durationMilliseconds: AgentStudioPerformanceTraceRecorder.milliseconds(
                        from: deltaBuildStart.duration(to: ContinuousClock.now)
                    )
                )
                let contentRegisterStart = ContinuousClock.now
                await reviewContentStore.activate(
                    handles: result.registeredContentHandles,
                    reviewGeneration: reviewGeneration
                )
                await recordSwiftTelemetry(
                    name: "performance.bridge.swift.content_register",
                    phase: "content_register",
                    priorityHint: .cold,
                    traceContext: makeChildTraceContext(parent: packageTraceContext),
                    durationMilliseconds: AgentStudioPerformanceTraceRecorder.milliseconds(
                        from: contentRegisterStart.duration(to: ContinuousClock.now)
                    )
                )
                paneState.diff.setPackageMetadata(
                    result.package.withRevision(delta?.revision ?? result.package.revision)
                )
                paneState.diff.setPackageDelta(delta)
                paneState.diff.setStatus(.ready)
                ingestRuntimeEvent(
                    .diff(.diffLoaded(stats: Self.diffStats(from: result.package.summary))),
                    commandId: commandId,
                    correlationId: correlationId
                )
                return .success(commandId: commandId)
            } catch BridgeProviderFailure.providerUnavailable {
                paneState.diff.setStatus(.error, error: "providerUnavailable")
                return .failure(.backendUnavailable(backend: "BridgeReviewSourceProvider"))
            } catch {
                bridgeDiffCommandLogger.error(
                    "Bridge review package load failed: \(String(describing: error), privacy: .private)"
                )
                paneState.diff.setStatus(.error, error: "loadFailed")
                return .failure(.invalidPayload(description: "Failed to load bridge review package"))
            }
        }
    }

    func handlePaneFilesystemContextEvent(_ event: PaneFilesystemContextEvent) async {
        guard shouldRefreshReviewPackage(for: event) else { return }

        let refreshTask: Task<Void, Never>
        let wasCoalesced: Bool
        hasPendingReviewRefresh = true
        if let activeReviewRefreshTask {
            refreshTask = activeReviewRefreshTask
            wasCoalesced = true
        } else {
            let newRefreshTask = Task { @MainActor [weak self] in
                guard let self else { return }
                await self.drainPendingReviewRefreshes()
            }
            activeReviewRefreshTask = newRefreshTask
            refreshTask = newRefreshTask
            wasCoalesced = false
        }
        await recordSwiftTelemetry(
            name: "performance.bridge.refresh",
            phase: "invalidation",
            priorityHint: .warm,
            traceContext: makeChildTraceContext(parent: lastReviewPackageTraceContext),
            durationMilliseconds: nil,
            numericAttributes: [
                "agentstudio.performance.bridge.coalesced_demand.count": wasCoalesced ? 1 : 0,
                "agentstudio.performance.bridge.invalidation.count": 1,
            ]
        )
        await refreshTask.value
    }

    private func drainPendingReviewRefreshes() async {
        while hasPendingReviewRefresh, !Task.isCancelled {
            hasPendingReviewRefresh = false
            await refreshCurrentReviewPackage()
        }
        activeReviewRefreshTask = nil
    }

    private func refreshCurrentReviewPackage() async {
        guard let currentPackage = paneState.diff.packageMetadata else { return }
        let refreshStart = ContinuousClock.now
        let refreshTraceContext = makeChildTraceContext(parent: lastReviewPackageTraceContext)
        do {
            let packageTraceContext = makeRootTraceContext()
            let packageBuildStart = ContinuousClock.now
            let result = try await reviewPipeline.loadPackage(
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
                durationMilliseconds: AgentStudioPerformanceTraceRecorder.milliseconds(
                    from: packageBuildStart.duration(to: ContinuousClock.now)
                )
            )
            guard !Task.isCancelled,
                paneState.diff.packageMetadata?.packageId == currentPackage.packageId,
                paneState.diff.packageMetadata?.reviewGeneration == currentPackage.reviewGeneration
            else {
                await recordRefreshTelemetry(
                    outcome: .staleRejection,
                    traceContext: refreshTraceContext,
                    start: refreshStart
                )
                return
            }

            lastReviewPackageTraceContext = packageTraceContext
            let deltaBuildStart = ContinuousClock.now
            let delta = try await reviewChangeIndex.ingestExplicitLoad(result.package)
            await recordSwiftTelemetry(
                name: "performance.bridge.swift.delta_build",
                phase: "delta_build",
                priorityHint: .warm,
                traceContext: makeChildTraceContext(parent: packageTraceContext),
                durationMilliseconds: AgentStudioPerformanceTraceRecorder.milliseconds(
                    from: deltaBuildStart.duration(to: ContinuousClock.now)
                )
            )
            let contentRegisterStart = ContinuousClock.now
            await reviewContentStore.activate(
                handles: result.registeredContentHandles,
                reviewGeneration: result.package.reviewGeneration
            )
            await recordSwiftTelemetry(
                name: "performance.bridge.swift.content_register",
                phase: "content_register",
                priorityHint: .cold,
                traceContext: makeChildTraceContext(parent: packageTraceContext),
                durationMilliseconds: AgentStudioPerformanceTraceRecorder.milliseconds(
                    from: contentRegisterStart.duration(to: ContinuousClock.now)
                )
            )
            paneState.diff.setPackageMetadata(
                result.package.withRevision(delta?.revision ?? currentPackage.revision)
            )
            paneState.diff.setPackageDelta(delta)
            paneState.diff.setStatus(.ready)
            await recordRefreshTelemetry(
                outcome: .finalCommit,
                traceContext: refreshTraceContext,
                start: refreshStart
            )
        } catch BridgeProviderFailure.providerUnavailable {
            await recordRefreshTelemetry(
                outcome: .providerUnavailable,
                traceContext: refreshTraceContext,
                start: refreshStart
            )
            bridgeDiffCommandLogger.debug("Skipped bridge review refresh: provider unavailable")
        } catch {
            await recordRefreshTelemetry(
                outcome: .failed,
                traceContext: refreshTraceContext,
                start: refreshStart
            )
            bridgeDiffCommandLogger.debug(
                "Skipped bridge review refresh: \(String(describing: error), privacy: .private)"
            )
        }
    }

    private func recordRefreshTelemetry(
        outcome: BridgeRefreshTelemetryOutcome,
        traceContext: BridgeTraceContext?,
        start: ContinuousClock.Instant
    ) async {
        await recordSwiftTelemetry(
            name: "performance.bridge.refresh",
            phase: outcome.phase,
            priorityHint: .warm,
            traceContext: traceContext,
            durationMilliseconds: AgentStudioPerformanceTraceRecorder.milliseconds(
                from: start.duration(to: ContinuousClock.now)
            ),
            numericAttributes: outcome.numericAttributes
        )
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
        let endpoints = makeReviewEndpoints(for: artifact)
        let query = BridgeReviewQuery(
            queryId: "query-\(artifact.diffId.uuidString)",
            queryKind: .compare,
            repoId: artifact.worktreeId,
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
        for artifact: DiffArtifact
    ) -> ReviewEndpointSelection {
        guard case .workspace(_, let baseline) = bridgePaneState.source else {
            return ReviewEndpointSelection(
                base: makeSourceEndpoint(
                    endpointId: "base-\(artifact.diffId.uuidString)",
                    kind: .gitRef,
                    repoId: artifact.worktreeId,
                    worktreeId: artifact.worktreeId,
                    label: "Base",
                    providerIdentity: "base:\(artifact.diffId.uuidString)"
                ),
                head: makeSourceEndpoint(
                    endpointId: "head-\(artifact.diffId.uuidString)",
                    kind: .workingTree,
                    repoId: artifact.worktreeId,
                    worktreeId: artifact.worktreeId,
                    label: "Working tree",
                    providerIdentity: "working-tree:\(artifact.diffId.uuidString)"
                ),
                comparisonSemantics: .workingTreeDelta,
                pathScope: []
            )
        }

        let repoId = artifact.worktreeId
        let base: BridgeSourceEndpoint
        let head: BridgeSourceEndpoint
        let semantics: BridgeReviewQuery.ComparisonSemantics
        switch baseline {
        case .headMinusOne:
            base = makeSourceEndpoint(
                endpointId: "baseline-headMinusOne",
                kind: .gitRef,
                repoId: repoId,
                worktreeId: artifact.worktreeId,
                label: "HEAD~1",
                providerIdentity: "HEAD~1"
            )
            head = makeSourceEndpoint(
                endpointId: "working-tree",
                kind: .workingTree,
                repoId: repoId,
                worktreeId: artifact.worktreeId,
                label: "Working tree",
                providerIdentity: "working-tree:\(artifact.worktreeId.uuidString)"
            )
            semantics = .workingTreeDelta
        case .staged:
            base = makeSourceEndpoint(
                endpointId: "baseline-head",
                kind: .gitRef,
                repoId: repoId,
                worktreeId: artifact.worktreeId,
                label: "HEAD",
                providerIdentity: "HEAD"
            )
            head = makeSourceEndpoint(
                endpointId: "index",
                kind: .index,
                repoId: repoId,
                worktreeId: artifact.worktreeId,
                label: "Index",
                providerIdentity: "index:\(artifact.worktreeId.uuidString)"
            )
            semantics = .indexDelta
        case .unstaged:
            base = makeSourceEndpoint(
                endpointId: "index",
                kind: .index,
                repoId: repoId,
                worktreeId: artifact.worktreeId,
                label: "Index",
                providerIdentity: "index:\(artifact.worktreeId.uuidString)"
            )
            head = makeSourceEndpoint(
                endpointId: "working-tree",
                kind: .workingTree,
                repoId: repoId,
                worktreeId: artifact.worktreeId,
                label: "Working tree",
                providerIdentity: "working-tree:\(artifact.worktreeId.uuidString)"
            )
            semantics = .workingTreeDelta
        }
        return ReviewEndpointSelection(
            base: base,
            head: head,
            comparisonSemantics: semantics,
            pathScope: []
        )
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

private struct ReviewEndpointSelection {
    let base: BridgeSourceEndpoint
    let head: BridgeSourceEndpoint
    let comparisonSemantics: BridgeReviewQuery.ComparisonSemantics
    let pathScope: [String]
}
