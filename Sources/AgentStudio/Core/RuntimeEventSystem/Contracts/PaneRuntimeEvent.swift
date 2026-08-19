import AppKit
import Foundation

/// Discriminated union for all pane-scoped runtime-plane events carried on `RuntimeEnvelope.pane`.
///
/// Each case defines its own domain payload and participates in self-classifying
/// `actionPolicy` routing through `NotificationReducer`.
package enum PaneRuntimeEvent: Sendable {
    case lifecycle(PaneLifecycleEvent)
    case terminal(GhosttyEvent)
    case terminalActivity(TerminalActivityEvent)
    case browser(BrowserEvent)
    case diff(DiffEvent)
    case editor(EditorEvent)
    case agentNotificationRequested(title: String, body: String?)
    case plugin(kind: PaneContentType, event: any PaneKindEvent & Sendable)
    case paneFilesystemContext(PaneFilesystemContextEvent)
    case filesystem(FilesystemEvent)
    case artifact(ArtifactEvent)
    case security(SecurityEvent)
    case error(RuntimeErrorEvent)
}

extension PaneRuntimeEvent {
    /// Envelope scheduling policy derived from the concrete event payload.
    package var actionPolicy: ActionPolicy {
        switch self {
        case .terminal(let event): return event.actionPolicy
        case .terminalActivity(let event): return event.actionPolicy
        case .browser(let event): return event.actionPolicy
        case .diff(let event): return event.actionPolicy
        case .editor(let event): return event.actionPolicy
        case .agentNotificationRequested:
            return .critical
        case .plugin(_, let event): return event.actionPolicy
        case .paneFilesystemContext(let event): return event.actionPolicy
        case .lifecycle, .filesystem, .artifact, .security, .error:
            return .critical
        }
    }
}

package struct TerminalSettledActivity: Sendable, Equatable {
    package let burstWindowId: UUID
    package let thresholdRows: Int
    package let debounceMilliseconds: Int
    package let startedAtMilliseconds: Int64
    package let settledAtMilliseconds: Int64
    package let eventCount: Int
    package let rowsAdded: Int
    package let baselineRows: Int
    package let latestRows: Int
    package let isPinnedToBottom: Bool
    /// The last non-empty, contracted line of terminal output observed at
    /// settle time, bounded and prompt-filtered at the Terminal source
    /// boundary (see `TerminalLastOutputLineContract`). Nil when no
    /// printable output was found or the line is unchanged from the pane's
    /// previous settle.
    package let lastOutputLine: String?

    package init(
        burstWindowId: UUID,
        thresholdRows: Int,
        debounceMilliseconds: Int,
        startedAtMilliseconds: Int64,
        settledAtMilliseconds: Int64,
        eventCount: Int,
        rowsAdded: Int,
        baselineRows: Int,
        latestRows: Int,
        isPinnedToBottom: Bool,
        lastOutputLine: String? = nil
    ) {
        self.burstWindowId = burstWindowId
        self.thresholdRows = thresholdRows
        self.debounceMilliseconds = debounceMilliseconds
        self.startedAtMilliseconds = startedAtMilliseconds
        self.settledAtMilliseconds = settledAtMilliseconds
        self.eventCount = eventCount
        self.rowsAdded = rowsAdded
        self.baselineRows = baselineRows
        self.latestRows = latestRows
        self.isPinnedToBottom = isPinnedToBottom
        self.lastOutputLine = lastOutputLine
    }
}

package struct TerminalPaneObservationState: Sendable, Equatable {
    package let isPinnedToBottom: Bool

    package init(isPinnedToBottom: Bool) {
        self.isPinnedToBottom = isPinnedToBottom
    }
}

package enum TerminalActivityEvent: Sendable, Equatable {
    case paneObservationChanged(TerminalPaneObservationState)
    case unseenActivitySettled(TerminalSettledActivity)
    case agentSettledActivityPromoted(TerminalSettledActivity)
    case agentSettledActivityRevoked

    var actionPolicy: ActionPolicy {
        .critical
    }
}

