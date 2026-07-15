import Foundation

extension FilesystemActor {
    func updateWatchedFolders(_ watchedPaths: [WatchedPath]) async {
        _ = await refreshWatchedFolders(watchedPaths)
    }

    func refreshWatchedFolders(_ watchedPaths: [WatchedPath]) async -> WatchedFolderRefreshSummary {
        if let activeRefresh = watchedFolderScanState.manualRefreshState.task {
            _ = await activeRefresh.value
            return await refreshWatchedFolders(watchedPaths)
        }
        let refreshID = UUIDv7.generate()
        let refreshTask = Task { [weak self] in
            guard let self else {
                return WatchedFolderRefreshSummary(repoPathsByWatchedFolder: [:])
            }
            let summary = await self.performManualWatchedFolderRefresh(
                watchedPaths,
                refreshID: refreshID
            )
            await self.finishManualWatchedFolderRefreshTask(refreshID: refreshID)
            return summary
        }
        watchedFolderScanState.manualRefreshState = .running(id: refreshID, task: refreshTask)
        return await refreshTask.value
    }

    private func performManualWatchedFolderRefresh(
        _ watchedPaths: [WatchedPath],
        refreshID: UUID
    ) async -> WatchedFolderRefreshSummary {
        guard !watchedFolderScanState.isShuttingDown else {
            return watchedFolderRefreshSummary()
        }
        startIngressTaskIfNeeded()
        let newlyRegisteredSourceIDs = await reconcileWatchedFolderRegistrations(watchedPaths)
        ensureWatchedFolderResultDrainStarted()

        var receiptsBySourceID: [FilesystemSourceID: WatchedFolderScanDemandReceipt] = [:]
        for registration in watchedFolderScanState.registrationsBySourceID.values {
            let request = WatchedFolderScanRequest(
                canonicalRoot: registration.registeredRoot,
                cause: newlyRegisteredSourceIDs.contains(registration.registeredRoot.sourceID)
                    ? .initialAdd : .manual
            )
            switch await watchedFolderScanScheduler.submit(request, intent: .tracked) {
            case .accepted(.tracked(let receipt, _)):
                receiptsBySourceID[request.sourceID] = receipt
                watchedFolderScanState.latestDemandCoverageBySourceID[request.sourceID] = receipt.coverage
            case .accepted(.untracked):
                preconditionFailure("tracked scan admission must return a receipt")
            case .rejected:
                continue
            }
        }

        guard !watchedFolderScanState.isShuttingDown, !receiptsBySourceID.isEmpty else {
            startFallbackRescan()
            return watchedFolderRefreshSummary()
        }

        let summary = await withCheckedContinuation { continuation in
            guard
                case .running(let currentRefreshID, let refreshTask) =
                    watchedFolderScanState.manualRefreshState,
                currentRefreshID == refreshID,
                !watchedFolderScanState.isShuttingDown
            else {
                continuation.resume(returning: watchedFolderRefreshSummary())
                return
            }
            watchedFolderScanState.manualRefreshState = .waitingForResults(
                id: refreshID,
                task: refreshTask,
                wait: FilesystemManualWatchedFolderRefreshWait(
                    receiptsBySourceID: receiptsBySourceID,
                    continuation: continuation
                )
            )
            completeManualRefreshIfSatisfied()
        }
        startFallbackRescan()
        return summary
    }

    private func finishManualWatchedFolderRefreshTask(refreshID: UUID) {
        switch watchedFolderScanState.manualRefreshState {
        case .running(let currentRefreshID, _):
            if currentRefreshID == refreshID {
                watchedFolderScanState.manualRefreshState = .idle
            }
        case .waitingForResults(let currentRefreshID, _, _):
            if currentRefreshID == refreshID {
                watchedFolderScanState.manualRefreshState = .idle
            }
        case .idle:
            break
        }
    }

    func isWatchedFolderBatch(_ worktreeID: UUID) -> Bool {
        watchedFolderScanState.sourceIDByLegacyCallbackRoutingID[worktreeID] != nil
    }

    func handleWatchedFolderFSEvent(_ batch: FSEventBatch) async {
        guard batch.paths.contains(where: Self.isGitTopologyPath) else { return }
        guard
            let sourceID = watchedFolderScanState.sourceIDByLegacyCallbackRoutingID[
                batch.worktreeId
            ]
        else { return }
        await submitWatchedFolderScan(sourceID: sourceID, cause: .callback)
    }

