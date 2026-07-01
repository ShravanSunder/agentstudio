import Foundation
import os.log

private struct BridgeWorktreeOpenTreeExtent: Sendable {
    let pathCount: Int?
    let estimatedTotalHeightPixels: Double?
}

private let bridgeWorktreeFileSurfaceLogger = Logger(
    subsystem: "com.agentstudio",
    category: "BridgeWorktreeFileSurface"
)
private let worktreeFileTreeRowHeightPixels: Double = 24
private let worktreeFileTreeWindowRowLimit =
    AppPolicies.Bridge.worktreeFileTreeMetadataWindowRowLimit
private let estimatedRowsPerScopedDirectory = 1000
private let estimatedRowsForRootDirectory = 10_000

struct BridgeWorktreeFileSurfaceActiveSourceState: Sendable {
    var openedSource: BridgeWorktreeFileOpenedSource
    let source: BridgeWorktreeFileSurfaceSourceIdentity
    let streamId: String
    var nextSequence: Int
}

enum BridgeWorktreeFileSurfaceSequenceReservationError: Error, Equatable, Sendable {
    case invalidCount
    case noActiveSource
    case sourceMismatch
    case streamMismatch
    case staleGeneration
}

@MainActor
extension BridgePaneController {
    func handleWorktreeFileSurfaceOpenSourceStream(
        _ params: WorktreeFileSurfaceMethods.OpenSourceStreamMethod.Params
    ) async throws -> BridgeWorktreeFileSurfaceOpenSourceOutcome {
        let worktree = try makeWorktreeFileSurfaceAuthority()
        let generation = nextWorktreeFileSurfaceGeneration + 1
        nextWorktreeFileSurfaceGeneration = generation
        var openedSource: BridgeWorktreeFileOpenedSource
        do {
            openedSource = try BridgeWorktreeFileSourceProvider.openSource(
                spec: params,
                worktree: worktree,
                subscriptionGeneration: generation
            )
        } catch BridgeWorktreeFileSourceProviderError.worktreeMismatch {
            throw RPCMethodDispatchError.invalidParams("worktree_file.worktree_mismatch")
        } catch BridgeWorktreeFileSourceProviderError.rootTokenMismatch {
            throw RPCMethodDispatchError.invalidParams("worktree_file.root_token_mismatch")
        } catch BridgeWorktreeFileSourceProviderError.selectorEscapesRoot {
            throw RPCMethodDispatchError.invalidParams("worktree_file.selector_escapes_root")
        } catch BridgeWorktreeFileSourceProviderError.unsupportedReservedContract {
            throw RPCMethodDispatchError.invalidParams("worktree_file.unsupported_reserved_contract")
        }

        let streamId = "worktree-file:\(paneId.uuidString)"
        pendingWorktreeFileIntakeFrames.removeAll(keepingCapacity: true)
        worktreeFileIntakeReadyStreamId = nil
        activeWorktreeFileTreeWindowTask?.cancel()
        activeWorktreeFileTreeWindowTask = nil
        resourceLeaseRegistry.revokeSynchronously(paneId: paneId, protocolId: "worktree-file")
        activeWorktreeFileSurfaceSource = BridgeWorktreeFileSurfaceActiveSourceState(
            openedSource: openedSource,
            source: openedSource.source,
            streamId: streamId,
            nextSequence: 1
        )
        activeWorktreeFileTreeWindowTask = Task { @MainActor [weak self] in
            await self?.prepareInitialWorktreeFileSurfaceMetadata(
                rootURL: worktree.path,
                openedSource: openedSource,
                requestSelector: params,
                streamId: streamId,
                generation: generation
            )
        }
        return BridgeWorktreeFileSurfaceOpenSourceOutcome(
            streamId: streamId,
            generation: generation
        )
    }

