import AppKit
import GhosttyKit
import Observation
import SwiftUI
import os.log

// swiftlint:disable file_length type_body_length

private final class RestoreAwareTerminalContainerView: NSView {
    var onNonEmptyLayoutBoundsChanged: ((CGRect) -> Void)?
    private var lastLoggedBounds: CGRect = .zero
    private var lastPublishedBounds: CGRect = .zero
    private var layoutGeneration: Int = 0

    override func layout() {
        super.layout()
        logBoundsChangeIfNeeded(reason: "layout")
        publishNonEmptyLayoutBoundsChangedIfNeeded()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        RestoreTrace.log(
            "RestoreAwareTerminalContainerView.viewDidMoveToWindow window=\(window != nil) id=\(ObjectIdentifier(self)) superview=\(superview != nil) bounds=\(NSStringFromRect(bounds))"
        )
        logBoundsChangeIfNeeded(reason: "viewDidMoveToWindow")
        publishNonEmptyLayoutBoundsChangedIfNeeded()
    }

    private func logBoundsChangeIfNeeded(reason: StaticString) {
        guard bounds != lastLoggedBounds else { return }
        layoutGeneration += 1
        lastLoggedBounds = bounds
        RestoreTrace.log(
            "RestoreAwareTerminalContainerView \(reason) generation=\(layoutGeneration) bounds=\(NSStringFromRect(bounds)) window=\(window != nil)"
        )
    }

    private func publishNonEmptyLayoutBoundsChangedIfNeeded() {
        guard !bounds.isEmpty, bounds != lastPublishedBounds else { return }
        lastPublishedBounds = bounds
        onNonEmptyLayoutBoundsChanged?(bounds)
    }
}

/// Tab-based terminal controller with custom Ghostty-style tab bar.
///
/// PaneTabViewController is a composition-oriented controller in `App/`. It reads
/// from WorkspaceStore for state and routes user actions through the validated
/// ActionExecutor pipeline. Most flow changes are dispatched, while AppKit-only
/// concerns (focus, observers, empty-state visibility, tab bar coordination) stay
/// local. It also handles direct tab-order updates (`store.moveTab`) from drag
/// interactions as a UI-only mutation.
@MainActor
class PaneTabViewController: NSViewController, NSPopoverDelegate, WorkspaceCommandHandling {
    typealias OpenEditorHandler =
        @MainActor (_ id: EditorTargetId, _ path: URL, _ installedTargets: [ExternalEditorTarget]) -> Bool

    private static let logger = Logger(subsystem: "com.agentstudio", category: "PaneTabViewController")
    private static let genericGitHubURL = URL(string: "https://github.com")!

    // MARK: - Dependencies (injected)

    private let store: WorkspaceStore
    private let repoCache: RepoCacheAtom
    private let applicationLifecycleMonitor: ApplicationLifecycleMonitor
    private let appLifecycleStore: AppLifecycleAtom
    private let windowLifecycleStore: WindowLifecycleAtom
    private let workspaceWindowId: UUID?
    private let executor: ActionExecutor
    private let tabBarAdapter: TabBarAdapter
    private let viewRegistry: ViewRegistry
    private let paneInboxPresentation: PaneInboxPresentation?
    private let closeTransitionCoordinator: PaneCloseTransitionCoordinator
    private let tabRenamePopoverState: TabRenamePopoverState
    private let arrangementInlineRenameState: ArrangementInlineRenameState
    private let arrangementPanelPresentation: ArrangementPanelPresentationAtom
    private let registersAsCommandHandler: Bool
    private let installedEditorTargetsProvider: @MainActor () -> [ExternalEditorTarget]
    private let openEditorHandler: OpenEditorHandler
    private let openFinderHandler: @MainActor (URL) -> Bool
    private let copyPathHandler: @MainActor (URL) -> Void
    private let paneNotePresentation: PaneNotePresentation?
    private var arrangementView: WorkspaceArrangementViewDerived {
        WorkspaceArrangementViewDerived(
            tabLayoutAtom: store.tabLayoutAtom,
            paneAtom: store.paneAtom,
            managementLayerAtom: atom(\.managementLayer)
        )
    }
    private lazy var splitDropInteractionController = SplitDropInteractionController(
        store: store,
        visiblePaneIdsProvider: { [weak self] tab in
            guard let self else { return [] }
            return self.arrangementView.activeVisiblePaneIds(forTab: tab.id)
        },
        drawerParentByPaneIdProvider: { [weak self] in
            self?.drawerParentByPaneId() ?? [:]
        },
        drawerLayoutByParentPaneIdProvider: { [weak self] in
            self?.drawerLayoutByParentPaneId() ?? [:]
        },
        dispatchAction: { [weak self] action in
            self?.dispatchAction(action)
        }
    )
    private var tabContentHostControllerStorage: TabContentHostController?
    private lazy var actionDispatcher = PaneTabActionDispatcher(
        dispatch: { [weak self] action in
            guard let self else {
                RestoreTrace.log(
                    "PaneTabActionDispatcher.dispatch dropped ownerReleased action=\(String(describing: action))"
                )
                return
            }
            self.dispatchAction(action)
        },
        shouldHandleSplitDragPayload: { [weak self] payload in
            guard let self else {
                RestoreTrace.log("PaneTabActionDispatcher.shouldHandleSplitDragPayload dropped ownerReleased")
                return false
            }
            return self.splitDropInteractionController.shouldHandleSplitDragPayload(payload)
        },
        shouldAcceptDrop: { [weak self] payload, destPaneId, zone, sizingMode in
            guard let self else {
                RestoreTrace.log(
                    "PaneTabActionDispatcher.shouldAcceptDrop dropped ownerReleased destPaneId=\(destPaneId) zone=\(zone)"
                )
                return false
            }
            return self.splitDropInteractionController.shouldAcceptDrop(
                payload: payload,
                destPaneId: destPaneId,
                zone: zone,
                sizingMode: sizingMode
            )
        },
        handleDrop: { [weak self] payload, destPaneId, zone, sizingMode in
            guard let self else {
                RestoreTrace.log(
                    "PaneTabActionDispatcher.handleDrop dropped ownerReleased destPaneId=\(destPaneId) zone=\(zone)"
                )
                return
            }
            self.splitDropInteractionController.handleDrop(
                payload: payload,
                destPaneId: destPaneId,
                zone: zone,
                sizingMode: sizingMode
            )
        }
    )

    private var paneAuxiliaryCommandControllerStorage: PaneAuxiliaryCommandController?

    // MARK: - View State

    private var tabBarHostingView: DraggableTabBarHostingView!
    private var terminalContainer: RestoreAwareTerminalContainerView!
    private var emptyStateView: NSHostingView<WorkspaceEmptyStateView>?
    private var lastEmptyStateModel: WorkspaceEmptyStateModel?
    #if DEBUG
        private(set) var paneRepresentableDismantleCount = 0
    #endif

    /// Local event monitor for arrangement bar keyboard shortcut
    private var arrangementBarEventMonitor: Any?
    private var notificationTasks: [Task<Void, Never>] = []

    private lazy var workspaceFocusController = WorkspaceFocusController(
        store: store,
        executor: executor,
        viewRegistry: viewRegistry,
        windowProvider: { [weak self] in
            self?.view.window
        }
    )

    private lazy var managementLayerCommandController = ManagementLayerCommandController(
        store: store,
        repoCache: repoCache,
        executor: executor,
        workspaceFocusController: workspaceFocusController,
        arrangementViewProvider: { [store] in
            WorkspaceArrangementViewDerived(
                tabLayoutAtom: store.tabLayoutAtom,
                paneAtom: store.paneAtom,
                managementLayerAtom: atom(\.managementLayer)
            )
        },
        dispatchAction: { [weak self] action in
            self?.dispatchAction(action)
        },
        executeCommand: { [weak self] command in
            self?.execute(command)
        },
        canExecuteCommand: { [weak self] command in
            self?.canExecute(command) ?? false
        },
        handlePaneFocusTrigger: { [weak self] trigger in
            self?.handlePaneFocusTrigger(trigger)
        },
        openGitHubWebview: { [weak self] paneId in
            self?.openGitHubWebview(for: paneId)
        },
        focusTargetedDrawerPane: { [weak self] parentPaneId, drawerPaneId in
            self?.focusTargetedDrawerPane(parentPaneId: parentPaneId, drawerPaneId: drawerPaneId)
        }
    )

    private lazy var tabBarInteractionController = TabBarInteractionController(
        store: store,
        tabBarAdapter: tabBarAdapter,
        arrangementInlineRenameState: arrangementInlineRenameState,
        tabRenamePopoverState: tabRenamePopoverState,
        windowLifecycleStore: windowLifecycleStore,
        workspaceWindowId: workspaceWindowId,
        dispatchAction: { [weak self] action in
            self?.dispatchAction(action)
        },
        handlePaneFocusTrigger: { [weak self] trigger in
            self?.handlePaneFocusTrigger(trigger)
        },
        addNewTab: { [weak self] in
            self?.addNewTab()
        },
        openGitHubWebview: { [weak self] in
            self?.openGitHubWebview()
        }
    )

