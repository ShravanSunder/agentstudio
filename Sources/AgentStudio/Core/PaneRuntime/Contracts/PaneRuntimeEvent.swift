import Foundation

/// Discriminated union for all runtime-plane events carried on `PaneEventEnvelope`.
///
/// Each case defines its own domain payload and participates in self-classifying
/// `actionPolicy` routing through `NotificationReducer`.
enum PaneRuntimeEvent: Sendable {
    case lifecycle(PaneLifecycleEvent)
    case terminal(GhosttyEvent)
    case browser(BrowserEvent)
    case diff(DiffEvent)
    case editor(EditorEvent)
    case plugin(kind: PaneContentType, event: any PaneKindEvent & Sendable)
    case filesystem(FilesystemEvent)
    case artifact(ArtifactEvent)
    case security(SecurityEvent)
    case error(RuntimeErrorEvent)
}

extension PaneRuntimeEvent {
    /// Envelope scheduling policy derived from the concrete event payload.
    var actionPolicy: ActionPolicy {
        switch self {
        case .terminal(let event): return event.actionPolicy
        case .browser(let event): return event.actionPolicy
        case .diff(let event): return event.actionPolicy
        case .editor(let event): return event.actionPolicy
        case .plugin(_, let event): return event.actionPolicy
        case .lifecycle, .filesystem, .artifact, .security, .error:
            return .critical
        }
    }
}

enum PaneLifecycleEvent: Sendable {
    case surfaceCreated
    case sizeObserved(cols: Int, rows: Int)
    case sizeStabilized
    case attachStarted
    case attachSucceeded
    case attachFailed(error: AttachError)
    case paneClosed
    case activePaneChanged
    case drawerExpanded
    case drawerCollapsed
    case tabSwitched(activeTabId: UUID)
}

enum AttachError: Error, Sendable, Equatable {
    case surfaceNotFound
    case surfaceAlreadyAttached
    case backendUnavailable(reason: String)
    case timeout
}

enum FilesystemEvent: Sendable {
    case worktreeRegistered(worktreeId: UUID, repoId: UUID, rootPath: URL)
    case worktreeUnregistered(worktreeId: UUID, repoId: UUID)
    case filesChanged(changeset: FileChangeset)
    case gitSnapshotChanged(snapshot: GitWorkingTreeSnapshot)
    case diffAvailable(diffId: UUID, worktreeId: UUID, repoId: UUID)
    case branchChanged(worktreeId: UUID, repoId: UUID, from: String, to: String)
}

/// Compatibility namespace mapping used during staged migration from
/// `PaneEventEnvelope` to scoped `RuntimeEnvelope` event routing.
enum FilesystemCompatibilityScope: Sendable, Equatable {
    case systemTopology
    case worktreeFilesystem
    case worktreeGitWorkingDirectory
}

extension FilesystemCompatibilityScope: CustomStringConvertible {
    var description: String {
        switch self {
        case .systemTopology: return "system.topology"
        case .worktreeFilesystem: return "worktree.filesystem"
        case .worktreeGitWorkingDirectory: return "worktree.gitWorkingDirectory"
        }
    }
}

extension FilesystemEvent {
    /// Returns the scoped RuntimeEnvelope namespace this legacy event will target.
    var compatibilityScope: FilesystemCompatibilityScope {
        switch self {
        case .worktreeRegistered, .worktreeUnregistered:
            return .systemTopology
        case .filesChanged:
            return .worktreeFilesystem
        case .gitSnapshotChanged, .diffAvailable, .branchChanged:
            return .worktreeGitWorkingDirectory
        }
    }

    /// Returns a compatibility worktree-scoped event when old/new payloads are shape-compatible.
    var compatibilityWorktreeScopedEvent: WorktreeScopedEvent? {
        switch self {
        case .filesChanged(let changeset):
            return .filesystem(.filesChanged(changeset: changeset))
        case .gitSnapshotChanged(let snapshot):
            return .gitWorkingDirectory(.snapshotChanged(snapshot: snapshot))
        case .diffAvailable(let diffId, let worktreeId, let repoId):
            return .gitWorkingDirectory(
                .diffAvailable(diffId: diffId, worktreeId: worktreeId, repoId: repoId)
            )
        case .branchChanged(let worktreeId, let repoId, let from, let to):
            return .gitWorkingDirectory(
                .branchChanged(worktreeId: worktreeId, repoId: repoId, from: from, to: to)
            )
        case .worktreeRegistered, .worktreeUnregistered:
            return nil
        }
    }

