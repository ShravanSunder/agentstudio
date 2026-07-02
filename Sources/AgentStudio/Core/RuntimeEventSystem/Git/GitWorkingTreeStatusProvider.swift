import Foundation

enum GitOriginResolution: Sendable, Equatable {
    case awaitingResolution
    case confirmedAbsent
    case resolved(String)
}

/// Per-file working-tree status fact, projected from the SDK `GitStatusEntry`.
///
/// The projector folds scoped status results into a cached full entry set, so
/// it needs the per-path axes that drive the emitted summary counts (staged,
/// unstaged/changed, untracked) plus enough rename signal to guard the fold.
/// `path`/`previousPath` are repo-relative, matching pathspec semantics.
struct GitWorkingTreeStatusEntry: Sendable, Equatable {
    let path: String
    let previousPath: String?
    let hasStagedChange: Bool
    let hasUnstagedChange: Bool
    let isUntracked: Bool
    let isRename: Bool

    init(
        path: String,
        previousPath: String? = nil,
        hasStagedChange: Bool,
        hasUnstagedChange: Bool,
        isUntracked: Bool,
        isRename: Bool = false
    ) {
        self.path = path
        self.previousPath = previousPath
        self.hasStagedChange = hasStagedChange
        self.hasUnstagedChange = hasUnstagedChange
        self.isUntracked = isUntracked
        self.isRename = isRename
    }
}

struct GitWorkingTreeStatus: Sendable, Equatable {
    let summary: GitWorkingTreeSummary
    let branch: String?
    let originResolution: GitOriginResolution
    /// Per-file entries consistent with `summary`. When a status is constructed
    /// from a summary alone, canonical placeholder entries are synthesized so the
    /// projector's scoped fold can reconstruct the same counts.
    let entries: [GitWorkingTreeStatusEntry]

    init(
        summary: GitWorkingTreeSummary,
        branch: String?,
        originResolution: GitOriginResolution,
        entries: [GitWorkingTreeStatusEntry]
    ) {
        self.summary = summary
        self.branch = branch
        self.originResolution = originResolution
        self.entries = entries
    }

    init(
        summary: GitWorkingTreeSummary,
        branch: String?,
        originResolution: GitOriginResolution
    ) {
        self.init(
            summary: summary,
            branch: branch,
            originResolution: originResolution,
            entries: Self.canonicalEntries(for: summary)
        )
    }

    init(
        summary: GitWorkingTreeSummary,
        branch: String?,
        origin: String?
    ) {
        self.init(
            summary: summary,
            branch: branch,
            originResolution: origin.map(GitOriginResolution.resolved) ?? .confirmedAbsent,
            entries: Self.canonicalEntries(for: summary)
        )
    }

    var origin: String? {
        switch originResolution {
        case .resolved(let origin):
            origin
        case .awaitingResolution, .confirmedAbsent:
            nil
        }
    }

    /// Recomputes the three emitted file counts from an entry set, mirroring the
    /// SDK summary mapping (changed==unstaged file count, staged, untracked).
    static func fileCounts(
        for entries: [GitWorkingTreeStatusEntry]
    ) -> (changed: Int, staged: Int, untracked: Int) {
        var changed = 0
        var staged = 0
        var untracked = 0
        for entry in entries {
            if entry.hasUnstagedChange { changed += 1 }
            if entry.hasStagedChange { staged += 1 }
            if entry.isUntracked { untracked += 1 }
        }
        return (changed, staged, untracked)
    }

    /// Synthesizes a canonical, count-faithful entry set from a summary. Paths use
    /// a control-character prefix so they never collide with real repo paths or
    /// pathspecs, keeping the fold safe for summary-only (test/parity) providers.
    private static func canonicalEntries(
        for summary: GitWorkingTreeSummary
    ) -> [GitWorkingTreeStatusEntry] {
        var entries: [GitWorkingTreeStatusEntry] = []
        for index in 0..<max(0, summary.staged) {
            entries.append(
                GitWorkingTreeStatusEntry(
                    path: "\u{1}synthetic/staged/\(index)",
                    hasStagedChange: true,
                    hasUnstagedChange: false,
                    isUntracked: false
                )
            )
        }
        for index in 0..<max(0, summary.changed) {
            entries.append(
                GitWorkingTreeStatusEntry(
                    path: "\u{1}synthetic/changed/\(index)",
                    hasStagedChange: false,
                    hasUnstagedChange: true,
                    isUntracked: false
                )
            )
        }
        for index in 0..<max(0, summary.untracked) {
            entries.append(
                GitWorkingTreeStatusEntry(
                    path: "\u{1}synthetic/untracked/\(index)",
                    hasStagedChange: false,
                    hasUnstagedChange: false,
                    isUntracked: true
                )
            )
        }
        return entries
    }
}

enum GitWorkingTreeStatusUnavailableReason: String, Sendable, Equatable {
    case providerReturnedNil = "provider_returned_nil"
    case timeout
    case readAlreadyInFlight = "read_already_in_flight"
    case readCapacityExceeded = "read_capacity_exceeded"
    case cancelled
    case sdkError = "sdk_error"
}

struct GitWorkingTreeStatusUnavailable: Sendable, Equatable {
    let reason: GitWorkingTreeStatusUnavailableReason
}

enum GitWorkingTreeStatusResult: Sendable, Equatable {
    case available(GitWorkingTreeStatus)
    case unavailable(GitWorkingTreeStatusUnavailable)
}

protocol GitWorkingTreeStatusProvider: Sendable {
    /// Reads working-tree status. A non-`nil` `pathspecs` scopes the entry walk to
    /// just those repo-relative paths (see `GitStatusOptions.pathspecs`); line,
    /// branch, and sync facts remain full-worktree. `nil` is a full status.
    func statusResult(for rootPath: URL, pathspecs: [String]?) async -> GitWorkingTreeStatusResult
}

extension GitWorkingTreeStatusProvider {
    func statusResult(for rootPath: URL) async -> GitWorkingTreeStatusResult {
        await statusResult(for: rootPath, pathspecs: nil)
    }

    func status(for rootPath: URL, pathspecs: [String]? = nil) async -> GitWorkingTreeStatus? {
        switch await statusResult(for: rootPath, pathspecs: pathspecs) {
        case .available(let status):
            status
        case .unavailable:
            nil
        }
    }
}