    private func ensureTabContentHostController() -> TabContentHostController {
        if let controller = tabContentHostControllerStorage {
            return controller
        }

        let controller = TabContentHostController(
            store: store,
            repoCache: repoCache,
            viewRegistry: viewRegistry,
            appLifecycleStore: appLifecycleStore,
            closeTransitionCoordinator: closeTransitionCoordinator,
            actionDispatcher: actionDispatcher,
            executor: executor,
            paneInboxPresentation: paneInboxPresentation,
            workspaceWindowId: workspaceWindowId,
            terminalContainerProvider: { [weak self] in
                self?.terminalContainer
            },
            rootViewProvider: { [weak self] in
                guard let self, self.isViewLoaded else { return nil }
                return self.view
            },
            tabBarHostingViewProvider: { [weak self] in
                self?.tabBarHostingView
            },
            handlePaneFocusTrigger: { [weak self] trigger in
                self?.handlePaneFocusTrigger(trigger)
            },
            openPaneGitHub: { [weak self] paneId in
                self?.openGitHubWebview(for: paneId)
            }
        )
        tabContentHostControllerStorage = controller
        return controller
    }

    private func ensurePaneAuxiliaryCommandController() -> PaneAuxiliaryCommandController {
        if let controller = paneAuxiliaryCommandControllerStorage {
            return controller
        }

        let controller = PaneAuxiliaryCommandController(
            store: store,
            windowLifecycleStore: windowLifecycleStore,
            workspaceWindowId: workspaceWindowId,
            viewRegistry: viewRegistry,
            paneInboxPresentation: paneInboxPresentation,
            paneNotePresentation: paneNotePresentation,
            installedEditorTargetsProvider: installedEditorTargetsProvider,
            openEditorHandler: openEditorHandler,
            openFinderHandler: openFinderHandler,
            copyPathHandler: copyPathHandler,
            activeMainPaneIdProvider: { [weak self] in
                self?.activeMainPaneId()
            },
            visibleActiveDrawerPaneIdProvider: { [weak self] parentPaneId in
                self?.visibleActiveDrawerPaneId(for: parentPaneId)
            },
            workspaceFocusOwnerProvider: { [weak self] in
                self?.normalizedWorkspaceNavigationScopeState() ?? .mainPane(paneId: nil)
            },
            focusTargetedPane: { [weak self] paneId in
                self?.focusTargetedPane(paneId)
            },
            fallbackAnchorViewProvider: { [weak self] in
                guard let self, self.isViewLoaded else { return nil }
                return self.view
            },
            popoverDelegateProvider: { [weak self] in
                self
            }
        )
        paneAuxiliaryCommandControllerStorage = controller
        return controller
    }

    // MARK: - Init

    init(
        store: WorkspaceStore,
        repoCache: RepoCacheAtom,
        applicationLifecycleMonitor: ApplicationLifecycleMonitor,
        appLifecycleStore: AppLifecycleAtom,
        windowLifecycleStore: WindowLifecycleAtom = atom(\.windowLifecycle),
        workspaceWindowId: UUID? = nil,
        executor: ActionExecutor,
        tabBarAdapter: TabBarAdapter,
        viewRegistry: ViewRegistry,
        paneInboxPresentation: PaneInboxPresentation? = nil,
        installedEditorTargetsProvider: @escaping @MainActor () -> [ExternalEditorTarget] = {
            ExternalEditorTarget.refreshInstalledTargets()
        },
        openEditorHandler: @escaping OpenEditorHandler = { id, path, installedTargets in
            ExternalWorkspaceOpener.openInEditor(
                id: id,
                path: path,
                installedTargets: installedTargets
            )
        },
        openFinderHandler: @escaping @MainActor (URL) -> Bool = { path in
            ExternalWorkspaceOpener.openInFinder(path)
        },
        copyPathHandler: @escaping @MainActor (URL) -> Void = { path in
            PathActions.copyPath(path)
        },
        paneNotePresentation: PaneNotePresentation? = nil,
        closeTransitionCoordinator: PaneCloseTransitionCoordinator = PaneCloseTransitionCoordinator(),
        tabRenamePopoverState: TabRenamePopoverState = TabRenamePopoverState(),
        arrangementInlineRenameState: ArrangementInlineRenameState = ArrangementInlineRenameState(),
        arrangementPanelPresentation: ArrangementPanelPresentationAtom = atom(\.arrangementPanelPresentation),
        registersAsCommandHandler: Bool = true
    ) {
        self.store = store
        self.repoCache = repoCache
        self.applicationLifecycleMonitor = applicationLifecycleMonitor
        self.appLifecycleStore = appLifecycleStore
        self.windowLifecycleStore = windowLifecycleStore
        self.workspaceWindowId = workspaceWindowId
        self.executor = executor
        self.tabBarAdapter = tabBarAdapter
        self.viewRegistry = viewRegistry
        self.paneInboxPresentation = paneInboxPresentation
        self.installedEditorTargetsProvider = installedEditorTargetsProvider
        self.openEditorHandler = openEditorHandler
        self.openFinderHandler = openFinderHandler
        self.copyPathHandler = copyPathHandler
        self.paneNotePresentation = paneNotePresentation
        self.closeTransitionCoordinator = closeTransitionCoordinator
        self.tabRenamePopoverState = tabRenamePopoverState
        self.arrangementInlineRenameState = arrangementInlineRenameState
        self.arrangementPanelPresentation = arrangementPanelPresentation
        self.registersAsCommandHandler = registersAsCommandHandler
        super.init(nibName: nil, bundle: nil)
        setupNotificationObservers()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    #if DEBUG
        func recordPaneRepresentableDismantleForTesting() {
            paneRepresentableDismantleCount += 1
        }
    #endif

    // MARK: - View Lifecycle

    override func loadView() {
        let containerView = NSView()
        containerView.wantsLayer = true

        // Create terminal container FIRST (so it's behind tab bar)
        terminalContainer = RestoreAwareTerminalContainerView()
        terminalContainer.wantsLayer = true
        terminalContainer.translatesAutoresizingMaskIntoConstraints = false
        terminalContainer.layer?.cornerRadius = 8
        terminalContainer.layer?.masksToBounds = true
        terminalContainer.onNonEmptyLayoutBoundsChanged = { [weak self] bounds in
            self?.applicationLifecycleMonitor.handleTerminalContainerBoundsChanged(bounds)
            self?.handleTerminalContainerBoundsChanged(reason: "terminalContainerLayout")
        }
        containerView.addSubview(terminalContainer)

        // Create custom tab bar AFTER (so it's on top visually)
        tabBarHostingView = tabBarInteractionController.makeTabBarHostingView(popoverDelegate: self)
        tabBarHostingView.translatesAutoresizingMaskIntoConstraints = false
        tabBarHostingView.wantsLayer = true
        containerView.addSubview(tabBarHostingView)

        // Create empty state view
        let emptyView = createEmptyStateView()
        emptyView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(emptyView)
        self.emptyStateView = emptyView
        lastEmptyStateModel = emptyStateModel

        NSLayoutConstraint.activate([
            // Tab bar at top - use safeAreaLayoutGuide to respect titlebar
            tabBarHostingView.topAnchor.constraint(equalTo: containerView.safeAreaLayoutGuide.topAnchor),
            tabBarHostingView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            tabBarHostingView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            tabBarHostingView.heightAnchor.constraint(equalToConstant: 36),

            // Terminal container below tab bar
            terminalContainer.topAnchor.constraint(equalTo: tabBarHostingView.bottomAnchor),
            terminalContainer.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            terminalContainer.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            terminalContainer.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),

            // Empty state fills container (respects safe area)
            emptyView.topAnchor.constraint(equalTo: containerView.safeAreaLayoutGuide.topAnchor),
            emptyView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            emptyView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            emptyView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        ])

        view = containerView
        updateEmptyState()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        if registersAsCommandHandler {
            CommandDispatcher.shared.handler = self
        }

        let tabContentHostController = ensureTabContentHostController()
        tabContentHostController.syncTabContentHosts()
        tabContentHostController.updateVisibleTabHost()

        // Observe store for AppKit-level concerns (empty state visibility, focus management)
        updateEmptyState()
        observeForAppKitState()

        // App-owned global shortcuts route through the centralized command pipeline.
        arrangementBarEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard self.view.window?.isKeyWindow == true else { return event }
            if self.handleAppOwnedKeyEvent(event) {
                return nil
            }
            return event
        }

    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if handleAppOwnedKeyEvent(event, allowsModifiedEmptyDrawerShortcutWithTextFocus: true) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func viewWillLayout() {
        super.viewWillLayout()
        let tabContentHostController = ensureTabContentHostController()
        tabContentHostController.syncTabContentHosts()
        tabContentHostController.updateVisibleTabHost()
        updateEmptyState()
    }

    private func setupNotificationObservers() {
        guard notificationTasks.isEmpty else { return }
        setupAppNotificationObservers()
    }

    private func setupAppNotificationObservers() {
        notificationTasks.append(
            Task { [weak self] in
                let stream = await AppEventBus.shared.subscribe()
                for await event in stream {
                    guard !Task.isCancelled else { break }
                    switch event {
                    case .terminalProcessTerminated(let paneId):
                        await MainActor.run { [weak self] in
                            self?.handleTerminalProcessTerminated(paneId: paneId)
                        }
                    case .terminalProcessTerminationHandled, .worktreeBellRang:
                        continue
                    }
                }
            })
    }