    func handleWorktreeFileDescriptorRequest(
        _ params: WorktreeFileSurfaceMethods.RequestFileDescriptorMethod.Params
    ) async throws -> RPCNoResponse {
        guard let activeSource = activeWorktreeFileSurfaceSource else {
            throw RPCMethodDispatchError.invalidParams("worktree_file.no_active_source")
        }
        guard activeSource.source == params.sourceIdentity else {
            throw RPCMethodDispatchError.invalidParams("worktree_file.source_identity_mismatch")
        }
        guard activeSource.source.subscriptionGeneration == nextWorktreeFileSurfaceGeneration else {
            throw RPCMethodDispatchError.invalidParams("worktree_file.stale_source_generation")
        }
        guard
            BridgeWorktreeFileMaterializer.canMaterializeDemandPath(
                params.path,
                openedSource: activeSource.openedSource
            )
        else {
            throw RPCMethodDispatchError.invalidParams("worktree_file.descriptor_path_out_of_scope")
        }
        let rootURL = try worktreeFileSurfaceRootURL()
        let materializedDescriptor = try await BridgeWorktreeFileMaterializer.materializeRequestedFileDescriptor(
            request: BridgeWorktreeRequestedFileDescriptorRequest(
                rootURL: rootURL,
                paneId: paneId,
                ignorePolicy: activeSource.openedSource.ignorePolicy,
                source: activeSource.source,
                streamId: activeSource.streamId,
                sequence: 0,
                relativePath: params.path
            )
        )
        guard materializedDescriptor.frame.descriptor.fileId == params.fileId else {
            throw RPCMethodDispatchError.invalidParams("worktree_file.descriptor_file_id_mismatch")
        }
        guard materializedDescriptor.frame.descriptor.path == params.path else {
            throw RPCMethodDispatchError.invalidParams("worktree_file.descriptor_path_mismatch")
        }
        guard activeSource.source.subscriptionGeneration == nextWorktreeFileSurfaceGeneration else {
            throw RPCMethodDispatchError.invalidParams("worktree_file.stale_source_generation")
        }
        try await activateWorktreeFileSurfaceLeases([
            materializedDescriptor.frame.descriptor.contentDescriptor.descriptor
        ])
        await worktreeFileResourceStore.register(
            materializedDescriptor.resource,
            body: materializedDescriptor.body
        )
        let sequence = try reserveWorktreeFileSurfaceSequenceBlock(
            count: 1,
            source: activeSource.source,
            streamId: activeSource.streamId
        )
        let frame = BridgeWorktreeFileDescriptorFrame(
            streamId: activeSource.streamId,
            sequence: sequence,
            descriptor: materializedDescriptor.frame.descriptor
        )
        try await dispatchWorktreeFileIntakeFrames(
            [frame],
            allowsTreeWindowPublication: params.lane == .foreground
        )
        return RPCNoResponse()
    }

    func handleWorktreeFileMetadataInterestUpdate(
        _ params: ReviewMethods.MetadataInterestUpdateMethod.Params
    ) async throws {
        guard params.protocolId == "worktree-file" else {
            throw RPCMethodDispatchError.invalidParams("metadata interest protocol must be worktree-file")
        }
        guard let activeSource = activeWorktreeFileSurfaceSource else {
            throw RPCMethodDispatchError.invalidParams("worktree_file.no_active_source")
        }
        if let streamId = params.streamId, streamId != activeSource.streamId {
            throw RPCMethodDispatchError.invalidParams("worktree_file.metadata_interest_stale_stream")
        }
        if let generation = params.generation, generation != activeSource.source.subscriptionGeneration {
            throw RPCMethodDispatchError.invalidParams("worktree_file.metadata_interest_stale_generation")
        }
        let requestedPaths = Self.uniqueWorktreeMetadataInterestPaths(
            params.paths ?? [],
            openedSource: activeSource.openedSource
        )
        guard !requestedPaths.isEmpty else {
            return
        }

        let rootURL = try worktreeFileSurfaceRootURL()
        let rows = try await BridgeWorktreeFileMaterializer.materializeAllTreeRows(
            request: BridgeWorktreeFileMaterializationRequest(
                rootURL: rootURL,
                paneId: paneId,
                openedSource: activeSource.openedSource,
                streamId: activeSource.streamId,
                firstSequence: 0
            )
        ).filter { requestedPaths.contains($0.path) }
        guard !rows.isEmpty else {
            return
        }
        guard let latestActiveSource = activeWorktreeFileSurfaceSource,
            latestActiveSource.source == activeSource.source,
            latestActiveSource.streamId == activeSource.streamId,
            latestActiveSource.source.subscriptionGeneration == nextWorktreeFileSurfaceGeneration
        else {
            return
        }
        let sequence = try reserveWorktreeFileSurfaceSequenceBlock(
            count: 1,
            source: latestActiveSource.source,
            streamId: latestActiveSource.streamId
        )
        let frame = BridgeWorktreeFileSurfaceFrameBuilder.treeWindow(
            request: BridgeWorktreeTreeWindowBuildRequest(
                paneId: paneId.uuidString,
                source: latestActiveSource.source,
                streamId: latestActiveSource.streamId,
                sequence: sequence,
                treeWindowKey:
                    "worktree-interest-\(latestActiveSource.source.sourceId)-\(latestActiveSource.source.subscriptionGeneration)-\(params.lane.rawValue)-\(sequence)",
                pathScope: latestActiveSource.openedSource.canonicalPathScope,
                treePathCount: nil,
                treeEstimatedTotalHeightPixels: nil,
                treeWindowStartIndex: nil,
                treeWindowRowCount: rows.count,
                treeRowHeightPixels: worktreeFileTreeRowHeightPixels,
                rows: rows
            )
        )
        try await dispatchWorktreeFileIntakeFrames(
            [frame],
            allowsTreeWindowPublication: true,
            pendingPlacement: .beforeIdleTreeWindows,
            metadataLineageOverride: Self.worktreeMetadataLineage(for: params.lane)
        )
    }

    func publishWorktreeFileSurfaceStatus(_ status: GitWorkingTreeStatus) async throws {
        guard let activeSource = activeWorktreeFileSurfaceSource else {
            return
        }
        guard activeSource.source.subscriptionGeneration == nextWorktreeFileSurfaceGeneration else {
            return
        }
        let sequence = try reserveWorktreeFileSurfaceSequenceBlock(
            count: 1,
            source: activeSource.source,
            streamId: activeSource.streamId
        )
        let frame = BridgeWorktreeFileSurfaceClassifier.statusPatchFrame(
            request: BridgeWorktreeStatusPatchBuildRequest(
                source: activeSource.source,
                streamId: activeSource.streamId,
                sequence: sequence,
                status: status
            )
        )
        try await dispatchWorktreeFileIntakeFrames([frame])
    }

