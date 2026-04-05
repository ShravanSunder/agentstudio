import Foundation
import Observation
import os.log

private let workspaceStoreLogger = Logger(subsystem: "com.agentstudio", category: "WorkspaceStore")

/// Main-actor persistence aggregate for the workspace atoms.
///
/// This type owns debounced persistence, restore, and flush. Workspace-domain
/// mutations live on the owning atoms or `WorkspaceMutationCoordinator`.
@MainActor
final class WorkspaceStore {
    let metadataAtom: WorkspaceMetadataAtom
    let repositoryTopologyAtom: WorkspaceRepositoryTopologyAtom
    let paneAtom: WorkspacePaneAtom
    let tabLayoutAtom: WorkspaceTabLayoutAtom
    let mutationCoordinator: WorkspaceMutationCoordinator

    private let persistor: WorkspacePersistor
    private let persistDebounceDuration: Duration
    private let clock: any Clock<Duration>
    private var debouncedSaveTask: Task<Void, Never>?
    private var isObservingPersistedState = false
    private var isRestoringState = false
    private(set) var isDirty: Bool = false

    init(
        metadataAtom: WorkspaceMetadataAtom = WorkspaceMetadataAtom(),
        repositoryTopologyAtom: WorkspaceRepositoryTopologyAtom = WorkspaceRepositoryTopologyAtom(),
        paneAtom: WorkspacePaneAtom = WorkspacePaneAtom(),
        tabLayoutAtom: WorkspaceTabLayoutAtom = WorkspaceTabLayoutAtom(),
        mutationCoordinator: WorkspaceMutationCoordinator? = nil,
        persistor: WorkspacePersistor = WorkspacePersistor(),
        persistDebounceDuration: Duration = .milliseconds(500),
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.metadataAtom = metadataAtom
        self.repositoryTopologyAtom = repositoryTopologyAtom
        self.paneAtom = paneAtom
        self.tabLayoutAtom = tabLayoutAtom
        self.mutationCoordinator =
            mutationCoordinator
            ?? WorkspaceMutationCoordinator(
                repositoryTopologyAtom: repositoryTopologyAtom,
                workspacePaneAtom: paneAtom,
                workspaceTabLayoutAtom: tabLayoutAtom
            )
        self.persistor = persistor
        self.persistDebounceDuration = persistDebounceDuration
        self.clock = clock
        observePersistedState()
    }

    // MARK: - Read Aggregate

    var repos: [Repo] {
        repositoryTopologyAtom.repos
    }

    var watchedPaths: [WatchedPath] {
        repositoryTopologyAtom.watchedPaths
    }

    var panes: [UUID: Pane] {
        paneAtom.panes
    }

    var tabs: [Tab] {
        tabLayoutAtom.tabs
    }

    var activeTabId: UUID? {
        tabLayoutAtom.activeTabId
    }

    var workspaceId: UUID {
        metadataAtom.workspaceId
    }

    var workspaceName: String {
        metadataAtom.workspaceName
    }

    var sidebarWidth: CGFloat {
        metadataAtom.sidebarWidth
    }

    var windowFrame: CGRect? {
        metadataAtom.windowFrame
    }

    var createdAt: Date {
        metadataAtom.createdAt
    }

    var unavailableRepoIds: Set<UUID> {
        repositoryTopologyAtom.unavailableRepoIds
    }

    var activeTab: Tab? {
        tabLayoutAtom.activeTab
    }

    var activePaneIds: Set<UUID> {
        tabLayoutAtom.activePaneIds
    }

    var orphanedPanes: [Pane] {
        paneAtom.orphanedPanes(excluding: tabLayoutAtom.allPaneIds)
    }

    func pane(_ id: UUID) -> Pane? {
        paneAtom.pane(id)
    }

    func tab(_ id: UUID) -> Tab? {
        tabLayoutAtom.tab(id)
    }

    func tabContaining(paneId: UUID) -> Tab? {
        tabLayoutAtom.tabContaining(paneId: paneId)
    }

    func repo(_ id: UUID) -> Repo? {
        repositoryTopologyAtom.repo(id)
    }