    func shutdown() {
        tabContentHostControllerStorage?.shutdown()
        if let monitor = arrangementBarEventMonitor {
            NSEvent.removeMonitor(monitor)
            arrangementBarEventMonitor = nil
        }
        for task in notificationTasks {
            task.cancel()
        }
        notificationTasks.removeAll()
    }

    isolated deinit {
        tabContentHostControllerStorage?.shutdown()
        let monitor = arrangementBarEventMonitor
        let tasks = notificationTasks
        Task { @MainActor in
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            for task in tasks {
                task.cancel()
            }
        }
    }

    // MARK: - Store Observation (AppKit-Level Concerns)

    /// Observe store for AppKit-level state: empty state visibility and focus management.
    /// SwiftUI rendering is handled by per-tab SingleTabContent hosts — this method
    /// only handles things that live outside the SwiftUI tree (host visibility, firstResponder).
    private func observeForAppKitState() {
        withObservationTracking {
            _ = self.store.tabLayoutAtom.tabs
            _ = self.store.tabLayoutAtom.activeTabId
            _ = self.store.repositoryTopologyAtom.repos
            _ = atom(\.welcome).isChoosingFolder
            _ = atom(\.welcome).folderScanState
            _ = self.repoCache.recentTargets
            _ = atom(\.managementLayer).isActive
        } onChange: {
            Task { @MainActor [weak self] in
                self?.handleAppKitStateChange()
                self?.observeForAppKitState()
            }
        }
    }

    private func handleAppKitStateChange() {
        let tabContentHostController = ensureTabContentHostController()
        tabContentHostController.syncTabContentHosts()
        tabContentHostController.updateVisibleTabHost()
        rebuildEmptyStateView()
        updateEmptyState()
        prunePaneInboxPresentationState()

        workspaceFocusController.handleAppKitStateChange()
    }

    private func prunePaneInboxPresentationState() {
        guard let paneInboxPresentation else { return }
        let retainedParentPaneIds = Set(
            store.paneAtom.panes.values.compactMap { pane in
                pane.isDrawerChild ? nil : pane.id
            }
        )
        paneInboxPresentation.pruneFilterModes(retainedParentPaneIds)
    }

    func handlePaneFocusTrigger(_ trigger: PaneFocusTrigger) {
        workspaceFocusController.handlePaneFocusTrigger(trigger)
    }

    func requestPaneRefocus(_ reason: PaneRefocusRequestTrigger.Reason = .explicit) {
        workspaceFocusController.requestPaneRefocus(reason)
    }

    private func normalizedWorkspaceNavigationFocusScope() -> WorkspaceNavigationFocusScope {
        workspaceFocusController.normalizedWorkspaceNavigationFocusScope()
    }

    private func normalizedWorkspaceNavigationScopeState() -> WorkspaceFocusOwner {
        workspaceFocusController.normalizedWorkspaceNavigationScopeState()
    }

    @discardableResult
    private func clearFirstResponderToWindowContentForDrawer(parentPaneId: UUID) -> Bool {
        workspaceFocusController.clearFirstResponderToWindowContentForDrawer(parentPaneId: parentPaneId)
    }

    private func syncFocusOwnerAfterDrawerMutation(parentPaneId: UUID) {
        workspaceFocusController.syncFocusOwnerAfterDrawerMutation(parentPaneId: parentPaneId)
    }

    private func drawerParentByPaneId() -> [UUID: UUID] {
        workspaceFocusController.drawerParentByPaneId()
    }

    private func drawerLayoutByParentPaneId() -> [UUID: DrawerGridLayout] {
        workspaceFocusController.drawerLayoutByParentPaneId()
    }

    private func visibleActiveDrawerPaneId(for parentPaneId: UUID) -> UUID? {
        workspaceFocusController.visibleActiveDrawerPaneId(for: parentPaneId)
    }

    // MARK: - Tab Content Hosts

    private func activeTabHost() -> PersistentTabHostView? {
        ensureTabContentHostController().activeTabHost()
    }

    private func handleTerminalContainerBoundsChanged(reason: StaticString) {
        ensureTabContentHostController().handleTerminalContainerBoundsChanged(reason: reason)
    }

    func syncVisibleTerminalGeometry(reason: StaticString) {
        ensureTabContentHostController().syncVisibleTerminalGeometry(reason: reason)
    }

    func geometryHierarchySnapshot(reason: StaticString) -> String {
        ensureTabContentHostController().geometryHierarchySnapshot(reason: reason)
    }

    // MARK: - Empty State

    private var emptyStateModel: WorkspaceEmptyStateModel {
        WorkspaceLauncherProjector.project(
            store: store
        )
    }

    private func createEmptyStateView() -> NSHostingView<WorkspaceEmptyStateView> {
        PaneTabEmptyStateViewFactory.make(
            model: emptyStateModel,

            onWatchFolder: { [weak self] in self?.watchFolderAction() },
            onOpenRecent: { [weak self] target in self?.openRecentTarget(target) },
            onOpenAllRecent: { [weak self] in self?.openAllRecentTargets() }
        )
    }

    @objc private func watchFolderAction() {
        CommandDispatcher.shared.dispatch(.watchFolder)
    }

    private func updateEmptyState() {
        let hasTabs = !store.tabLayoutAtom.tabs.isEmpty
        tabBarHostingView.isHidden = !hasTabs
        terminalContainer.isHidden = !hasTabs
        emptyStateView?.isHidden = hasTabs
    }

    private func rebuildEmptyStateView() {
        let currentModel = emptyStateModel
        guard currentModel != lastEmptyStateModel else { return }
        emptyStateView?.rootView = WorkspaceEmptyStateView(
            model: currentModel,

            onWatchFolder: { [weak self] in self?.watchFolderAction() },
            onOpenRecent: { [weak self] target in self?.openRecentTarget(target) },
            onOpenAllRecent: { [weak self] in self?.openAllRecentTargets() }
        )
        lastEmptyStateModel = currentModel
    }

    private func openRecentTarget(_ target: RecentWorkspaceTarget) {
        let fileManager = FileManager.default
        if let worktreeId = target.worktreeId {
            guard store.repositoryTopologyAtom.worktree(worktreeId) != nil else {
                Self.logger.warning(
                    "Recent target removed because worktree is missing: \(target.id, privacy: .public)")
                repoCache.removeRecentTarget(target.id)
                return
            }
            guard store.repositoryTopologyAtom.repo(containing: worktreeId) != nil else {
                Self.logger.warning(
                    "Recent target removed because repo is missing for worktreeId=\(worktreeId.uuidString, privacy: .public)"
                )
                repoCache.removeRecentTarget(target.id)
                return
            }
            guard fileManager.fileExists(atPath: target.path.path) else {
                Self.logger.warning(
                    "Recent target removed because path is missing: \(target.path.path, privacy: .public)")
                repoCache.removeRecentTarget(target.id)
                return
            }
            dispatchAction(
                .openNewTerminalInTab(
                    worktreeId: worktreeId,
                    launchDirectory: target.path,
                    title: target.displayTitle
                )
            )
            return
        }

        guard fileManager.fileExists(atPath: target.path.path) else {
            Self.logger.warning(
                "Recent target removed because path is missing: \(target.path.path, privacy: .public)")
            repoCache.removeRecentTarget(target.id)
            return
        }

        dispatchAction(.openFloatingTerminal(launchDirectory: target.path, title: target.displayTitle))
    }

    private func openAllRecentTargets() {
        for target in emptyStateModel.recentTargets {
            openRecentTarget(target)
        }
    }

    private func openGitHubWebview() {
        executor.openWebview(url: Self.genericGitHubURL)
    }

    private func openGitHubWebview(for paneId: UUID) {
        let url = GitHubWebviewLaunchResolver.url(
            for: paneId,
            store: store,
            repoCache: repoCache
        )
        guard let targetTabId = store.tabLayoutAtom.activeTabId else {
            executor.openWebview(url: url)
            return
        }
        _ = executor.openContextualWebviewInPane(
            sourcePaneId: paneId,
            targetTabId: targetTabId,
            url: url
        )
    }

    private func activeMainPaneId() -> UUID? {
        workspaceFocusController.activeMainPaneId()
    }

