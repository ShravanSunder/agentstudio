import Foundation

let worktreeFileTreeRowHeightPixels: Double = 24

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
        if let telemetryRecorder {
            await worktreeFileMetadataScheduler.configureTelemetry(
                BridgePaneMetadataSchedulerTelemetryAdapter(recorder: telemetryRecorder)
            )
        }
        await worktreeFileMetadataScheduler.closeGate(protocolId: "worktree-file")
        await worktreeFileMetadataScheduler.acceptGeneration(generation, protocolId: "worktree-file")
        activeWorktreeFileTreeWindowTask?.cancel()
        activeWorktreeFileTreeWindowTask = nil
        resourceLeaseRegistry.revokeSynchronously(paneId: paneId, protocolId: "worktree-file")
        activeWorktreeFileSurfaceSource = BridgeWorktreeFileSurfaceActiveSourceState(
            openedSource: openedSource,
            source: openedSource.source,
            streamId: streamId,
            nextSequence: 0
        )
        activeWorktreeFileManifestIndex = BridgeWorktreeFileManifestIndex(generation: generation)
        clearActiveViewerModeAcceptedSignalForExplicitFileSurfaceRequest()
        if shouldSuppressWorktreeFileProduction(generation: generation) {
            await recordActiveViewerModeSuppression(
                suppressedProtocolId: "worktree-file",
                generation: generation,
                phase: "worktree_file_open"
            )
            return BridgeWorktreeFileSurfaceOpenSourceOutcome(
                streamId: streamId,
                generation: generation
            )
        }
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
        clearActiveViewerModeAcceptedSignalForExplicitFileSurfaceRequest()
        try await activateWorktreeFileSurfaceLeases([
            materializedDescriptor.frame.descriptor.contentDescriptor.descriptor
        ])
        await worktreeFileResourceStore.register(
            materializedDescriptor.resource,
            body: materializedDescriptor.body
        )
        let generation = activeSource.source.subscriptionGeneration
        let descriptor = materializedDescriptor.frame.descriptor
        await enqueueWorktreeFileMetadataJob(lane: params.lane, generation: generation) { [weak self] in
            guard let self else { return true }
            return await self.deliverWorktreeFileFrameJob(generation: generation) { current, sequence in
                BridgeWorktreeFileDescriptorFrame(
                    streamId: current.streamId,
                    sequence: sequence,
                    descriptor: descriptor
                )
            }
        }
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
        guard let manifestIndex = activeWorktreeFileManifestIndex,
            manifestIndex.generation == activeSource.source.subscriptionGeneration
        else {
            return
        }
        let generation = activeSource.source.subscriptionGeneration
        guard !shouldSuppressWorktreeFileProduction(generation: generation) else {
            await recordActiveViewerModeSuppression(
                suppressedProtocolId: "worktree-file",
                generation: generation,
                phase: "worktree_file_interest"
            )
            return
        }

        // Interest is served from the manifest index in O(requested paths):
        // membership comes from the accepted generation manifest (interest is
        // not discovery), and freshness stat-truth rebuilds the member rows
        // off the MainActor. Re-enumerating the worktree here is a contract
        // violation (performance-demand-lanes.md, manifest index contract).
        let memberPaths = await manifestIndex.memberPaths(of: requestedPaths)
        guard !memberPaths.isEmpty else {
            return
        }
        let rootURL = try worktreeFileSurfaceRootURL()
        let refreshed = await BridgeWorktreeFileMaterializer.refreshTreeRows(
            rootURL: rootURL,
            relativePaths: memberPaths
        )
        guard let latestActiveSource = activeWorktreeFileSurfaceSource,
            latestActiveSource.source == activeSource.source,
            latestActiveSource.streamId == activeSource.streamId,
            latestActiveSource.source.subscriptionGeneration == nextWorktreeFileSurfaceGeneration
        else {
            return
        }
        await manifestIndex.applyRefreshedRows(refreshed.rows)
        let removedRows = await manifestIndex.removePaths(refreshed.missingPaths)
        let lane = params.lane
        if !refreshed.rows.isEmpty {
            let rows = refreshed.rows
            await enqueueWorktreeFileMetadataJob(lane: lane, generation: generation) { [weak self] in
                guard let self else { return true }
                return await self.deliverWorktreeFileFrameJob(generation: generation) { current, sequence in
                    BridgeWorktreeFileSurfaceFrameBuilder.treeWindow(
                        request: BridgeWorktreeTreeWindowBuildRequest(
                            paneId: self.paneId.uuidString,
                            source: current.source,
                            streamId: current.streamId,
                            sequence: sequence,
                            treeWindowKey:
                                "worktree-interest-\(current.source.sourceId)-\(current.source.subscriptionGeneration)-\(lane.rawValue)-\(sequence)",
                            pathScope: current.openedSource.canonicalPathScope,
                            treePathCount: nil,
                            treeEstimatedTotalHeightPixels: nil,
                            treeWindowStartIndex: nil,
                            treeWindowRowCount: rows.count,
                            treeRowHeightPixels: worktreeFileTreeRowHeightPixels,
                            rows: rows,
                            metadataLineage: Self.worktreeMetadataLineage(for: lane)
                        )
                    )
                }
            }
        }
        if !removedRows.isEmpty {
            // Stat-truth: a missing manifest member is removed, never served
            // as a stale upsert.
            let rowIds = removedRows.map(\.rowId)
            let paths = removedRows.map(\.path)
            await enqueueWorktreeFileMetadataJob(lane: lane, generation: generation) { [weak self] in
                guard let self else { return true }
                return await self.deliverWorktreeFileFrameJob(generation: generation) { current, sequence in
                    BridgeWorktreeTreeDeltaFrame(
                        streamId: current.streamId,
                        generation: current.source.subscriptionGeneration,
                        sequence: sequence,
                        operations: [.removeRows(rowIds: rowIds, paths: paths)]
                    )
                }
            }
        }
    }

    /// Job body: re-validates the active source for the captured generation,
    /// reserves one sequence, builds the frame, and delivers it. Stale jobs
    /// are consumed silently — the scheduler already generation-gates, and
    /// this closes the enqueue-to-execute race.
    func deliverWorktreeFileFrameJob<Frame: Encodable>(
        generation: Int,
        buildFrame: (BridgeWorktreeFileSurfaceActiveSourceState, Int) -> Frame
    ) async -> Bool {
        guard let current = activeWorktreeFileSurfaceSource,
            current.source.subscriptionGeneration == generation,
            generation == nextWorktreeFileSurfaceGeneration
        else {
            return true
        }
        guard !shouldSuppressWorktreeFileProduction(generation: generation) else {
            await recordActiveViewerModeSuppression(
                suppressedProtocolId: "worktree-file",
                generation: generation,
                phase: "worktree_file_delivery"
            )
            return true
        }
        guard
            let sequence = try? reserveWorktreeFileSurfaceSequenceBlock(
                count: 1,
                source: current.source,
                streamId: current.streamId
            )
        else {
            return true
        }
        let frame = buildFrame(current, sequence)
        let delivered = await deliverWorktreeFileIntakeFramesNow([frame])
        if !delivered {
            rollbackWorktreeFileSurfaceSequenceReservation(firstSequence: sequence, count: 1)
        }
        return delivered
    }

    func publishWorktreeFileSurfaceStatus(_ status: GitWorkingTreeStatus) async throws {
        guard let activeSource = activeWorktreeFileSurfaceSource else {
            return
        }
        guard activeSource.source.subscriptionGeneration == nextWorktreeFileSurfaceGeneration else {
            return
        }
        let generation = activeSource.source.subscriptionGeneration
        guard !shouldSuppressWorktreeFileProduction(generation: generation) else {
            await recordActiveViewerModeSuppression(
                suppressedProtocolId: "worktree-file",
                generation: generation,
                phase: "worktree_file_status_publish"
            )
            return
        }
        await enqueueWorktreeFileMetadataJob(lane: .active, generation: generation) { [weak self] in
            guard let self else { return true }
            return await self.deliverWorktreeFileFrameJob(generation: generation) { current, sequence in
                BridgeWorktreeFileSurfaceClassifier.statusPatchFrame(
                    request: BridgeWorktreeStatusPatchBuildRequest(
                        source: current.source,
                        streamId: current.streamId,
                        sequence: sequence,
                        status: status
                    )
                )
            }
        }
    }

    func publishWorktreeFileSurfaceChangeset(_ changeset: FileChangeset) async throws {
        guard let activeSource = activeWorktreeFileSurfaceSource else {
            return
        }
        guard activeSource.source.subscriptionGeneration == nextWorktreeFileSurfaceGeneration else {
            return
        }
        let generation = activeSource.source.subscriptionGeneration
        guard !shouldSuppressWorktreeFileProduction(generation: generation) else {
            await recordActiveViewerModeSuppression(
                suppressedProtocolId: "worktree-file",
                generation: generation,
                phase: "worktree_file_changeset_publish"
            )
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
        try await reconcileWorktreeFileManifestIndexForWatchEvent(
            changedPaths: scopedChangedPaths,
            latestActiveSource: latestActiveSource,
            rootURL: rootURL
        )
        let invalidationFrameCount = scopedChangeset.paths.filter { !Self.isWorktreeFileGitInternalPath($0) }.count
        guard invalidationFrameCount > 0 else {
            if changeset.containsGitInternalChanges {
                await enqueueWorktreeFileMetadataJob(lane: .active, generation: generation) { [weak self] in
                    guard let self else { return true }
                    return await self.deliverWorktreeFileFrameJob(generation: generation) { current, sequence in
                        BridgeWorktreeFileSurfaceClassifier.statusInvalidatedFrame(
                            request: BridgeWorktreeStatusInvalidationBuildRequest(
                                source: current.source,
                                streamId: current.streamId,
                                sequence: sequence,
                                changeset: changeset
                            )
                        )
                    }
                }
            }
            return
        }
        await enqueueWorktreeFileChangesetInvalidationJob(
            generation: generation,
            invalidationFrameCount: invalidationFrameCount,
            scopedChangeset: scopedChangeset,
            latestDescriptorsByPath: latestDescriptorsByPath
        )
    }

    /// Multi-frame invalidation emission as one scheduler job: the sequence
    /// block reserves inside the serialized drain, and a failed delivery
    /// rolls the whole block back so the retained-job retry redelivers with
    /// the same sequences.
    private func enqueueWorktreeFileChangesetInvalidationJob(
        generation: Int,
        invalidationFrameCount: Int,
        scopedChangeset: FileChangeset,
        latestDescriptorsByPath: [String: BridgeWorktreeFileDescriptor]
    ) async {
        await enqueueWorktreeFileMetadataJob(lane: .active, generation: generation) { [weak self] in
            guard let self else { return true }
            guard !self.shouldSuppressWorktreeFileProduction(generation: generation) else {
                await self.recordActiveViewerModeSuppression(
                    suppressedProtocolId: "worktree-file",
                    generation: generation,
                    phase: "worktree_file_changeset_delivery"
                )
                return true
            }
            guard let current = self.activeWorktreeFileSurfaceSource,
                current.source.subscriptionGeneration == generation,
                generation == self.nextWorktreeFileSurfaceGeneration,
                let firstSequence = try? self.reserveWorktreeFileSurfaceSequenceBlock(
                    count: invalidationFrameCount,
                    source: current.source,
                    streamId: current.streamId
                )
            else {
                return true
            }
            let invalidationFrames = BridgeWorktreeFileSurfaceClassifier.fileInvalidationFrames(
                request: BridgeWorktreeFileChangesetClassificationRequest(
                    source: current.source,
                    streamId: current.streamId,
                    firstSequence: firstSequence,
                    changeset: scopedChangeset,
                    latestDescriptorsByPath: latestDescriptorsByPath
                )
            )
            let delivered = await self.deliverWorktreeFileIntakeFramesNow(invalidationFrames)
            if !delivered {
                self.rollbackWorktreeFileSurfaceSequenceReservation(
                    firstSequence: firstSequence,
                    count: invalidationFrameCount
                )
            }
            return delivered
        }
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
        activeWorktreeFileManifestIndex = nil
        nextWorktreeFileSurfaceGeneration += 1
        await worktreeFileMetadataScheduler.closeGate(protocolId: "worktree-file")
        await worktreeFileMetadataScheduler.acceptGeneration(
            nextWorktreeFileSurfaceGeneration,
            protocolId: "worktree-file"
        )
        resourceLeaseRegistry.revokeSynchronously(paneId: paneId, protocolId: "worktree-file")
        await worktreeFileResourceStore.reset(protocolId: "worktree-file")
        // Reset frames deliver directly: they are the lifecycle boundary, and
        // the browser's generation gate stale-drops any queued laggards.
        _ = await deliverWorktreeFileIntakeFramesNow([frame])
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

    /// Failed deliveries roll their reservation back so the scheduler's
    /// retained-job retry redelivers with the same sequence instead of
    /// leaving a gap that wedges the browser's monotonic intake gate.
    /// Reservations only advance inside serialized scheduler jobs, so the
    /// failed block is always the newest one; the guard makes the rollback
    /// a no-op if that invariant is ever broken rather than corrupting the
    /// cursor.
    func rollbackWorktreeFileSurfaceSequenceReservation(firstSequence: Int, count: Int) {
        guard var activeSource = activeWorktreeFileSurfaceSource,
            activeSource.source.subscriptionGeneration == nextWorktreeFileSurfaceGeneration,
            activeSource.nextSequence == firstSequence + count
        else {
            return
        }
        activeSource.nextSequence = firstSequence
        activeWorktreeFileSurfaceSource = activeSource
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
        where BridgeWorktreeFileMaterializer.isInterestEligibleDemandPath(
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
