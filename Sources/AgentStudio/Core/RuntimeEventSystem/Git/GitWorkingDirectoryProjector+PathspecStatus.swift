import Foundation

/// Pathspec-scoped status folding: instead of recomputing a full-worktree status
/// on every file-change batch, the projector scopes the status walk to just the
/// changed paths and folds the scoped entries into the cached full entry set.
///
/// Only the per-file counts (changed/staged/untracked) are reconstructed from the
/// fold; `linesAdded`/`linesDeleted`, branch, sync, and origin come straight from
/// the scoped result because the SDK computes those over the full worktree
/// regardless of the pathspec. Split from the projector actor body to keep it
/// under the type/file length caps.
extension GitWorkingDirectoryProjector {
    enum GitStatusScope: Sendable {
        case full
        case pathspec

        var traceValue: String {
            switch self {
            case .full: "full"
            case .pathspec: "pathspec"
            }
        }
    }

    struct ResolvedGitStatus: Sendable {
        let result: GitWorkingTreeStatusResult
        let scope: GitStatusScope
        let pathspecCount: Int
    }

    private enum ScopeDecision {
        case full
        case scoped(pathspecs: [String], cachedEntries: [GitWorkingTreeStatusEntry])
    }

    /// Resolves the status for a changeset, choosing a full or pathspec-scoped
    /// compute and folding a scoped result into the cached entry set. The scope
    /// decision captures the cached entries synchronously so a concurrent
    /// unregistration cannot race the fold.
    func resolveStatusResult(for changeset: FileChangeset) async -> ResolvedGitStatus {
        switch scopeDecision(for: changeset) {
        case .full:
            let result = await gitWorkingTreeProvider.statusResult(for: changeset.rootPath, pathspecs: nil)
            return ResolvedGitStatus(result: result, scope: .full, pathspecCount: 0)
        case .scoped(let pathspecs, let cachedEntries):
            let scopedResult = await gitWorkingTreeProvider.statusResult(
                for: changeset.rootPath,
                pathspecs: pathspecs
            )
            guard case .available(let scoped) = scopedResult else {
                // Scoped compute failed: hand the unavailable result back so the
                // existing circuit-breaker / nil-retry handling runs unchanged.
                return ResolvedGitStatus(result: scopedResult, scope: .pathspec, pathspecCount: pathspecs.count)
            }
            guard
                let folded = Self.foldScopedStatus(
                    cachedEntries: cachedEntries,
                    scoped: scoped,
                    pathspecs: pathspecs
                )
            else {
                // Rename guard tripped: recompute the full worktree for this batch.
                let fullResult = await gitWorkingTreeProvider.statusResult(for: changeset.rootPath, pathspecs: nil)
                return ResolvedGitStatus(result: fullResult, scope: .full, pathspecCount: 0)
            }
            return ResolvedGitStatus(result: .available(folded), scope: .pathspec, pathspecCount: pathspecs.count)
        }
    }

    private func scopeDecision(for changeset: FileChangeset) -> ScopeDecision {
        // A scoped fold requires a cached full entry set to fold into; the first
        // compute for a worktree, periodic/synthetic ticks (empty paths), and any
        // git-internal touch stay full so drift is caught.
        guard let cachedEntries = lastStatusEntriesByWorktreeId[changeset.worktreeId] else { return .full }
        guard !changeset.paths.isEmpty else { return .full }
        guard !Self.changesetTouchesGitInternal(changeset) else { return .full }

        let pathspecs = Self.normalizedPathspecs(changeset.paths)
        guard !pathspecs.isEmpty else { return .full }
        guard pathspecs.count <= refreshPolicy.maxScopedStatusPathspecCount else { return .full }
        // fnmatch metacharacters would make a literal changed path match unintended
        // entries; fall back to a full status rather than mis-scope.
        guard !pathspecs.contains(where: Self.containsPathspecMetacharacters) else { return .full }

        return .scoped(pathspecs: pathspecs, cachedEntries: cachedEntries)
    }

    /// Folds a scoped status result into the cached full entry set: cached entries
    /// outside the pathspec are kept, in-scope entries are replaced by the scoped
    /// result (entries absent from it became clean and are dropped), and the
    /// file counts are recomputed. Returns `nil` when a rename half cannot be
    /// reconciled against the cache, signalling a full-recompute fallback.
    nonisolated static func foldScopedStatus(
        cachedEntries: [GitWorkingTreeStatusEntry],
        scoped: GitWorkingTreeStatus,
        pathspecs: [String]
    ) -> GitWorkingTreeStatus? {
        for entry in scoped.entries {
            if let previousPath = entry.previousPath {
                guard pathspecCovers(pathspecs, previousPath) else { return nil }
            } else if entry.isRename {
                return nil
            }
        }

        var entriesByPath: [String: GitWorkingTreeStatusEntry] = [:]
        for entry in cachedEntries where !pathspecCovers(pathspecs, entry.path) {
            entriesByPath[entry.path] = entry
        }
        for entry in scoped.entries {
            entriesByPath[entry.path] = entry
        }
        let foldedEntries = Array(entriesByPath.values)

        let counts = GitWorkingTreeStatus.fileCounts(for: foldedEntries)
        let foldedSummary = GitWorkingTreeSummary(
            changed: counts.changed,
            staged: counts.staged,
            untracked: counts.untracked,
            linesAdded: scoped.summary.linesAdded,
            linesDeleted: scoped.summary.linesDeleted,
            aheadCount: scoped.summary.aheadCount,
            behindCount: scoped.summary.behindCount,
            hasUpstream: scoped.summary.hasUpstream
        )
        return GitWorkingTreeStatus(
            summary: foldedSummary,
            branch: scoped.branch,
            originResolution: scoped.originResolution,
            entries: foldedEntries
        )
    }

    nonisolated static func changesetTouchesGitInternal(_ changeset: FileChangeset) -> Bool {
        changeset.containsGitInternalChanges
            || changeset.suppressedGitInternalPathCount > 0
            || changeset.paths.contains(where: isGitInternalPath)
    }

    nonisolated static func normalizedPathspecs(_ paths: [String]) -> [String] {
        var seen = Set<String>()
        var normalizedPaths: [String] = []
        for path in paths {
            let normalized = normalizePath(path)
            guard !normalized.isEmpty else { continue }
            guard seen.insert(normalized).inserted else { continue }
            normalizedPaths.append(normalized)
        }
        return normalizedPaths
    }

    nonisolated static func pathspecCovers(_ pathspecs: [String], _ path: String) -> Bool {
        pathspecs.contains { pathspec in
            path == pathspec || path.hasPrefix("\(pathspec)/")
        }
    }

    nonisolated private static func isGitInternalPath(_ path: String) -> Bool {
        let normalized = normalizePath(path)
        return normalized == ".git"
            || normalized.hasPrefix(".git/")
            || normalized.contains("/.git/")
            || normalized.hasSuffix("/.git")
    }

    nonisolated private static func containsPathspecMetacharacters(_ pathspec: String) -> Bool {
        pathspec.contains { character in
            character == "*" || character == "?" || character == "[" || character == "]"
        }
    }

    nonisolated private static func normalizePath(_ path: String) -> String {
        path
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