    func handleAppOwnedKeyEvent(
        _ event: NSEvent,
        allowsModifiedEmptyDrawerShortcutWithTextFocus: Bool = false
    ) -> Bool {
        guard let trigger = ShortcutDecoder.decode(event: event) else {
            return false
        }

        if shouldConsumeSuppressedTerminalHostTrigger(trigger) { return true }

        let globalShortcut = ShortcutDecoder.shortcut(for: trigger, in: .global)

        let keyboardContext = KeyboardRoutingContext.current(
            windowLifecycle: windowLifecycleStore,
            managementLayer: atom(\.managementLayer),
            uiState: atom(\.workspaceSidebarState),
            commandBarSurface: atom(\.commandBarSurface),
            transientKeyboardSurface: atom(\.transientKeyboardSurface),
            workspaceWindowId: workspaceWindowId
        )

        if let shortcut = globalShortcut,
            AppShortcutDispatchPolicy.isCommandBarActivationShortcut(shortcut)
        {
            guard
                AppShortcutDispatchPolicy.shouldDispatchGlobalShortcut(
                    shortcut,
                    context: keyboardContext
                ),
                CommandDispatcher.shared.canDispatch(shortcut.command)
            else {
                return false
            }
            CommandDispatcher.shared.dispatch(shortcut.command)
            return true
        }

        if let handled = handleTerminalRuntimeShortcut(trigger, context: keyboardContext) {
            return handled
        }

        if let shortcut = globalShortcut {
            let shouldDispatchGlobalShortcut = AppShortcutDispatchPolicy.shouldDispatchGlobalShortcut(
                shortcut,
                context: keyboardContext
            )
            guard shouldDispatchGlobalShortcut || shortcut.requiresPaneTargetFallback else {
                return false
            }
            guard
                shouldDispatchGlobalShortcut
                    || AppShortcutDispatchPolicy.shouldRouteAppOwnedKeyEvent(context: keyboardContext)
            else {
                return false
            }
            if CommandDispatcher.shared.canDispatch(shortcut.command) {
                CommandDispatcher.shared.dispatch(shortcut.command)
                return true
            }
            if AppShortcutDispatchPolicy.shouldConsumeUnavailableGlobalShortcut(
                shortcut,
                context: keyboardContext
            ) {
                // Global shortcuts only consume unavailable commands when
                // the active surface explicitly reserves that chord.
                return true
            }
            guard shortcut.requiresPaneTargetFallback else {
                return false
            }
            // Empty-drawer creation needs a pane target, so it falls
            // through to the targeted app-owned path below.
        }

        guard AppShortcutDispatchPolicy.shouldRouteAppOwnedKeyEvent(context: keyboardContext) else {
            return false
        }

        // Raw-character triggers always require neutral focus, even
        // when modifier-keyed shortcuts are allowed through text focus.
        if let parentPaneId = firstDrawerPaneParentId(
            for: trigger,
            event: event,
            requiresNeutralFocus: trigger.modifiers.isEmpty || !allowsModifiedEmptyDrawerShortcutWithTextFocus
        ) {
            guard
                CommandDispatcher.shared.canDispatch(
                    .addDrawerPane,
                    target: parentPaneId,
                    targetType: .pane
                )
            else {
                return false
            }
            CommandDispatcher.shared.dispatch(.addDrawerPane, target: parentPaneId, targetType: .pane)
            return true
        }

        let keyboardOwner = keyboardContext.stableOwner

        if shouldHandleScopeAwarePaneTrigger(event: event, keyboardOwner: keyboardOwner),
            isScopeAwarePaneMovementTrigger(trigger)
        {
            // Consume every reserved option-I/J/K/L chord in pane scope,
            // even when there is no concrete move, so terminal content
            // never receives app-owned navigation keystrokes.
            if let command = scopeAwarePaneCommand(for: trigger), canExecute(command) {
                execute(command)
            }
            return true
        }

        return false
    }

    private func shouldConsumeSuppressedTerminalHostTrigger(_ trigger: ShortcutTrigger) -> Bool {
        AppShortcutDispatchPolicy.shouldSuppressTerminalHostTrigger(trigger)
    }

    private func handleTerminalRuntimeShortcut(
        _ trigger: ShortcutTrigger,
        context keyboardContext: KeyboardRoutingContext
    ) -> Bool? {
        guard let shortcut = ShortcutDecoder.shortcut(for: trigger, in: .terminalAppOwned),
            AppShortcutDispatchPolicy.isTerminalRuntimeCommand(shortcut.command)
        else {
            return nil
        }

        // Terminal runtime shortcuts are app-owned reservations. When AppKit
        // sends them through the pane controller instead of Ghostty, consume
        // even rejected chords so terminal/default responders never see them.
        guard
            AppShortcutDispatchPolicy.shouldDispatchTerminalAppOwnedShortcut(
                shortcut,
                context: keyboardContext
            ),
            CommandDispatcher.shared.canDispatch(shortcut.command)
        else {
            return true
        }
        CommandDispatcher.shared.dispatch(shortcut.command)
        return true
    }

    private func scopeAwarePaneCommand(for trigger: ShortcutTrigger) -> AppCommand? {
        let scope = normalizedWorkspaceNavigationScopeState()
        switch trigger {
        case .init(key: .character(.i), modifiers: [.option]):
            return if case .drawerPane = scope { .focusDrawerPaneUp } else { nil }
        case .init(key: .character(.j), modifiers: [.option]):
            switch scope {
            case .mainPane:
                return .focusPaneLeft
            case .emptyDrawer:
                return nil
            case .drawerPane:
                return .focusDrawerPaneLeft
            }
        case .init(key: .character(.k), modifiers: [.option]):
            switch scope {
            case .mainPane:
                return nil
            case .emptyDrawer:
                return nil
            case .drawerPane:
                return .focusDrawerPaneDown
            }
        case .init(key: .character(.l), modifiers: [.option]):
            switch scope {
            case .mainPane:
                return .focusPaneRight
            case .emptyDrawer:
                return nil
            case .drawerPane:
                return .focusDrawerPaneRight
            }
        default:
            return nil
        }
    }

    private func isScopeAwarePaneMovementTrigger(_ trigger: ShortcutTrigger) -> Bool {
        switch trigger {
        case .init(key: .character(.i), modifiers: [.option]),
            .init(key: .character(.j), modifiers: [.option]),
            .init(key: .character(.k), modifiers: [.option]),
            .init(key: .character(.l), modifiers: [.option]):
            return true
        default:
            return false
        }
    }

    private func shouldHandleScopeAwarePaneTrigger(
        event: NSEvent,
        keyboardOwner: KeyboardOwner
    ) -> Bool {
        guard keyboardOwner == .mainWindowChain else { return false }
        return !rawCharacterHasTextResponder(for: event)
    }

    private func firstDrawerPaneParentId(
        for trigger: ShortcutTrigger,
        event: NSEvent,
        requiresNeutralFocus: Bool = true
    ) -> UUID? {
        // Routing goes through the command-spec system: decode the
        // event once, then ask whether it dispatches `.addDrawerPane`
        // in the `.emptyDrawer` context. The raw-character "P"
        // alternate is empty-drawer only; cmd-shift-D reaches this
        // path when the drawer is open and empty.
        guard
            atom(\.managementLayer).isActive == false,
            ShortcutDecoder.shortcut(for: trigger, in: .emptyDrawer) == .addDrawerPane
        else {
            return nil
        }
        // Raw-character alternates must never be intercepted while
        // text input owns focus. Modified shortcuts may fire from
        // performKeyEquivalent even when a text field is focused.
        if requiresNeutralFocus, rawCharacterHasTextResponder(for: event) {
            return nil
        }

        guard
            case .emptyDrawer(let parentPaneId) = normalizedWorkspaceNavigationScopeState(),
            store.paneAtom.pane(parentPaneId)?.drawer?.paneIds.isEmpty == true
        else {
            Self.logger.warning(
                "empty drawer shortcut ignored because navigation scope and pane drawer state disagree")
            return nil
        }
        return parentPaneId
    }

    private func rawCharacterHasTextResponder(for event: NSEvent) -> Bool {
        let eventWindow = event.window ?? windowForRawCharacterEvent(event)
        let responders = [
            eventWindow?.firstResponder,
            view.window?.firstResponder,
        ]
        return responders.contains { !Self.isNeutralResponderForRawCharacter($0) }
    }

    private func windowForRawCharacterEvent(_ event: NSEvent) -> NSWindow? {
        guard event.windowNumber > 0 else { return nil }

        let application = NSApplication.shared
        return application.window(withWindowNumber: event.windowNumber)
            ?? application.windows.first { $0.windowNumber == event.windowNumber }
    }

    /// A responder is "neutral" for raw character keystrokes when it
    /// will NOT consume the keystroke as text input. NSText (and its
    /// subclasses NSTextView / NSTextField field editor) absorb typed
    /// characters; everything else is considered neutral.
    static func isNeutralResponderForRawCharacter(_ responder: NSResponder?) -> Bool {
        guard let responder else { return true }
        return !(responder is NSText)
    }

    private func canExecuteContextualCommand(_ command: AppCommand) -> Bool {
        switch command {
        case .addDrawerPane, .toggleDrawer:
            return activeMainPaneId() != nil
        case .closeDrawerPane:
            guard let parentPaneId = activeMainPaneId() else { return false }
            return visibleActiveDrawerPaneId(for: parentPaneId) != nil
        default:
            return false
        }
    }

    // MARK: - New Tab

    /// Create a new empty tab rooted at the first watched folder, or the user's
    /// home directory when no watched folder exists yet.
    private func addNewTab() {
        let launchDirectory =
            store.repositoryTopologyAtom.watchedPaths.first?.path
            ?? FileManager.default.homeDirectoryForCurrentUser
        dispatchAction(.openFloatingTerminal(launchDirectory: launchDirectory, title: nil))
    }

    // MARK: - Terminal Management

    func openTerminal(for worktree: Worktree, in _: Repo) {
        dispatchAction(.openWorktree(worktreeId: worktree.id))
    }

