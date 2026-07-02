import Foundation
import os.log

private let bridgeWorktreeFileManifestLogger = Logger(
    subsystem: "com.agentstudio",
    category: "BridgeWorktreeFileManifest"
)
private let worktreeFileTreeWindowRowLimit =
    AppPolicies.Bridge.worktreeFileTreeMetadataWindowRowLimit
private let estimatedRowsPerScopedDirectory = 1000
private let estimatedRowsForRootDirectory = 10_000

struct BridgeWorktreeOpenTreeExtent: Sendable {
    let pathCount: Int?
    let estimatedTotalHeightPixels: Double?
}

@MainActor
extension BridgePaneController {
    private struct WorktreeFileManifestPublication {
        let openedSource: BridgeWorktreeFileOpenedSource
        let requestSelector: BridgeWorktreeFileSurfaceSourceSpec
        let rootURL: URL
        let streamId: String
        let treeExtent: BridgeWorktreeOpenTreeExtent
        let openStartedAt: ContinuousClock.Instant
    }

    func prepareInitialWorktreeFileSurfaceMetadata(
        rootURL: URL,
        openedSource: BridgeWorktreeFileOpenedSource,
        requestSelector: BridgeWorktreeFileSurfaceSourceSpec,
        streamId: String,
        generation: Int
    ) async {
        let openStartedAt = ContinuousClock.now
        let ignorePolicy = await BridgeWorktreeFileIgnorePolicy.load(rootURL: rootURL)
        let openedSourceWithIgnorePolicy = openedSource.withIgnorePolicy(ignorePolicy)
        let treeExtent = await Self.resolveOpenTreeExtent(
            rootURL: rootURL,
            scopedPaths: openedSourceWithIgnorePolicy.canonicalPathScope
        )
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
        guard let manifestIndex = activeWorktreeFileManifestIndex,
            manifestIndex.generation == generation
        else {
            return
        }
        await resourceLeaseRegistry.reset(paneId: paneId, protocolId: "worktree-file")
        await worktreeFileResourceStore.reset(protocolId: "worktree-file")
        await publishWorktreeFileSurfaceManifest(
            publication: WorktreeFileManifestPublication(
                openedSource: openedSourceWithIgnorePolicy,
                requestSelector: requestSelector,
                rootURL: rootURL,
                streamId: streamId,
                treeExtent: treeExtent,
                openStartedAt: openStartedAt
            ),
            manifestIndex: manifestIndex
        )
    }

    private struct WorktreeFileManifestCounters {
        var snapshotRowCount = 0
        var emittedWindowCount = 0
        var latestDiscoveredRowCount = 0
        var firstPublishedSequence: Int?
        var snapshotSent = false
    }

    // Single enumeration per accepted generation: one walk feeds the manifest
    // index; the first window becomes the snapshot and the remaining windows
    // publish as continuation frames from the same pass. Interest serving
    // reads the index and never re-walks.
    private func publishWorktreeFileSurfaceManifest(
        publication: WorktreeFileManifestPublication,
        manifestIndex: BridgeWorktreeFileManifestIndex
    ) async {
        var counters = WorktreeFileManifestCounters()
        do {
            await manifestIndex.beginEnumeration()
            for try await batch in BridgeWorktreeFileMaterializer.materializeTreeRowWindows(
                request: BridgeWorktreeFileMaterializationRequest(
                    rootURL: publication.rootURL,
                    paneId: paneId,
                    openedSource: publication.openedSource,
                    streamId: publication.streamId,
                    firstSequence: 1
                ),
                afterCount: 0,
                windowSize: worktreeFileTreeWindowRowLimit
            ) {
                guard !Task.isCancelled else {
                    throw CancellationError()
                }
                counters.latestDiscoveredRowCount = batch.discoveredRowCount
                guard isWorktreeFileManifestSourceCurrent(publication: publication) else {
                    await recordManifestPublicationOutcome(
                        "stale_source_before_window_dispatch",
                        counters: counters
                    )
                    return
                }
                await manifestIndex.appendEnumeratedRows(batch.rows)
                if counters.snapshotSent {
                    await publishManifestContinuationWindow(
                        batch: batch,
                        publication: publication,
                        counters: &counters
                    )
                } else {
                    counters.snapshotSent = true
                    counters.snapshotRowCount = batch.rows.count
                    await dispatchWorktreeFileSurfaceSnapshot(
                        rows: batch.rows,
                        publication: publication
                    )
                }
            }
            if !counters.snapshotSent {
                await dispatchWorktreeFileSurfaceSnapshot(rows: [], publication: publication)
            }
            await manifestIndex.markEnumerationComplete()
            await recordNativeWorktreeFileFullManifestTelemetry(
                durationMilliseconds: Self.milliseconds(
                    from: publication.openStartedAt.duration(to: ContinuousClock.now)
                ),
                expectedTotal: counters.latestDiscoveredRowCount,
                emittedTotal: counters.latestDiscoveredRowCount,
                remainingTotal: 0
            )
            await recordManifestPublicationOutcome(
                counters.emittedWindowCount > 0 ? "dispatched" : "no_additional_rows",
                counters: counters
            )
        } catch is CancellationError {
            await recordManifestPublicationOutcome("cancelled_error", counters: counters)
        } catch {
            await recordManifestPublicationOutcome("failed", counters: counters)
            bridgeWorktreeFileManifestLogger.warning(
                "[Bridge] Worktree/File initial metadata preparation failed pane=\(self.paneId.uuidString, privacy: .public)"
            )
        }
    }

