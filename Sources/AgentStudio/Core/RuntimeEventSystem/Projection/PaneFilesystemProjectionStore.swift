import Foundation
import Observation

@Observable
@MainActor
final class PaneFilesystemProjectionStore {
    struct PaneSnapshot: Equatable, Sendable {
        let paneId: UUID
        let worktreeId: UUID
        let changedPaths: [String]
        let batchSequence: UInt64
        let timestamp: ContinuousClock.Instant
        let lastGitSummary: GitWorkingTreeSummary?
    }

    private(set) var snapshotsByPaneId: [UUID: PaneSnapshot] = [:]
    private(set) var contextsByPaneId: [UUID: PaneFilesystemContext] = [:]
    private var nextSequenceByPaneId: [UUID: UInt64] = [:]

    func registerPaneContext(_ context: PaneFilesystemContext) {
        contextsByPaneId[context.paneId.uuid] = context
    }

    func unregisterPaneContext(_ paneUUID: UUID) {
        contextsByPaneId.removeValue(forKey: paneUUID)
        snapshotsByPaneId.removeValue(forKey: paneUUID)
        nextSequenceByPaneId.removeValue(forKey: paneUUID)
    }

    func context(for paneUUID: UUID) -> PaneFilesystemContext? {
        contextsByPaneId[paneUUID]
    }

    func updatePaneCwd(paneId paneUUID: UUID, newCwd: URL) {
        guard var existing = contextsByPaneId[paneUUID] else { return }
        let normalizedCwd = newCwd.standardizedFileURL.resolvingSymlinksInPath()
        guard existing.cwd != normalizedCwd else { return }
        existing = PaneFilesystemContext(
            paneId: existing.paneId,
            repoId: existing.repoId,
            cwd: normalizedCwd,
            worktreeId: existing.worktreeId
        )
        contextsByPaneId[paneUUID] = existing
        snapshotsByPaneId.removeValue(forKey: paneUUID)
    }

    func consume(
        _ envelope: RuntimeEnvelope,
        panesById: [UUID: Pane],
        worktreeRootsByWorktreeId: [UUID: URL]
    ) -> [RuntimeEnvelope] {
        guard case .worktree(let worktreeEnvelope) = envelope else { return [] }

        switch worktreeEnvelope.event {
        case .filesystem(.filesChanged(let changeset)):
            guard let worktreeRootPath = worktreeRootsByWorktreeId[changeset.worktreeId] else { return [] }

            let panes = panesById.values.filter { $0.worktreeId == changeset.worktreeId }
            guard !panes.isEmpty else { return [] }

            var derivedEnvelopes: [RuntimeEnvelope] = []
            for pane in panes {
                let filteredPaths = Self.filteredPaths(
                    changesetPaths: changeset.paths,
                    paneCwd: pane.metadata.facets.cwd,
                    worktreeRootPath: worktreeRootPath
                )
                guard !filteredPaths.isEmpty else { continue }

                let previousSummary = snapshotsByPaneId[pane.id]?.lastGitSummary
                snapshotsByPaneId[pane.id] = PaneSnapshot(
                    paneId: pane.id,
                    worktreeId: changeset.worktreeId,
                    changedPaths: filteredPaths,
                    batchSequence: changeset.batchSeq,
                    timestamp: changeset.timestamp,
                    lastGitSummary: previousSummary
                )

                let context = resolvedContext(for: pane, fallbackCwd: worktreeRootPath)
                derivedEnvelopes.append(
                    makePaneContextEnvelope(
                        pane: pane,
                        timestamp: changeset.timestamp,
                        correlationId: worktreeEnvelope.correlationId,
                        commandId: worktreeEnvelope.commandId,
                        event: .paneFilesystemContext(
                            .cwdSubtreeChanged(
                                context: context,
                                paths: Set(filteredPaths),
                                batchSeq: changeset.batchSeq
                            )
                        )
                    )
                )
            }
            return derivedEnvelopes

        case .gitWorkingDirectory(.snapshotChanged(let snapshot)):
            let panes = panesById.values.filter { $0.worktreeId == snapshot.worktreeId }
            guard !panes.isEmpty else { return [] }

            var derivedEnvelopes: [RuntimeEnvelope] = []
            for pane in panes {
                let previousSnapshot = snapshotsByPaneId[pane.id]
                snapshotsByPaneId[pane.id] = PaneSnapshot(
                    paneId: pane.id,
                    worktreeId: snapshot.worktreeId,
                    changedPaths: previousSnapshot?.changedPaths ?? [],
                    batchSequence: previousSnapshot?.batchSequence ?? 0,
                    timestamp: worktreeEnvelope.timestamp,
                    lastGitSummary: snapshot.summary
                )

                let context = resolvedContext(for: pane, fallbackCwd: snapshot.rootPath)
                derivedEnvelopes.append(
                    makePaneContextEnvelope(
                        pane: pane,
                        timestamp: worktreeEnvelope.timestamp,
                        correlationId: worktreeEnvelope.correlationId,
                        commandId: worktreeEnvelope.commandId,
                        event: .paneFilesystemContext(
                            .gitWorkingTreeInCwd(
                                context: context,
                                staged: snapshot.summary.staged,
                                unstaged: snapshot.summary.changed,
                                untracked: snapshot.summary.untracked
                            )
                        )
                    )
                )
            }
            return derivedEnvelopes

        default:
            // Only filesystem batches and git snapshot facts participate in
            // the pane-scoped filesystem projection. Other worktree events are
            // intentionally ignored here.
            return []
        }
    }