package enum PaneLifecycleEvent: Sendable {
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

package enum AttachError: Error, Sendable, Equatable {
    case surfaceNotFound
    case surfaceAlreadyAttached
    case backendUnavailable(reason: String)
    case timeout
}

package enum FilesystemEvent: Sendable {
    case worktreeRegistered(worktreeId: UUID, repoId: UUID, rootPath: URL)
    case worktreeUnregistered(worktreeId: UUID, repoId: UUID)
    case filesChanged(changeset: FileChangeset)
    case gitSnapshotChanged(snapshot: GitWorkingTreeSnapshot)
    case diffAvailable(diffId: UUID, worktreeId: UUID, repoId: UUID)
    case branchChanged(worktreeId: UUID, repoId: UUID, from: String, to: String)
}

package struct FileChangeset: Sendable {
    package let worktreeId: WorktreeId
    package let repoId: UUID
    package let rootPath: URL
    package let paths: [String]
    package let containsGitInternalChanges: Bool
    package let suppressedIgnoredPathCount: Int
    package let suppressedGitInternalPathCount: Int
    package let timestamp: ContinuousClock.Instant
    package let batchSeq: UInt64

    package init(
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

package struct GitWorkingTreeSummary: Sendable, Equatable {
    package let changed: Int
    package let staged: Int
    package let untracked: Int
    package let linesAdded: Int
    package let linesDeleted: Int
    package let aheadCount: Int?
    package let behindCount: Int?
    package let hasUpstream: Bool?

    package init(
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

package struct GitWorkingTreeSnapshot: Sendable, Equatable {
    package let worktreeId: UUID
    package let repoId: UUID
    let rootPath: URL
    package let summary: GitWorkingTreeSummary
    package let branch: String?

    package init(
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

package enum ArtifactEvent: Sendable {
    case diffProduced(worktreeId: UUID, artifact: DiffArtifact)
    case approvalRequested(request: ApprovalRequest)
    case approvalDecided(decision: ApprovalDecision)
}

package struct DiffArtifact: Sendable {
    package let diffId: UUID
    package let worktreeId: UUID
    package let patchData: Data

    package init(diffId: UUID, worktreeId: UUID, patchData: Data) {
        self.diffId = diffId
        self.worktreeId = worktreeId
        self.patchData = patchData
    }
}

package struct ApprovalRequest: Sendable {
    package let id: UUID
    package let summary: String

    package init(id: UUID, summary: String) {
        self.id = id
        self.summary = summary
    }
}

package struct ApprovalDecision: Sendable {
    let requestId: UUID
    let approved: Bool
}

package enum SecurityEvent: Sendable {
    case networkEgressBlocked(destination: String, rule: String)
    case filesystemAccessDenied(path: String, operation: String)
    case secretAccessed(secretId: String, consumerId: String)
    case processSpawnBlocked(command: String, rule: String)
    case sandboxStarted(backend: ExecutionBackend, policy: String)
    case sandboxStopped(reason: String)
    case sandboxHealthChanged(healthy: Bool)
}

package enum ExecutionBackend: Sendable, Equatable, Hashable, Codable {
    case local
    case docker(image: String)
    case gondolin(policyId: String)
    case remote(host: String)
}

package enum RuntimeErrorEvent: Error, Sendable {
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
package enum GhosttyCloseTabMode: Sendable, Equatable {
    case thisTab
    case otherTabs
    case rightTabs
}

package enum GhosttyGotoTabTarget: Sendable, Equatable {
    case previous
    case next
    case last
    case index(Int)
}

package enum GhosttySplitDirection: Sendable, Equatable {
    case left
    case right
    case up
    case down
}

package enum GhosttyGotoSplitDirection: Sendable, Equatable {
    case previous
    case next
    case left
    case right
    case up
    case down
}

package enum GhosttyResizeSplitDirection: Sendable, Equatable {
    case left
    case right
    case up
    case down
}

package struct ProgressState: Sendable, Equatable {
    package enum Kind: Sendable, Equatable {
        case set
        case error
        case indeterminate
        case paused
    }

    package let kind: Kind
    package let percent: UInt8?

    package init(kind: Kind, percent: UInt8?) {
        self.kind = kind
        self.percent = percent
    }
}

package struct TerminalSizeConstraints: Sendable, Equatable {
    let minWidth: UInt32
    let minHeight: UInt32
    let maxWidth: UInt32
    let maxHeight: UInt32

    package init(minWidth: UInt32, minHeight: UInt32, maxWidth: UInt32, maxHeight: UInt32) {
        self.minWidth = minWidth
        self.minHeight = minHeight
        self.maxWidth = maxWidth
        self.maxHeight = maxHeight
    }
}

package struct GhosttyInputTrigger: Sendable, Equatable {
    package enum TriggerTag: Sendable, Equatable {
        case physical
        case unicode
        case catchAll
    }

    let tag: TriggerTag
    let key: UInt32?
    let modifiers: UInt32

    package init(tag: TriggerTag, key: UInt32?, modifiers: UInt32) {
        self.tag = tag
        self.key = key
        self.modifiers = modifiers
    }
}

package enum GhosttyKeyTableChange: Sendable, Equatable {
    case activate(name: String)
    case deactivate
    case deactivateAll
}

package enum TerminalColorKind: Sendable, Equatable {
    case foreground
    case background
    case cursor
    case palette(index: UInt8)
}

package struct TerminalColorChange: Sendable, Equatable {
    let kind: TerminalColorKind
    let red: UInt8
    let green: UInt8
    let blue: UInt8

    package init(kind: TerminalColorKind, red: UInt8, green: UInt8, blue: UInt8) {
        self.kind = kind
        self.red = red
        self.green = green
        self.blue = blue
    }
}

package enum TitlePromptScope: Sendable, Equatable {
    case surface
    case tab
}

package enum OpenURLKind: Sendable, Equatable {
    case unknown
    case text
    case html
}

package enum SecureInputMode: Sendable, Equatable {
    case on
    case off
    case toggle
}

package enum TerminalMouseShape: Sendable, Equatable {
    case text
    case pointer
    case crosshair
    case verticalText
    case other(rawValue: UInt32)
}

package enum GhosttyEvent: PaneKindEvent, Sendable, Equatable {
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
    case mouseShapeChanged(shape: TerminalMouseShape)
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

    package var actionPolicy: ActionPolicy {
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

    package var eventName: EventIdentifier {
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

package struct ScrollbarState: Sendable, Equatable {
    package let top: Int
    package let bottom: Int
    package let total: Int

    package init(top: Int, bottom: Int, total: Int) {
        precondition(top >= 0, "ScrollbarState.top must be non-negative")
        precondition(bottom >= top, "ScrollbarState.bottom must be >= top")
        precondition(total >= bottom, "ScrollbarState.total must be >= bottom")
        self.top = top
        self.bottom = bottom
        self.total = total
    }

    package var visibleRowCount: Int {
        bottom - top
    }

    package var isPinnedToBottom: Bool {
        bottom >= total
    }
}

package struct TerminalSearchState: Sendable, Equatable {
    package var query: String
    package var totalMatches: Int?
    package var selectedMatchIndex: Int?

    package init(
        query: String,
        totalMatches: Int? = nil,
        selectedMatchIndex: Int? = nil
    ) {
        self.query = query
        self.totalMatches = totalMatches
        self.selectedMatchIndex = selectedMatchIndex
    }
}

package enum BrowserEvent: PaneKindEvent, Sendable {
    case navigationCompleted(url: URL, statusCode: Int?)
    case pageLoaded(url: URL)
    case consoleMessage(level: ConsoleLevel, message: String)

    package var actionPolicy: ActionPolicy {
        switch self {
        case .consoleMessage:
            return .lossy(consolidationKey: "console")
        case .navigationCompleted, .pageLoaded:
            return .critical
        }
    }

    package var eventName: EventIdentifier {
        switch self {
        case .navigationCompleted: return .navigationCompleted
        case .pageLoaded: return .pageLoaded
        case .consoleMessage: return .consoleMessage
        }
    }
}

package enum ConsoleLevel: String, Sendable {
    case log
    case warn
    case error
    case debug
    case info
}

package enum DiffEvent: PaneKindEvent, Sendable {
    case diffLoaded(stats: DiffStats)

    package var actionPolicy: ActionPolicy {
        switch self {
        case .diffLoaded:
            return .critical
        }
    }

    package var eventName: EventIdentifier {
        switch self {
        case .diffLoaded: return .diffLoaded
        }
    }
}

package struct DiffStats: Sendable, Equatable {
    package let filesChanged: Int
    package let insertions: Int
    package let deletions: Int

    package init(filesChanged: Int, insertions: Int, deletions: Int) {
        self.filesChanged = filesChanged
        self.insertions = insertions
        self.deletions = deletions
    }
}

package enum EditorEvent: PaneKindEvent, Sendable {
    case contentSaved(path: String)
    case fileOpened(path: String, language: String?)
    case diagnosticsUpdated(path: String, errors: Int, warnings: Int)

    package var actionPolicy: ActionPolicy {
        switch self {
        case .contentSaved, .fileOpened:
            return .critical
        case .diagnosticsUpdated:
            return .lossy(consolidationKey: "diagnostics")
        }
    }

    package var eventName: EventIdentifier {
        switch self {
        case .contentSaved: return .contentSaved
        case .fileOpened: return .fileOpened
        case .diagnosticsUpdated: return .diagnosticsUpdated
        }
    }
}
