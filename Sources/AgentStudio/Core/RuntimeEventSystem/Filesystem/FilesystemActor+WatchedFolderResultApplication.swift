import AgentStudioInfrastructure
import CryptoKit
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

        let observedAt: RepositoryRetentionTime?
        if case .authoritativeReplacement = reduction {
            observedAt = try? await RepositoryRetentionTime.current()
        } else {
            observedAt = nil
        }
        guard watchedFolderScanState.registrationsBySourceID[sourceID]?.registeredRoot == registration.registeredRoot
        else {
            return
        }
        let coverage: WatchedFolderTopologyCoverage
        switch reduction {
        case .authoritativeReplacement(let replacement):
            if let observedAt,
                watchedFolderScanState.latestDemandCoverageBySourceID[sourceID] == result.demandCoverage
            {
                coverage = .authoritative(observedAt)
                watchedFolderScanState.inventoryBySourceID[sourceID] = .init(repoGroups: replacement.repoGroups)
            } else {
                coverage = .additive
                guard
                    case .additiveMerge(let fallback) = WatchedFolderInventoryReducer.reduce(
                        previousGroups: previousGroups, scannerResult: result.scannerResult,
                        mayReplaceNegativeSpace: false
                    )
                else { preconditionFailure("complete evidence must support additive fallback") }
                watchedFolderScanState.inventoryBySourceID[sourceID] = .init(repoGroups: fallback.repoGroups)
            }
        case .additiveMerge(let replacement):
            coverage = .additive
            watchedFolderScanState.inventoryBySourceID[sourceID] = .init(repoGroups: replacement.repoGroups)
        case .preserved:
            coverage = .additive
        }
        let entries = Self.validatedEntries(in: result.scannerResult)
        watchedFolderScanState.validatedPathsBySourceID[sourceID] = Set(entries.map { $0.path.standardizedFileURL })
        if case .authoritative = coverage {
            watchedFolderScanState.authoritativeSourceIDs.insert(sourceID)
        } else {
            watchedFolderScanState.authoritativeSourceIDs.remove(sourceID)
        }
        watchedFolderScanState.appliedDemandCoverageBySourceID[sourceID] = result.demandCoverage
        watchedFolderScanState.lastAppliedResultIDBySourceID[sourceID] = result.resultID
        var otherPaths = Set<URL>()
        var incompleteScopes: [URL] = []
        for (otherID, otherRegistration) in watchedFolderScanState.registrationsBySourceID where otherID != sourceID {
            if watchedFolderScanState.authoritativeSourceIDs.contains(otherID),
                let applied = watchedFolderScanState.appliedDemandCoverageBySourceID[otherID],
                applied == watchedFolderScanState.latestDemandCoverageBySourceID[otherID]
            {
                otherPaths.formUnion(watchedFolderScanState.validatedPathsBySourceID[otherID] ?? [])
            } else {
                incompleteScopes.append(otherRegistration.watchedPath.path.standardizedFileURL)
                incompleteScopes.append(
                    URL(fileURLWithPath: otherRegistration.registeredRoot.aliases.onceResolvedCanonical.path))
            }
        }
        nextEnvelopeSequence += 1
        _ = await runtimeBus.post(
            .system(
                SystemEnvelope(
                    source: .builtin(.filesystemWatcher), seq: nextEnvelopeSequence, timestamp: envelopeClock.now,
                    event: .topology(
                        .watchedFolderReconciled(
                            WatchedFolderTopologyObservation(
                                root: registration.watchedPath.path,
                                registration: registration.registeredRoot.registration,
                                entries: entries, otherObservedPaths: otherPaths, coverage: coverage,
                                baselineMembershipRevision: result.request.baselineMembershipRevision,
                                incompleteOtherScopes: incompleteScopes, demandCoverage: result.demandCoverage,
                                canonicalRoot: URL(
                                    fileURLWithPath: registration.registeredRoot.aliases.onceResolvedCanonical.path)
                            )))
                )))
        completeManualRefreshIfSatisfied()
    }

    package func isCurrentWatchedFolderObservation(_ observation: WatchedFolderTopologyObservation) -> Bool {
        let sourceID = observation.registration.sourceID
        guard let registration = watchedFolderScanState.registrationsBySourceID[sourceID],
            registration.registeredRoot.registration == observation.registration,
            registration.watchedPath.path.standardizedFileURL == observation.root.standardizedFileURL,
            registration.registeredRoot.aliases.onceResolvedCanonical.path == observation.canonicalRoot.path,
            let coverage = observation.demandCoverage,
            watchedFolderScanState.latestDemandCoverageBySourceID[sourceID] == coverage,
            watchedFolderScanState.appliedDemandCoverageBySourceID[sourceID] == coverage
        else { return false }
        return true
    }

    private static func validatedEntries(in result: RepoScannerResult) -> [RepoScanner.ResolvedGitEntry] {
        switch result {
        case .completeAuthoritative(let scan): return scan.verifiedEntries
        case .partial(let scan): return scan.verifiedEntries
        case .cancelled(let scan): return scan.verifiedEntries
        case .failed, .unavailable: return []
        }
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

    func watchedFolderRefreshSummary() -> WatchedFolderRefreshSummary {
        var repoPathsByWatchedFolder: [URL: [URL]] = [:]
        var linkedWorktreePathsByWatchedFolder: [URL: [URL]] = [:]
        var fingerprintComponents: [String] = []
        for (sourceID, registration) in watchedFolderScanState.registrationsBySourceID {
            let watchedRoot = registration.watchedPath.path.standardizedFileURL
            let groups = watchedFolderScanState.inventoryBySourceID[sourceID]?.repoGroups ?? []
            let repoPaths = groups.map(\.clonePath).sorted(by: Self.sortByPath)
            let linkedWorktreePaths = groups.flatMap(\.linkedWorktreePaths).sorted(by: Self.sortByPath)
            repoPathsByWatchedFolder[watchedRoot] = repoPaths
            linkedWorktreePathsByWatchedFolder[watchedRoot] = linkedWorktreePaths
            fingerprintComponents.append("root:\(StableKey.fromPath(watchedRoot))")
            fingerprintComponents.append(contentsOf: repoPaths.map { "repo:\(StableKey.fromPath($0))" })
            fingerprintComponents.append(
                contentsOf: linkedWorktreePaths.map { "worktree:\(StableKey.fromPath($0))" }
            )
        }
        let topologyFingerprint: String?
        if repoPathsByWatchedFolder.values.allSatisfy({ !$0.isEmpty }) {
            let digest = SHA256.hash(
                data: Data(fingerprintComponents.sorted().joined(separator: "\n").utf8)
            )
            topologyFingerprint = digest.map { String(format: "%02x", $0) }.joined()
        } else {
            topologyFingerprint = nil
        }
        return WatchedFolderRefreshSummary(
            repoPathsByWatchedFolder: repoPathsByWatchedFolder,
            linkedWorktreePathsByWatchedFolder: linkedWorktreePathsByWatchedFolder,
            topologyFingerprint: topologyFingerprint
        )
    }
}