    func publishWorktreeFileSurfaceChangeset(_ changeset: FileChangeset) async throws {
        guard let activeSource = activeWorktreeFileSurfaceSource else {
            return
        }
        guard activeSource.source.subscriptionGeneration == nextWorktreeFileSurfaceGeneration else {
            return
        }
        let scopedChangedPaths = changeset.paths.filter { path in
            BridgeWorktreeFileMaterializer.canMaterializeDemandPath(path, openedSource: activeSource.openedSource)
        }
        let scopedChangeset = FileChangeset(
            worktreeId: changeset.worktreeId,
            repoId: changeset.repoId,
            rootPath: changeset.rootPath,
            paths: scopedChangedPaths,
            containsGitInternalChanges: changeset.containsGitInternalChanges,
            suppressedIgnoredPathCount: changeset.suppressedIgnoredPathCount,
            suppressedGitInternalPathCount: changeset.suppressedGitInternalPathCount,
            timestamp: changeset.timestamp,
            batchSeq: changeset.batchSeq
        )
        let rootURL = try worktreeFileSurfaceRootURL()
        let materializedDescriptors = try await BridgeWorktreeFileMaterializer.materializeChangedFileDescriptors(
            request: BridgeWorktreeChangedFileMaterializationRequest(
                rootURL: rootURL,
                paneId: paneId,
                ignorePolicy: activeSource.openedSource.ignorePolicy,
                source: activeSource.source,
                streamId: activeSource.streamId,
                firstSequence: activeSource.nextSequence,
                relativePaths: scopedChangedPaths
            )
        )
        guard let latestActiveSource = activeWorktreeFileSurfaceSource,
            latestActiveSource.source == activeSource.source,
            latestActiveSource.streamId == activeSource.streamId,
            latestActiveSource.source.subscriptionGeneration == nextWorktreeFileSurfaceGeneration
        else {
            return
        }
        try await activateWorktreeFileSurfaceLeases(
            materializedDescriptors.map { $0.frame.descriptor.contentDescriptor.descriptor }
        )
        for descriptor in materializedDescriptors {
            await worktreeFileResourceStore.register(descriptor.resource, body: descriptor.body)
        }
        let latestDescriptorsByPath = Dictionary(
            uniqueKeysWithValues: materializedDescriptors.map {
                ($0.frame.descriptor.path, $0.frame.descriptor)
            }
        )
        let invalidationFrameCount = scopedChangeset.paths.filter { !Self.isWorktreeFileGitInternalPath($0) }.count
        guard invalidationFrameCount > 0 else {
            if changeset.containsGitInternalChanges {
                let sequence = try reserveWorktreeFileSurfaceSequenceBlock(
                    count: 1,
                    source: latestActiveSource.source,
                    streamId: latestActiveSource.streamId
                )
                let statusFrame = BridgeWorktreeFileSurfaceClassifier.statusInvalidatedFrame(
                    request: BridgeWorktreeStatusInvalidationBuildRequest(
                        source: latestActiveSource.source,
                        streamId: latestActiveSource.streamId,
                        sequence: sequence,
                        changeset: changeset
                    )
                )
                try await dispatchWorktreeFileIntakeFrames([statusFrame])
            }
            return
        }
        let firstSequence = try reserveWorktreeFileSurfaceSequenceBlock(
            count: invalidationFrameCount,
            source: latestActiveSource.source,
            streamId: latestActiveSource.streamId
        )
        let invalidationFrames = BridgeWorktreeFileSurfaceClassifier.fileInvalidationFrames(
            request: BridgeWorktreeFileChangesetClassificationRequest(
                source: latestActiveSource.source,
                streamId: latestActiveSource.streamId,
                firstSequence: firstSequence,
                changeset: scopedChangeset,
                latestDescriptorsByPath: latestDescriptorsByPath
            )
        )
        try await dispatchWorktreeFileIntakeFrames(invalidationFrames)
    }

    func publishWorktreeFileSurfaceReset(reason: BridgeWorktreeResetReason) async throws {
        guard let activeSource = activeWorktreeFileSurfaceSource else {
            return
        }
        guard activeSource.source.subscriptionGeneration == nextWorktreeFileSurfaceGeneration else {
            return
        }
        let frame = BridgeWorktreeFileSurfaceFrameBuilder.reset(
            request: BridgeWorktreeResetBuildRequest(
                streamId: activeSource.streamId,
                sequence: activeSource.nextSequence,
                reason: reason,
                source: activeSource.source,
                replacementDescriptor: nil
            )
        )
        activeWorktreeFileTreeWindowTask?.cancel()
        activeWorktreeFileTreeWindowTask = nil
        activeWorktreeFileSurfaceSource = nil
        nextWorktreeFileSurfaceGeneration += 1
        pendingWorktreeFileIntakeFrames.removeAll(keepingCapacity: false)
        resourceLeaseRegistry.revokeSynchronously(paneId: paneId, protocolId: "worktree-file")
        await worktreeFileResourceStore.reset(protocolId: "worktree-file")
        try await dispatchWorktreeFileIntakeFrames([frame])
        worktreeFileIntakeReadyStreamId = nil
    }

