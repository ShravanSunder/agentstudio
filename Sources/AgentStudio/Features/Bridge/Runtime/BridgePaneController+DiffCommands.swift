import Foundation
import os.log

private let bridgeDiffCommandLogger = Logger(subsystem: "com.agentstudio", category: "BridgeDiffCommands")

struct BridgeReviewPackageLoadFrames {
    let package: BridgeReviewPackage
    let delta: BridgeReviewDelta?
    let snapshotFrame: BridgeReviewSnapshotFrame
    let deltaFrame: BridgeReviewDeltaFrame?
    let packageBodyFacts: BridgeReviewProtocolBodyResourceFacts
    let deltaBodyFacts: BridgeReviewProtocolBodyResourceFacts?
}

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
            return await handleLoadDiffCommand(
                artifact: artifact,
                commandId: commandId,
                correlationId: correlationId
            )
        }
    }

    private struct ReviewPackageLoadReset {
        let reviewGeneration: BridgeReviewGeneration
        let contentAuthorityLifetime: Int
        let expectedRevocationRevision: UInt64
        let expectedDeltaResourceRevocationRevision: UInt64
        let expectedPackageResourceRevocationRevision: UInt64
        let resetFrame: BridgeReviewProtocolFrame
    }

    private func handleLoadDiffCommand(
        artifact: DiffArtifact,
        commandId: UUID,
        correlationId: UUID?
    ) async -> ActionResult {
        let packageTraceContext = makeRootTraceContext()
        let reset = await beginReviewPackageLoad(artifact: artifact)
        await deliverReviewProtocolFrameBestEffort(reset.resetFrame, traceContext: packageTraceContext)
        var reviewLoadStage = "request"
        do {
            let result = try await loadReviewPackageResult(
                artifact: artifact,
                reviewGeneration: reset.reviewGeneration,
                reviewLoadStage: &reviewLoadStage,
                packageTraceContext: packageTraceContext
            )
            guard reset.reviewGeneration == nextReviewGeneration else {
                return .failure(.invalidPayload(description: "Stale bridge review load"))
            }
            lastReviewPackageTraceContext = packageTraceContext
            let frames = try await makeReviewPackageLoadFrames(
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
            try await activateReviewProtocolBodyResources(
                frames: frames,
                expectedPackageResourceRevocationRevision: reset.expectedPackageResourceRevocationRevision,
                expectedDeltaResourceRevocationRevision: reset.expectedDeltaResourceRevocationRevision
            )
            await recordReviewContentRegisterTelemetry(
                traceContext: packageTraceContext,
                contentRegisterStart: contentRegisterStart
            )
            await commitReviewPackageLoad(frames, traceContext: packageTraceContext)
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
            let failureSummary = Self.reviewPackageLoadFailureSummary(for: error, stage: reviewLoadStage)
            bridgeDiffCommandLogger.error(
                "Bridge review package load failed: \(failureSummary, privacy: .public)"
            )
            paneState.diff.setStatus(.error, error: failureSummary)
            return .failure(.invalidPayload(description: "Failed to load bridge review package"))
        }
    }

    private func beginReviewPackageLoad(artifact: DiffArtifact) async -> ReviewPackageLoadReset {
        paneState.diff.setStatus(.loading)
        paneState.diff.advanceEpoch()
        let reviewGeneration = nextReviewGeneration.next()
        nextReviewGeneration = reviewGeneration
        let resetFrame = makeReviewProtocolResetFrame(
            currentPackage: paneState.diff.packageMetadata,
            artifact: artifact,
            generation: reviewGeneration,
            reason: "authorityChanged"
        )
        paneState.diff.setPackageMetadata(nil)
        paneState.diff.setPackageDelta(nil)
        let contentAuthorityLifetime = revokeReviewContentAuthoritySynchronously()
        revokeReviewResourceAuthoritySynchronously(resourceKind: "review-package")
        revokeReviewResourceAuthoritySynchronously(resourceKind: "review-delta")
        let expectedPackageResourceRevocationRevision = reviewResourceRevocationRevision(
            resourceKind: "review-package")
        let expectedDeltaResourceRevocationRevision = reviewResourceRevocationRevision(
            resourceKind: "review-delta")
        await clearReviewContentAuthority(revokeAuthority: false)
        await clearReviewResourceAuthority(resourceKind: "review-package", revokeAuthority: false)
        await clearReviewResourceAuthority(resourceKind: "review-delta", revokeAuthority: false)
        return ReviewPackageLoadReset(
            reviewGeneration: reviewGeneration,
            contentAuthorityLifetime: contentAuthorityLifetime,
            expectedRevocationRevision: reviewContentRevocationRevision(),
            expectedDeltaResourceRevocationRevision: expectedDeltaResourceRevocationRevision,
            expectedPackageResourceRevocationRevision: expectedPackageResourceRevocationRevision,
            resetFrame: resetFrame
        )
    }

    private func loadReviewPackageResult(
        artifact: DiffArtifact,
        reviewGeneration: BridgeReviewGeneration,
        reviewLoadStage: inout String,
        packageTraceContext: BridgeTraceContext?
    ) async throws -> BridgeReviewPipelineResult {
        let request = makeReviewPipelineRequest(artifact: artifact, reviewGeneration: reviewGeneration)
        let packageBuildStart = ContinuousClock.now
        let result: BridgeReviewPipelineResult
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
        }
        await recordSwiftTelemetry(
            name: "performance.bridge.swift.package_build",
            phase: "package_build",
            priorityHint: .cold,
            traceContext: packageTraceContext,
            durationMilliseconds: AgentStudioPerformanceTraceRecorder.milliseconds(
                from: packageBuildStart.duration(to: ContinuousClock.now)
            )
        )
        return result
    }

    private func makeReviewPackageLoadFrames(
        result: BridgeReviewPipelineResult,
        fallbackRevision: Int? = nil,
        reviewLoadStage: inout String,
        packageTraceContext: BridgeTraceContext?
    ) async throws -> BridgeReviewPackageLoadFrames {
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
        let packageBodyFacts = try await BridgeReviewJSONResourceEmitter.packageBodyFacts(package)
        reviewLoadStage = "snapshotFrame"
        let snapshotFrame = try makeReviewProtocolSnapshotFrame(
            package: package,
            bodyFacts: packageBodyFacts
        )
        reviewLoadStage = "deltaFrame"
        let deltaFrame: BridgeReviewDeltaFrame?
        let deltaBodyFacts: BridgeReviewProtocolBodyResourceFacts?
        if let delta {
            let computedDeltaBodyFacts = try await BridgeReviewJSONResourceEmitter.deltaOperationsBodyFacts(
                delta.operations)
            deltaBodyFacts = computedDeltaBodyFacts
            deltaFrame = try makeReviewProtocolDeltaFrame(
                package: package,
                delta: delta,
                bodyFacts: computedDeltaBodyFacts
            )
        } else {
            deltaBodyFacts = nil
            deltaFrame = nil
        }
        reviewLoadStage = "contentRegister"
        return BridgeReviewPackageLoadFrames(
            package: package,
            delta: delta,
            snapshotFrame: snapshotFrame,
            deltaFrame: deltaFrame,
            packageBodyFacts: packageBodyFacts,
            deltaBodyFacts: deltaBodyFacts
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
                    maxBytes: handle.sizeBytes
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
            do {
                try await dispatchReviewProtocolFrame(
                    makeReviewProtocolInvalidationFrame(currentPackage: currentPackage, event: event),
                    traceContext: lastReviewPackageTraceContext
                )
            } catch {
                bridgeDiffCommandLogger.warning(
                    "Bridge review invalidation intake failed: \(error.localizedDescription, privacy: .private)"
                )
                paneState.connection.setHealth(.error)
            }
        }
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
        let contentAuthorityLifetime = reviewContentAuthorityLifetime
        let expectedRevocationRevision = reviewContentRevocationRevision()
        let expectedPackageResourceRevocationRevision = reviewResourceRevocationRevision(
            resourceKind: "review-package")
        let expectedDeltaResourceRevocationRevision = reviewResourceRevocationRevision(
            resourceKind: "review-delta")
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
            var reviewLoadStage = "delta"
            let frames = try await makeReviewPackageLoadFrames(
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
            try await activateReviewProtocolBodyResources(
                frames: frames,
                expectedPackageResourceRevocationRevision: expectedPackageResourceRevocationRevision,
                expectedDeltaResourceRevocationRevision: expectedDeltaResourceRevocationRevision
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
            await commitReviewPackageLoad(frames, traceContext: packageTraceContext)
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

    private func makeReviewProtocolResetFrame(
        currentPackage: BridgeReviewPackage?,
        artifact: DiffArtifact,
        generation: BridgeReviewGeneration,
        reason: String
    ) -> BridgeReviewProtocolFrame {
        let sourceIdentity = currentPackage?.query.queryId ?? reviewSourceIdentity(for: artifact)
        return .reset(
            BridgeReviewProtocolFrameBuilder.reset(
                request: BridgeReviewProtocolResetBuildRequest(
                    sourceIdentity: sourceIdentity,
                    streamId: "review:\(paneId.uuidString)",
                    generation: generation.rawValue,
                    sequence: 0,
                    reason: reason,
                    packageId: currentPackage?.packageId,
                    replacementDescriptor: nil
                )
            )
        )
    }

    private func makeReviewProtocolSnapshotFrame(
        package: BridgeReviewPackage,
        bodyFacts: BridgeReviewProtocolBodyResourceFacts?
    ) throws -> BridgeReviewSnapshotFrame {
        try BridgeReviewProtocolFrameBuilder.snapshot(
            request: BridgeReviewProtocolSnapshotBuildRequest(
                paneId: paneId.uuidString,
                sourceIdentity: package.query.queryId,
                streamId: "review:\(paneId.uuidString)",
                sequence: package.revision,
                package: package,
                packageBodyFacts: bodyFacts,
                changesetCluster: package.changesetCluster
            )
        )
    }

    private func makeReviewProtocolDeltaFrame(
        package: BridgeReviewPackage,
        delta: BridgeReviewDelta,
        bodyFacts: BridgeReviewProtocolBodyResourceFacts?
    ) throws -> BridgeReviewDeltaFrame {
        try BridgeReviewProtocolFrameBuilder.delta(
            request: BridgeReviewProtocolDeltaBuildRequest(
                paneId: paneId.uuidString,
                sourceIdentity: package.query.queryId,
                streamId: "review:\(paneId.uuidString)",
                sequence: delta.revision,
                fromRevision: max(delta.revision - 1, 0),
                toRevision: delta.revision,
                package: package,
                operationsBodyFacts: bodyFacts
            )
        )
    }

    private func makeReviewProtocolInvalidationFrame(
        currentPackage: BridgeReviewPackage,
        event: PaneFilesystemContextEvent
    ) -> BridgeReviewProtocolFrame {
        let sequence: Int
        let scope: String
        let pathHints: [String]?
        switch event {
        case .cwdSubtreeChanged(_, let paths, let batchSeq):
            sequence = Int(clamping: batchSeq)
            let sortedPaths = paths.sorted()
            scope = sortedPaths.isEmpty ? "package" : "paths"
            pathHints = sortedPaths.isEmpty ? nil : sortedPaths
        case .gitWorkingTreeInCwd:
            sequence = currentPackage.revision + 1
            scope = "package"
            pathHints = nil
        }
        return .invalidation(
            BridgeReviewProtocolFrameBuilder.invalidation(
                request: BridgeReviewProtocolInvalidationBuildRequest(
                    streamId: "review:\(paneId.uuidString)",
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

private struct ReviewEndpointSelection {
    let base: BridgeSourceEndpoint
    let head: BridgeSourceEndpoint
    let comparisonSemantics: BridgeReviewQuery.ComparisonSemantics
    let pathScope: [String]
}
