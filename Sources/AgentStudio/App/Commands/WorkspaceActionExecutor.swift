import AgentStudioBridge
import AgentStudioCore
import Foundation
import os.log

/// Executes validated PaneActions by delegating to `WorkspaceSurfaceCoordinator`.
/// This class remains the app-facing entry point and preserves historical action
/// API semantics while orchestration now lives in `WorkspaceSurfaceCoordinator`.
@MainActor
final class WorkspaceActionExecutor {
    typealias SwitchArrangementTransitions = WorkspaceSurfaceCoordinator.SwitchArrangementTransitions
    private static let logger = Logger(subsystem: "com.agentstudio", category: "WorkspaceActionExecutor")

    private let coordinator: WorkspaceSurfaceCoordinator
    private let store: WorkspaceStore
    private var submittedGestureTail: Task<Bool, Never>?
    private var submittedGestureGeneration: UInt64 = 0
    private var acceptsWorkspaceCommands = true

    init(coordinator: WorkspaceSurfaceCoordinator, store: WorkspaceStore) {
        self.coordinator = coordinator
        self.store = store
        coordinator.workspaceActionSubmission = { [weak self] action in
            _ = self?.submit(action)
        }
    }

    private var arrangementView: WorkspaceArrangementViewDerived {
        WorkspaceArrangementViewDerived(
            tabLayoutAtom: store.tabLayoutAtom,
            paneAtom: store.paneAtom,
            managementLayerAtom: atom(\.managementLayer)
        )
    }

    static func computeSwitchArrangementTransitions(
        previousVisiblePaneIds: Set<UUID>,
        previouslyMinimizedPaneIds: Set<UUID>,
        newVisiblePaneIds: Set<UUID>,
        newMinimizedPaneIds: Set<UUID>,
        retainedVisiblePaneIds: Set<UUID> = []
    ) -> SwitchArrangementTransitions {
        WorkspaceSurfaceCoordinator.computeSwitchArrangementTransitions(
            previousVisiblePaneIds: previousVisiblePaneIds,
            previouslyMinimizedPaneIds: previouslyMinimizedPaneIds,
            newVisiblePaneIds: newVisiblePaneIds,
            newMinimizedPaneIds: newMinimizedPaneIds,
            retainedVisiblePaneIds: retainedVisiblePaneIds
        )
    }

    var undoStack: [WorkspaceMutationCoordinator.CloseEntry] {
        coordinator.undoStack
    }

    // MARK: - High-Level Operations

    /// Open a terminal for a worktree. Creates pane + tab + view.
    /// Returns the pane if a new one was created, nil if already open.
    @discardableResult
    func openTerminal(for worktree: Worktree, in repo: Repo) async -> Pane? {
        var createdPane: Pane?
        _ = await submitGesture { [self] _ in
            do {
                createdPane = try await coordinator.openTerminal(for: worktree, in: repo)
                return true
            } catch {
                Self.logger.error("Terminal creation failed before publication")
                return false
            }
        }.value
        return createdPane
    }

    /// Open a new terminal for a worktree, always creating a fresh pane+tab
    /// (never navigates to an existing one).
    @discardableResult
    func openNewTerminal(for worktree: Worktree, in repo: Repo) async -> Pane? {
        var createdPane: Pane?
        _ = await submitGesture { [self] _ in
            do {
                createdPane = try await coordinator.openNewTerminal(for: worktree, in: repo)
                return true
            } catch {
                Self.logger.error("Terminal creation failed before publication")
                return false
            }
        }.value
        return createdPane
    }

    /// Open a new generic GitHub webview pane in a new tab.
    @discardableResult
    func openWebview(url: URL = URL(string: "https://github.com")!) -> Pane? {
        coordinator.openWebview(url: url)
    }

    func resolveBridgePaneCommand(worktreeId: UUID? = nil) -> BridgePaneCommandTarget? {
        coordinator.resolveBridgePaneCommand(worktreeId: worktreeId)
    }

    @discardableResult
    func requestBridgePaneSurface(_ surface: BridgeProductSurface, paneId: UUID) -> Bool {
        coordinator.requestBridgePaneSurface(surface, paneId: paneId)
    }

    @discardableResult
    func reconcileZoomCompanion(
        sourcePaneId: UUID,
        owningTabId: UUID,
        viewerSurfaceRequest: @MainActor (BridgeProductSurface, UUID) -> Bool
    ) -> ZoomViewerPresentation {
        coordinator.reconcileZoomCompanion(
            sourcePaneId: sourcePaneId,
            owningTabId: owningTabId,
            viewerSurfaceRequest: viewerSurfaceRequest
        )
    }

    func refreshZoomCompanionActivities() {
        coordinator.refreshBridgePaneActivities()
    }

    func detachZoomSourceAfterExitIfHidden(
        sourcePaneId: UUID,
        tabId: UUID
    ) {
        guard !arrangementView.activeVisiblePaneIds(forTab: tabId).contains(sourcePaneId) else {
            return
        }
        coordinator.detachForViewSwitch(paneId: sourcePaneId)
    }

    func reattachZoomSourceForPresentationIfHidden(
        sourcePaneId: UUID,
        tabId: UUID
    ) {
        guard !arrangementView.activeVisiblePaneIds(forTab: tabId).contains(sourcePaneId) else {
            return
        }
        coordinator.reattachForViewSwitch(paneId: sourcePaneId)
    }