    private func makeWorktreeFileSurfaceAuthority() throws -> Worktree {
        guard let repoId = runtime.metadata.repoId,
            let worktreeId = runtime.metadata.worktreeId
        else {
            throw RPCMethodDispatchError.invalidParams("worktree_file.missing_worktree_identity")
        }
        let rootURL = try worktreeFileSurfaceRootURL()
        return Worktree(
            id: worktreeId,
            repoId: repoId,
            name: runtime.metadata.worktreeName ?? rootURL.lastPathComponent,
            path: rootURL
        )
    }

    private func worktreeFileSurfaceRootURL() throws -> URL {
        if case .workspace(let rootPath, _) = bridgePaneState.source {
            return URL(fileURLWithPath: rootPath).standardizedFileURL.resolvingSymlinksInPath()
        }
        if let cwd = runtime.metadata.cwd {
            return cwd.standardizedFileURL.resolvingSymlinksInPath()
        }
        throw RPCMethodDispatchError.invalidParams("worktree_file.missing_root_path")
    }

    private func publishRemainingWorktreeFileTreeWindows(
        rootURL: URL,
        openedSource: BridgeWorktreeFileOpenedSource,
        streamId: String,
        treeExtent: BridgeWorktreeOpenTreeExtent,
        initialRowCount: Int,
        openStartedAt: ContinuousClock.Instant
    ) async {
        var emittedWindowCount = 0
        var latestDiscoveredRowCount = initialRowCount
        var firstPublishedSequence: Int?
        do {
            let materializationRequest = BridgeWorktreeFileMaterializationRequest(
                rootURL: rootURL,
                paneId: paneId,
                openedSource: openedSource,
                streamId: streamId,
                firstSequence: 1
            )
            for try await batch in BridgeWorktreeFileMaterializer.materializeTreeRowWindows(
                request: materializationRequest,
                afterCount: initialRowCount,
                windowSize: worktreeFileTreeWindowRowLimit
            ) {
                guard !Task.isCancelled else {
                    throw CancellationError()
                }
                latestDiscoveredRowCount = batch.discoveredRowCount
                guard let activeSource = activeWorktreeFileSurfaceSource,
                    activeSource.source == openedSource.source,
                    activeSource.streamId == streamId,
                    activeSource.source.subscriptionGeneration == nextWorktreeFileSurfaceGeneration
                else {
                    await recordWorktreeFileTreeWindowPublicationTelemetry(
                        resultReason: "stale_source_before_window_dispatch",
                        initialRowCount: initialRowCount,
                        allRowCount: latestDiscoveredRowCount,
                        windowCount: emittedWindowCount,
                        firstSequence: firstPublishedSequence,
                        pendingFrameCount: pendingWorktreeFileIntakeFrames.count
                    )
                    return
                }
                let batchPublishStart = ContinuousClock.now
                let publication = try await publishWorktreeFileTreeWindowBatch(
                    batch,
                    openedSource: openedSource,
                    streamId: streamId,
                    treeExtent: treeExtent
                )
                if firstPublishedSequence == nil {
                    firstPublishedSequence = publication.sequence
                }
                await recordWorktreeFileTreeWindowBatchTelemetry(
                    batch: batch,
                    publication: publication,
                    durationMilliseconds: Self.milliseconds(
                        from: batchPublishStart.duration(to: ContinuousClock.now)
                    ),
                    pendingFrameCount: pendingWorktreeFileIntakeFrames.count
                )
                emittedWindowCount += 1
                if worktreeFileIntakeReadyStreamId != nil {
                    await flushPendingWorktreeFileIntakeFrames()
                }
            }
            await recordNativeWorktreeFileFullManifestTelemetry(
                durationMilliseconds: Self.milliseconds(from: openStartedAt.duration(to: ContinuousClock.now)),
                expectedTotal: latestDiscoveredRowCount,
                emittedTotal: latestDiscoveredRowCount,
                remainingTotal: 0
            )
            await recordWorktreeFileTreeWindowPublicationTelemetry(
                resultReason: emittedWindowCount > 0 ? "dispatched" : "no_additional_rows",
                initialRowCount: initialRowCount,
                allRowCount: latestDiscoveredRowCount,
                windowCount: emittedWindowCount,
                firstSequence: firstPublishedSequence,
                pendingFrameCount: pendingWorktreeFileIntakeFrames.count
            )
        } catch is CancellationError {
            await recordWorktreeFileTreeWindowPublicationTelemetry(
                resultReason: "cancelled_error",
                initialRowCount: initialRowCount,
                allRowCount: latestDiscoveredRowCount,
                windowCount: emittedWindowCount,
                firstSequence: firstPublishedSequence,
                pendingFrameCount: pendingWorktreeFileIntakeFrames.count
            )
            return
        } catch {
            await recordWorktreeFileTreeWindowPublicationTelemetry(
                resultReason: "failed",
                initialRowCount: initialRowCount,
                allRowCount: latestDiscoveredRowCount,
                windowCount: emittedWindowCount,
                firstSequence: firstPublishedSequence,
                pendingFrameCount: pendingWorktreeFileIntakeFrames.count
            )
            bridgeWorktreeFileSurfaceLogger.warning(
                "[Bridge] Worktree/File tree window publication failed pane=\(self.paneId.uuidString, privacy: .public)"
            )
        }
    }