    func prune(validPaneIds: Set<UUID>, validWorktreeIds: Set<UUID>) {
        snapshotsByPaneId = snapshotsByPaneId.filter { paneId, snapshot in
            validPaneIds.contains(paneId) && validWorktreeIds.contains(snapshot.worktreeId)
        }
        contextsByPaneId = contextsByPaneId.filter { paneId, context in
            validPaneIds.contains(paneId) && validWorktreeIds.contains(context.worktreeId)
        }
        nextSequenceByPaneId = nextSequenceByPaneId.filter { paneId, _ in
            validPaneIds.contains(paneId)
        }
    }

    func reset() {
        snapshotsByPaneId.removeAll()
        contextsByPaneId.removeAll()
        nextSequenceByPaneId.removeAll()
    }

    private func resolvedContext(for pane: Pane, fallbackCwd: URL) -> PaneFilesystemContext {
        if let existing = contextsByPaneId[pane.id] {
            return existing
        }

        guard let repoId = pane.repoId ?? pane.metadata.repoId,
            let worktreeId = pane.worktreeId ?? pane.metadata.worktreeId
        else {
            return PaneFilesystemContext(
                paneId: PaneId(uuid: pane.id),
                repoId: pane.id,
                cwd: (pane.metadata.facets.cwd ?? fallbackCwd).standardizedFileURL.resolvingSymlinksInPath(),
                worktreeId: pane.id
            )
        }

        let context = PaneFilesystemContext(
            paneId: PaneId(uuid: pane.id),
            repoId: repoId,
            cwd: (pane.metadata.facets.cwd ?? fallbackCwd).standardizedFileURL.resolvingSymlinksInPath(),
            worktreeId: worktreeId
        )
        contextsByPaneId[pane.id] = context
        return context
    }

    private func makePaneContextEnvelope(
        pane: Pane,
        timestamp: ContinuousClock.Instant,
        correlationId: UUID?,
        commandId: UUID?,
        event: PaneRuntimeEvent
    ) -> RuntimeEnvelope {
        let nextSequence = nextSequenceByPaneId[pane.id, default: 0] + 1
        nextSequenceByPaneId[pane.id] = nextSequence

        return .pane(
            PaneEnvelope(
                source: .pane(PaneId(uuid: pane.id)),
                seq: nextSequence,
                timestamp: timestamp,
                correlationId: correlationId,
                commandId: commandId,
                paneId: PaneId(uuid: pane.id),
                paneKind: pane.metadata.contentType,
                event: event
            )
        )
    }

    static func filteredPaths(
        changesetPaths: [String],
        paneCwd: URL?,
        worktreeRootPath: URL
    ) -> [String] {
        guard !changesetPaths.isEmpty else { return [] }

        let rootPath = canonicalPath(worktreeRootPath)
        let panePath = canonicalPath(paneCwd ?? worktreeRootPath)
        let boundedPanePath = boundedToWorktree(panePath: panePath, worktreeRootPath: rootPath)
        let subtreePrefix = relativePath(from: rootPath, to: boundedPanePath)

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

    private static func matchesSubtree(_ relativePath: String, subtreePrefix: String) -> Bool {
        guard !subtreePrefix.isEmpty else { return true }
        if relativePath == "." { return true }
        if relativePath == subtreePrefix { return true }
        return relativePath.hasPrefix(subtreePrefix + "/")
    }

    private static func boundedToWorktree(panePath: String, worktreeRootPath: String) -> String {
        if panePath == worktreeRootPath {
            return panePath
        }
        if panePath.hasPrefix(worktreeRootPath + "/") {
            return panePath
        }
        return worktreeRootPath
    }

    private static func relativePath(from rootPath: String, to panePath: String) -> String {
        guard panePath != rootPath else { return "" }
        let prefix = rootPath == "/" ? "/" : rootPath + "/"
        if panePath.hasPrefix(prefix) {
            return String(panePath.dropFirst(prefix.count))
        }
        return ""
    }

    private static func canonicalPath(_ pathURL: URL) -> String {
        pathURL.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private static func normalizedRelativePath(_ rawPath: String) -> String {
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
}