    /// Watch events patch the manifest index (spec: manifest index contract,
    /// live updates): stat-truth reconciles the changed paths against the
    /// accepted generation's manifest and emits one `worktree.treeDelta`
    /// frame so the browser tree stays aligned without a reset.
    func reconcileWorktreeFileManifestIndexForWatchEvent(
        changedPaths: [String],
        latestActiveSource: BridgeWorktreeFileSurfaceActiveSourceState,
        rootURL: URL
    ) async throws {
        guard let manifestIndex = activeWorktreeFileManifestIndex,
            manifestIndex.generation == latestActiveSource.source.subscriptionGeneration,
            !changedPaths.isEmpty
        else {
            return
        }
        let refreshed = await BridgeWorktreeFileMaterializer.refreshTreeRows(
            rootURL: rootURL,
            relativePaths: Set(changedPaths),
            includeAncestorDirectories: true
        )
        guard let currentSource = activeWorktreeFileSurfaceSource,
            currentSource.source == latestActiveSource.source,
            currentSource.source.subscriptionGeneration == nextWorktreeFileSurfaceGeneration
        else {
            return
        }
        await manifestIndex.upsertRows(refreshed.rows)
        let removedRows = await manifestIndex.removePaths(refreshed.missingPaths)
        var operations: [BridgeWorktreeTreeOperation] = []
        if !refreshed.rows.isEmpty {
            operations.append(.upsertRows(refreshed.rows))
        }
        if !removedRows.isEmpty {
            operations.append(
                .removeRows(
                    rowIds: removedRows.map(\.rowId),
                    paths: removedRows.map(\.path)
                )
            )
        }
        guard !operations.isEmpty else {
            return
        }
        let generation = latestActiveSource.source.subscriptionGeneration
        let deltaOperations = operations
        await enqueueWorktreeFileMetadataJob(lane: .active, generation: generation) { [weak self] in
            guard let self else { return true }
            return await self.deliverWorktreeFileFrameJob(generation: generation) { current, sequence in
                BridgeWorktreeTreeDeltaFrame(
                    streamId: current.streamId,
                    generation: current.source.subscriptionGeneration,
                    sequence: sequence,
                    operations: deltaOperations
                )
            }
        }
    }

    private func isWorktreeFileManifestSourceCurrent(
        publication: WorktreeFileManifestPublication
    ) -> Bool {
        guard let activeSource = activeWorktreeFileSurfaceSource else {
            return false
        }
        return activeSource.source == publication.openedSource.source
            && activeSource.streamId == publication.streamId
            && activeSource.source.subscriptionGeneration == nextWorktreeFileSurfaceGeneration
    }