    /// Returns a compatibility topology event for legacy register/unregister facts.
    ///
    /// `worktreeUnregistered` does not carry path context in the legacy payload;
    /// callers may pass `unregisterRootPath` from retained registration state.
    func compatibilityTopologyEvent(unregisterRootPath: URL? = nil) -> TopologyEvent? {
        switch self {
        case .worktreeRegistered(_, _, let rootPath):
            return .repoDiscovered(
                repoPath: rootPath,
                parentPath: rootPath.deletingLastPathComponent()
            )
        case .worktreeUnregistered:
            guard let unregisterRootPath else { return nil }
            return .repoRemoved(repoPath: unregisterRootPath)
        case .filesChanged, .gitSnapshotChanged, .diffAvailable, .branchChanged:
            return nil
        }
    }
}

struct FileChangeset: Sendable {
    let worktreeId: WorktreeId
    let repoId: UUID
    let rootPath: URL
    let paths: [String]
    let containsGitInternalChanges: Bool
    let suppressedIgnoredPathCount: Int
    let suppressedGitInternalPathCount: Int
    let timestamp: ContinuousClock.Instant
    let batchSeq: UInt64

    init(
        worktreeId: WorktreeId,
        repoId: UUID? = nil,
        rootPath: URL,
        paths: [String],
        containsGitInternalChanges: Bool = false,
        suppressedIgnoredPathCount: Int = 0,
        suppressedGitInternalPathCount: Int = 0,
        timestamp: ContinuousClock.Instant,
        batchSeq: UInt64
    ) {
        self.worktreeId = worktreeId
        self.repoId = repoId ?? worktreeId
        self.rootPath = rootPath
        self.paths = paths
        self.containsGitInternalChanges = containsGitInternalChanges
        self.suppressedIgnoredPathCount = suppressedIgnoredPathCount
        self.suppressedGitInternalPathCount = suppressedGitInternalPathCount
        self.timestamp = timestamp
        self.batchSeq = batchSeq
    }
}

struct GitWorkingTreeSummary: Sendable, Equatable {
    let changed: Int
    let staged: Int
    let untracked: Int
}

struct GitWorkingTreeSnapshot: Sendable, Equatable {
    let worktreeId: UUID
    let repoId: UUID
    let rootPath: URL
    let summary: GitWorkingTreeSummary
    let branch: String?

    init(
        worktreeId: UUID,
        repoId: UUID? = nil,
        rootPath: URL,
        summary: GitWorkingTreeSummary,
        branch: String?
    ) {
        self.worktreeId = worktreeId
        self.repoId = repoId ?? worktreeId
        self.rootPath = rootPath
        self.summary = summary
        self.branch = branch
    }
}

enum ArtifactEvent: Sendable {
    case diffProduced(worktreeId: UUID, artifact: DiffArtifact)
    case approvalRequested(request: ApprovalRequest)
    case approvalDecided(decision: ApprovalDecision)
}

struct DiffArtifact: Sendable {
    let diffId: UUID
    let worktreeId: UUID
    let patchData: Data
}

struct ApprovalRequest: Sendable {
    let id: UUID
    let summary: String
}

struct ApprovalDecision: Sendable {
    let requestId: UUID
    let approved: Bool
}

enum SecurityEvent: Sendable {
    case networkEgressBlocked(destination: String, rule: String)
    case filesystemAccessDenied(path: String, operation: String)
    case secretAccessed(secretId: String, consumerId: String)
    case processSpawnBlocked(command: String, rule: String)
    case sandboxStarted(backend: ExecutionBackend, policy: String)
    case sandboxStopped(reason: String)
    case sandboxHealthChanged(healthy: Bool)
}

enum ExecutionBackend: Sendable, Equatable, Hashable, Codable {
    case local
    case docker(image: String)
    case gondolin(policyId: String)
    case remote(host: String)
}

enum RuntimeErrorEvent: Error, Sendable {
    case surfaceCrashed(reason: String)
    case commandTimeout(commandId: UUID)
    case commandDispatchFailed(command: String, underlyingDescription: String)
    case adapterError(String)
    case resourceExhausted(resource: String)
    case internalStateCorrupted
}

// Ghostty payload enums are colocated with GhosttyEvent because they are associated
// value types of a core runtime contract. Moving them under Features/Terminal would
// introduce a Core -> Features import.
enum GhosttyCloseTabMode: Sendable, Equatable {
    case thisTab
    case otherTabs
    case rightTabs
}

enum GhosttyGotoTabTarget: Sendable, Equatable {
    case previous
    case next
    case last
    case index(Int)
}

