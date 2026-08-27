import Foundation

package enum GitOriginResolution: Sendable, Equatable {
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
package struct GitWorkingTreeStatusEntry: Sendable, Equatable {
    package let path: String
    package let previousPath: String?
    package let hasStagedChange: Bool
    package let hasUnstagedChange: Bool
    package let isUntracked: Bool
    package let isRename: Bool

    package init(
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

package struct GitWorkingTreeStatus: Sendable, Equatable {
    package let summary: GitWorkingTreeSummary
    package let branch: String?
    package let originResolution: GitOriginResolution
    /// True only for a pathspec-scoped read containing a standalone add,
    /// delete, or untracked entry that may be one visible half of a rename.
    package let containsPathIdentityAmbiguity: Bool
    /// Per-file entries consistent with `summary`. When a status is constructed
    /// from a summary alone, canonical placeholder entries are synthesized so the
    /// projector's scoped fold can reconstruct the same counts.
    package let entries: [GitWorkingTreeStatusEntry]

    package init(
        summary: GitWorkingTreeSummary,
        branch: String?,
        originResolution: GitOriginResolution,
        entries: [GitWorkingTreeStatusEntry],
        containsPathIdentityAmbiguity: Bool = false
    ) {
        self.summary = summary
        self.branch = branch
        self.originResolution = originResolution
        self.entries = entries
        self.containsPathIdentityAmbiguity = containsPathIdentityAmbiguity
    }

    package init(
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

    package init(
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

    package var origin: String? {
        switch originResolution {
        case .resolved(let origin):
            origin
        case .awaitingResolution, .confirmedAbsent:
            nil
        }
    }

    /// Recomputes the three emitted file counts from an entry set, mirroring the
    /// SDK summary mapping (changed==unstaged file count, staged, untracked).
    package static func fileCounts(
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

package struct GitWorkingTreeStatusFacts: Sendable, Equatable {
    package let changed: Int
    package let staged: Int
    package let untracked: Int
    package let aheadCount: Int?
    package let behindCount: Int?
    package let hasUpstream: Bool?
    package let branch: String?
    package let originResolution: GitOriginResolution
    package let entries: [GitWorkingTreeStatusEntry]
    package let containsPathIdentityAmbiguity: Bool
    package let exactCleanAuthority: GitCleanContinuityAuthority?

    package init(
        status: GitWorkingTreeStatus,
        exactCleanAuthority: GitCleanContinuityAuthority? = nil
    ) {
        changed = status.summary.changed
        staged = status.summary.staged
        untracked = status.summary.untracked
        aheadCount = status.summary.aheadCount
        behindCount = status.summary.behindCount
        hasUpstream = status.summary.hasUpstream
        branch = status.branch
        originResolution = status.originResolution
        entries = status.entries
        containsPathIdentityAmbiguity = status.containsPathIdentityAmbiguity
        self.exactCleanAuthority = exactCleanAuthority
    }

    package func composing(_ detail: GitWorkingTreeLineDetail) -> GitWorkingTreeStatus {
        GitWorkingTreeStatus(
            summary: GitWorkingTreeSummary(
                changed: changed,
                staged: staged,
                untracked: untracked,
                linesAdded: detail.linesAdded,
                linesDeleted: detail.linesDeleted,
                aheadCount: aheadCount,
                behindCount: behindCount,
                hasUpstream: hasUpstream
            ),
            branch: branch,
            originResolution: originResolution,
            entries: entries,
            containsPathIdentityAmbiguity: containsPathIdentityAmbiguity
        )
    }

    package static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.changed == rhs.changed
            && lhs.staged == rhs.staged
            && lhs.untracked == rhs.untracked
            && lhs.aheadCount == rhs.aheadCount
            && lhs.behindCount == rhs.behindCount
            && lhs.hasUpstream == rhs.hasUpstream
            && lhs.branch == rhs.branch
            && lhs.originResolution == rhs.originResolution
            && lhs.entries == rhs.entries
            && lhs.containsPathIdentityAmbiguity == rhs.containsPathIdentityAmbiguity
    }
}

package struct GitWorkingTreeLineDetail: Sendable, Equatable {
    package let linesAdded: Int
    package let linesDeleted: Int

    package init(linesAdded: Int, linesDeleted: Int) {
        self.linesAdded = linesAdded
        self.linesDeleted = linesDeleted
    }

    package init(status: GitWorkingTreeStatus) {
        self.init(linesAdded: status.summary.linesAdded, linesDeleted: status.summary.linesDeleted)
    }
}

package enum GitWorkingTreeStatusUnavailableReason: String, Sendable, Equatable {
    case providerReturnedNil = "provider_returned_nil"
    case timeout
    case readAlreadyInFlight = "read_already_in_flight"
    case readCapacityExceeded = "read_capacity_exceeded"
    case cancelled
    case sdkError = "sdk_error"
}

package struct GitWorkingTreeStatusUnavailable: Sendable, Equatable {
    package let reason: GitWorkingTreeStatusUnavailableReason

    package init(reason: GitWorkingTreeStatusUnavailableReason) {
        self.reason = reason
    }
}

package enum GitWorkingTreeStatusResult: Sendable, Equatable {
    case available(GitWorkingTreeStatus)
    case unavailable(GitWorkingTreeStatusUnavailable)
}

package enum GitWorkingTreeStatusFactsResult: Sendable, Equatable {
    case available(GitWorkingTreeStatusFacts)
    case unavailable(GitWorkingTreeStatusUnavailable)
}

extension GitWorkingTreeStatusFactsResult {
    package var statusResult: GitWorkingTreeStatusResult {
        switch self {
        case .available:
            preconditionFailure("Available facts require line detail before status composition")
        case .unavailable(let unavailable):
            .unavailable(unavailable)
        }
    }
}

package enum GitWorkingTreeLineDetailResult: Sendable, Equatable {
    case available(GitWorkingTreeLineDetail)
    case unavailable(GitWorkingTreeStatusUnavailable)
}

package enum GitExactCleanRenewalResult: Sendable, Equatable {
    case renewed(GitCleanContinuityAuthority)
    case requiresExact(GitCleanContinuityFailureReason)
}

package enum GitExactCleanStatusFactsResult: Sendable, Equatable {
    case available(GitWorkingTreeStatusFacts)
    case requiresExact(GitCleanContinuityFailureReason)
    case unavailable(GitWorkingTreeStatusUnavailable)
}

package protocol GitWorkingTreeStatusProvider: Sendable {
    /// Reads working-tree status. A non-`nil` `pathspecs` scopes the entry walk to
    /// just those repo-relative paths (see `GitStatusOptions.pathspecs`); line,
    /// branch, and sync facts remain full-worktree. `nil` is a full status.
    func statusResult(for rootPath: URL, pathspecs: [String]?) async -> GitWorkingTreeStatusResult
    func statusFactsResult(for rootPath: URL, pathspecs: [String]?) async -> GitWorkingTreeStatusFactsResult
    func lineDetailResult(for rootPath: URL) async -> GitWorkingTreeLineDetailResult
    func physicalCompletionGeneration() -> UInt64?
    func waitForPhysicalCompletion(after generation: UInt64) async
}

package protocol GitExactCleanStatusProviding: GitWorkingTreeStatusProvider {
    func exactCleanStatusFactsResult(
        for worktreeId: UUID,
        rootPath: URL
    ) async -> GitExactCleanStatusFactsResult
    func renewExactCleanAuthority(
        _ authority: GitCleanContinuityAuthority
    ) async -> GitExactCleanRenewalResult
    func retireExactCleanAuthority(worktreeId: UUID, rootPath: URL)
}

extension GitWorkingTreeStatusProvider {
    package func physicalCompletionGeneration() -> UInt64? {
        nil
    }

    package func waitForPhysicalCompletion(after _: UInt64) async {}

    package func statusFactsResult(
        for rootPath: URL,
        pathspecs: [String]?
    ) async -> GitWorkingTreeStatusFactsResult {
        switch await statusResult(for: rootPath, pathspecs: pathspecs) {
        case .available(let status): .available(GitWorkingTreeStatusFacts(status: status))
        case .unavailable(let unavailable): .unavailable(unavailable)
        }
    }

    package func lineDetailResult(for rootPath: URL) async -> GitWorkingTreeLineDetailResult {
        switch await statusResult(for: rootPath, pathspecs: nil) {
        case .available(let status): .available(GitWorkingTreeLineDetail(status: status))
        case .unavailable(let unavailable): .unavailable(unavailable)
        }
    }

    package func statusResult(for rootPath: URL) async -> GitWorkingTreeStatusResult {
        await statusResult(for: rootPath, pathspecs: nil)
    }

    package func status(for rootPath: URL, pathspecs: [String]? = nil) async -> GitWorkingTreeStatus? {
        switch await statusResult(for: rootPath, pathspecs: pathspecs) {
        case .available(let status):
            status
        case .unavailable:
            nil
        }
    }
}
