import Foundation

extension FilesystemActor {
    func ensureWatchedFolderResultDrainStarted() {
        guard !watchedFolderScanState.isShuttingDown,
            case .idle = watchedFolderScanState.resultDrainState
        else { return }
        let bindingID = UUIDv7.generate()
        let drainTask = Task { [weak self] in
            guard let self else { return }
            await self.bindAndDrainWatchedFolderScanResults(bindingID: bindingID)
        }
        watchedFolderScanState.resultDrainState = .bindingConsumer(
            id: bindingID,
            task: drainTask
        )
    }

    private func bindAndDrainWatchedFolderScanResults(bindingID: UUID) async {
        switch await watchedFolderScanScheduler.bindResultConsumer(
            watchedFolderScanState.resultConsumer
        ) {
        case .bound, .alreadyBound:
            break
        case .rejected(.schedulerShutDown):
            finishWatchedFolderResultDrain(bindingID: bindingID)
            return
        case .rejected(.anotherConsumerBound):
            preconditionFailure("FilesystemActor must own the sole watched-folder result consumer")
        }
        guard
            case .bindingConsumer(let retainedBindingID, let drainTask) =
                watchedFolderScanState.resultDrainState,
            retainedBindingID == bindingID
        else { return }
        watchedFolderScanState.resultDrainState = .running(
            id: bindingID,
            task: drainTask
        )
        await drainWatchedFolderScanResults(bindingID: bindingID)
    }

    private func drainWatchedFolderScanResults(bindingID: UUID) async {
        let consumer = watchedFolderScanState.resultConsumer
        while !Task.isCancelled {
            switch await watchedFolderScanScheduler.nextResultLease(for: consumer) {
            case .leased(let lease):
                await applyWatchedFolderScanResult(lease.result)
                let resolution = await watchedFolderScanScheduler.resolveResultLease(
                    for: consumer,
                    leaseID: lease.leaseID,
                    resolution: .transferred
                )
                await recordLogicalDebtSnapshotIfChanged()
                switch resolution {
                case .transferred, .staleResultDiscarded:
                    break
                case .queuedForRetry:
                    preconditionFailure("transferred result cannot be queued for retry")
                case .rejected:
                    preconditionFailure("FilesystemActor lost exact result-lease custody")
                }
            case .cancelled, .consumerUnbound, .schedulerShutDown:
                finishWatchedFolderResultDrain(bindingID: bindingID)
                return
            case .rejected(.consumerMismatch):
                preconditionFailure("FilesystemActor result consumer identity changed")
            case .rejected(.waiterAlreadyRegistered):
                preconditionFailure("FilesystemActor created multiple result waiters")
            case .rejected(.leaseAlreadyOutstanding):
                preconditionFailure("FilesystemActor requested a second result lease")
            case .rejected(.leaseIdentityExhausted):
                preconditionFailure("watched-folder result lease UUIDv7 generation exhausted")
            }
        }
        finishWatchedFolderResultDrain(bindingID: bindingID)
    }

    private func finishWatchedFolderResultDrain(bindingID: UUID) {
        switch watchedFolderScanState.resultDrainState {
        case .idle:
            return
        case .bindingConsumer(let retainedBindingID, _),
            .running(let retainedBindingID, _):
            guard retainedBindingID == bindingID else { return }
            watchedFolderScanState.resultDrainState = .idle
        }
    }

    private func applyWatchedFolderScanResult(_ result: ScheduledWatchedFolderScanResult) async {
        let sourceID = result.request.sourceID
        guard
            let registration = watchedFolderScanState.registrationsBySourceID[sourceID],
            registration.registeredRoot == result.request.canonicalRoot,
            result.demandCoverage.registration == registration.registeredRoot.registration
        else { return }
        guard watchedFolderScanState.lastAppliedResultIDBySourceID[sourceID] != result.resultID else {
            return
        }

        let previousGroups = watchedFolderScanState.inventoryBySourceID[sourceID]?.repoGroups ?? []
        let latestCoverage = watchedFolderScanState.latestDemandCoverageBySourceID[sourceID]
        let reduction = WatchedFolderInventoryReducer.reduce(
            previousGroups: previousGroups,
            scannerResult: result.scannerResult,
            mayReplaceNegativeSpace: latestCoverage == result.demandCoverage
        )

        let mutation: WatchedFolderInventoryMutation?
        switch reduction {
        case .authoritativeReplacement(let replacement):
            guard
                case .additiveMerge(let additiveFallback) = WatchedFolderInventoryReducer.reduce(
                    previousGroups: previousGroups,
                    scannerResult: result.scannerResult,
                    mayReplaceNegativeSpace: false
                )
            else {
                preconditionFailure("complete evidence must support additive fallback")
            }
            if let envelopes = prepareAuthoritativeWatchedFolderMutation(
                replacement,
                sourceID: sourceID,
                registration: registration,
                demandCoverage: result.demandCoverage
            ) {
                _ = await runtimeBus.post(contentsOf: envelopes)
            } else {
                watchedFolderScanState.inventoryBySourceID[sourceID] =
                    FilesystemWatchedFolderInventory(repoGroups: additiveFallback.repoGroups)
                await emitReposDiscovered(
                    parentPath: registration.watchedPath.path,
                    repositories: additiveFallback.changedRepositories
                )
            }
            mutation = nil
        case .additiveMerge(let replacement):
            mutation = replacement
            watchedFolderScanState.inventoryBySourceID[sourceID] =
                FilesystemWatchedFolderInventory(repoGroups: replacement.repoGroups)
        case .preserved:
            mutation = nil
        }
        watchedFolderScanState.appliedDemandCoverageBySourceID[sourceID] = result.demandCoverage
        watchedFolderScanState.lastAppliedResultIDBySourceID[sourceID] = result.resultID

        if let mutation {
            await emitReposDiscovered(
                parentPath: registration.watchedPath.path,
                repositories: mutation.changedRepositories
            )
            await emitRemovedClones(
                noLongerReferencedByAnyWatchedFolder: mutation.removedClonePaths
            )
        }
        completeManualRefreshIfSatisfied()
    }

