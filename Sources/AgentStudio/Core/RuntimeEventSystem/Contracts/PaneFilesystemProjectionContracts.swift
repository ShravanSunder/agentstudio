import Foundation

struct FilesystemProjectionTopologyEntry: Sendable, Equatable {
    let repoId: UUID
    let worktreeId: UUID
    let rootPath: URL
    let isUnavailable: Bool
}

struct FilesystemProjectionPaneEntry: Sendable, Equatable {
    let paneId: UUID
    let paneKind: PaneContentType
    let repoId: UUID?
    let worktreeId: UUID?
    let cwd: URL?
}

struct FilesystemProjectionPaneUpdate: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case upsert(FilesystemProjectionPaneEntry)
        case remove(paneId: UUID)
    }

    let requestGeneration: UInt64
    let kind: Kind
}

struct FilesystemSourceSyncRequest: Sendable, Equatable {
    let requestGeneration: UInt64
    let paneContextGeneration: UInt64
    let topologyEntries: [FilesystemProjectionTopologyEntry]
    let paneEntries: [FilesystemProjectionPaneEntry]
    let appliedContextsByWorktreeId: [UUID: WorktreeFilesystemContext]
    let appliedActivityByWorktreeId: [UUID: Bool]
    let activePaneWorktreeId: UUID?
    let appliedActivePaneWorktreeId: UUID?
    let sidebarVisibleWorktreeIds: Set<UUID>
    let appliedSidebarVisibleWorktreeIds: Set<UUID>

    init(
        requestGeneration: UInt64,
        paneContextGeneration: UInt64,
        topologyEntries: [FilesystemProjectionTopologyEntry],
        paneEntries: [FilesystemProjectionPaneEntry],
        appliedContextsByWorktreeId: [UUID: WorktreeFilesystemContext] = [:],
        appliedActivityByWorktreeId: [UUID: Bool],
        activePaneWorktreeId: UUID?,
        appliedActivePaneWorktreeId: UUID?,
        sidebarVisibleWorktreeIds: Set<UUID> = [],
        appliedSidebarVisibleWorktreeIds: Set<UUID> = []
    ) {
        self.requestGeneration = requestGeneration
        self.paneContextGeneration = paneContextGeneration
        self.topologyEntries = topologyEntries
        self.paneEntries = paneEntries
        self.appliedContextsByWorktreeId = appliedContextsByWorktreeId
        self.appliedActivityByWorktreeId = appliedActivityByWorktreeId
        self.activePaneWorktreeId = activePaneWorktreeId
        self.appliedActivePaneWorktreeId = appliedActivePaneWorktreeId
        self.sidebarVisibleWorktreeIds = sidebarVisibleWorktreeIds
        self.appliedSidebarVisibleWorktreeIds = appliedSidebarVisibleWorktreeIds
    }
}

struct FilesystemSourceSyncDiff: Sendable, Equatable {
    struct Registration: Sendable, Equatable {
        let worktreeId: UUID
        let repoId: UUID
        let rootPath: URL
    }

    struct ActivityUpdate: Sendable, Equatable {
        let worktreeId: UUID
        let isActiveInApp: Bool
    }

    let requestGeneration: UInt64
    let contextsByWorktreeId: [UUID: WorktreeFilesystemContext]
    let unregisterWorktreeIds: [UUID]
    let registerWorktrees: [Registration]
    let activityUpdates: [ActivityUpdate]
    let activityByWorktreeId: [UUID: Bool]
    let activePaneWorktreeId: UUID?
    let shouldUpdateActivePaneWorktree: Bool
    let sidebarVisibleWorktreeIds: Set<UUID>
    let shouldUpdateSidebarVisibleWorktrees: Bool
    let validPaneIds: Set<UUID>
    let validWorktreeIds: Set<UUID>
}

struct PaneFilesystemProjectionRequest: Sendable {
    let requestGeneration: UInt64
    let paneContextGeneration: UInt64
    let topologyGeneration: UInt64
    let envelope: RuntimeEnvelope
}

struct PaneFilesystemProjectionResult: Sendable {
    let requestGeneration: UInt64
    let paneContextGeneration: UInt64
    let topologyGeneration: UInt64
    let intents: [PaneFilesystemProjectionIntent]
    let worktreeCount: Int
    let paneCount: Int
}

struct PaneFilesystemCWDSubtreeProjection: Sendable {
    let paneId: UUID
    let paneKind: PaneContentType
    let context: PaneFilesystemContext
    let paths: [String]
    let batchSequence: UInt64
    let timestamp: ContinuousClock.Instant
    let correlationId: UUID?
    let commandId: UUID?
}

struct PaneFilesystemGitProjection: Sendable {
    let paneId: UUID
    let paneKind: PaneContentType
    let context: PaneFilesystemContext
    let summary: GitWorkingTreeSummary
    let timestamp: ContinuousClock.Instant
    let correlationId: UUID?
    let commandId: UUID?
}

enum PaneFilesystemProjectionIntent: Sendable {
    case cwdSubtreeChanged(PaneFilesystemCWDSubtreeProjection)
    case gitWorkingTreeInCwd(PaneFilesystemGitProjection)
}