    func openNewTerminal(for worktree: Worktree, in _: Repo) {
        dispatchAction(.openNewTerminalInTab(worktreeId: worktree.id, launchDirectory: nil, title: nil))
    }

    func openWorktreeInPane(for worktree: Worktree, in _: Repo) {
        dispatchAction(.openWorktreeInPane(worktreeId: worktree.id))
    }

    func closeTerminal(for worktreeId: UUID) {
        // Find the tab containing this worktree
        guard
            let tab = store.tabLayoutAtom.tabs.first(where: { tab in
                tab.allPaneIds.contains { id in
                    store.paneAtom.pane(id)?.worktreeId == worktreeId
                }
            })
        else { return }

        guard
            let matchedPaneId = tab.allPaneIds.first(where: { id in
                store.paneAtom.pane(id)?.worktreeId == worktreeId
            })
        else { return }
        dispatchAction(.closePane(tabId: tab.id, paneId: matchedPaneId))
    }

    func closeActiveTab() {
        guard let activeId = store.tabLayoutAtom.activeTabId else { return }
        dispatchAction(.closeTab(tabId: activeId))
    }

    func selectTab(at index: Int) {
        let tabs = store.tabLayoutAtom.tabs
        guard index >= 0, index < tabs.count else { return }
        handlePaneFocusTrigger(.command(.selectTab(tabs[index].id)))
    }

    // MARK: - Validated Action Pipeline

    /// Central entry point: validates a PaneActionCommand and executes it if valid.
    /// All input sources (keyboard, menu, drag-drop, commands) converge here.
    private func dispatchAction(_ action: PaneActionCommand) {
        let snapshot = WorkspaceCommandResolver.snapshot(
            from: store.tabLayoutAtom.tabs,
            activeTabId: store.tabLayoutAtom.activeTabId,
            isManagementLayerActive: atom(\.managementLayer).isActive,
            knownWorktreeIds: Set(store.repositoryTopologyAtom.repos.flatMap(\.worktrees).map(\.id)),
            drawerParentByPaneId: drawerParentByPaneId(),
            drawerLayoutByParentPaneId: drawerLayoutByParentPaneId(),
            visiblePaneIds: { [arrangementView] tab in
                arrangementView.activeVisiblePaneIds(forTab: tab.id)
            }
        )

        switch WorkspaceCommandValidator.validate(action, state: snapshot) {
        case .success:
            executor.execute(action)
            syncFocusOwnerAfterValidatedAction(action)
        case .failure(let error):
            ghosttyLogger.warning("Action rejected: \(error)")
        }
    }

    private func syncFocusOwnerAfterValidatedAction(_ action: PaneActionCommand) {
        switch action {
        case .addDrawerPane(let parentPaneId),
            .removeDrawerPane(let parentPaneId, _),
            .toggleDrawer(let parentPaneId),
            .setActiveDrawerPane(let parentPaneId, _),
            .insertDrawerPane(let parentPaneId, _, _, _),
            .moveDrawerPane(let parentPaneId, _, _, _),
            .minimizeDrawerPane(let parentPaneId, _),
            .expandDrawerPane(let parentPaneId, _):
            syncFocusOwnerAfterDrawerMutation(parentPaneId: parentPaneId)
        case .detachDrawerPane:
            workspaceFocusController.setNavigationScope(.mainRow)
            atom(\.workspaceFocusOwner).focusMainPane(activeMainPaneId())
        default:
            break
        }
    }

    // MARK: - Tab Commands

    func executeTabContextMenuCommand(_ command: AppCommand, tabId: UUID) {
        tabBarInteractionController.handleTabCommand(command, tabId: tabId)
    }

    func popoverDidClose(_ notification: Notification) {
        if paneAuxiliaryCommandControllerStorage?.handlePopoverDidClose(notification) == true {
            return
        }

        _ = tabBarInteractionController.handlePopoverDidClose(notification)
    }

    // MARK: - Process Termination

    func handleTerminalProcessTerminated(paneId: UUID) {
        if closeTransitionCoordinator.closingPaneIds.contains(paneId) {
            return
        }
        if let pane = store.paneAtom.pane(paneId) {
            AppEventBus.post(.terminalProcessTerminationHandled(paneId: paneId))
            if let parentPaneId = pane.parentPaneId,
                let parentTab = store.tabLayoutAtom.tabContaining(paneId: parentPaneId)
            {
                dispatchAction(.closePane(tabId: parentTab.id, paneId: paneId))
                return
            }

            if let tab = store.tabLayoutAtom.tabContaining(paneId: paneId) {
                dispatchAction(.closePane(tabId: tab.id, paneId: paneId))
                return
            }

            RestoreTrace.log(
                "PaneTabViewController.handleTerminalProcessTerminated deferredNoop pane=\(paneId) reason=orphanedPane"
            )
            return
        }

        RestoreTrace.log(
            "PaneTabViewController.handleTerminalProcessTerminated deferredNoop pane=\(paneId) reason=notInAnyTab"
        )
    }

    private func handleExtractPaneRequested(tabId: UUID, paneId: UUID, targetTabIndex: Int?) {
        tabBarInteractionController.handleExtractPaneRequested(
            tabId: tabId,
            paneId: paneId,
            targetTabIndex: targetTabIndex
        )
    }

    private func dispatchMovePaneToTab(sourcePaneId: UUID, sourceTabId: UUID?, targetTabId: UUID) {
        tabBarInteractionController.dispatchMovePaneToTab(
            sourcePaneId: sourcePaneId,
            sourceTabId: sourceTabId,
            targetTabId: targetTabId
        )
    }

    // MARK: - Undo Close Tab

    private func handleUndoCloseTab() {
        executor.undoCloseTab()
    }

    // MARK: - Refocus Active Pane

    func refocusActivePane() {
        requestPaneRefocus(.explicit)
    }

    // MARK: - WorkspaceCommandHandling Conformance

    func execute(_ command: AppCommand) {
        if handlePaneFocusCommand(command) {
            return
        }

        if handleTerminalRuntimeCommand(command) {
            return
        }

        // Try the validated pipeline for pane/tab structural actions
        if let action = WorkspaceCommandResolver.resolve(
            command: command,
            tabs: store.tabLayoutAtom.tabs,
            activeTabId: store.tabLayoutAtom.activeTabId,
            visiblePaneIds: { [arrangementView] tab in
                arrangementView.activeVisiblePaneIds(forTab: tab.id)
            }
        ) {
            dispatchAction(action)
            return
        }

        if handleManagementCommand(command) {
            return
        }

        if handleArrangementCommand(command) {
            return
        }

        handleDirectCommand(command)
    }

    private func handleArrangementCommand(_ command: AppCommand) -> Bool {
        switch command {
        case .switchArrangement:
            requestArrangementPanel()
            return true
        case .previousArrangement:
            switchActiveArrangement(delta: -1)
            return true
        case .nextArrangement, .cycleArrangement:
            switchActiveArrangement(delta: 1)
            return true
        default:
            return false
        }
    }

    private func handleTerminalRuntimeCommand(_ command: AppCommand) -> Bool {
        guard let paneId = focusedTerminalCommandTargetPaneId() else { return false }
        return dispatchTerminalRuntimeCommand(command, paneId: paneId)
    }

    private func dispatchTerminalRuntimeCommand(_ command: AppCommand, paneId: UUID) -> Bool {
        let runtimeCommand: RuntimeCommand
        switch command {
        case .scrollToBottom:
            runtimeCommand = .terminal(.scrollToBottom)
        case .scrollPageUp:
            runtimeCommand = .terminal(.scrollPageUp)
        case .jumpToPreviousPrompt:
            runtimeCommand = .terminal(.jumpToPrompt(delta: -1))
        case .jumpToNextPrompt:
            runtimeCommand = .terminal(.jumpToPrompt(delta: 1))
        default:
            return false
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = await self.executor.dispatchRuntimeCommand(runtimeCommand, target: .pane(PaneId(uuid: paneId)))
        }
        return true
    }

    private func handleTargetedTerminalRuntimeCommand(
        _ command: AppCommand,
        target targetId: UUID,
        targetType: SearchItemType
    ) -> Bool {
        guard isPaneTargetType(targetType), canExecuteTargetedTerminalRuntimeCommand(command, target: targetId) else {
            return false
        }
        return dispatchTerminalRuntimeCommand(command, paneId: targetId)
    }

    private func canExecuteTargetedTerminalRuntimeCommand(
        _ command: AppCommand,
        target targetId: UUID
    ) -> Bool {
        guard AppShortcutDispatchPolicy.isTerminalRuntimeCommand(command),
            let pane = store.paneAtom.pane(targetId)
        else {
            return false
        }
        guard case .terminal = pane.content else { return false }
        return true
    }

    private func isPaneTargetType(_ targetType: SearchItemType) -> Bool {
        targetType == .pane || targetType == .floatingTerminal
    }