    func completeManualRefreshIfSatisfied() {
        guard
            case .waitingForResults(let refreshID, let refreshTask, let manualRefresh) =
                watchedFolderScanState.manualRefreshState
        else { return }
        let allSatisfied = manualRefresh.receiptsBySourceID.allSatisfy { sourceID, receipt in
            watchedFolderScanState.appliedDemandCoverageBySourceID[sourceID]?.covers(receipt) == true
        }
        guard allSatisfied else { return }
        watchedFolderScanState.manualRefreshState = .running(id: refreshID, task: refreshTask)
        manualRefresh.continuation.resume(returning: watchedFolderRefreshSummary())
    }

    func cancelManualWatchedFolderRefreshForShutdown() {
        guard
            case .waitingForResults(let refreshID, let refreshTask, let manualRefresh) =
                watchedFolderScanState.manualRefreshState
        else { return }
        watchedFolderScanState.manualRefreshState = .running(id: refreshID, task: refreshTask)
        manualRefresh.continuation.resume(returning: watchedFolderRefreshSummary())
    }

    private func prepareAuthoritativeWatchedFolderMutation(
        _ mutation: WatchedFolderInventoryMutation,
        sourceID: FilesystemSourceID,
        registration: FilesystemWatchedFolderRegistration,
        demandCoverage: WatchedFolderScanDemandCoverage
    ) -> [RuntimeEnvelope]? {
        guard watchedFolderScanState.latestDemandCoverageBySourceID[sourceID] == demandCoverage else {
            return nil
        }

        watchedFolderScanState.inventoryBySourceID[sourceID] =
            FilesystemWatchedFolderInventory(repoGroups: mutation.repoGroups)
        var envelopes: [RuntimeEnvelope] = []
        if !mutation.changedRepositories.isEmpty {
            nextEnvelopeSequence += 1
            envelopes.append(
                .system(
                    SystemEnvelope(
                        source: .builtin(.filesystemWatcher),
                        seq: nextEnvelopeSequence,
                        timestamp: envelopeClock.now,
                        event: .topology(
                            .reposDiscovered(
                                parentPath: registration.watchedPath.path,
                                repositories: mutation.changedRepositories
                            )
                        )
                    )
                )
            )
        }
        for repoPath in mutation.removedClonePaths.sorted(by: Self.sortByPath) {
            guard !isReferencedByAnyWatchedFolder(repoPath) else { continue }
            nextEnvelopeSequence += 1
            envelopes.append(
                .system(
                    SystemEnvelope(
                        source: .builtin(.filesystemWatcher),
                        seq: nextEnvelopeSequence,
                        timestamp: envelopeClock.now,
                        event: .topology(.repoRemoved(repoPath: repoPath))
                    )
                )
            )
        }
        return envelopes
    }

    func watchedFolderRefreshSummary() -> WatchedFolderRefreshSummary {
        var repoPathsByWatchedFolder: [URL: [URL]] = [:]
        for (sourceID, registration) in watchedFolderScanState.registrationsBySourceID {
            repoPathsByWatchedFolder[registration.watchedPath.path.standardizedFileURL] =
                watchedFolderScanState.inventoryBySourceID[sourceID]?.repoGroups
                .map(\.clonePath).sorted(by: Self.sortByPath) ?? []
        }
        return WatchedFolderRefreshSummary(repoPathsByWatchedFolder: repoPathsByWatchedFolder)
    }
}
