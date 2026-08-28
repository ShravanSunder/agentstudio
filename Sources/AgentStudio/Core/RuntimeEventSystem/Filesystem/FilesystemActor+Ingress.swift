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

        let observedActivityPaths = Set(activityObservations.map(\.path))
        let ordinaryPathSet = Set(paths)
        var qualifyingRepositoryStableKeys: Set<String> = []
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
            pendingChanges.recordPendingChange(at: schedulingClock.now())
            pendingChangesByWorktreeId[ownedPath.worktreeId] = pendingChanges
        }

        if let activityParticipant,
            let processedThroughEventID = activityObservations.map(\.eventID).max()
        {
            if let repositoryStableKey = repositoryStableKeysByWorktreeId[worktreeId],
                activityObservations.contains(where: {
                    !ordinaryPathSet.contains($0.path)
                        && RepositoryLocalActivityPathClassifier.qualifiesGitMetadataPath($0.path)
                })
            {
                qualifyingRepositoryStableKeys.insert(repositoryStableKey)
            }
            let coverageLostRepositoryStableKeys: Set<String>
            if activityObservations.contains(where: \.hasCoverageLoss),
                let repositoryStableKey = repositoryStableKeysByWorktreeId[worktreeId]
            {
                coverageLostRepositoryStableKeys = [repositoryStableKey]
            } else {
                coverageLostRepositoryStableKeys = []
            }
            await repositoryLocalActivityProjector?.ingest(
                RepositoryLocalActivityObservedEvent(
                    scopeKey: activityParticipant.scopeKey,
                    generation: activityParticipant.generation,
                    eventID: processedThroughEventID,
                    qualifyingRepositoryStableKeys: qualifyingRepositoryStableKeys,
                    coverageLostRepositoryStableKeys: coverageLostRepositoryStableKeys,
                    observedAt: Date()
                )
            )
            recordPendingActivityCheckpoint()
        }

        if shouldScheduleAndRecord {
            scheduleDrainIfNeeded()
            await recordLogicalDebtSnapshotIfChanged()
        }
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