    func worktree(_ id: UUID) -> Worktree? {
        repositoryTopologyAtom.worktree(id)
    }

    func repo(containing worktreeId: UUID) -> Repo? {
        repositoryTopologyAtom.repo(containing: worktreeId)
    }

    func repoAndWorktree(containing cwd: URL?) -> (repo: Repo, worktree: Worktree)? {
        repositoryTopologyAtom.repoAndWorktree(containing: cwd)
    }

    func panes(for worktreeId: UUID) -> [Pane] {
        paneAtom.panes(for: worktreeId)
    }

    func paneCount(for worktreeId: UUID) -> Int {
        paneAtom.paneCount(for: worktreeId)
    }

    func isWorktreeActive(_ worktreeId: UUID) -> Bool {
        paneAtom.isWorktreeActive(worktreeId)
    }

    // MARK: - Persistence

    func restore() {
        _ = persistor.ensureDirectory()
        switch persistor.load() {
        case .loaded(let state):
            isRestoringState = true
            WorkspacePersistenceTransformer.hydrate(
                state,
                metadataAtom: metadataAtom,
                repositoryTopologyAtom: repositoryTopologyAtom,
                workspacePaneAtom: paneAtom,
                workspaceTabLayoutAtom: tabLayoutAtom
            )
            isRestoringState = false
            workspaceStoreLogger.info(
                "Restored workspace '\(state.name)' with \(state.panes.count) pane(s), \(state.tabs.count) tab(s)"
            )
        case .corrupt(let error):
            workspaceStoreLogger.error(
                "Workspace file exists but failed to decode — starting with empty state: \(error)"
            )
        case .missing:
            workspaceStoreLogger.info("No workspace files found — first launch")
        }
    }

    @discardableResult
    func flush() -> Bool {
        debouncedSaveTask?.cancel()
        debouncedSaveTask = nil
        return persistNow()
    }

    var prePersistHook: (() -> Void)?

    private func observePersistedState() {
        guard !isObservingPersistedState else { return }
        isObservingPersistedState = true
        withObservationTracking {
            _ = metadataAtom.workspaceId
            _ = metadataAtom.workspaceName
            _ = metadataAtom.createdAt
            _ = metadataAtom.sidebarWidth
            _ = metadataAtom.windowFrame
            _ = repositoryTopologyAtom.repos
            _ = repositoryTopologyAtom.watchedPaths
            _ = repositoryTopologyAtom.unavailableRepoIds
            _ = paneAtom.panes
            _ = tabLayoutAtom.tabs
            _ = tabLayoutAtom.activeTabId
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let shouldIgnore = self.isRestoringState
                self.isObservingPersistedState = false
                self.observePersistedState()
                guard !shouldIgnore else { return }
                self.markDirtyObserved()
            }
        }
    }

    private func markDirtyObserved() {
        if !isDirty {
            isDirty = true
            ProcessInfo.processInfo.disableSuddenTermination()
        }

        debouncedSaveTask?.cancel()
        debouncedSaveTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await self.clock.sleep(for: self.persistDebounceDuration)
            guard !Task.isCancelled else { return }
            _ = self.persistNow()
        }
    }

    @discardableResult
    private func persistNow() -> Bool {
        prePersistHook?()
        guard persistor.ensureDirectory() else {
            workspaceStoreLogger.error(
                "Failed to persist workspace because the workspaces directory could not be created"
            )
            return false
        }

        let persistedAt = Date()
        let state = WorkspacePersistenceTransformer.makePersistableState(
            metadataAtom: metadataAtom,
            repositoryTopologyAtom: repositoryTopologyAtom,
            workspacePaneAtom: paneAtom,
            workspaceTabLayoutAtom: tabLayoutAtom,
            persistedAt: persistedAt
        )

        do {
            try persistor.save(state)
            if isDirty {
                isDirty = false
                ProcessInfo.processInfo.enableSuddenTermination()
            }
            return true
        } catch {
            workspaceStoreLogger.error("Failed to persist workspace: \(error.localizedDescription)")
            return false
        }
    }
}