    private func focusedTerminalCommandTargetPaneId() -> UUID? {
        let candidatePaneId: UUID?
        switch normalizedWorkspaceNavigationScopeState() {
        case .mainPane(let mainPaneId):
            candidatePaneId = mainPaneId ?? activeMainPaneId()
        case .emptyDrawer(let parentPaneId):
            candidatePaneId = parentPaneId
        case .drawerPane(_, let drawerPaneId):
            candidatePaneId = drawerPaneId
        }

        guard
            let candidatePaneId,
            let pane = store.paneAtom.pane(candidatePaneId),
            case .terminal = pane.content
        else {
            return nil
        }
        return candidatePaneId
    }

    private func handleManagementCommand(_ command: AppCommand) -> Bool {
        managementLayerCommandController.handleManagementCommand(command)
    }

    private func handleDirectCommand(_ command: AppCommand) {
        let paneAuxiliaryCommandController = ensurePaneAuxiliaryCommandController()
        if paneAuxiliaryCommandController.handlePaneLocationCommand(command) {
            return
        }
        if paneAuxiliaryCommandController.handlePaneInboxCommand(command) {
            return
        }

        switch command {
        case .newTab:
            addNewTab()

        case .undoCloseTab:
            handleUndoCloseTab()
        case .renameTab:
            guard let activeTabId = store.tabLayoutAtom.activeTabId else { break }
            tabBarInteractionController.requestTabRenamePresentation(for: activeTabId)
        case .watchFolder, .toggleSidebar, .filterSidebar,
            .showInboxNotifications, .toggleInboxNotificationSort,
            .clearReadInboxNotifications, .clearAllInboxNotifications,
            .showPaneInboxNotifications, .clearPaneInboxNotifications, .showWorktreeSidebar,
            .signInGitHub, .signInGoogle:
            break
        case .enterDrawer:
            managementLayerCommandController.enterDrawerFromActivePane()
        case .focusDrawerPaneUp, .focusDrawerPaneLeft, .focusDrawerPaneDown, .focusDrawerPaneRight:
            managementLayerCommandController.moveDrawerFocus(command)
        case .addDrawerPane:
            guard let tabId = store.tabLayoutAtom.activeTabId,
                let tab = store.tabLayoutAtom.tab(tabId),
                let paneId = tab.activePaneId
            else { break }
            dispatchAction(.addDrawerPane(parentPaneId: paneId))

        case .toggleDrawer:
            guard let tabId = store.tabLayoutAtom.activeTabId,
                let tab = store.tabLayoutAtom.tab(tabId),
                let paneId = tab.activePaneId
            else { break }
            dispatchAction(.toggleDrawer(paneId: paneId))
            handlePaneFocusTrigger(.drawer(.toggle(parentPaneId: paneId)))
            syncFocusOwnerAfterDrawerMutation(parentPaneId: paneId)

        case .closeDrawerPane:
            guard let tabId = store.tabLayoutAtom.activeTabId,
                let tab = store.tabLayoutAtom.tab(tabId),
                let paneId = tab.activePaneId,
                store.paneAtom.pane(paneId)?.drawer != nil,
                let activeDrawerPaneId = arrangementView.drawerView(forParent: paneId)?.activeChildId
            else { break }
            dispatchAction(.closePane(tabId: tabId, paneId: activeDrawerPaneId))

        case .saveArrangement:
            guard let tabId = store.tabLayoutAtom.activeTabId,
                let tab = store.tabLayoutAtom.tab(tabId)
            else { break }
            let name = ArrangementDerived.nextCustomArrangementName(existing: tab.arrangements)
            dispatchAction(.createArrangement(tabId: tabId, name: name))

        case .newTerminalInTab:
            guard let activeTabId = store.tabLayoutAtom.activeTabId,
                let tab = store.tabLayoutAtom.tab(activeTabId),
                let targetPaneId = tab.activePaneId
            else { break }
            dispatchAction(
                .insertPane(
                    source: .newTerminal,
                    targetTabId: activeTabId,
                    targetPaneId: targetPaneId,
                    direction: .right,
                    sizingMode: .halveTarget
                ))
        case .newFloatingTerminal:
            let activePaneCwd = store.tabLayoutAtom.activeTabId
                .flatMap { store.tabLayoutAtom.tab($0)?.activePaneId }
                .flatMap { store.paneAtom.pane($0)?.metadata.facets.cwd }
            dispatchAction(.openFloatingTerminal(launchDirectory: activePaneCwd, title: nil))
        case .openWebview:
            executor.openWebview()
        case .detachDrawerPane:
            guard case .drawerPane(let parentPaneId, let drawerPaneId) = normalizedWorkspaceNavigationScopeState()
            else {
                break
            }
            dispatchAction(.detachDrawerPane(parentPaneId: parentPaneId, drawerPaneId: drawerPaneId))
        case .showCommandBarEverything, .showCommandBarCommands,
            .showCommandBarPanes, .showCommandBarRepos,
            .openNewTerminalInTab, .openWorktree, .openWorktreeInPane,
            .switchArrangement, .deleteArrangement, .renameArrangement,
            .navigateDrawerPane, .movePaneToTab,
            .selectTab, .focusPane:
            return  // Handled via drill-in (target selection in command bar)
        default:
            Self.logger.warning(
                "PaneTabViewController.handleDirectCommand ignored unhandled command=\(String(describing: command), privacy: .public)"
            )
        }
    }

    func execute(_ command: AppCommand, target: UUID, targetType: SearchItemType) {
        if command == .selectTab, targetType == .tab {
            handlePaneFocusTrigger(.command(.selectTab(target)))
            return
        }

        if ensurePaneAuxiliaryCommandController().handleTargetedPaneInboxCommand(
            command,
            target: target,
            targetType: targetType
        ) {
            return
        }

        if command == .focusPane && (targetType == .pane || targetType == .floatingTerminal) {
            focusTargetedPane(target)
            return
        }

        if handleTargetedTerminalRuntimeCommand(command, target: target, targetType: targetType) {
            return
        }

        if let action = targetedAction(command: command, target: target, targetType: targetType) {
            dispatchAction(action)
            return
        }

        // Targeted non-pane commands (e.g. from command bar)
        switch (command, targetType) {
        case (.renameTab, .tab):
            guard store.tabLayoutAtom.tab(target) != nil else {
                Self.logger.warning("renameTab targeted command ignored: tab \(target) not found")
                return
            }
            tabBarInteractionController.requestTabRenamePresentation(for: target)
        case (.renameArrangement, .tab):
            guard
                let tab = store.tabLayoutAtom.tabs.first(where: { tab in
                    tab.arrangements.contains(where: { $0.id == target })
                }),
                let arrangement = tab.arrangements.first(where: { $0.id == target })
            else {
                Self.logger.warning("renameArrangement targeted command ignored: arrangement \(target) not found")
                return
            }
            guard !arrangement.isDefault else {
                Self.logger.warning("renameArrangement targeted command ignored: cannot rename default arrangement")
                return
            }
            if store.tabLayoutAtom.activeTabId != tab.id {
                dispatchAction(.selectTab(tabId: tab.id))
            }
            arrangementInlineRenameState.beginEditing(
                arrangementId: arrangement.id,
                currentName: arrangement.name,
                isDefault: arrangement.isDefault
            )
        default:
            Self.logger.warning(
                "Targeted command ignored for unsupported target pair command=\(String(describing: command), privacy: .public) targetType=\(targetType.rawValue, privacy: .public)"
            )
        }
    }

    private func focusTargetedPane(_ paneId: UUID) {
        if let parentPaneId = store.paneAtom.pane(paneId)?.parentPaneId {
            focusTargetedDrawerPane(parentPaneId: parentPaneId, drawerPaneId: paneId)
            return
        }

        guard let tab = store.tabLayoutAtom.tabContaining(paneId: paneId) else { return }
        handlePaneFocusTrigger(.command(.focusPane(tabId: tab.id, paneId: paneId)))
    }

    private func revealArrangementContainingPane(tabId: UUID, paneId: UUID) {
        guard let tab = store.tabLayoutAtom.tab(tabId),
            !tab.activeArrangement.layout.contains(paneId),
            let containingArrangement = tab.arrangements.first(where: { $0.layout.contains(paneId) })
        else {
            return
        }

        store.tabLayoutAtom.switchArrangement(to: containingArrangement.id, inTab: tabId)
    }

    private func focusTargetedDrawerPane(parentPaneId: UUID, drawerPaneId: UUID) {
        guard
            let tab = store.tabLayoutAtom.tabContaining(paneId: parentPaneId),
            store.paneAtom.pane(parentPaneId)?.drawer?.paneIds.contains(drawerPaneId) == true
        else {
            return
        }

        handlePaneFocusTrigger(.command(.focusPane(tabId: tab.id, paneId: parentPaneId)))
        if store.paneAtom.pane(parentPaneId)?.drawer?.isExpanded == false {
            dispatchAction(.toggleDrawer(paneId: parentPaneId))
        }
        handlePaneFocusTrigger(.drawer(.selectPane(parentPaneId: parentPaneId, drawerPaneId: drawerPaneId)))
    }

    private func focusMainPaneOrdinal(command: AppCommand) -> Bool {
        guard let target = resolveMainPaneOrdinalTarget(for: command) else { return false }
        if target.tab.activeMinimizedPaneIds.contains(target.paneId) {
            dispatchAction(.expandPane(tabId: target.tab.id, paneId: target.paneId))
        }
        if let zoomedPaneId = target.tab.zoomedPaneId, zoomedPaneId != target.paneId {
            dispatchAction(.toggleSplitZoom(tabId: target.tab.id, paneId: target.paneId))
        }
        handlePaneFocusTrigger(.command(.focusPane(tabId: target.tab.id, paneId: target.paneId)))
        return true
    }