    private func prepareInitialWorktreeFileSurfaceMetadata(
        rootURL: URL,
        openedSource: BridgeWorktreeFileOpenedSource,
        requestSelector: BridgeWorktreeFileSurfaceSourceSpec,
        streamId: String,
        generation: Int
    ) async {
        let openStartedAt = ContinuousClock.now
        do {
            let ignorePolicy = await BridgeWorktreeFileIgnorePolicy.load(rootURL: rootURL)
            let openedSourceWithIgnorePolicy = openedSource.withIgnorePolicy(ignorePolicy)
            async let resolvedTreeExtent = Self.resolveOpenTreeExtent(
                rootURL: rootURL,
                scopedPaths: openedSourceWithIgnorePolicy.canonicalPathScope
            )
            async let resolvedTreeRows = BridgeWorktreeFileMaterializer.materializeInitialTreeRows(
                request: BridgeWorktreeFileMaterializationRequest(
                    rootURL: rootURL,
                    paneId: paneId,
                    openedSource: openedSourceWithIgnorePolicy,
                    streamId: streamId,
                    firstSequence: 1
                )
            )
            let treeExtent = await resolvedTreeExtent
            let initialTreeRows = try await resolvedTreeRows
            guard !Task.isCancelled,
                var activeSource = activeWorktreeFileSurfaceSource,
                activeSource.source == openedSource.source,
                activeSource.streamId == streamId,
                activeSource.source.subscriptionGeneration == generation,
                generation == nextWorktreeFileSurfaceGeneration
            else {
                return
            }
            activeSource.openedSource = openedSourceWithIgnorePolicy
            activeWorktreeFileSurfaceSource = activeSource
            let treePathCount: Int? =
                if let pathCount = treeExtent.pathCount {
                    max(pathCount, initialTreeRows.count)
                } else {
                    nil
                }
            await resourceLeaseRegistry.reset(paneId: paneId, protocolId: "worktree-file")
            await worktreeFileResourceStore.reset(protocolId: "worktree-file")
            let snapshotFrame = BridgeWorktreeFileSurfaceFrameBuilder.snapshot(
                request: BridgeWorktreeFileSnapshotBuildRequest(
                    paneId: paneId.uuidString,
                    source: openedSourceWithIgnorePolicy.source,
                    requestSelector: requestSelector,
                    streamId: streamId,
                    sequence: 0,
                    treePathCount: treePathCount,
                    treeEstimatedTotalHeightPixels: treeExtent.estimatedTotalHeightPixels,
                    treeWindowStartIndex: 0,
                    treeWindowRowCount: initialTreeRows.count,
                    treeRowHeightPixels: worktreeFileTreeRowHeightPixels,
                    treeRows: initialTreeRows,
                    includeStatusPatch: openedSourceWithIgnorePolicy.includeStatuses
                )
            )
            try await dispatchWorktreeFileIntakeFrames([snapshotFrame])
            await recordNativeWorktreeFileOpenToFirstWindowTelemetry(
                durationMilliseconds: Self.milliseconds(from: openStartedAt.duration(to: ContinuousClock.now)),
                emittedRows: initialTreeRows.count,
                expectedTotal: treePathCount
            )
            if worktreeFileIntakeReadyStreamId != nil {
                await flushPendingWorktreeFileIntakeFrames()
            }
            await publishRemainingWorktreeFileTreeWindows(
                rootURL: rootURL,
                openedSource: openedSourceWithIgnorePolicy,
                streamId: streamId,
                treeExtent: treeExtent,
                initialRowCount: initialTreeRows.count,
                openStartedAt: openStartedAt
            )
        } catch is CancellationError {
            return
        } catch {
            bridgeWorktreeFileSurfaceLogger.warning(
                "[Bridge] Worktree/File initial metadata preparation failed pane=\(self.paneId.uuidString, privacy: .public)"
            )
        }
    }

    private struct WorktreeFileTreeWindowPublicationTiming: Sendable {
        let dispatchElapsedMilliseconds: Double
        let prepareElapsedMilliseconds: Double
        let sequence: Int
    }

