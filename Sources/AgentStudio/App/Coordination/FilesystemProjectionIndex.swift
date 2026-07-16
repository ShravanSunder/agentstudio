import Foundation

protocol WorkspaceFilesystemProjectionIndexing: Sendable {
    func reconcileSourceSync(_ request: FilesystemSourceSyncRequest) async -> FilesystemSourceSyncDiff
    func commitSourceSync(requestGeneration: UInt64, topologyGeneration: UInt64) async -> Bool
    func applyPaneUpdate(_ update: FilesystemProjectionPaneUpdate) async
    func projectPaneFilesystem(_ request: PaneFilesystemProjectionRequest) async -> PaneFilesystemProjectionResult
}

actor FilesystemProjectionIndex: WorkspaceFilesystemProjectionIndexing {
    private struct IndexedWorktree: Sendable, Equatable {
        let repoId: UUID
        let rootPath: URL
        let canonicalRootPath: String
    }

    private struct IndexedPane: Sendable, Equatable {
        let paneId: UUID
        let paneKind: PaneContentType
        let repoId: UUID
        let worktreeId: UUID
        let cwd: URL
        let canonicalCwdPath: String
    }

    private struct PendingSourceSyncSnapshot: Sendable {
        let worktreesById: [UUID: IndexedWorktree]
        let panesById: [UUID: IndexedPane]
        let paneIdsByWorktreeId: [UUID: Set<UUID>]
        let activityByWorktreeId: [UUID: Bool]
        let activePaneWorktreeId: UUID?
        let paneContextGeneration: UInt64
    }

    private var worktreesById: [UUID: IndexedWorktree] = [:]
    private var panesById: [UUID: IndexedPane] = [:]
    private var paneIdsByWorktreeId: [UUID: Set<UUID>] = [:]
    private var activityByWorktreeId: [UUID: Bool] = [:]
    private var activePaneWorktreeId: UUID?
    private var topologyGeneration: UInt64 = 0
    private var appliedPaneUpdateGeneration: UInt64 = 0
    private var canonicalPathByRawPath: [String: String] = [:]
    private var pendingSourceSyncsByRequestGeneration: [UInt64: PendingSourceSyncSnapshot] = [:]
    private var paneUpdateWaiters: [UInt64: [CheckedContinuation<Void, Never>]] = [:]

    func reconcileSourceSync(_ request: FilesystemSourceSyncRequest) async -> FilesystemSourceSyncDiff {
        let nextWorktreesById = buildWorktreeIndex(from: request.topologyEntries)
        let nextPanesById = buildPaneIndex(
            from: request.paneEntries,
            worktreesById: nextWorktreesById
        )
        let nextPaneIdsByWorktreeId = buildPaneIdsByWorktreeId(nextPanesById)
        let nextActivityByWorktreeId = nextWorktreesById.keys.reduce(into: [UUID: Bool]()) { result, worktreeId in
            result[worktreeId] = !(nextPaneIdsByWorktreeId[worktreeId]?.isEmpty ?? true)
        }

        let currentContextsByWorktreeId = worktreesById.mapValues { worktree in
            WorktreeFilesystemContext(repoId: worktree.repoId, rootPath: worktree.rootPath)
        }
        let nextContextsByWorktreeId = nextWorktreesById.mapValues { worktree in
            WorktreeFilesystemContext(repoId: worktree.repoId, rootPath: worktree.rootPath)
        }

        let currentWorktreeIds = Set(currentContextsByWorktreeId.keys)
        let nextWorktreeIds = Set(nextContextsByWorktreeId.keys)
        let removedWorktreeIds = currentWorktreeIds.subtracting(nextWorktreeIds)
            .sorted(by: sortUUIDs)

        let registrations =
            nextContextsByWorktreeId
            .filter { worktreeId, context in
                currentContextsByWorktreeId[worktreeId] != context
            }
            .map { worktreeId, context in
                FilesystemSourceSyncDiff.Registration(
                    worktreeId: worktreeId,
                    repoId: context.repoId,
                    rootPath: context.rootPath
                )
            }
            .sorted { lhs, rhs in
                sortWorktreeByPriority(
                    lhs.worktreeId,
                    rhs.worktreeId,
                    activePaneWorktreeId: request.activePaneWorktreeId
                )
            }

        let activityUpdates =
            nextActivityByWorktreeId
            .filter { worktreeId, isActiveInApp in
                request.appliedActivityByWorktreeId[worktreeId] != isActiveInApp
            }
            .map { FilesystemSourceSyncDiff.ActivityUpdate(worktreeId: $0.key, isActiveInApp: $0.value) }
            .sorted { lhs, rhs in
                sortWorktreeByPriority(
                    lhs.worktreeId,
                    rhs.worktreeId,
                    activePaneWorktreeId: request.activePaneWorktreeId
                )
            }

        let shouldUpdateActivePaneWorktree = request.appliedActivePaneWorktreeId != request.activePaneWorktreeId

        pendingSourceSyncsByRequestGeneration = pendingSourceSyncsByRequestGeneration.filter { requestGeneration, _ in
            requestGeneration >= request.requestGeneration
        }
        pendingSourceSyncsByRequestGeneration[request.requestGeneration] = PendingSourceSyncSnapshot(
            worktreesById: nextWorktreesById,
            panesById: nextPanesById,
            paneIdsByWorktreeId: nextPaneIdsByWorktreeId,
            activityByWorktreeId: nextActivityByWorktreeId,
            activePaneWorktreeId: request.activePaneWorktreeId,
            paneContextGeneration: request.paneContextGeneration
        )

        return FilesystemSourceSyncDiff(
            requestGeneration: request.requestGeneration,
            contextsByWorktreeId: nextContextsByWorktreeId,
            unregisterWorktreeIds: removedWorktreeIds,
            registerWorktrees: registrations,
            activityUpdates: activityUpdates,
            activityByWorktreeId: nextActivityByWorktreeId,
            activePaneWorktreeId: request.activePaneWorktreeId,
            shouldUpdateActivePaneWorktree: shouldUpdateActivePaneWorktree,
            validPaneIds: Set(nextPanesById.keys),
            validWorktreeIds: nextWorktreeIds
        )
    }

    func commitSourceSync(requestGeneration: UInt64, topologyGeneration: UInt64) async -> Bool {
        guard let pending = pendingSourceSyncsByRequestGeneration.removeValue(forKey: requestGeneration) else {
            return false
        }
        guard appliedPaneUpdateGeneration <= pending.paneContextGeneration else {
            return false
        }
        worktreesById = pending.worktreesById
        panesById = pending.panesById
        paneIdsByWorktreeId = pending.paneIdsByWorktreeId
        activityByWorktreeId = pending.activityByWorktreeId
        activePaneWorktreeId = pending.activePaneWorktreeId
        self.topologyGeneration = topologyGeneration
        appliedPaneUpdateGeneration = max(appliedPaneUpdateGeneration, pending.paneContextGeneration)
        pendingSourceSyncsByRequestGeneration = pendingSourceSyncsByRequestGeneration.filter { generation, _ in
            generation > requestGeneration
        }
        resumePaneUpdateWaiters()
        return true
    }

    func applyPaneUpdate(_ update: FilesystemProjectionPaneUpdate) async {
        guard update.requestGeneration >= appliedPaneUpdateGeneration else { return }
        switch update.kind {
        case .remove(let paneId):
            removePane(paneId)
        case .upsert(let entry):
            removePane(entry.paneId)
            guard let indexedPane = indexedPane(from: entry, worktreesById: worktreesById) else { return }
            panesById[entry.paneId] = indexedPane
            paneIdsByWorktreeId[indexedPane.worktreeId, default: []].insert(indexedPane.paneId)
            activityByWorktreeId[indexedPane.worktreeId] = true
        }
        appliedPaneUpdateGeneration = update.requestGeneration
        resumePaneUpdateWaiters()
    }

    func projectPaneFilesystem(_ request: PaneFilesystemProjectionRequest) async -> PaneFilesystemProjectionResult {
        await waitForPaneUpdates(through: request.paneContextGeneration)
        guard case .worktree(let worktreeEnvelope) = request.envelope else {
            return emptyProjectionResult(for: request)
        }

        let intents: [PaneFilesystemProjectionIntent]
        switch worktreeEnvelope.event {
        case .filesystem(.filesChanged(let changeset)):
            intents = filesystemIntents(for: changeset, envelope: worktreeEnvelope)
        case .gitWorkingDirectory(.snapshotChanged(let snapshot)):
            intents = gitSnapshotIntents(for: snapshot, envelope: worktreeEnvelope)
        default:
            intents = []
        }

        return PaneFilesystemProjectionResult(
            requestGeneration: request.requestGeneration,
            paneContextGeneration: request.paneContextGeneration,
            topologyGeneration: topologyGeneration,
            intents: intents,
            worktreeCount: worktreesById.count,
            paneCount: panesById.count
        )
    }

    private func waitForPaneUpdates(through generation: UInt64) async {
        guard appliedPaneUpdateGeneration < generation else { return }
        await withCheckedContinuation { continuation in
            paneUpdateWaiters[generation, default: []].append(continuation)
        }
    }

    private func resumePaneUpdateWaiters() {
        let readyGenerations = paneUpdateWaiters.keys.filter { $0 <= appliedPaneUpdateGeneration }
        for generation in readyGenerations {
            let waiters = paneUpdateWaiters.removeValue(forKey: generation) ?? []
            for waiter in waiters {
                waiter.resume()
            }
        }
    }

    private func buildWorktreeIndex(
        from entries: [FilesystemProjectionTopologyEntry]
    ) -> [UUID: IndexedWorktree] {
        var nextWorktreesById: [UUID: IndexedWorktree] = [:]
        for entry in entries where !entry.isUnavailable {
            let rootPath = entry.rootPath.standardizedFileURL.resolvingSymlinksInPath()
            nextWorktreesById[entry.worktreeId] = IndexedWorktree(
                repoId: entry.repoId,
                rootPath: rootPath,
                canonicalRootPath: canonicalPath(rootPath)
            )
        }
        return nextWorktreesById
    }

    private func buildPaneIndex(
        from entries: [FilesystemProjectionPaneEntry],
        worktreesById: [UUID: IndexedWorktree]
    ) -> [UUID: IndexedPane] {
        var nextPanesById: [UUID: IndexedPane] = [:]
        for entry in entries {
            guard let indexedPane = indexedPane(from: entry, worktreesById: worktreesById) else { continue }
            nextPanesById[entry.paneId] = indexedPane
        }
        return nextPanesById
    }

    private func indexedPane(
        from entry: FilesystemProjectionPaneEntry,
        worktreesById: [UUID: IndexedWorktree]
    ) -> IndexedPane? {
        guard
            let repoId = entry.repoId,
            let worktreeId = entry.worktreeId,
            let worktree = worktreesById[worktreeId]
        else {
            return nil
        }
        let cwd = (entry.cwd ?? worktree.rootPath).standardizedFileURL.resolvingSymlinksInPath()
        return IndexedPane(
            paneId: entry.paneId,
            paneKind: entry.paneKind,
            repoId: repoId,
            worktreeId: worktreeId,
            cwd: cwd,
            canonicalCwdPath: boundedToWorktree(
                panePath: canonicalPath(cwd),
                worktreeRootPath: worktree.canonicalRootPath
            )
        )
    }

    private func buildPaneIdsByWorktreeId(_ panesById: [UUID: IndexedPane]) -> [UUID: Set<UUID>] {
        panesById.values.reduce(into: [UUID: Set<UUID>]()) { result, pane in
            result[pane.worktreeId, default: []].insert(pane.paneId)
        }
    }

    private func removePane(_ paneId: UUID) {
        guard let existingPane = panesById.removeValue(forKey: paneId) else { return }
        paneIdsByWorktreeId[existingPane.worktreeId]?.remove(paneId)
        if paneIdsByWorktreeId[existingPane.worktreeId]?.isEmpty == true {
            paneIdsByWorktreeId.removeValue(forKey: existingPane.worktreeId)
            activityByWorktreeId[existingPane.worktreeId] = false
        }
    }

    private func filesystemIntents(
        for changeset: FileChangeset,
        envelope: WorktreeEnvelope
    ) -> [PaneFilesystemProjectionIntent] {
        guard let worktree = worktreesById[changeset.worktreeId] else { return [] }
        let paneIds = paneIdsByWorktreeId[changeset.worktreeId] ?? []
        guard !paneIds.isEmpty else { return [] }

        return paneIds.compactMap { paneId in
            guard let pane = panesById[paneId] else { return nil }
            let subtreePrefix = relativePath(
                from: worktree.canonicalRootPath,
                to: pane.canonicalCwdPath
            )
            let filteredPaths = filteredPaths(
                changesetPaths: changeset.paths,
                subtreePrefix: subtreePrefix
            )
            guard !filteredPaths.isEmpty else { return nil }
            return .cwdSubtreeChanged(
                PaneFilesystemCWDSubtreeProjection(
                    paneId: pane.paneId,
                    paneKind: pane.paneKind,
                    context: context(for: pane),
                    paths: filteredPaths,
                    batchSequence: changeset.batchSeq,
                    timestamp: changeset.timestamp,
                    correlationId: envelope.correlationId,
                    commandId: envelope.commandId
                )
            )
        }
    }

    private func gitSnapshotIntents(
        for snapshot: GitWorkingTreeSnapshot,
        envelope: WorktreeEnvelope
    ) -> [PaneFilesystemProjectionIntent] {
        let paneIds = paneIdsByWorktreeId[snapshot.worktreeId] ?? []
        guard !paneIds.isEmpty else { return [] }

        return paneIds.compactMap { paneId in
            guard let pane = panesById[paneId] else { return nil }
            return .gitWorkingTreeInCwd(
                PaneFilesystemGitProjection(
                    paneId: pane.paneId,
                    paneKind: pane.paneKind,
                    context: context(for: pane),
                    summary: snapshot.summary,
                    timestamp: envelope.timestamp,
                    correlationId: envelope.correlationId,
                    commandId: envelope.commandId
                )
            )
        }
    }

    private func context(for pane: IndexedPane) -> PaneFilesystemContext {
        PaneFilesystemContext(
            paneId: PaneId(existingUUID: pane.paneId),
            repoId: pane.repoId,
            cwd: pane.cwd,
            worktreeId: pane.worktreeId
        )
    }

    private func emptyProjectionResult(for request: PaneFilesystemProjectionRequest) -> PaneFilesystemProjectionResult {
        PaneFilesystemProjectionResult(
            requestGeneration: request.requestGeneration,
            paneContextGeneration: request.paneContextGeneration,
            topologyGeneration: request.topologyGeneration,
            intents: [],
            worktreeCount: worktreesById.count,
            paneCount: panesById.count
        )
    }

    private func canonicalPath(_ pathURL: URL) -> String {
        let rawPath = pathURL.path
        if let cached = canonicalPathByRawPath[rawPath] {
            return cached
        }
        let canonical = pathURL.standardizedFileURL.resolvingSymlinksInPath().path
        canonicalPathByRawPath[rawPath] = canonical
        return canonical
    }

    private func filteredPaths(changesetPaths: [String], subtreePrefix: String) -> [String] {
        guard !changesetPaths.isEmpty else { return [] }
        var seen: Set<String> = []
        var filtered: [String] = []
        for rawPath in changesetPaths {
            let normalizedPath = normalizedRelativePath(rawPath)
            guard matchesSubtree(normalizedPath, subtreePrefix: subtreePrefix) else { continue }
            if seen.insert(normalizedPath).inserted {
                filtered.append(normalizedPath)
            }
        }
        return filtered
    }

    private func matchesSubtree(_ relativePath: String, subtreePrefix: String) -> Bool {
        guard !subtreePrefix.isEmpty else { return true }
        if relativePath == "." { return true }
        if relativePath == subtreePrefix { return true }
        return relativePath.hasPrefix(subtreePrefix + "/")
    }

    private func boundedToWorktree(panePath: String, worktreeRootPath: String) -> String {
        if panePath == worktreeRootPath {
            return panePath
        }
        if panePath.hasPrefix(worktreeRootPath + "/") {
            return panePath
        }
        return worktreeRootPath
    }

    private func relativePath(from rootPath: String, to panePath: String) -> String {
        guard panePath != rootPath else { return "" }
        let prefix = rootPath == "/" ? "/" : rootPath + "/"
        if panePath.hasPrefix(prefix) {
            return String(panePath.dropFirst(prefix.count))
        }
        return ""
    }

    private func normalizedRelativePath(_ rawPath: String) -> String {
        let trimmedPath = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return "." }

        var normalizedPath = trimmedPath
        while normalizedPath.hasPrefix("./") {
            normalizedPath.removeFirst(2)
        }
        if normalizedPath.hasPrefix("/") {
            normalizedPath.removeFirst()
        }
        return normalizedPath.isEmpty ? "." : normalizedPath
    }

    private func sortWorktreeByPriority(
        _ lhs: UUID,
        _ rhs: UUID,
        activePaneWorktreeId: UUID?
    ) -> Bool {
        let lhsActive = lhs == activePaneWorktreeId
        let rhsActive = rhs == activePaneWorktreeId
        if lhsActive != rhsActive { return lhsActive }
        return sortUUIDs(lhs, rhs)
    }

    private func sortUUIDs(_ lhs: UUID, _ rhs: UUID) -> Bool {
        lhs.uuidString < rhs.uuidString
    }
}