enum GhosttySplitDirection: Sendable, Equatable {
    case left
    case right
    case up
    case down
}

enum GhosttyGotoSplitDirection: Sendable, Equatable {
    case previous
    case next
    case left
    case right
    case up
    case down
}

enum GhosttyResizeSplitDirection: Sendable, Equatable {
    case left
    case right
    case up
    case down
}

enum GhosttyEvent: PaneKindEvent, Sendable, Equatable {
    case newTab
    case closeTab(mode: GhosttyCloseTabMode)
    case gotoTab(target: GhosttyGotoTabTarget)
    case moveTab(amount: Int)
    case newSplit(direction: GhosttySplitDirection)
    case gotoSplit(direction: GhosttyGotoSplitDirection)
    case resizeSplit(amount: UInt16, direction: GhosttyResizeSplitDirection)
    case equalizeSplits
    case toggleSplitZoom
    case titleChanged(String)
    case cwdChanged(String)
    case commandFinished(exitCode: Int, duration: UInt64)
    case bellRang
    case scrollbarChanged(ScrollbarState)
    case unhandled(tag: UInt32)

    var actionPolicy: ActionPolicy {
        switch self {
        case .scrollbarChanged:
            return .lossy(consolidationKey: "scroll")
        case .newTab, .closeTab, .gotoTab, .moveTab, .newSplit, .gotoSplit, .resizeSplit, .equalizeSplits,
            .toggleSplitZoom, .titleChanged, .cwdChanged, .commandFinished, .bellRang, .unhandled:
            return .critical
        }
    }

    var eventName: EventIdentifier {
        switch self {
        case .newTab: return .newTab
        case .closeTab: return .closeTab
        case .gotoTab: return .gotoTab
        case .moveTab: return .moveTab
        case .newSplit: return .newSplit
        case .gotoSplit: return .gotoSplit
        case .resizeSplit: return .resizeSplit
        case .equalizeSplits: return .equalizeSplits
        case .toggleSplitZoom: return .toggleSplitZoom
        case .titleChanged: return .titleChanged
        case .cwdChanged: return .cwdChanged
        case .commandFinished: return .commandFinished
        case .bellRang: return .bellRang
        case .scrollbarChanged: return .scrollbarChanged
        case .unhandled: return .unhandled
        }
    }
}

struct ScrollbarState: Sendable, Equatable {
    let top: Int
    let bottom: Int
    let total: Int
}

enum BrowserEvent: PaneKindEvent, Sendable {
    case navigationCompleted(url: URL, statusCode: Int?)
    case pageLoaded(url: URL)
    case consoleMessage(level: ConsoleLevel, message: String)

    var actionPolicy: ActionPolicy {
        switch self {
        case .consoleMessage:
            return .lossy(consolidationKey: "console")
        case .navigationCompleted, .pageLoaded:
            return .critical
        }
    }

    var eventName: EventIdentifier {
        switch self {
        case .navigationCompleted: return .navigationCompleted
        case .pageLoaded: return .pageLoaded
        case .consoleMessage: return .consoleMessage
        }
    }
}

enum ConsoleLevel: String, Sendable {
    case log
    case warn
    case error
    case debug
    case info
}

enum DiffEvent: PaneKindEvent, Sendable {
    case diffLoaded(stats: DiffStats)
    case hunkApproved(hunkId: String)
    case allApproved

    var actionPolicy: ActionPolicy {
        switch self {
        case .diffLoaded:
            return .critical
        case .hunkApproved, .allApproved:
            return .critical
        }
    }

    var eventName: EventIdentifier {
        switch self {
        case .diffLoaded: return .diffLoaded
        case .hunkApproved: return .hunkApproved
        case .allApproved: return .allApproved
        }
    }
}

struct DiffStats: Sendable, Equatable {
    let filesChanged: Int
    let insertions: Int
    let deletions: Int
}

enum EditorEvent: PaneKindEvent, Sendable {
    case contentSaved(path: String)
    case fileOpened(path: String, language: String?)
    case diagnosticsUpdated(path: String, errors: Int, warnings: Int)

    var actionPolicy: ActionPolicy {
        switch self {
        case .contentSaved, .fileOpened:
            return .critical
        case .diagnosticsUpdated:
            return .lossy(consolidationKey: "diagnostics")
        }
    }

    var eventName: EventIdentifier {
        switch self {
        case .contentSaved: return .contentSaved
        case .fileOpened: return .fileOpened
        case .diagnosticsUpdated: return .diagnosticsUpdated
        }
    }
}
