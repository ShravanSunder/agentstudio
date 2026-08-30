import Foundation

extension FilesystemActor {
    func ingestRawPaths(
        worktreeId: UUID,
        paths: [String],
        requiresFullGitRefresh: Bool,
        activityParticipant: FSEventParticipant? = nil,
        activityObservations: [FSEventObservation] = [],
        shouldScheduleAndRecord: Bool = true
    ) async {
        guard !hasBegunShutdown else { return }
        guard roots[worktreeId] != nil else {
            Self.logger.debug(
                "Dropped filesystem path batch for unregistered worktree \(worktreeId.uuidString, privacy: .public)"
            )
            return
        }
        guard !paths.isEmpty || requiresFullGitRefresh || !activityObservations.isEmpty else {
            return
        }

        recordRequiredFullGitRefresh(for: worktreeId, when: requiresFullGitRefresh)

        let observedActivityPaths = Set(
            activityObservations.lazy.filter { !$0.isOwnEvent }.map(\.path)
        )
        let ownedEventPaths = Set(
            activityObservations.lazy.filter(\.isOwnEvent).map(\.path)
        )
        let ordinaryPathSet = Set(paths)
        var qualifyingRepositoryStableKeys: Set<String> = []
        var coverageLostRepositoryStableKeys: Set<String> = []
        for rawPath in paths {
            guard let ownedPath = rootOwnership.route(sourceWorktreeId: worktreeId, rawPath: rawPath)
            else {
                Self.logger.debug(
                    "Dropped unroutable filesystem path for source worktree \(worktreeId.uuidString, privacy: .public): \(rawPath, privacy: .public)"
                )
                continue
            }
            guard let root = roots[ownedPath.worktreeId] else { continue }

            if Self.isGitIgnoreReloadPath(rawPath: rawPath, relativePath: ownedPath.relativePath) {
                if observedActivityPaths.contains(rawPath),
                    let repositoryStableKey = repositoryStableKeysByWorktreeId[ownedPath.worktreeId]
                {
                    qualifyingRepositoryStableKeys.insert(repositoryStableKey)
                }
                let pathFilter = await FilesystemPathFilter.loadOffExecutor(forRootPath: root.rootPath)
                guard !hasBegunShutdown else { return }
                guard var latestRoot = roots[ownedPath.worktreeId] else { continue }
                latestRoot.pathFilter = pathFilter
                roots[ownedPath.worktreeId] = latestRoot

                var pendingChanges = pendingChangesByWorktreeId[ownedPath.worktreeId] ?? PendingWorktreeChanges()
                pendingChanges.containsGitInternalChanges = true
                pendingChanges.recordPendingChange(at: schedulingClock.now())
                pendingChangesByWorktreeId[ownedPath.worktreeId] = pendingChanges
                continue
            }

            var pendingChanges = pendingChangesByWorktreeId[ownedPath.worktreeId] ?? PendingWorktreeChanges()
            let pathDisposition = root.pathFilter.classify(relativePath: ownedPath.relativePath)
            switch pathDisposition {
            case .projected:
                pendingChanges.projectedPaths.insert(ownedPath.relativePath)
            case .gitInternal:
                pendingChanges.containsGitInternalChanges = true
                pendingChanges.suppressedGitInternalPathCount += 1
            case .ignoredByPolicy:
                pendingChanges.suppressedIgnoredPathCount += 1
            }
            if observedActivityPaths.contains(rawPath),
                let repositoryStableKey = repositoryStableKeysByWorktreeId[ownedPath.worktreeId],
                RepositoryLocalActivityPathClassifier.qualifiesWorktreePath(
                    relativePath: ownedPath.relativePath,
                    disposition: pathDisposition
                )
            {
                qualifyingRepositoryStableKeys.insert(repositoryStableKey)
            }
            if ownedEventPaths.contains(rawPath),
                pathDisposition == .gitInternal,
                RepositoryLocalActivityPathClassifier.qualifiesGitMetadataPath(
                    ownedPath.relativePath
                ),
                let repositoryStableKey = repositoryStableKeysByWorktreeId[ownedPath.worktreeId]
            {
                coverageLostRepositoryStableKeys.insert(repositoryStableKey)
            }
            pendingChanges.recordPendingChange(at: schedulingClock.now())
            pendingChangesByWorktreeId[ownedPath.worktreeId] = pendingChanges
        }

        if let activityParticipant {
            await ingestRepositoryLocalActivity(
                RepositoryLocalActivityIngress(
                    sourceWorktreeID: worktreeId,
                    participant: activityParticipant,
                    observations: activityObservations,
                    ordinaryPaths: ordinaryPathSet,
                    qualifyingRepositoryStableKeys: qualifyingRepositoryStableKeys,
                    coverageLostRepositoryStableKeys: coverageLostRepositoryStableKeys
                )
            )
        }

        if shouldScheduleAndRecord {
            scheduleDrainIfNeeded()
            await recordLogicalDebtSnapshotIfChanged()
        }
    }