    private func resolveMainPaneOrdinalTarget(for command: AppCommand) -> (tab: Tab, paneId: UUID)? {
        guard
            let ordinal = mainPaneOrdinal(for: command),
            let activeTabId = store.tabLayoutAtom.activeTabId,
            let tab = store.tabLayoutAtom.tab(activeTabId),
            let paneId = PaneOrdinalMap(orderedPaneIds: tab.activePaneIds).paneId(forOrdinal: ordinal)
        else {
            return nil
        }
        return (tab, paneId)
    }

    private func mainPaneOrdinal(for command: AppCommand) -> Int? {
        AppCommand.focusPaneCommands.firstIndex(of: command).map { $0 + 1 }
    }

    private func requestArrangementPanel() {
        guard let activeTabId = store.tabLayoutAtom.activeTabId else { return }
        guard
            let workspaceWindowId =
                workspaceWindowId
                ?? windowLifecycleStore.focusedWindowId
                ?? windowLifecycleStore.keyWindowId
        else { return }
        arrangementPanelPresentation.present(
            tabId: activeTabId,
            workspaceWindowId: workspaceWindowId
        )
    }

    private func switchActiveArrangement(delta: Int) {
        guard
            let activeTabId = store.tabLayoutAtom.activeTabId,
            let tab = store.tabLayoutAtom.tab(activeTabId),
            tab.arrangements.count > 1,
            let activeIndex = tab.arrangements.firstIndex(where: { $0.id == tab.activeArrangementId })
        else {
            return
        }

        let count = tab.arrangements.count
        let nextIndex = (activeIndex + delta + count) % count
        let arrangement = tab.arrangements[nextIndex]
        dispatchAction(.switchArrangement(tabId: tab.id, arrangementId: arrangement.id))
    }

    private func handlePaneFocusCommand(_ command: AppCommand) -> Bool {
        switch command {
        case .focusPane1, .focusPane2, .focusPane3, .focusPane4, .focusPane5,
            .focusPane6, .focusPane7, .focusPane8, .focusPane9:
            return focusMainPaneOrdinal(command: command)
        case .focusDrawerPane1, .focusDrawerPane2, .focusDrawerPane3, .focusDrawerPane4,
            .focusDrawerPane5, .focusDrawerPane6, .focusDrawerPane7, .focusDrawerPane8,
            .focusDrawerPane9:
            return managementLayerCommandController.focusDrawerPaneOrdinal(command: command)
        case .focusPaneLeft, .focusPaneRight, .focusPaneUp, .focusPaneDown, .focusNextPane, .focusPrevPane:
            guard let trigger = makePaneKeyboardFocusTrigger(for: command) else { return false }
            handlePaneFocusTrigger(.keyboard(trigger))
            return true
        case .nextTab, .prevTab,
            .selectTab1, .selectTab2, .selectTab3, .selectTab4, .selectTab5,
            .selectTab6, .selectTab7, .selectTab8, .selectTab9:
            guard let tabId = resolvePaneFocusTabSelectionTarget(for: command) else { return false }
            handlePaneFocusTrigger(.command(.selectTab(tabId)))
            return true
        default:
            return false
        }
    }

    private func makePaneKeyboardFocusTrigger(for command: AppCommand) -> PaneKeyboardFocusTrigger? {
        guard
            let activeTabId = store.tabLayoutAtom.activeTabId,
            let tab = store.tabLayoutAtom.tab(activeTabId),
            let activePaneId = tab.activePaneId
        else {
            Self.logger.warning(
                "Pane keyboard focus trigger dropped reason=activeSelectionUnavailable command=\(String(describing: command), privacy: .public)"
            )
            return nil
        }

        let targetPaneId: UUID?
        switch command {
        case .focusPaneLeft:
            targetPaneId = tab.neighborPaneId(of: activePaneId, direction: .left)
        case .focusPaneRight:
            targetPaneId = tab.neighborPaneId(of: activePaneId, direction: .right)
        case .focusPaneUp:
            targetPaneId = tab.neighborPaneId(of: activePaneId, direction: .up)
        case .focusPaneDown:
            targetPaneId = tab.neighborPaneId(of: activePaneId, direction: .down)
        case .focusNextPane:
            targetPaneId = tab.nextPaneId(after: activePaneId)
        case .focusPrevPane:
            targetPaneId = tab.previousPaneId(before: activePaneId)
        default:
            targetPaneId = nil
        }

        guard let targetPaneId else {
            Self.logger.warning(
                "Pane keyboard focus trigger dropped reason=neighborUnavailable command=\(String(describing: command), privacy: .public) activePane=\(activePaneId.uuidString, privacy: .public)"
            )
            return nil
        }
        return .moveToPane(
            tabId: activeTabId,
            paneId: targetPaneId,
            paneKind: PaneFocusContext.PaneKind(content: store.paneAtom.pane(targetPaneId)?.content)
        )
    }

    private func resolvePaneFocusTabSelectionTarget(for command: AppCommand) -> UUID? {
        let tabs = store.tabLayoutAtom.tabs
        guard !tabs.isEmpty else {
            Self.logger.warning(
                "Pane tab selection trigger dropped reason=noTabs command=\(String(describing: command), privacy: .public)"
            )
            return nil
        }

        switch command {
        case .nextTab:
            guard
                let activeTabId = store.tabLayoutAtom.activeTabId,
                let currentIndex = tabs.firstIndex(where: { $0.id == activeTabId }),
                !tabs.isEmpty
            else {
                Self.logger.warning(
                    "Pane tab selection trigger dropped reason=activeTabUnavailable command=\(String(describing: command), privacy: .public)"
                )
                return nil
            }
            return tabs[(currentIndex + 1) % tabs.count].id
        case .prevTab:
            guard
                let activeTabId = store.tabLayoutAtom.activeTabId,
                let currentIndex = tabs.firstIndex(where: { $0.id == activeTabId }),
                !tabs.isEmpty
            else {
                Self.logger.warning(
                    "Pane tab selection trigger dropped reason=activeTabUnavailable command=\(String(describing: command), privacy: .public)"
                )
                return nil
            }
            return tabs[(currentIndex - 1 + tabs.count) % tabs.count].id
        case .selectTab1:
            return tabs.isEmpty ? nil : tabs[0].id
        case .selectTab2:
            return tabs.count > 1 ? tabs[1].id : nil
        case .selectTab3:
            return tabs.count > 2 ? tabs[2].id : nil
        case .selectTab4:
            return tabs.count > 3 ? tabs[3].id : nil
        case .selectTab5:
            return tabs.count > 4 ? tabs[4].id : nil
        case .selectTab6:
            return tabs.count > 5 ? tabs[5].id : nil
        case .selectTab7:
            return tabs.count > 6 ? tabs[6].id : nil
        case .selectTab8:
            return tabs.count > 7 ? tabs[7].id : nil
        case .selectTab9:
            return tabs.count > 8 ? tabs[8].id : nil
        default:
            return nil
        }
    }

    private func targetedAction(
        command: AppCommand,
        target: UUID,
        targetType: SearchItemType
    ) -> PaneActionCommand? {
        if let repositoryAction = targetedRepositoryAction(command: command, target: target, targetType: targetType) {
            return repositoryAction
        }

        switch (command, targetType) {
        case (.selectTab, .tab):
            return .selectTab(tabId: target)
        case (.closeTab, .tab):
            return .closeTab(tabId: target)
        case (.breakUpTab, .tab):
            return .breakUpTab(tabId: target)
        case (.closePane, .pane), (.closePane, .floatingTerminal):
            guard let tab = store.tabLayoutAtom.tabs.first(where: { $0.activePaneIds.contains(target) }) else {
                return nil
            }
            return .closePane(tabId: tab.id, paneId: target)
        case (.extractPaneToTab, .pane), (.extractPaneToTab, .floatingTerminal):
            guard let tab = store.tabLayoutAtom.tabs.first(where: { $0.activePaneIds.contains(target) }) else {
                return nil
            }
            return .extractPaneToTab(tabId: tab.id, paneId: target)
        case (.movePaneToTab, .tab):
            guard
                let activeTabId = store.tabLayoutAtom.activeTabId,
                let activePaneId = store.tabLayoutAtom.tab(activeTabId)?.activePaneId
            else { return nil }
            return tabBarInteractionController.makeMovePaneToTabAction(
                sourcePaneId: activePaneId,
                sourceTabId: activeTabId,
                targetTabId: target
            )
        case (.switchArrangement, .tab):
            guard let tabId = store.tabLayoutAtom.activeTabId else { return nil }
            return .switchArrangement(tabId: tabId, arrangementId: target)
        case (.deleteArrangement, .tab):
            guard let tabId = store.tabLayoutAtom.activeTabId else { return nil }
            return .removeArrangement(tabId: tabId, arrangementId: target)
        case (.navigateDrawerPane, .pane):
            guard let tabId = store.tabLayoutAtom.activeTabId,
                let tab = store.tabLayoutAtom.tab(tabId),
                let paneId = tab.activePaneId
            else { return nil }
            return .setActiveDrawerPane(parentPaneId: paneId, drawerPaneId: target)
        case (.detachDrawerPane, .pane):
            guard let parentPaneId = store.paneAtom.pane(target)?.parentPaneId else { return nil }
            return .detachDrawerPane(parentPaneId: parentPaneId, drawerPaneId: target)
        case (.addDrawerPane, .pane), (.addDrawerPane, .floatingTerminal):
            return .addDrawerPane(parentPaneId: target)
        case (.newTerminalInTab, .tab):
            guard let tab = store.tabLayoutAtom.tab(target), let targetPaneId = tab.activePaneId else { return nil }
            return .insertPane(
                source: .newTerminal,
                targetTabId: tab.id,
                targetPaneId: targetPaneId,
                direction: .right,
                sizingMode: .halveTarget
            )
        case (.renameArrangement, .tab):
            return nil
        default:
            return nil
        }
    }