    private func reconcileWatchedFolderRegistrations(
        _ watchedPaths: [WatchedPath]
    ) async -> Set<FilesystemSourceID> {
        var desiredBySourceID: [FilesystemSourceID: WatchedPath] = [:]
        for watchedPath in watchedPaths.sorted(by: { $0.path.path < $1.path.path }) {
            let sourceID = FilesystemSourceID(
                kind: .watchedParentMembership,
                rootID: watchedPath.id
            )
            if desiredBySourceID[sourceID] == nil {
                desiredBySourceID[sourceID] = watchedPath
            }
        }
        var newlyRegisteredSourceIDs = Set<FilesystemSourceID>()
        let removedSourceIDs = Set(watchedFolderScanState.registrationsBySourceID.keys)
            .subtracting(desiredBySourceID.keys)
        var removedClonePaths = Set<URL>()

        for sourceID in removedSourceIDs {
            guard
                let registration = watchedFolderScanState.registrationsBySourceID.removeValue(
                    forKey: sourceID
                )
            else { continue }
            _ = await watchedFolderScanScheduler.retireRegistration(registration.registeredRoot)
            fseventStreamClient.unregister(worktreeId: registration.legacyCallbackRoutingID)
            watchedFolderScanState.sourceIDByLegacyCallbackRoutingID.removeValue(
                forKey: registration.legacyCallbackRoutingID
            )
            if let inventory = watchedFolderScanState.inventoryBySourceID.removeValue(
                forKey: sourceID
            ) {
                removedClonePaths.formUnion(inventory.repoGroups.map(\.clonePath))
            }
            watchedFolderScanState.latestDemandCoverageBySourceID.removeValue(forKey: sourceID)
            watchedFolderScanState.appliedDemandCoverageBySourceID.removeValue(forKey: sourceID)
            watchedFolderScanState.lastAppliedResultIDBySourceID.removeValue(forKey: sourceID)
        }

        for (sourceID, watchedPath) in desiredBySourceID {
            if let existing = watchedFolderScanState.registrationsBySourceID[sourceID],
                existing.watchedPath == watchedPath
            {
                continue
            }
            if let existing = watchedFolderScanState.registrationsBySourceID[sourceID] {
                _ = await watchedFolderScanScheduler.retireRegistration(existing.registeredRoot)
                fseventStreamClient.unregister(worktreeId: existing.legacyCallbackRoutingID)
                watchedFolderScanState.sourceIDByLegacyCallbackRoutingID.removeValue(
                    forKey: existing.legacyCallbackRoutingID
                )
            }
            guard
                let registeredRoot = makeWatchedFolderRegisteredRoot(
                    sourceID: sourceID,
                    watchedPath: watchedPath
                )
            else {
                continue
            }
            let legacyCallbackRoutingID = UUIDv7.generate()
            watchedFolderScanState.registrationsBySourceID[sourceID] =
                FilesystemWatchedFolderRegistration(
                    watchedPath: watchedPath,
                    registeredRoot: registeredRoot,
                    legacyCallbackRoutingID: legacyCallbackRoutingID
                )
            watchedFolderScanState.sourceIDByLegacyCallbackRoutingID[
                legacyCallbackRoutingID
            ] = sourceID
            newlyRegisteredSourceIDs.insert(sourceID)
            fseventStreamClient.register(
                worktreeId: legacyCallbackRoutingID,
                repoId: watchedPath.id,
                rootPath: watchedPath.path
            )
        }

        await emitRemovedClones(noLongerReferencedByAnyWatchedFolder: removedClonePaths)
        return newlyRegisteredSourceIDs
    }

    private func makeWatchedFolderRegisteredRoot(
        sourceID: FilesystemSourceID,
        watchedPath: WatchedPath
    ) -> RegisteredRootDescriptor? {
        let previousGeneration =
            watchedFolderScanState.nextRegistrationGenerationBySourceID[sourceID] ?? 0
        let (generation, overflow) = previousGeneration.addingReportingOverflow(1)
        guard !overflow else { return nil }
        let registration = FSEventRegistrationToken(
            sourceID: sourceID,
            registrationGeneration: generation,
            rootGeneration: generation
        )
        do {
            let registeredRoot = try FilesystemSourceConfiguration.registerRoot(
                from: .hostAuthorized(
                    FilesystemHostAuthorizedRootInput(
                        registration: registration,
                        authorizedBoundary: watchedPath.path,
                        registeredRoot: watchedPath.path
                    )
                )
            )
            watchedFolderScanState.nextRegistrationGenerationBySourceID[sourceID] = generation
            return registeredRoot
        } catch {
            return nil
        }
    }

    private func submitWatchedFolderScan(
        sourceID: FilesystemSourceID,
        cause: WatchedFolderScanCause
    ) async {
        guard let registration = watchedFolderScanState.registrationsBySourceID[sourceID] else {
            return
        }
        let request = WatchedFolderScanRequest(
            canonicalRoot: registration.registeredRoot,
            cause: cause
        )
        switch await watchedFolderScanScheduler.submit(request) {
        case .accepted(let acceptance):
            watchedFolderScanState.latestDemandCoverageBySourceID[sourceID] = acceptance.coverage
            ensureWatchedFolderResultDrainStarted()
        case .rejected:
            return
        }
    }

    private func startFallbackRescan() {
        watchedFolderScanState.fallbackTask?.cancel()
        guard !watchedFolderScanState.isShuttingDown,
            !watchedFolderScanState.registrationsBySourceID.isEmpty
        else { return }
        watchedFolderScanState.fallbackTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await AsyncDelay.taskSleep.wait(
                        AppPolicies.WatchedFolderScanning.fallbackCadence
                    )
                } catch {
                    return
                }
                guard let self else { return }
                await self.submitAllWatchedFolderScans(cause: .fallback)
            }
        }
    }

    private func submitAllWatchedFolderScans(cause: WatchedFolderScanCause) async {
        for sourceID in watchedFolderScanState.registrationsBySourceID.keys {
            await submitWatchedFolderScan(sourceID: sourceID, cause: cause)
        }
    }

    private static func isGitTopologyPath(_ path: String) -> Bool {
        path.contains("/.git/") || path.hasSuffix("/.git")
    }
}
