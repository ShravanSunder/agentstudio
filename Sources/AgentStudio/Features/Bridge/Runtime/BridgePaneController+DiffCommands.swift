import Foundation
import os.log

private let bridgeDiffCommandLogger = Logger(subsystem: "com.agentstudio", category: "BridgeDiffCommands")
private let bridgeReviewStartupVisibleItemLimit = 80
private let bridgeReviewMetadataWindowItemLimit = 80

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

    /// Full reload for an intake-ready announce on an already-loaded pane.
    /// Bypasses the idle/no-package bootstrap guard on purpose: the announce
    /// means the browser has no applied snapshot, and re-delivery must carry a
    /// NEW generation (via the loadDiff reset path) to re-key the receiver.
    func scheduleReviewPackageReloadForIntakeAnnounce() {
        scheduleReviewPackageReloadForIntakeAnnounce(reason: .intakeReannounce)
    }

    func scheduleReviewPackageReloadForIntakeAnnounce(reason: BridgeReviewPackageBuildReason) {
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
        switch command {
        case .loadDiff(let artifact):
            return await handleLoadDiffCommand(
                artifact: artifact,
                commandId: commandId,
                correlationId: correlationId
            )
        }
    }

    private struct ReviewPackageLoadReset {
        let reviewGeneration: BridgeReviewGeneration
        let streamId: String
        let contentAuthorityLifetime: Int
        let expectedRevocationRevision: UInt64
        let resetSourceIdentity: String
    }

    private func handleLoadDiffCommand(
        artifact: DiffArtifact,
        commandId: UUID,
        correlationId: UUID?
    ) async -> ActionResult {
        let packageTraceContext = makeRootTraceContext()
        let reset = await beginReviewPackageLoad(artifact: artifact)
        await enqueueReviewProtocolFrameJob(
            lane: .foreground,
            generation: reset.reviewGeneration.rawValue,
            traceContext: packageTraceContext
        ) { sequence in
            .reset(
                BridgeReviewProtocolFrameBuilder.reset(
                    request: BridgeReviewProtocolResetBuildRequest(
                        sourceIdentity: reset.resetSourceIdentity,
                        streamId: reset.streamId,
                        generation: reset.reviewGeneration.rawValue,
                        sequence: sequence,
                        reason: "authorityChanged"
                    )
                )
            )
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
            guard reset.reviewGeneration == nextReviewGeneration else {
                return .failure(.invalidPayload(description: "Stale bridge review load"))
            }
            lastReviewPackageTraceContext = packageTraceContext
            let load = try await makeReviewPackageLoadData(
                result: result,
                reviewLoadStage: &reviewLoadStage,
                packageTraceContext: packageTraceContext
            )
            let contentRegisterStart = ContinuousClock.now
            try await activateReviewContentHandles(
                handles: result.registeredContentHandles,
                reviewGeneration: reset.reviewGeneration,
                expectedRevocationRevision: reset.expectedRevocationRevision,
                expectedAuthorityLifetime: reset.contentAuthorityLifetime
            )
            await recordReviewContentRegisterTelemetry(
                traceContext: packageTraceContext,
                contentRegisterStart: contentRegisterStart
            )
            await commitReviewPackageLoad(load, traceContext: packageTraceContext)
            ingestRuntimeEvent(
                .diff(.diffLoaded(stats: Self.diffStats(from: result.package.summary))),
                commandId: commandId,
                correlationId: correlationId
            )
            return .success(commandId: commandId)
        } catch BridgeProviderFailure.providerUnavailable {
            paneState.diff.setStatus(.error, error: "providerUnavailable")
            await productSchemeProvider?.publish(
                availability: .failed,
                traceContext: packageTraceContext
            )
            await deliverReviewProtocolErrorFrame(
                streamId: reset.streamId,
                generation: reset.reviewGeneration.rawValue,
                message: "providerUnavailable",
                traceContext: packageTraceContext
            )
            return .failure(.backendUnavailable(backend: "BridgeReviewSourceProvider"))
        } catch {
            let failureSummary = Self.reviewPackageLoadFailureSummary(for: error, stage: reviewLoadStage)
            bridgeDiffCommandLogger.error(
                "Bridge review package load failed: \(failureSummary, privacy: .public)"
            )
            paneState.diff.setStatus(.error, error: failureSummary)
            await productSchemeProvider?.publish(
                availability: .failed,
                traceContext: packageTraceContext
            )
            await deliverReviewProtocolErrorFrame(
                streamId: reset.streamId,
                generation: reset.reviewGeneration.rawValue,
                message: failureSummary,
                traceContext: packageTraceContext
            )
            return .failure(.invalidPayload(description: "Failed to load bridge review package"))
        }
    }

    private func beginReviewPackageLoad(artifact: DiffArtifact) async -> ReviewPackageLoadReset {
        paneState.diff.setStatus(.loading)
        await productSchemeProvider?.publish(availability: .loading)
        paneState.diff.advanceEpoch()
        let reviewGeneration = nextReviewGeneration.next()
        nextReviewGeneration = reviewGeneration
        nextReviewProtocolSequence = 0
        // Accepting the new generation stale-drops queued review jobs from
        // the previous package; the intake gate stays as-is because the
        // review stream identity survives package reloads.
        await worktreeFileMetadataScheduler.acceptGeneration(
            reviewGeneration.rawValue,
            protocolId: "review"
        )
        let resetSourceIdentity =
            paneState.diff.packageMetadata?.query.queryId ?? reviewSourceIdentity(for: artifact)
        paneState.diff.setPackageMetadata(nil)
        paneState.diff.setPackageDelta(nil)
        let contentAuthorityLifetime = revokeReviewContentAuthoritySynchronously()
        await clearReviewContentAuthority(revokeAuthority: false)
        let streamId = reviewProtocolStreamId()
        return ReviewPackageLoadReset(
            reviewGeneration: reviewGeneration,
            streamId: streamId,
            contentAuthorityLifetime: contentAuthorityLifetime,
            expectedRevocationRevision: reviewContentRevocationRevision(),
            resetSourceIdentity: resetSourceIdentity
        )
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
        fallbackRevision: Int? = nil,
        reviewLoadStage: inout String,
        packageTraceContext: BridgeTraceContext?
    ) async throws -> BridgeReviewPackageLoadData {
        let deltaBuildStart = ContinuousClock.now
        reviewLoadStage = "delta"
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

    private func activateReviewContentHandles(
        handles: [BridgeContentHandle],
        reviewGeneration: BridgeReviewGeneration,
        expectedRevocationRevision: UInt64,
        expectedAuthorityLifetime: Int
    ) async throws {
        guard reviewContentAuthorityLifetime == expectedAuthorityLifetime else {
            throw BridgeProviderFailure.providerFailed(message: "Stale bridge review content lifetime")
        }
        let leases: [BridgeTransportResourceLease]
        do {
            leases = try makeReviewContentLeases(handles: handles, reviewGeneration: reviewGeneration)
        } catch {
            throw error
        }
        let replaced = await resourceLeaseRegistry.replace(
            paneId: paneId,
            protocolId: "review",
            resourceKind: "content",
            leases: leases,
            expectedRevocationRevision: expectedRevocationRevision
        )
        guard replaced else {
            await clearReviewContentAuthority()
            throw BridgeProviderFailure.providerFailed(message: "Invalid bridge review content lease set")
        }
        guard reviewContentAuthorityLifetime == expectedAuthorityLifetime else {
            await clearReviewContentAuthority()
            throw BridgeProviderFailure.providerFailed(message: "Stale bridge review content lifetime")
        }
        await reviewContentStore.activate(handles: handles, reviewGeneration: reviewGeneration)
    }

    private func makeReviewContentLeases(
        handles: [BridgeContentHandle],
        reviewGeneration: BridgeReviewGeneration
    ) throws -> [BridgeTransportResourceLease] {
        var leases: [BridgeTransportResourceLease] = []
        for handle in handles where handle.reviewGeneration == reviewGeneration {
            guard
                let resource = BridgeTransportResourceURL.parse(
                    handle.resourceUrl,
                    allowedResourceKindsByProtocol: BridgeResourceProtocolRegistry.reviewContentResourceKinds
                ),
                resource.opaqueId == handle.handleId,
                resource.generation == reviewGeneration.rawValue,
                handle.sizeBytes >= 0
            else {
                throw BridgeProviderFailure.providerFailed(message: "Invalid bridge review content handle")
            }
            leases.append(
                BridgeTransportResourceLease(
                    paneId: paneId,
                    descriptorId: resource.opaqueId,
                    resource: resource,
                    maxBytes: handle.sizeBytesIsExact
                        ? handle.sizeBytes
                        : AppPolicies.Bridge.contentMaxBytesPerItem
                ))
        }
        return leases
    }

    @discardableResult
    func revokeReviewContentAuthoritySynchronously() -> Int {
        reviewContentAuthorityLifetime += 1
        resourceLeaseRegistry.revokeSynchronously(paneId: paneId, protocolId: "review", resourceKind: "content")
        return reviewContentAuthorityLifetime
    }

    func clearReviewContentAuthority(revokeAuthority: Bool = true) async {
        if revokeAuthority {
            revokeReviewContentAuthoritySynchronously()
        }
        await reviewContentStore.deactivate()
        await resourceLeaseRegistry.reset(
            paneId: paneId,
            protocolId: "review",
            resourceKind: "content",
            revokeAuthority: false
        )
    }

    private func reviewContentRevocationRevision() -> UInt64 {
        resourceLeaseRegistry.revocationRevision(paneId: paneId, protocolId: "review", resourceKind: "content")
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

        if let currentPackage = paneState.diff.packageMetadata {
            await enqueueReviewProtocolFrameJob(
                lane: .active,
                generation: currentPackage.reviewGeneration.rawValue,
                traceContext: lastReviewPackageTraceContext
            ) { [weak self] sequence in
                guard let self else { return nil }
                return self.makeReviewProtocolInvalidationFrame(
                    currentPackage: currentPackage,
                    event: event,
                    sequence: sequence
                )
            }
        }
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
        guard let currentPackage = paneState.diff.packageMetadata else { return }
        let contentAuthorityLifetime = reviewContentAuthorityLifetime
        let expectedRevocationRevision = reviewContentRevocationRevision()
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
            guard !Task.isCancelled,
                paneState.diff.packageMetadata?.packageId == currentPackage.packageId,
                paneState.diff.packageMetadata?.reviewGeneration == currentPackage.reviewGeneration
            else {
                return
            }

            lastReviewPackageTraceContext = packageTraceContext
            var reviewLoadStage = "delta"
            let load = try await makeReviewPackageLoadData(
                result: result,
                fallbackRevision: currentPackage.revision,
                reviewLoadStage: &reviewLoadStage,
                packageTraceContext: packageTraceContext
            )
            let contentRegisterStart = ContinuousClock.now
            try await activateReviewContentHandles(
                handles: result.registeredContentHandles,
                reviewGeneration: result.package.reviewGeneration,
                expectedRevocationRevision: expectedRevocationRevision,
                expectedAuthorityLifetime: contentAuthorityLifetime
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
            await commitReviewPackageLoad(load, traceContext: packageTraceContext)
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
            .intakeReannounce,
            .suppressionCatchUp,
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

    func makeReviewProtocolSnapshotFrame(
        package: BridgeReviewPackage,
        sequence: Int
    ) throws -> BridgeReviewSnapshotFrame {
        let visibleItemIds = Array(package.orderedItemIds.prefix(bridgeReviewStartupVisibleItemLimit))
        return try BridgeReviewProtocolFrameBuilder.snapshot(
            request: BridgeReviewProtocolSnapshotBuildRequest(
                paneId: paneId.uuidString,
                sourceIdentity: package.query.queryId,
                streamId: reviewProtocolStreamId(),
                sequence: sequence,
                package: package,
                selectedItemId: package.orderedItemIds.first,
                visibleItemIds: visibleItemIds,
                changesetCluster: package.changesetCluster
            )
        )
    }

    /// Startup metadata window chunks past the visible snapshot prefix. Each
    /// chunk becomes one speculative-lane scheduler job at commit time.
    static func reviewStartupMetadataWindowItemIdChunks(package: BridgeReviewPackage) -> [[String]] {
        let windowedItemIds = Array(package.orderedItemIds.dropFirst(bridgeReviewStartupVisibleItemLimit))
        guard !windowedItemIds.isEmpty else { return [] }
        var chunks: [[String]] = []
        chunks.reserveCapacity(
            Int(ceil(Double(windowedItemIds.count) / Double(bridgeReviewMetadataWindowItemLimit)))
        )
        var windowStartIndex = 0
        while windowStartIndex < windowedItemIds.count {
            let windowEndIndex = min(
                windowStartIndex + bridgeReviewMetadataWindowItemLimit,
                windowedItemIds.count
            )
            chunks.append(Array(windowedItemIds[windowStartIndex..<windowEndIndex]))
            windowStartIndex = windowEndIndex
        }
        return chunks
    }

    func makeReviewProtocolMetadataWindowFrame(
        package: BridgeReviewPackage,
        itemIds: [String],
        sequence: Int,
        loadedBy: BridgeReviewMetadataLoadedBy = .idle,
        lane: BridgeDemandLane = .idle
    ) async throws -> BridgeReviewMetadataWindowFrame {
        let metadataWindowBuildStart = ContinuousClock.now
        let frame = try BridgeReviewProtocolFrameBuilder.metadataWindow(
            request: BridgeReviewProtocolMetadataWindowBuildRequest(
                paneId: paneId.uuidString,
                sourceIdentity: package.query.queryId,
                streamId: reviewProtocolStreamId(),
                sequence: sequence,
                package: package,
                itemIds: itemIds,
                loadedBy: loadedBy,
                lane: lane
            )
        )
        await recordSwiftTelemetry(
            name: "performance.bridge.swift.review_metadata_window_batch",
            phase: "review_metadata_window_batch",
            priorityHint: .cold,
            traceContext: makeChildTraceContext(parent: lastReviewPackageTraceContext),
            durationMilliseconds: AgentStudioPerformanceTraceRecorder.milliseconds(
                from: metadataWindowBuildStart.duration(to: ContinuousClock.now)
            )
        )
        return frame
    }

    func makeReviewProtocolDeltaFrame(
        package: BridgeReviewPackage,
        delta: BridgeReviewDelta,
        sequence: Int
    ) throws -> BridgeReviewDeltaFrame {
        try BridgeReviewProtocolFrameBuilder.delta(
            request: BridgeReviewProtocolDeltaBuildRequest(
                paneId: paneId.uuidString,
                sourceIdentity: package.query.queryId,
                streamId: reviewProtocolStreamId(),
                sequence: sequence,
                fromRevision: max(delta.revision - 1, 0),
                toRevision: delta.revision,
                package: package,
                operations: delta.operations
            )
        )
    }

    private func makeReviewProtocolInvalidationFrame(
        currentPackage: BridgeReviewPackage,
        event: PaneFilesystemContextEvent,
        sequence: Int
    ) -> BridgeReviewProtocolFrame {
        let scope: String
        let pathHints: [String]?
        switch event {
        case .cwdSubtreeChanged(_, let paths, _):
            let sortedPaths = paths.sorted()
            scope = sortedPaths.isEmpty ? "package" : "paths"
            pathHints = sortedPaths.isEmpty ? nil : sortedPaths
        case .gitWorkingTreeInCwd:
            scope = "package"
            pathHints = nil
        }
        return .invalidation(
            BridgeReviewProtocolFrameBuilder.invalidation(
                request: BridgeReviewProtocolInvalidationBuildRequest(
                    streamId: reviewProtocolStreamId(),
                    generation: currentPackage.reviewGeneration.rawValue,
                    sequence: sequence,
                    scope: scope,
                    itemIds: nil,
                    pathHints: pathHints,
                    reason: "watchEvent"
                )
            )
        )
    }

    func consumeNextReviewProtocolSequence() -> Int {
        let sequence = nextReviewProtocolSequence
        nextReviewProtocolSequence += 1
        return sequence
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
        guard
            !shouldSuppressReviewProtocolProduction(
                generation: currentPackage.reviewGeneration.rawValue
            )
        else { return false }
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