    private func targetedRepositoryAction(
        command: AppCommand,
        target: UUID,
        targetType: SearchItemType
    ) -> PaneActionCommand? {
        switch (command, targetType) {
        case (.removeRepo, .repo):
            return .removeRepo(repoId: target)
        case (.openWorktree, .worktree):
            return .openWorktree(worktreeId: target)
        case (.openNewTerminalInTab, .worktree):
            return .openNewTerminalInTab(worktreeId: target, launchDirectory: nil, title: nil)
        case (.openWorktreeInPane, .worktree):
            return .openWorktreeInPane(worktreeId: target)
        default:
            return nil
        }
    }

    func executeExtractPaneToTab(tabId: UUID, paneId: UUID, targetTabIndex: Int?) {
        handleExtractPaneRequested(tabId: tabId, paneId: paneId, targetTabIndex: targetTabIndex)
    }

    func executeMovePaneToTab(sourcePaneId: UUID, sourceTabId: UUID?, targetTabId: UUID) {
        dispatchMovePaneToTab(
            sourcePaneId: sourcePaneId,
            sourceTabId: sourceTabId,
            targetTabId: targetTabId
        )
    }

    func canExecute(_ command: AppCommand, target: UUID, targetType: SearchItemType) -> Bool {
        if let canExecute = ensurePaneAuxiliaryCommandController().canExecuteTargetedPaneInboxCommand(
            command,
            target: target,
            targetType: targetType
        ) {
            return canExecute
        }

        if canExecuteTargetedTerminalRuntimeCommand(command, target: target),
            isPaneTargetType(targetType)
        {
            return true
        }

        if let action = targetedAction(command: command, target: target, targetType: targetType) {
            let snapshot = WorkspaceCommandResolver.snapshot(
                from: store.tabLayoutAtom.tabs,
                activeTabId: store.tabLayoutAtom.activeTabId,
                isManagementLayerActive: atom(\.managementLayer).isActive,
                knownRepoIds: Set(store.repositoryTopologyAtom.repos.map(\.id)),
                knownWorktreeIds: Set(store.repositoryTopologyAtom.repos.flatMap(\.worktrees).map(\.id)),
                drawerParentByPaneId: drawerParentByPaneId(),
                drawerLayoutByParentPaneId: drawerLayoutByParentPaneId(),
                visiblePaneIds: { [arrangementView] tab in
                    arrangementView.activeVisiblePaneIds(forTab: tab.id)
                }
            )
            if case .success = WorkspaceCommandValidator.validate(action, state: snapshot) {
                return true
            }
            return false
        }

        switch (command, targetType) {
        case (.renameTab, .tab):
            return store.tabLayoutAtom.tab(target) != nil
        case (.renameArrangement, .tab):
            guard
                let tab = store.tabLayoutAtom.tabs.first(where: { tab in
                    tab.arrangements.contains(where: { $0.id == target })
                }),
                let arrangement = tab.arrangements.first(where: { $0.id == target })
            else {
                return false
            }
            return !arrangement.isDefault
        default:
            return false
        }
    }

    func canExecute(_ command: AppCommand) -> Bool {
        if let canExecute = ensurePaneAuxiliaryCommandController().canExecuteDirectCommand(command) {
            return canExecute
        }

        switch command {
        case .managementLayerFocusLeft, .managementLayerFocusRight, .managementLayerEnterDrawer,
            .managementLayerExitDrawer, .managementLayerOpenDrawer,
            .managementLayerCreateTerminal, .managementLayerCreateBrowser, .managementLayerExit:
            return managementLayerCommandController.canExecuteManagementCommand(command)
        case .enterDrawer:
            return activeMainPaneId() != nil
        case .focusDrawerPaneUp, .focusDrawerPaneLeft, .focusDrawerPaneDown, .focusDrawerPaneRight:
            return managementLayerCommandController.canExecuteDrawerFocusCommand(command)
        case .focusDrawerPane1, .focusDrawerPane2, .focusDrawerPane3, .focusDrawerPane4,
            .focusDrawerPane5, .focusDrawerPane6, .focusDrawerPane7, .focusDrawerPane8,
            .focusDrawerPane9:
            return managementLayerCommandController.canExecuteDrawerOrdinalCommand(command)
        case .navigateDrawerPane:
            guard let parentPaneId = activeMainPaneId() else { return false }
            return !(store.paneAtom.pane(parentPaneId)?.drawer?.paneIds.isEmpty ?? true)
        case .detachDrawerPane:
            if case .drawerPane = normalizedWorkspaceNavigationScopeState() {
                return true
            }
            return false
        case .focusPaneLeft, .focusPaneRight, .focusPaneUp, .focusPaneDown, .focusNextPane, .focusPrevPane:
            return makePaneKeyboardFocusTrigger(for: command) != nil
        case .focusPane1, .focusPane2, .focusPane3, .focusPane4, .focusPane5,
            .focusPane6, .focusPane7, .focusPane8, .focusPane9:
            return resolveMainPaneOrdinalTarget(for: command) != nil
        case .nextTab, .prevTab,
            .selectTab1, .selectTab2, .selectTab3, .selectTab4, .selectTab5,
            .selectTab6, .selectTab7, .selectTab8, .selectTab9:
            return resolvePaneFocusTabSelectionTarget(for: command) != nil
        case .renameTab:
            return store.tabLayoutAtom.activeTabId != nil
        case .switchArrangement:
            return store.tabLayoutAtom.activeTabId != nil
        case .previousArrangement, .nextArrangement, .cycleArrangement:
            guard
                let activeTabId = store.tabLayoutAtom.activeTabId,
                let tab = store.tabLayoutAtom.tab(activeTabId)
            else {
                return false
            }
            return tab.arrangements.count > 1
        case .scrollToBottom, .scrollPageUp, .jumpToPreviousPrompt, .jumpToNextPrompt:
            return focusedTerminalCommandTargetPaneId() != nil
        case .addDrawerPane, .toggleDrawer, .closeDrawerPane:
            return canExecuteContextualCommand(command)
        default:
            break
        }

        // Try resolving — if it resolves, validate it
        if let action = WorkspaceCommandResolver.resolve(
            command: command,
            tabs: store.tabLayoutAtom.tabs,
            activeTabId: store.tabLayoutAtom.activeTabId,
            visiblePaneIds: { [arrangementView] tab in
                arrangementView.activeVisiblePaneIds(forTab: tab.id)
            }
        ) {
            let snapshot = WorkspaceCommandResolver.snapshot(
                from: store.tabLayoutAtom.tabs,
                activeTabId: store.tabLayoutAtom.activeTabId,
                isManagementLayerActive: atom(\.managementLayer).isActive,
                knownRepoIds: Set(store.repositoryTopologyAtom.repos.map(\.id)),
                knownWorktreeIds: Set(store.repositoryTopologyAtom.repos.flatMap(\.worktrees).map(\.id)),
                drawerParentByPaneId: drawerParentByPaneId(),
                drawerLayoutByParentPaneId: drawerLayoutByParentPaneId(),
                visiblePaneIds: { [arrangementView] tab in
                    arrangementView.activeVisiblePaneIds(forTab: tab.id)
                }
            )
            switch WorkspaceCommandValidator.validate(action, state: snapshot) {
            case .success: return true
            case .failure: return false
            }
        }
        return true
    }

}

#if DEBUG
    extension PaneTabViewController {
        var splitHostingViewForTesting: NSView? { activeTabHost()?.hostingView }
        var appLifecycleStoreForTesting: AppLifecycleAtom { appLifecycleStore }
        func tabHostViewForTesting(tabId: UUID) -> NSView? {
            ensureTabContentHostController().tabHostViewForTesting(tabId: tabId)
        }
        var paneRepresentableDismantleCountForTesting: Int {
            paneRepresentableDismantleCount
        }
        var managementNavigationScopeDescriptionForTesting: String {
            workspaceFocusController.navigationScopeDescriptionForTesting
        }
        func setManagementNavigationScopeToDrawerForTesting(parentPaneId: UUID) {
            workspaceFocusController.setNavigationScopeToDrawerForTesting(parentPaneId: parentPaneId)
        }
    }
#endif
