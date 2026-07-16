import Foundation
import os.log

private let bridgeDiffCommandLogger = Logger(subsystem: "com.agentstudio", category: "BridgeDiffCommands")

@MainActor
extension BridgePaneController: BridgeRuntimeCommandHandling {
    func scheduleInitialReviewPackageLoadIfPossible() {
        scheduleInitialReviewPackageLoadIfPossible(reason: .initialIntake)
    }

    func scheduleInitialReviewPackageLoadIfPossible(reason: BridgeReviewPackageBuildReason) {
        pendingReviewPackageBuildReasons.insert(reason)
        guard activeReviewRefreshTask == nil else { return }
        activeReviewRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            _ = await self.loadInitialReviewPackageIfPossible(correlationId: nil)
            self.activeReviewRefreshTask = nil
        }
    }

    /// Full reload for a typed product resync request on an already-loaded pane.
    func scheduleReviewPackageReloadForProductResync() {
        scheduleReviewPackageReloadForProductResync(reason: .productResync)
    }

    func scheduleReviewPackageReloadForProductResync(reason: BridgeReviewPackageBuildReason) {
        pendingReviewPackageBuildReasons.insert(reason)
        guard activeReviewRefreshTask == nil else { return }
        guard case .workspace = bridgePaneState.source,
            let worktreeId = runtime.metadata.worktreeId
        else { return }
        activeReviewRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            _ = await self.loadReviewPackage(worktreeId: worktreeId, correlationId: nil)
            self.activeReviewRefreshTask = nil
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
        guard let productAdmission = productAdmissionGate.acquire() else {
            return .failure(.invalidPayload(description: "Bridge pane is closed"))
        }
        switch command {
        case .loadDiff(let artifact):
            return await handleLoadDiffCommand(
                artifact: artifact,
                commandId: commandId,
                correlationId: correlationId,
                productAdmission: productAdmission
            )
        }
    }

    private struct ReviewPackageLoadReset {
        let reviewGeneration: BridgeReviewGeneration
        let contentAuthorityLifetime: Int
    }

    private func handleLoadDiffCommand(
        artifact: DiffArtifact,
        commandId: UUID,
        correlationId: UUID?,
        productAdmission: BridgeProductAdmissionContext
    ) async -> ActionResult {
        let packageTraceContext = makeRootTraceContext()
        guard
            let reset = await beginReviewPackageLoad(
                artifact: artifact,
                productAdmission: productAdmission
            )
        else {
            return .failure(.invalidPayload(description: "Bridge pane is closed"))
        }
        var reviewLoadStage = "request"
        do {
            let result = try await loadReviewPackageResult(
                artifact: artifact,
                reviewGeneration: reset.reviewGeneration,
                buildReason: consumePendingReviewPackageBuildReason(default: .initialIntake),
                reviewLoadStage: &reviewLoadStage,
                packageTraceContext: packageTraceContext
            )
            guard
                productAdmission.withValidAdmission({
                    guard reset.reviewGeneration == nextReviewGeneration else {
                        return false
                    }
                    lastReviewPackageTraceContext = packageTraceContext
                    return true
                }) == true
            else {
                return .failure(.invalidPayload(description: "Stale bridge review load"))
            }
            let load = try await makeReviewPackageLoadData(
                result: result,
                productAdmission: productAdmission,
                reviewLoadStage: &reviewLoadStage,
                packageTraceContext: packageTraceContext
            )
            let contentRegisterStart = ContinuousClock.now
            try await installReviewContentSourceHandles(
                handles: result.registeredContentHandles,
                reviewGeneration: reset.reviewGeneration,
                expectedAuthorityLifetime: reset.contentAuthorityLifetime,
                productAdmission: productAdmission
            )
            await recordReviewContentRegisterTelemetry(
                traceContext: packageTraceContext,
                contentRegisterStart: contentRegisterStart
            )
            guard
                await commitReviewPackageLoadAndPublishDiffLoaded(
                    load: load,
                    summary: result.package.summary,
                    commandId: commandId,
                    correlationId: correlationId,
                    productAdmission: productAdmission,
                    traceContext: packageTraceContext
                )
            else {
                return .failure(.invalidPayload(description: "Bridge pane is closed"))
            }
            return .success(commandId: commandId)
        } catch BridgeProviderFailure.providerUnavailable {
            guard
                productAdmission.withValidAdmission({
                    paneState.diff.setStatus(.error, error: "providerUnavailable")
                }) != nil
            else {
                return .failure(.invalidPayload(description: "Bridge pane is closed"))
            }
            await productSchemeProvider?.publish(
                availability: .failed,
                productAdmission: productAdmission,
                traceContext: packageTraceContext
            )
            return .failure(.backendUnavailable(backend: "BridgeReviewSourceProvider"))
        } catch {
            let failureSummary = Self.reviewPackageLoadFailureSummary(for: error, stage: reviewLoadStage)
            bridgeDiffCommandLogger.error(
                "Bridge review package load failed: \(failureSummary, privacy: .public)"
            )
            guard
                productAdmission.withValidAdmission({
                    paneState.diff.setStatus(.error, error: failureSummary)
                }) != nil
            else {
                return .failure(.invalidPayload(description: "Bridge pane is closed"))
            }
            await productSchemeProvider?.publish(
                availability: .failed,
                productAdmission: productAdmission,
                traceContext: packageTraceContext
            )
            return .failure(.invalidPayload(description: "Failed to load bridge review package"))
        }
    }

    private func commitReviewPackageLoadAndPublishDiffLoaded(
        load: BridgeReviewPackageLoadData,
        summary: BridgeReviewPackageSummary,
        commandId: UUID,
        correlationId: UUID?,
        productAdmission: BridgeProductAdmissionContext,
        traceContext: BridgeTraceContext?
    ) async -> Bool {
        guard
            await commitReviewPackageLoad(
                load,
                productAdmission: productAdmission,
                traceContext: traceContext
            ) == .committed
        else { return false }
        return productAdmission.withValidAdmission {
            ingestRuntimeEvent(
                .diff(.diffLoaded(stats: Self.diffStats(from: summary))),
                commandId: commandId,
                correlationId: correlationId
            )
            return true
        } == true
    }

    private func beginReviewPackageLoad(
        artifact: DiffArtifact,
        productAdmission: BridgeProductAdmissionContext
    ) async -> ReviewPackageLoadReset? {
        guard
            productAdmission.withValidAdmission({
                paneState.diff.setStatus(.loading)
            }) != nil
        else {
            return nil
        }
        await productSchemeProvider?.publish(
            availability: .loading,
            productAdmission: productAdmission
        )
        guard
            let reset = productAdmission.withValidAdmission({
                paneState.diff.advanceEpoch()
                let reviewGeneration = nextReviewGeneration.next()
                nextReviewGeneration = reviewGeneration
                paneState.diff.setPackageMetadata(nil)
                paneState.diff.setPackageDelta(nil)
                let contentAuthorityLifetime = revokeReviewContentAuthoritySynchronously()
                return ReviewPackageLoadReset(
                    reviewGeneration: reviewGeneration,
                    contentAuthorityLifetime: contentAuthorityLifetime
                )
            })
        else {
            return nil
        }
        await clearReviewContentAuthority(revokeAuthority: false)
        return productAdmission.withValidAdmission { reset }
    }

    private func loadReviewPackageResult(
        artifact: DiffArtifact,
        reviewGeneration: BridgeReviewGeneration,
        buildReason: BridgeReviewPackageBuildReason,
        reviewLoadStage: inout String,
        packageTraceContext: BridgeTraceContext?
    ) async throws -> BridgeReviewPipelineResult {
        let request = makeReviewPipelineRequest(artifact: artifact, reviewGeneration: reviewGeneration)
        let packageBuildStart = ContinuousClock.now
        let result: BridgeReviewPipelineResult
        var telemetryReason = buildReason
        do {
            reviewLoadStage = "package"
            result = try await reviewPipeline.loadPackage(request)
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
            result = try await reviewPipeline.loadPackage(fallbackRequest)
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
        return result
    }

    private func makeReviewPackageLoadData(
        result: BridgeReviewPipelineResult,
        productAdmission: BridgeProductAdmissionContext,
        fallbackRevision: Int? = nil,
        reviewLoadStage: inout String,
        packageTraceContext: BridgeTraceContext?
    ) async throws -> BridgeReviewPackageLoadData {
        let deltaBuildStart = ContinuousClock.now
        reviewLoadStage = "delta"
        let delta = try await reviewChangeIndex.ingestExplicitLoad(
            result.package,
            productAdmission: productAdmission
        )
        await recordSwiftTelemetry(
            name: "performance.bridge.swift.delta_build",
            phase: "delta_build",
            priorityHint: .warm,
            traceContext: makeChildTraceContext(parent: packageTraceContext),
            durationMilliseconds: AgentStudioPerformanceTraceRecorder.milliseconds(
                from: deltaBuildStart.duration(to: ContinuousClock.now)
            )
        )
        let package = result.package.withRevision(delta?.revision ?? fallbackRevision ?? result.package.revision)
        reviewLoadStage = "contentRegister"
        return BridgeReviewPackageLoadData(package: package, delta: delta)
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

    private func installReviewContentSourceHandles(
        handles: [BridgeContentHandle],
        reviewGeneration: BridgeReviewGeneration,
        expectedAuthorityLifetime: Int,
        productAdmission: BridgeProductAdmissionContext
    ) async throws {
        guard
            productAdmission.withValidAdmission({
                reviewContentAuthorityLifetime == expectedAuthorityLifetime
            }) == true
        else {
            throw BridgeProviderFailure.providerFailed(message: "Stale bridge review content lifetime")
        }
        let matchingHandles = handles.filter { $0.reviewGeneration == reviewGeneration }
        let uniqueHandleIds = Set(matchingHandles.map(\.handleId))
        guard matchingHandles.count == handles.count,
            uniqueHandleIds.count == handles.count,
            handles.allSatisfy({ $0.sizeBytes >= 0 })
        else {
            throw BridgeProviderFailure.providerFailed(message: "Invalid bridge review content handles")
        }
        guard
            productAdmission.withValidAdmission({
                reviewContentAuthorityLifetime == expectedAuthorityLifetime
            }) == true
        else {
            await clearReviewContentAuthority()
            throw BridgeProviderFailure.providerFailed(message: "Stale bridge review content lifetime")
        }
        await reviewContentStore.activate(
            handles: handles,
            reviewGeneration: reviewGeneration,
            productAdmission: productAdmission
        )
    }

    @discardableResult
    func revokeReviewContentAuthoritySynchronously() -> Int {
        reviewContentAuthorityLifetime += 1
        return reviewContentAuthorityLifetime
    }

    func clearReviewContentAuthority(revokeAuthority: Bool = true) async {
        if revokeAuthority {
            revokeReviewContentAuthoritySynchronously()
        }
        await reviewContentStore.deactivate()
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
        pendingReviewPackageBuildReasons.insert(.filesystemRefresh)
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
        guard let productAdmission = productAdmissionGate.acquire() else { return }
        guard
            let admittedPackage = productAdmission.withValidAdmission({
                paneState.diff.packageMetadata
            }),
            let currentPackage = admittedPackage
        else {
            return
        }
        let contentAuthorityLifetime = reviewContentAuthorityLifetime
        do {
            let packageTraceContext = makeRootTraceContext()
            let packageBuildStart = ContinuousClock.now
            let buildReason = consumePendingReviewPackageBuildReason(default: .filesystemRefresh)
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
                stringAttributes: [
                    "agentstudio.bridge.package_build.reason": buildReason.rawValue
                ],
                durationMilliseconds: AgentStudioPerformanceTraceRecorder.milliseconds(
                    from: packageBuildStart.duration(to: ContinuousClock.now)
                )
            )
            guard
                !Task.isCancelled,
                productAdmission.withValidAdmission({
                    guard
                        paneState.diff.packageMetadata?.packageId == currentPackage.packageId,
                        paneState.diff.packageMetadata?.reviewGeneration == currentPackage.reviewGeneration
                    else {
                        return false
                    }
                    lastReviewPackageTraceContext = packageTraceContext
                    return true
                }) == true
            else {
                return
            }

            var reviewLoadStage = "delta"
            let load = try await makeReviewPackageLoadData(
                result: result,
                productAdmission: productAdmission,
                fallbackRevision: currentPackage.revision,
                reviewLoadStage: &reviewLoadStage,
                packageTraceContext: packageTraceContext
            )
            let contentRegisterStart = ContinuousClock.now
            try await installReviewContentSourceHandles(
                handles: result.registeredContentHandles,
                reviewGeneration: result.package.reviewGeneration,
                expectedAuthorityLifetime: contentAuthorityLifetime,
                productAdmission: productAdmission
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
            _ = await commitReviewPackageLoad(
                load,
                productAdmission: productAdmission,
                traceContext: packageTraceContext
            )
        } catch BridgeProviderFailure.providerUnavailable {
            bridgeDiffCommandLogger.debug("Skipped bridge review refresh: provider unavailable")
        } catch {
            bridgeDiffCommandLogger.debug(
                "Skipped bridge review refresh: \(String(describing: error), privacy: .private)"
            )
        }
    }

    private func consumePendingReviewPackageBuildReason(
        default defaultReason: BridgeReviewPackageBuildReason
    ) -> BridgeReviewPackageBuildReason {
        let reasonPriority: [BridgeReviewPackageBuildReason] = [
            .fallbackUnresolvedHead,
            .initialIntake,
            .productResync,
            .filesystemRefresh,
        ]
        let selected = reasonPriority.first { pendingReviewPackageBuildReasons.contains($0) } ?? defaultReason
        pendingReviewPackageBuildReasons.removeAll()
        return selected
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
            case BridgeProviderFailure.providerFailed(let message) = error
        else {
            return false
        }
        let normalizedMessage = message.lowercased()
        return normalizedMessage.contains("head")
            && (normalizedMessage.contains("not found") || normalizedMessage.contains("revspec"))
    }

    static func reviewPackageLoadFailureSummary(for error: Error, stage: String) -> String {
        let prefix = "loadFailed:\(stage)"
        if let providerFailure = error as? BridgeProviderFailure {
            switch providerFailure {
            case .providerUnavailable:
                return "\(prefix):providerUnavailable"
            case .unavailableEndpoint:
                return "\(prefix):unavailableEndpoint"
            case .missingContent:
                return "\(prefix):missingContent"
            case .contentHashMismatch:
                return "\(prefix):contentHashMismatch"
            case .oversizedContent:
                return "\(prefix):oversizedContent"
            case .binaryContent:
                return "\(prefix):binaryContent"
            case .staleReviewGeneration:
                return "\(prefix):staleReviewGeneration"
            case .providerFailed(let message):
                return "\(prefix):providerFailed:\(providerFailureReason(from: message))"
            }
        }
        if error is CancellationError {
            return "\(prefix):cancelled"
        }
        return "\(prefix):\(String(describing: type(of: error)))"
    }

    static func providerFailureReason(from message: String) -> String {
        let normalizedMessage = message.lowercased()
        if normalizedMessage.hasPrefix("gitdataplane:") {
            let prefixLength = "gitDataPlane:".count
            let suffix = String(message.dropFirst(prefixLength))
            return "git.\(suffix)"
        }
        if normalizedMessage.contains("invalid bridge review content handle") {
            return "invalidContentHandle"
        }
        if normalizedMessage.contains("invalid bridge review content lease set") {
            return "invalidContentLeaseSet"
        }
        if normalizedMessage.contains("stale bridge review content lifetime") {
            return "staleContentLifetime"
        }
        if normalizedMessage.contains("head")
            && (normalizedMessage.contains("not found") || normalizedMessage.contains("revspec"))
        {
            return "unresolvedHEAD"
        }
        if normalizedMessage.contains("data plane read timed out")
            || normalizedMessage.contains("timed out")
            || normalizedMessage.contains("timeouterror")
        {
            return "gitDataPlaneTimeout"
        }
        if normalizedMessage.contains("content too large") || normalizedMessage.contains("too large") {
            return "contentTooLarge"
        }
        if normalizedMessage.contains("path escapes") {
            return "pathEscapesRepository"
        }
        if normalizedMessage.contains("tree reads") {
            return "unsupportedTreeRead"
        }
        if normalizedMessage.contains("checkpoint endpoint") {
            return "unsupportedCheckpointEndpoint"
        }
        if normalizedMessage.contains("invalid") {
            return "invalidProviderPayload"
        }
        if normalizedMessage.contains("not found") {
            return "notFound"
        }
        return "providerError"
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