    /// Enqueues one continuation window as an idle-lane job. The job builds
    /// the frame, reserves its sequence, and delivers through the scheduler's
    /// serialized drain, so continuation can never overtake higher-lane work
    /// and delivery order equals sequence order.
    private func publishManifestContinuationWindow(
        batch: BridgeWorktreeTreeRowWindowBatch,
        publication: WorktreeFileManifestPublication,
        counters: inout WorktreeFileManifestCounters
    ) async {
        counters.emittedWindowCount += 1
        let generation = publication.openedSource.source.subscriptionGeneration
        await enqueueWorktreeFileMetadataJob(lane: .idle, generation: generation) { [weak self] in
            guard let self else { return true }
            let batchPublishStart = ContinuousClock.now
            let pathCount =
                if batch.isFinalWindow {
                    batch.discoveredRowCount
                } else {
                    publication.treeExtent.pathCount.map { max($0, batch.discoveredRowCount) }
                }
            let delivered = await self.deliverWorktreeFileFrameJob(generation: generation) { current, sequence in
                BridgeWorktreeFileSurfaceFrameBuilder.treeWindow(
                    request: BridgeWorktreeTreeWindowBuildRequest(
                        paneId: self.paneId.uuidString,
                        source: current.source,
                        streamId: current.streamId,
                        sequence: sequence,
                        treeWindowKey:
                            "worktree-tree-\(current.source.sourceId)-\(current.source.subscriptionGeneration)-\(batch.startIndex)",
                        pathScope: current.openedSource.canonicalPathScope,
                        treePathCount: pathCount,
                        treeEstimatedTotalHeightPixels: publication.treeExtent
                            .estimatedTotalHeightPixels,
                        treeWindowStartIndex: batch.startIndex,
                        treeWindowRowCount: batch.rows.count,
                        treeRowHeightPixels: worktreeFileTreeRowHeightPixels,
                        rows: batch.rows
                    )
                )
            }
            await self.recordWorktreeFileTreeWindowBatchTelemetry(
                batch: batch,
                durationMilliseconds: Self.milliseconds(
                    from: batchPublishStart.duration(to: ContinuousClock.now)
                ),
                pendingFrameCount: await self.worktreeFileMetadataScheduler.queuedJobCount
            )
            return delivered
        }
    }

    private func recordManifestPublicationOutcome(
        _ resultReason: String,
        counters: WorktreeFileManifestCounters
    ) async {
        await recordWorktreeFileTreeWindowPublicationTelemetry(
            resultReason: resultReason,
            initialRowCount: counters.snapshotRowCount,
            allRowCount: counters.latestDiscoveredRowCount,
            windowCount: counters.emittedWindowCount,
            firstSequence: counters.firstPublishedSequence,
            pendingFrameCount: await worktreeFileMetadataScheduler.queuedJobCount
        )
    }

    /// Enqueues the startup snapshot as a foreground job. The snapshot is
    /// always sequence 0 and must be the first delivered frame of the
    /// accepted stream; foreground priority plus the closed-until-ready gate
    /// guarantee that.
    private func dispatchWorktreeFileSurfaceSnapshot(
        rows: [BridgeWorktreeTreeRowMetadata],
        publication: WorktreeFileManifestPublication
    ) async {
        let generation = publication.openedSource.source.subscriptionGeneration
        await enqueueWorktreeFileMetadataJob(lane: .foreground, generation: generation) { [weak self] in
            guard let self else { return true }
            guard let current = self.activeWorktreeFileSurfaceSource,
                current.source.subscriptionGeneration == generation,
                generation == self.nextWorktreeFileSurfaceGeneration
            else {
                return true
            }
            let treePathCount: Int? =
                if let pathCount = publication.treeExtent.pathCount {
                    max(pathCount, rows.count)
                } else {
                    nil
                }
            let snapshotFrame = BridgeWorktreeFileSurfaceFrameBuilder.snapshot(
                request: BridgeWorktreeFileSnapshotBuildRequest(
                    paneId: self.paneId.uuidString,
                    source: publication.openedSource.source,
                    requestSelector: publication.requestSelector,
                    streamId: publication.streamId,
                    sequence: 0,
                    treePathCount: treePathCount,
                    treeEstimatedTotalHeightPixels: publication.treeExtent
                        .estimatedTotalHeightPixels,
                    treeWindowStartIndex: 0,
                    treeWindowRowCount: rows.count,
                    treeRowHeightPixels: worktreeFileTreeRowHeightPixels,
                    treeRows: rows,
                    includeStatusPatch: publication.openedSource.includeStatuses
                )
            )
            let delivered = await self.deliverWorktreeFileIntakeFramesNow([snapshotFrame])
            await self.recordNativeWorktreeFileOpenToFirstWindowTelemetry(
                durationMilliseconds: Self.milliseconds(
                    from: publication.openStartedAt.duration(to: ContinuousClock.now)
                ),
                emittedRows: rows.count,
                expectedTotal: treePathCount
            )
            return delivered
        }
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
                    "agentstudio.bridge.worktree_file.tree.window.row.count": Double(batch.rows.count),
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
}
