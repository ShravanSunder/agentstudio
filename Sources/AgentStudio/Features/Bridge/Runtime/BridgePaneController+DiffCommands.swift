import Foundation
import os.log

private let bridgeDiffCommandLogger = Logger(subsystem: "com.agentstudio", category: "BridgeDiffCommands")

@MainActor
extension BridgePaneController: BridgeRuntimeCommandHandling {
    func scheduleInitialReviewPackageLoadIfPossible() {
        guard activeReviewRefreshTask == nil else { return }
        activeReviewRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            _ = await self.loadInitialReviewPackageIfPossible(correlationId: nil)
            self.activeReviewRefreshTask = nil
        }
    }

    func loadInitialReviewPackageIfPossible(correlationId: UUID?) async -> ActionResult? {
        guard case .workspace = bridgePaneState.source,
            let worktreeId = runtime.metadata.worktreeId,
            paneState.diff.status == .idle,
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
                await activateReviewContentHandles(
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

    private func activateReviewContentHandles(
        handles: [BridgeContentHandle],
        reviewGeneration: BridgeReviewGeneration
    ) async {
        await reviewContentStore.activate(handles: handles, reviewGeneration: reviewGeneration)
        await resourceLeaseRegistry.reset(paneId: paneId, protocolId: "review", resourceKind: "content")
        for handle in handles where handle.reviewGeneration == reviewGeneration {
            guard
                let resource = BridgeTransportResourceURL.parse(
                    handle.resourceUrl,
                    allowedResourceKindsByProtocol: ["review": Set(["content"])]
                ),
                resource.opaqueId == handle.handleId,
                resource.generation == reviewGeneration.rawValue
            else {
                continue
            }
            await resourceLeaseRegistry.register(
                resource,
                paneId: paneId,
                descriptorId: resource.opaqueId,
                maxBytes: handle.sizeBytes
            )
        }
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

        hasPendingReviewRefresh = true
        if let activeReviewRefreshTask {
            await activeReviewRefreshTask.value
            return
        }

        let refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.drainPendingReviewRefreshes()
        }
        activeReviewRefreshTask = refreshTask
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
            await activateReviewContentHandles(
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
        } catch BridgeProviderFailure.providerUnavailable {
            bridgeDiffCommandLogger.debug("Skipped bridge review refresh: provider unavailable")
        } catch {
            bridgeDiffCommandLogger.debug(
                "Skipped bridge review refresh: \(String(describing: error), privacy: .private)"
            )
        }
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
            return makeFallbackReviewEndpoints(for: artifact)
        }

        let selection = makeWorkspaceEndpointSelection(
            baseline: baseline,
            worktreeId: artifact.worktreeId,
            repoId: artifact.worktreeId
        )
        return ReviewEndpointSelection(
            base: selection.base,
            head: selection.head,
            comparisonSemantics: selection.comparisonSemantics,
            pathScope: []
        )
    }

    private func makeFallbackReviewEndpoints(for artifact: DiffArtifact) -> ReviewEndpointSelection {
        ReviewEndpointSelection(
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

private struct ReviewEndpointSelection {
    let base: BridgeSourceEndpoint
    let head: BridgeSourceEndpoint
    let comparisonSemantics: BridgeReviewQuery.ComparisonSemantics
    let pathScope: [String]
}
