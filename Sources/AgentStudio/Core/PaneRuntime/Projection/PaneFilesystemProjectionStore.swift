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
    }

    static let shared = PaneFilesystemProjectionStore()

    private(set) var snapshotsByPaneId: [UUID: PaneSnapshot] = [:]

    func consume(
        _ envelope: PaneEventEnvelope,
        panesById: [UUID: Pane],
        worktreeRootsByWorktreeId: [UUID: URL]
    ) {
        guard case .filesystem(.filesChanged(let changeset)) = envelope.event else { return }
        guard let worktreeRootPath = worktreeRootsByWorktreeId[changeset.worktreeId] else { return }

        let panes = panesById.values.filter { $0.worktreeId == changeset.worktreeId }
        guard !panes.isEmpty else { return }

        for pane in panes {
            let filteredPaths = Self.filteredPaths(
                changesetPaths: changeset.paths,
                paneCwd: pane.metadata.facets.cwd,
                worktreeRootPath: worktreeRootPath
            )
            guard !filteredPaths.isEmpty else { continue }

            snapshotsByPaneId[pane.id] = PaneSnapshot(
                paneId: pane.id,
                worktreeId: changeset.worktreeId,
                changedPaths: filteredPaths,
                batchSequence: changeset.batchSeq,
                timestamp: changeset.timestamp
            )
        }
    }

    func prune(validPaneIds: Set<UUID>, validWorktreeIds: Set<UUID>) {
        snapshotsByPaneId = snapshotsByPaneId.filter { paneId, snapshot in
            validPaneIds.contains(paneId) && validWorktreeIds.contains(snapshot.worktreeId)
        }
    }

    func reset() {
        snapshotsByPaneId.removeAll()
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