    private struct RepositoryLocalActivityIngress {
        let sourceWorktreeID: UUID
        let participant: FSEventParticipant
        let observations: [FSEventObservation]
        let ordinaryPaths: Set<String>
        var qualifyingRepositoryStableKeys: Set<String>
        var coverageLostRepositoryStableKeys: Set<String>
    }

    private func ingestRepositoryLocalActivity(
        _ ingress: RepositoryLocalActivityIngress
    ) async {
        guard let processedThroughEventID = ingress.observations.map(\.eventID).max() else {
            return
        }
        var qualifyingRepositoryStableKeys = ingress.qualifyingRepositoryStableKeys
        var coverageLostRepositoryStableKeys = ingress.coverageLostRepositoryStableKeys
        if let repositoryStableKey = repositoryStableKeysByWorktreeId[ingress.sourceWorktreeID] {
            if ingress.observations.contains(where: {
                !ingress.ordinaryPaths.contains($0.path)
                    && !$0.isOwnEvent
                    && RepositoryLocalActivityPathClassifier.qualifiesGitMetadataPath($0.path)
            }) {
                qualifyingRepositoryStableKeys.insert(repositoryStableKey)
            }
            if ingress.observations.contains(where: {
                $0.hasCoverageLoss
                    || ($0.isOwnEvent
                        && RepositoryLocalActivityPathClassifier.qualifiesGitMetadataPath($0.path))
            }) {
                coverageLostRepositoryStableKeys.insert(repositoryStableKey)
            }
        }
        await repositoryLocalActivityProjector?.ingest(
            RepositoryLocalActivityObservedEvent(
                scopeKey: ingress.participant.scopeKey,
                generation: ingress.participant.generation,
                eventID: processedThroughEventID,
                qualifyingRepositoryStableKeys: qualifyingRepositoryStableKeys,
                coverageLostRepositoryStableKeys: coverageLostRepositoryStableKeys,
                observedAt: Date()
            )
        )
        recordPendingActivityCheckpoint()
    }

    private func recordRequiredFullGitRefresh(for worktreeId: UUID, when required: Bool) {
        guard required else { return }
        var pendingChanges = pendingChangesByWorktreeId[worktreeId] ?? PendingWorktreeChanges()
        pendingChanges.containsGitInternalChanges = true
        pendingChanges.recordPendingChange(at: schedulingClock.now())
        pendingChangesByWorktreeId[worktreeId] = pendingChanges
    }

    nonisolated private static func isGitIgnoreReloadPath(
        rawPath: String,
        relativePath: String
    ) -> Bool {
        if relativePath == ".gitignore" {
            return true
        }
        guard relativePath == "." else {
            return false
        }
        let normalizedRawPath =
            rawPath
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")
        return normalizedRawPath == ".gitignore" || normalizedRawPath.hasSuffix("/.gitignore")
    }
}