    private func recordNativeWorktreeFileOpenToFirstWindowTelemetry(
        durationMilliseconds: Double,
        emittedRows: Int,
        expectedTotal: Int?
    ) async {
        guard let telemetryRecorder else {
            return
        }
        var numericAttributes: [String: Double] = [
            "agentstudio.bridge.metadata_manifest.emitted_total": Double(emittedRows)
        ]
        if let expectedTotal {
            numericAttributes["agentstudio.bridge.metadata_manifest.expected_total"] = Double(expectedTotal)
            numericAttributes["agentstudio.bridge.metadata_manifest.remaining_total"] =
                Double(max(expectedTotal - emittedRows, 0))
        }
        await telemetryRecorder.record(
            sample: BridgeTelemetrySample(
                scope: .swift,
                name: "performance.bridge.native.metadata_open_to_first_window",
                durationMilliseconds: durationMilliseconds,
                traceContext: nil,
                stringAttributes: [
                    "agentstudio.bridge.phase": "metadata_open_to_first_window",
                    "agentstudio.bridge.plane": BridgeTelemetryPlane.data.rawValue,
                    "agentstudio.bridge.priority": BridgeTelemetryPriority.hot.rawValue,
                    "agentstudio.bridge.slice": BridgeTelemetrySlice.treePrepareInput.rawValue,
                    "agentstudio.bridge.transport": "swift",
                    "agentstudio.bridge.viewer": "file",
                ],
                numericAttributes: numericAttributes,
                booleanAttributes: [:]
            ),
            receivedAtUnixNano: UInt64(Date().timeIntervalSince1970 * 1_000_000_000)
        )
    }

    private func recordNativeWorktreeFileFullManifestTelemetry(
        durationMilliseconds: Double,
        expectedTotal: Int,
        emittedTotal: Int,
        remainingTotal: Int
    ) async {
        guard let telemetryRecorder else {
            return
        }
        await telemetryRecorder.record(
            sample: BridgeTelemetrySample(
                scope: .swift,
                name: "performance.bridge.native.metadata_full_manifest_complete",
                durationMilliseconds: durationMilliseconds,
                traceContext: nil,
                stringAttributes: [
                    "agentstudio.bridge.phase": "metadata_full_manifest_complete",
                    "agentstudio.bridge.plane": BridgeTelemetryPlane.data.rawValue,
                    "agentstudio.bridge.priority": BridgeTelemetryPriority.cold.rawValue,
                    "agentstudio.bridge.slice": BridgeTelemetrySlice.treePrepareInput.rawValue,
                    "agentstudio.bridge.transport": "swift",
                    "agentstudio.bridge.viewer": "file",
                ],
                numericAttributes: [
                    "agentstudio.bridge.metadata_manifest.emitted_total": Double(emittedTotal),
                    "agentstudio.bridge.metadata_manifest.expected_total": Double(expectedTotal),
                    "agentstudio.bridge.metadata_manifest.remaining_total": Double(remainingTotal),
                ],
                booleanAttributes: [
                    "agentstudio.bridge.metadata_manifest.complete": remainingTotal == 0
                ]
            ),
            receivedAtUnixNano: UInt64(Date().timeIntervalSince1970 * 1_000_000_000)
        )
    }

    private func publishWorktreeFileTreeWindowBatch(
        _ batch: BridgeWorktreeTreeRowWindowBatch,
        openedSource: BridgeWorktreeFileOpenedSource,
        streamId: String,
        treeExtent: BridgeWorktreeOpenTreeExtent
    ) async throws -> WorktreeFileTreeWindowPublicationTiming {
        beginWorktreeFileTreeWindowPublication()
        defer {
            finishWorktreeFileTreeWindowPublication()
        }
        let prepareStart = ContinuousClock.now
        let pathCount =
            if batch.isFinalWindow {
                batch.discoveredRowCount
            } else {
                treeExtent.pathCount.map { max($0, batch.discoveredRowCount) }
            }
        let preparedFrame = BridgeWorktreeFileSurfaceFrameBuilder.treeWindow(
            request: BridgeWorktreeTreeWindowBuildRequest(
                paneId: paneId.uuidString,
                source: openedSource.source,
                streamId: streamId,
                sequence: 0,
                treeWindowKey:
                    "worktree-tree-\(openedSource.source.sourceId)-\(openedSource.source.subscriptionGeneration)-\(batch.startIndex)",
                pathScope: openedSource.canonicalPathScope,
                treePathCount: pathCount,
                treeEstimatedTotalHeightPixels: treeExtent.estimatedTotalHeightPixels,
                treeWindowStartIndex: batch.startIndex,
                treeWindowRowCount: batch.rows.count,
                treeRowHeightPixels: worktreeFileTreeRowHeightPixels,
                rows: batch.rows
            )
        )
        guard !Task.isCancelled,
            let currentActiveSource = activeWorktreeFileSurfaceSource,
            currentActiveSource.source == openedSource.source,
            currentActiveSource.streamId == streamId,
            currentActiveSource.source.subscriptionGeneration == nextWorktreeFileSurfaceGeneration
        else {
            throw CancellationError()
        }
        let sequence = try reserveWorktreeFileSurfaceSequenceBlock(
            count: 1,
            source: currentActiveSource.source,
            streamId: currentActiveSource.streamId
        )
        let frame = BridgeWorktreeTreeWindowFrame(
            streamId: streamId,
            sequence: sequence,
            projectionIdentity: preparedFrame.projectionIdentity,
            rows: preparedFrame.rows,
            treeSizeFacts: preparedFrame.treeSizeFacts
        )
        let prepareElapsedMilliseconds = Self.milliseconds(from: prepareStart.duration(to: ContinuousClock.now))
        let dispatchStart = ContinuousClock.now
        try await dispatchWorktreeFileIntakeFrames([frame], allowsTreeWindowPublication: true)
        let dispatchElapsedMilliseconds = Self.milliseconds(from: dispatchStart.duration(to: ContinuousClock.now))
        return WorktreeFileTreeWindowPublicationTiming(
            dispatchElapsedMilliseconds: dispatchElapsedMilliseconds,
            prepareElapsedMilliseconds: prepareElapsedMilliseconds,
            sequence: sequence
        )
    }

