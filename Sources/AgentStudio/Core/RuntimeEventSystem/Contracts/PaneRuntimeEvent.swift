import AppKit
import Foundation

/// Discriminated union for all pane-scoped runtime-plane events carried on `RuntimeEnvelope.pane`.
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
    case paneFilesystemContext(PaneFilesystemContextEvent)
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
        case .paneFilesystemContext(let event): return event.actionPolicy
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
    let linesAdded: Int
    let linesDeleted: Int
    let aheadCount: Int?
    let behindCount: Int?
    let hasUpstream: Bool?

    init(
        changed: Int,
        staged: Int,
        untracked: Int,
        linesAdded: Int = 0,
        linesDeleted: Int = 0,
        aheadCount: Int? = nil,
        behindCount: Int? = nil,
        hasUpstream: Bool? = nil
    ) {
        self.changed = changed
        self.staged = staged
        self.untracked = untracked
        self.linesAdded = linesAdded
        self.linesDeleted = linesDeleted
        self.aheadCount = aheadCount
        self.behindCount = behindCount
        self.hasUpstream = hasUpstream
    }
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

struct ProgressState: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case set
        case error
        case indeterminate
        case paused
    }

    let kind: Kind
    let percent: UInt8?
}

struct TerminalSizeConstraints: Sendable, Equatable {
    let minWidth: UInt32
    let minHeight: UInt32
    let maxWidth: UInt32
    let maxHeight: UInt32
}

struct GhosttyInputTrigger: Sendable, Equatable {
    enum TriggerTag: Sendable, Equatable {
        case physical
        case unicode
        case catchAll
    }

    let tag: TriggerTag
    let key: UInt32?
    let modifiers: UInt32
}

enum GhosttyKeyTableChange: Sendable, Equatable {
    case activate(name: String)
    case deactivate
    case deactivateAll
}

enum TerminalColorKind: Sendable, Equatable {
    case foreground
    case background
    case cursor
    case palette(index: UInt8)
}

struct TerminalColorChange: Sendable, Equatable {
    let kind: TerminalColorKind
    let red: UInt8
    let green: UInt8
    let blue: UInt8
}

enum TitlePromptScope: Sendable, Equatable {
    case surface
    case tab
}

enum OpenURLKind: Sendable, Equatable {
    case unknown
    case text
    case html
}

enum SecureInputMode: Sendable, Equatable {
    case on
    case off
    case toggle
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
    case tabTitleChanged(String)
    case cwdChanged(String)
    case commandFinished(exitCode: Int, duration: UInt64)
    case progressReportUpdated(ProgressState?)
    case readOnlyChanged(Bool)
    case secureInputRequested(SecureInputMode)
    case secureInputChanged(Bool)
    case rendererHealthChanged(healthy: Bool)
    case cellSizeChanged(NSSize)
    case initialSizeChanged(NSSize)
    case sizeLimitChanged(TerminalSizeConstraints)
    case mouseShapeChanged(shapeRawValue: UInt32)
    case mouseVisibilityChanged(isVisible: Bool)
    case mouseLinkHovered(url: String?)
    case keySequenceChanged(active: Bool, trigger: GhosttyInputTrigger?)
    case keyTableChanged(GhosttyKeyTableChange)
    case colorChanged(TerminalColorChange)
    case configReloadRequested(soft: Bool)
    case configChanged
    case searchStarted(query: String?)
    case searchEnded
    case searchMatchesUpdated(totalMatches: Int?)
    case searchSelectionChanged(selectedMatchIndex: Int?)
    case promptTitleRequested(scope: TitlePromptScope)
    case desktopNotificationRequested(title: String, body: String)
    case openURLRequested(url: String, kind: OpenURLKind)
    case undoRequested
    case redoRequested
    case copyTitleToClipboardRequested
    case bellRang
    case scrollbarChanged(ScrollbarState)
    case deferred(tag: UInt32)
    case unhandled(tag: UInt32)

    var actionPolicy: ActionPolicy {
        switch self {
        case .progressReportUpdated:
            return .lossy(consolidationKey: "progress")
        case .cellSizeChanged:
            return .lossy(consolidationKey: "cellSize")
        case .mouseShapeChanged:
            return .lossy(consolidationKey: "mouseShape")
        case .mouseVisibilityChanged:
            return .lossy(consolidationKey: "mouseVisibility")
        case .mouseLinkHovered:
            return .lossy(consolidationKey: "mouseLink")
        case .keySequenceChanged:
            return .lossy(consolidationKey: "keySequence")
        case .keyTableChanged:
            return .lossy(consolidationKey: "keyTable")
        case .searchMatchesUpdated:
            return .lossy(consolidationKey: "searchTotal")
        case .searchSelectionChanged:
            return .lossy(consolidationKey: "searchSelected")
        case .scrollbarChanged:
            return .lossy(consolidationKey: "scroll")
        case .deferred:
            return .lossy(consolidationKey: "deferred")
        case .newTab, .closeTab, .gotoTab, .moveTab, .newSplit, .gotoSplit, .resizeSplit, .equalizeSplits,
            .toggleSplitZoom, .titleChanged, .tabTitleChanged, .cwdChanged, .commandFinished,
            .readOnlyChanged, .secureInputRequested, .secureInputChanged, .rendererHealthChanged,
            .initialSizeChanged, .sizeLimitChanged, .colorChanged, .configReloadRequested, .configChanged,
            .searchStarted, .searchEnded, .promptTitleRequested,
            .desktopNotificationRequested, .openURLRequested, .undoRequested, .redoRequested,
            .copyTitleToClipboardRequested, .bellRang, .unhandled:
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
        case .tabTitleChanged: return .tabTitleChanged
        case .cwdChanged: return .cwdChanged
        case .commandFinished: return .commandFinished
        case .progressReportUpdated: return .progressReportUpdated
        case .readOnlyChanged: return .readOnlyChanged
        case .secureInputRequested, .secureInputChanged: return .secureInputChanged
        case .rendererHealthChanged: return .rendererHealthChanged
        case .cellSizeChanged: return .cellSizeChanged
        case .initialSizeChanged: return .initialSizeChanged
        case .sizeLimitChanged: return .sizeLimitChanged
        case .mouseShapeChanged: return .mouseShapeChanged
        case .mouseVisibilityChanged: return .mouseVisibilityChanged
        case .mouseLinkHovered: return .mouseLinkHovered
        case .keySequenceChanged: return .keySequenceChanged
        case .keyTableChanged: return .keyTableChanged
        case .colorChanged: return .colorChanged
        case .configReloadRequested: return .configReloadRequested
        case .configChanged: return .configChanged
        case .searchStarted: return .searchStarted
        case .searchEnded: return .searchEnded
        case .searchMatchesUpdated: return .searchMatchesUpdated
        case .searchSelectionChanged: return .searchSelectionChanged
        case .promptTitleRequested: return .promptTitleRequested
        case .desktopNotificationRequested: return .desktopNotificationRequested
        case .openURLRequested: return .openURLRequested
        case .undoRequested: return .undoRequested
        case .redoRequested: return .redoRequested
        case .copyTitleToClipboardRequested: return .copyTitleToClipboardRequested
        case .bellRang: return .bellRang
        case .scrollbarChanged: return .scrollbarChanged
        case .deferred: return .deferred
        case .unhandled: return .unhandled
        }
    }
}

struct ScrollbarState: Sendable, Equatable {
    let top: Int
    let bottom: Int
    let total: Int
}

struct TerminalSearchState: Sendable, Equatable {
    var query: String
    var totalMatches: Int?
    var selectedMatchIndex: Int?
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
