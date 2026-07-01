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
                    try await publishManifestContinuationWindow(
                        batch: batch,
                        publication: publication,
                        counters: &counters
                    )
                } else {
                    counters.snapshotSent = true
                    counters.snapshotRowCount = batch.rows.count
                    try await dispatchWorktreeFileSurfaceSnapshot(
                        rows: batch.rows,
                        publication: publication
                    )
                }
            }
            if !counters.snapshotSent {
                try await dispatchWorktreeFileSurfaceSnapshot(rows: [], publication: publication)
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

    private func publishManifestContinuationWindow(
        batch: BridgeWorktreeTreeRowWindowBatch,
        publication: WorktreeFileManifestPublication,
        counters: inout WorktreeFileManifestCounters
    ) async throws {
        let batchPublishStart = ContinuousClock.now
        let timing = try await publishWorktreeFileTreeWindowBatch(
            batch,
            openedSource: publication.openedSource,
            streamId: publication.streamId,
            treeExtent: publication.treeExtent
        )
        if counters.firstPublishedSequence == nil {
            counters.firstPublishedSequence = timing.sequence
        }
        await recordWorktreeFileTreeWindowBatchTelemetry(
            batch: batch,
            publication: timing,
            durationMilliseconds: Self.milliseconds(
                from: batchPublishStart.duration(to: ContinuousClock.now)
            ),
            pendingFrameCount: pendingWorktreeFileIntakeFrames.count
        )
        counters.emittedWindowCount += 1
        if worktreeFileIntakeReadyStreamId != nil {
            await flushPendingWorktreeFileIntakeFrames()
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
            pendingFrameCount: pendingWorktreeFileIntakeFrames.count
        )
    }

    private func dispatchWorktreeFileSurfaceSnapshot(
        rows: [BridgeWorktreeTreeRowMetadata],
        publication: WorktreeFileManifestPublication
    ) async throws {
        let openedSource = publication.openedSource
        let requestSelector = publication.requestSelector
        let streamId = publication.streamId
        let treeExtent = publication.treeExtent
        let openStartedAt = publication.openStartedAt
        let treePathCount: Int? =
            if let pathCount = treeExtent.pathCount {
                max(pathCount, rows.count)
            } else {
                nil
            }
        let snapshotFrame = BridgeWorktreeFileSurfaceFrameBuilder.snapshot(
            request: BridgeWorktreeFileSnapshotBuildRequest(
                paneId: paneId.uuidString,
                source: openedSource.source,
                requestSelector: requestSelector,
                streamId: streamId,
                sequence: 0,
                treePathCount: treePathCount,
                treeEstimatedTotalHeightPixels: treeExtent.estimatedTotalHeightPixels,
                treeWindowStartIndex: 0,
                treeWindowRowCount: rows.count,
                treeRowHeightPixels: worktreeFileTreeRowHeightPixels,
                treeRows: rows,
                includeStatusPatch: openedSource.includeStatuses
            )
        )
        try await dispatchWorktreeFileIntakeFrames([snapshotFrame])
        await recordNativeWorktreeFileOpenToFirstWindowTelemetry(
            durationMilliseconds: Self.milliseconds(from: openStartedAt.duration(to: ContinuousClock.now)),
            emittedRows: rows.count,
            expectedTotal: treePathCount
        )
        if worktreeFileIntakeReadyStreamId != nil {
            await flushPendingWorktreeFileIntakeFrames()
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
}