    func beginWorktreeFileTreeWindowPublication() {
        isPublishingWorktreeFileTreeWindows = true
    }

    func finishWorktreeFileTreeWindowPublication() {
        isPublishingWorktreeFileTreeWindows = false
    }

    private func recordWorktreeFileTreeWindowPublicationTelemetry(
        resultReason: String,
        initialRowCount: Int,
        allRowCount: Int,
        windowCount: Int,
        firstSequence: Int?,
        pendingFrameCount: Int
    ) async {
        guard let telemetryRecorder else {
            return
        }
        var numericAttributes: [String: Double] = [
            "agentstudio.bridge.worktree_file.tree.initial_row.count": Double(initialRowCount),
            "agentstudio.bridge.worktree_file.tree.all_row.count": Double(allRowCount),
            "agentstudio.bridge.worktree_file.tree.window.count": Double(windowCount),
            "agentstudio.bridge.worktree_file.pending_frame.count": Double(pendingFrameCount),
        ]
        if let firstSequence {
            numericAttributes["agentstudio.bridge.worktree_file.tree.first_sequence"] = Double(firstSequence)
        }
        await telemetryRecorder.record(
            sample: BridgeTelemetrySample(
                scope: .swift,
                name: "performance.bridge.swift.worktree_file_tree_window_publication",
                durationMilliseconds: nil,
                traceContext: nil,
                stringAttributes: [
                    "agentstudio.bridge.phase": "worktree_file_tree_window_publication",
                    "agentstudio.bridge.plane": BridgeTelemetryPlane.data.rawValue,
                    "agentstudio.bridge.priority": BridgeTelemetryPriority.cold.rawValue,
                    "agentstudio.bridge.result_reason": resultReason,
                    "agentstudio.bridge.slice": BridgeTelemetrySlice.treePrepareInput.rawValue,
                    "agentstudio.bridge.transport": "swift",
                ],
                numericAttributes: numericAttributes,
                booleanAttributes: [:]
            ),
            receivedAtUnixNano: UInt64(Date().timeIntervalSince1970 * 1_000_000_000)
        )
    }

    private func recordWorktreeFileTreeWindowBatchTelemetry(
        batch: BridgeWorktreeTreeRowWindowBatch,
        publication: WorktreeFileTreeWindowPublicationTiming,
        durationMilliseconds: Double,
        pendingFrameCount: Int
    ) async {
        guard let telemetryRecorder else {
            return
        }
        await telemetryRecorder.record(
            sample: BridgeTelemetrySample(
                scope: .swift,
                name: "performance.bridge.swift.worktree_file_tree_window_batch",
                durationMilliseconds: durationMilliseconds,
                traceContext: nil,
                stringAttributes: [
                    "agentstudio.bridge.phase": "worktree_file_tree_window_batch",
                    "agentstudio.bridge.plane": BridgeTelemetryPlane.data.rawValue,
                    "agentstudio.bridge.priority": BridgeTelemetryPriority.cold.rawValue,
                    "agentstudio.bridge.slice": BridgeTelemetrySlice.treePrepareInput.rawValue,
                    "agentstudio.bridge.transport": "swift",
                ],
                numericAttributes: [
                    "agentstudio.bridge.worktree_file.pending_frame.count": Double(pendingFrameCount),
                    "agentstudio.bridge.worktree_file.tree.discovered_row.count": Double(batch.discoveredRowCount),
                    "agentstudio.bridge.worktree_file.tree.window.dispatch_elapsed_ms":
                        publication.dispatchElapsedMilliseconds,
                    "agentstudio.bridge.worktree_file.tree.window.prepare_elapsed_ms":
                        publication.prepareElapsedMilliseconds,
                    "agentstudio.bridge.worktree_file.tree.window.row.count": Double(batch.rows.count),
                    "agentstudio.bridge.worktree_file.tree.window.sequence": Double(publication.sequence),
                    "agentstudio.bridge.worktree_file.tree.window.start_index": Double(batch.startIndex),
                ],
                booleanAttributes: [
                    "agentstudio.bridge.worktree_file.tree.window.is_final": batch.isFinalWindow
                ]
            ),
            receivedAtUnixNano: UInt64(Date().timeIntervalSince1970 * 1_000_000_000)
        )
    }

    private nonisolated static func milliseconds(from duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000
            + Double(duration.components.attoseconds) / 1_000_000_000_000_000
    }