    /// Open an independent read-only Bridge review pane in a new tab.
    @discardableResult
    func openBridgeReviewInNewTab(worktreeId: UUID? = nil) -> Pane? {
        coordinator.openBridgeReviewInNewTab(worktreeId: worktreeId)
    }

    /// Open an independent Bridge file-viewer pane in a new tab.
    @discardableResult
    func openBridgeFilesInNewTab(worktreeId: UUID? = nil) -> Pane? {
        coordinator.openBridgeFilesInNewTab(worktreeId: worktreeId)
    }

    /// Undo the last close operation (tab or pane).
    @discardableResult
    func undoCloseTab() async -> Bool {
        await submitUndoClose().value
    }

    @discardableResult
    func submitUndoClose() -> Task<Bool, Never> {
        submitGesture { [self] _ in
            do { return try await coordinator.undoCloseTab() } catch {
                Self.logger.error("Undo failed before completion; ownership was preserved")
                return false
            }
        }
    }

    func restoreVisibleViewsForActiveTabIfNeeded(forceWhenBoundsExist: Bool = false) {
        coordinator.restoreViewsForActiveTabIfNeeded(forceWhenBoundsExist: forceWhenBoundsExist)
    }

    func clearPendingPaneRefocusRequestsAfterUserFocusChange() {
        coordinator.clearPendingPaneRefocusRequestsAfterUserFocusChange()
    }

    /// Forwards to the same reevaluation tail the canonical layout-changing
    /// actions call (SPEC R5 retry, R1 hidden hydration): the trusted
    /// container-layout callback in `PaneTabViewController` has no other path
    /// to the coordinator's `reevaluatePreparedTerminalGeometry()`.
    func reevaluatePreparedTerminalGeometry() {
        Task { [weak coordinator] in
            await coordinator?.reevaluatePreparedTerminalGeometry()
        }
    }

    private func drawerParentByPaneId() -> [UUID: UUID] {
        Dictionary(
            uniqueKeysWithValues: store.paneAtom.paneSnapshot().values.compactMap { pane in
                guard let parentPaneId = pane.parentPaneId else { return nil }
                return (pane.id, parentPaneId)
            }
        )
    }

    private func drawerLayoutByParentPaneId() -> [UUID: DrawerGridLayout] {
        Dictionary(
            uniqueKeysWithValues: store.paneAtom.paneSnapshot().values.compactMap { pane in
                guard pane.drawer != nil, let drawerView = arrangementView.drawerView(forParent: pane.id) else {
                    return nil
                }
                return (pane.id, drawerView.layout)
            }
        )
    }

    /// Validate/canonicalize a WorkspaceActionCommand against current state, then execute it.
    @discardableResult
    func execute(_ action: WorkspaceActionCommand) async -> Bool {
        await submit(action).value
    }

    @discardableResult
    func submit(_ action: WorkspaceActionCommand) -> Task<Bool, Never> {
        submitGesture { execute in await execute(action) }
    }

    /// One admitted user operation includes resolution and dependent effects, not just its first mutation.
    @discardableResult
    func submitGesture(
        _ operation: @escaping @MainActor (@MainActor (WorkspaceActionCommand) async -> Bool) async -> Bool
    ) -> Task<Bool, Never> {
        guard acceptsWorkspaceCommands else { return Task { false } }
        let predecessor = submittedGestureTail
        submittedGestureGeneration &+= 1
        let generation = submittedGestureGeneration
        let task = Task { @MainActor [self] in
            _ = await predecessor?.value
            let result = await operation { [self] action in await executeValidatedAction(action) }
            if submittedGestureGeneration == generation { submittedGestureTail = nil }
            return result
        }
        submittedGestureTail = task
        return task
    }

    /// Shutdown waits for accepted work; callers must use their own submission for a command result.
    func stopAcceptingCommandsAndDrain() async {
        acceptsWorkspaceCommands = false
        _ = await submittedGestureTail?.value
    }

    private func executeValidatedAction(_ action: WorkspaceActionCommand) async -> Bool {
        let tabLayout = store.tabLayoutAtom
        let repositoryTopology = store.repositoryTopologyAtom
        let snapshot = WorkspaceCommandResolver.snapshot(
            from: tabLayout.tabs,
            activeTabId: tabLayout.activeTabId,
            isManagementLayerActive: atom(\.managementLayer).isActive,
            zoomSourcePaneIdByTabId: store.panePresentationAtom.zoomPresentationsByTabId.mapValues(
                \.sourcePaneId
            ),
            knownRepoIds: Set(repositoryTopology.repos.map(\.id)),
            knownWorktreeIds: Set(repositoryTopology.repos.flatMap(\.worktrees).map(\.id)),
            drawerParentByPaneId: drawerParentByPaneId(),
            drawerLayoutByParentPaneId: drawerLayoutByParentPaneId(),
            visiblePaneIds: { [arrangementView] tab in
                arrangementView.activeVisiblePaneIds(forTab: tab.id)
            }
        )
        switch WorkspaceCommandValidator.validate(action, state: snapshot) {
        case .success(let validated):
            do {
                try await coordinator.execute(validated.action)
                return true
            } catch {
                Self.logger.error("Workspace action failed before completion")
                return false
            }
        case .failure(let error):
            Self.logger.warning(
                "Action rejected: \(String(describing: action), privacy: .public) reason=\(String(describing: error), privacy: .public)"
            )
            return false
        }
    }

}