    private nonisolated static func resolveOpenTreeExtent(
        rootURL: URL,
        scopedPaths: [String]
    ) async -> BridgeWorktreeOpenTreeExtent {
        // swiftlint:disable:next no_task_detached
        await Task.detached(priority: .utility) {
            let targetPaths =
                scopedPaths.isEmpty || scopedPaths == ["."]
                ? [rootURL]
                : scopedPaths.map { rootURL.appending(path: $0) }
            var fileCount = 0
            var missingCount = 0
            var directoryCount = 0
            for targetPath in targetPaths {
                let values = try? targetPath.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
                if values?.isRegularFile == true {
                    fileCount += 1
                } else if values?.isDirectory == true {
                    directoryCount += 1
                } else {
                    missingCount += 1
                }
            }
            if directoryCount == 0 {
                return BridgeWorktreeOpenTreeExtent(pathCount: fileCount, estimatedTotalHeightPixels: nil)
            }
            let estimatedRowsPerDirectory =
                scopedPaths.isEmpty || scopedPaths == ["."]
                ? estimatedRowsForRootDirectory
                : estimatedRowsPerScopedDirectory
            let estimatedRows =
                fileCount
                + missingCount
                + (directoryCount * estimatedRowsPerDirectory)
            return BridgeWorktreeOpenTreeExtent(
                pathCount: nil,
                estimatedTotalHeightPixels: Double(estimatedRows) * worktreeFileTreeRowHeightPixels
            )
        }.value
    }

    private nonisolated static func isWorktreeFileGitInternalPath(_ path: String) -> Bool {
        path == ".git" || path.hasPrefix(".git/")
    }

    func reserveWorktreeFileSurfaceSequenceBlock(
        count: Int,
        source: BridgeWorktreeFileSurfaceSourceIdentity,
        streamId: String
    ) throws -> Int {
        guard count > 0 else {
            throw BridgeWorktreeFileSurfaceSequenceReservationError.invalidCount
        }
        guard var activeSource = activeWorktreeFileSurfaceSource else {
            throw BridgeWorktreeFileSurfaceSequenceReservationError.noActiveSource
        }
        guard activeSource.source == source else {
            throw BridgeWorktreeFileSurfaceSequenceReservationError.sourceMismatch
        }
        guard activeSource.streamId == streamId else {
            throw BridgeWorktreeFileSurfaceSequenceReservationError.streamMismatch
        }
        guard activeSource.source.subscriptionGeneration == nextWorktreeFileSurfaceGeneration else {
            throw BridgeWorktreeFileSurfaceSequenceReservationError.staleGeneration
        }
        let firstSequence = activeSource.nextSequence
        activeSource.nextSequence += count
        activeWorktreeFileSurfaceSource = activeSource
        return firstSequence
    }

    private func activateWorktreeFileSurfaceLeases(
        _ descriptors: [BridgeResourceDescriptor]
    ) async throws {
        for descriptor in descriptors {
            guard
                let resource = BridgeTransportResourceURL.parse(
                    descriptor.resourceUrl,
                    allowedResourceKindsByProtocol: BridgeResourceProtocolRegistry.reviewViewerAllowedResourceKinds
                )
            else {
                throw RPCMethodDispatchError.handlerFailure("worktree_file.invalid_descriptor_url")
            }
            let expectedRevocationRevision = resourceLeaseRegistry.revocationRevision(
                paneId: paneId,
                protocolId: resource.protocolId,
                resourceKind: resource.resourceKind
            )
            let registered = await resourceLeaseRegistry.register(
                resource,
                paneId: paneId,
                descriptorId: descriptor.descriptorId,
                maxBytes: descriptor.content.maxBytes,
                expectedRevocationRevision: expectedRevocationRevision
            )
            guard registered else {
                throw RPCMethodDispatchError.handlerFailure("worktree_file.descriptor_lease_registration_failed")
            }
        }
    }

    private nonisolated static func uniqueWorktreeMetadataInterestPaths(
        _ paths: [String],
        openedSource: BridgeWorktreeFileOpenedSource
    ) -> Set<String> {
        var seenPaths = Set<String>()
        for path in paths
        where BridgeWorktreeFileMaterializer.canMaterializeDemandPath(
            path,
            openedSource: openedSource
        ) {
            seenPaths.insert(path)
        }
        return seenPaths
    }

    private nonisolated static func worktreeMetadataLineage(
        for lane: BridgeDemandLane
    ) -> BridgeWorktreeFileMetadataLineage {
        switch lane {
        case .foreground, .active:
            BridgeWorktreeFileMetadataLineage(loadedBy: "foreground", lane: lane.rawValue)
        case .visible:
            BridgeWorktreeFileMetadataLineage(loadedBy: "visible", lane: lane.rawValue)
        case .nearby:
            BridgeWorktreeFileMetadataLineage(loadedBy: "nearby", lane: lane.rawValue)
        case .speculative:
            BridgeWorktreeFileMetadataLineage(loadedBy: "speculative", lane: lane.rawValue)
        case .idle:
            BridgeWorktreeFileMetadataLineage(loadedBy: "idle", lane: lane.rawValue)
        }
    }

}
