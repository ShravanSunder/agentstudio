import AppKit
import Foundation
import SwiftUI
import os

@MainActor
final class TabBarInteractionController {
    private static let logger = Logger(subsystem: "com.agentstudio", category: "TabBarInteractionController")

    private let store: WorkspaceStore
    private let tabBarAdapter: TabBarAdapter
    private let arrangementInlineRenameState: ArrangementInlineRenameState
    private let tabRenamePopoverState: TabRenamePopoverState
    private let windowLifecycleStore: WindowLifecycleAtom
    private let workspaceWindowId: UUID?
    private let dispatchAction: @MainActor (PaneActionCommand) -> Void
    private let handlePaneFocusTrigger: @MainActor (PaneFocusTrigger) -> Void
    private let addNewTab: @MainActor () -> Void
    private let openGitHubWebview: @MainActor () -> Void

    private weak var tabBarHostingView: DraggableTabBarHostingView?
    private weak var popoverDelegate: NSPopoverDelegate?
    private var tabRenamePopover: NSPopover?
    private var tabRenameTransientSurfaceToken: TransientKeyboardSurfaceToken?

    init(
        store: WorkspaceStore,
        tabBarAdapter: TabBarAdapter,
        arrangementInlineRenameState: ArrangementInlineRenameState,
        tabRenamePopoverState: TabRenamePopoverState,
        windowLifecycleStore: WindowLifecycleAtom,
        workspaceWindowId: UUID?,
        dispatchAction: @escaping @MainActor (PaneActionCommand) -> Void,
        handlePaneFocusTrigger: @escaping @MainActor (PaneFocusTrigger) -> Void,
        addNewTab: @escaping @MainActor () -> Void,
        openGitHubWebview: @escaping @MainActor () -> Void
    ) {
        self.store = store
        self.tabBarAdapter = tabBarAdapter
        self.arrangementInlineRenameState = arrangementInlineRenameState
        self.tabRenamePopoverState = tabRenamePopoverState
        self.windowLifecycleStore = windowLifecycleStore
        self.workspaceWindowId = workspaceWindowId
        self.dispatchAction = dispatchAction
        self.handlePaneFocusTrigger = handlePaneFocusTrigger
        self.addNewTab = addNewTab
        self.openGitHubWebview = openGitHubWebview
    }

    func makeTabBarHostingView(popoverDelegate: NSPopoverDelegate) -> DraggableTabBarHostingView {
        let tabBar = CustomTabBar(
            adapter: tabBarAdapter,
            arrangementInlineRenameState: arrangementInlineRenameState,
            onSelect: { [weak self] tabId in
                self?.handlePaneFocusTrigger(.tabClick(PaneTabClickFocusTrigger(targetTabId: tabId)))
            },
            onClose: { [weak self] tabId in
                self?.dispatchAction(.closeTab(tabId: tabId))
            },
            onCommand: { [weak self] command, tabId in
                self?.handleTabCommand(command, tabId: tabId)
            },
            onTabFramesChanged: { [weak self] frames in
                self?.tabBarHostingView?.updateTabFrames(frames)
            },
            onAdd: { [weak self] in
                self?.addNewTab()
            },
            onOpenGitHub: { [weak self] in
                self?.openGitHubWebview()
            },
            onPaneAction: { [weak self] action in
                self?.dispatchAction(action)
            },
            onSaveArrangement: { [weak self] tabId in
                guard let self, let tab = self.store.tabLayoutAtom.tab(tabId) else { return }
                let name = ArrangementDerived.nextCustomArrangementName(existing: tab.arrangements)
                self.dispatchAction(.createArrangement(tabId: tabId, name: name))
            },
            onOpenRepoInTab: {
                CommandDispatcher.shared.dispatch(.showCommandBarRepos)
            },
            workspaceWindowId: workspaceWindowId
        )

        let hostingView = DraggableTabBarHostingView(rootView: tabBar)
        self.popoverDelegate = popoverDelegate
        hostingView.configure(adapter: tabBarAdapter) { [weak self] fromId, toIndex in
            self?.handleTabReorder(fromId: fromId, toIndex: toIndex)
        }
        hostingView.dragPayloadProvider = { [weak self] tabId in
            self?.createDragPayload(for: tabId)
        }
        hostingView.onSelect = { [weak self] tabId in
            self?.handlePaneFocusTrigger(.tabClick(PaneTabClickFocusTrigger(targetTabId: tabId)))
        }
        hostingView.expandedDrawerParentIdForTab = { [weak self] tabId in
            guard let self else { return nil }
            return DrawerDragOwnershipPolicy.expandedDrawerParentPaneId(
                tabId: tabId,
                tabLayoutAtom: self.store.tabLayoutAtom,
                paneAtom: self.store.paneAtom
            )
        }
        hostingView.onAutoDismissDrawerForDrag = { [weak self] _, drawerParentPaneId in
            self?.dispatchAction(.toggleDrawer(paneId: drawerParentPaneId))
        }
        tabBarHostingView = hostingView
        return hostingView
    }

    func handleTabCommand(_ command: AppCommand, tabId: UUID) {
        if command == .renameTab {
            guard store.tabLayoutAtom.tab(tabId) != nil else {
                Self.logger.warning("renameTab context menu command ignored: tab \(tabId) not found")
                return
            }
            requestTabRenamePresentation(for: tabId)
            return
        }

        let action: PaneActionCommand?

        switch command {
        case .closeTab:
            action = .closeTab(tabId: tabId)
        case .breakUpTab:
            action = .breakUpTab(tabId: tabId)
        case .equalizePanes:
            action = .equalizePanes(tabId: tabId)
        case .splitRight, .splitLeft:
            guard let tab = store.tabLayoutAtom.tab(tabId),
                let paneId = tab.activePaneId
            else { return }
            let direction: SplitNewDirection = {
                switch command {
                case .splitRight: return .right
                case .splitLeft: return .left
                default: return .right
                }
            }()
            action = .insertPane(
                source: .newTerminal,
                targetTabId: tabId,
                targetPaneId: paneId,
                direction: direction,
                sizingMode: .halveTarget
            )
        case .newFloatingTerminal:
            action = nil
        case .switchArrangement, .deleteArrangement, .renameArrangement:
            action = nil
        case .saveArrangement:
            guard let tab = store.tabLayoutAtom.tab(tabId) else { return }
            let name = ArrangementDerived.nextCustomArrangementName(existing: tab.arrangements)
            action = .createArrangement(tabId: tabId, name: name)
        default:
            action = nil
        }

        if let action {
            dispatchAction(action)
        }
    }

    func requestTabRenamePresentation(for tabId: UUID) {
        guard store.tabLayoutAtom.tab(tabId) != nil else {
            Self.logger.warning("renameTab presentation ignored: tab \(tabId) not found")
            return
        }
        if store.tabLayoutAtom.activeTabId != tabId {
            dispatchAction(.selectTab(tabId: tabId))
        }

        tabRenamePopoverState.dismiss()

        RunLoop.main.perform(inModes: [.default]) { [weak self] in
            MainActor.assumeIsolated {
                self?.presentTabRenamePopover(for: tabId)
            }
        }
    }

    func closeTabRenamePopover(updateState: Bool = true) {
        dismissTabRenameTransientSurface()
        let popover = tabRenamePopover
        tabRenamePopover = nil
        popover?.delegate = nil
        popover?.close()
        if updateState {
            tabRenamePopoverState.dismiss()
        }
    }

    func handlePopoverDidClose(_ notification: Notification) -> Bool {
        guard notification.object as? NSPopover === tabRenamePopover else { return false }
        dismissTabRenameTransientSurface()
        tabRenamePopover = nil
        tabRenamePopoverState.dismiss()
        return true
    }

    func handleExtractPaneRequested(tabId: UUID, paneId: UUID, targetTabIndex: Int?) {
        if let sourceTab = store.tabLayoutAtom.tab(tabId),
            sourceTab.activePaneIds.count == 1
        {
            if let targetTabIndex {
                dispatchAction(.reorderTab(tabId: tabId, newIndex: targetTabIndex))
            }
            return
        }

        let tabCountBefore = store.tabLayoutAtom.tabs.count
        dispatchAction(.extractPaneToTab(tabId: tabId, paneId: paneId))

        guard let targetTabIndex,
            store.tabLayoutAtom.tabs.count == tabCountBefore + 1,
            let extractedTabId = store.tabLayoutAtom.activeTabId
        else {
            return
        }

        dispatchAction(.reorderTab(tabId: extractedTabId, newIndex: targetTabIndex))
    }

    func dispatchMovePaneToTab(sourcePaneId: UUID, sourceTabId: UUID?, targetTabId: UUID) {
        guard
            let action = makeMovePaneToTabAction(
                sourcePaneId: sourcePaneId,
                sourceTabId: sourceTabId,
                targetTabId: targetTabId
            )
        else { return }
        dispatchAction(action)
    }

    func makeMovePaneToTabAction(
        sourcePaneId: UUID,
        sourceTabId: UUID?,
        targetTabId: UUID
    ) -> PaneActionCommand? {
        let resolvedSourceTabId: UUID? =
            if let sourceTabId, store.tabLayoutAtom.tab(sourceTabId)?.activePaneIds.contains(sourcePaneId) == true {
                sourceTabId
            } else {
                store.tabLayoutAtom.tabs.first(where: { $0.activePaneIds.contains(sourcePaneId) })?.id
            }

        guard let resolvedSourceTabId else { return nil }
        guard resolvedSourceTabId != targetTabId else { return nil }
        guard let targetTab = store.tabLayoutAtom.tab(targetTabId) else { return nil }
        guard let targetPaneId = targetTab.activePaneId ?? targetTab.activePaneIds.first else { return nil }

        return .movePaneAcrossTabs(
            CrossTabPaneMoveRequest(
                paneId: sourcePaneId,
                sourceTabId: resolvedSourceTabId,
                destTabId: targetTabId,
                targetPaneId: targetPaneId,
                direction: .horizontal,
                position: .after
            )
        )
    }

    private func presentTabRenamePopover(for tabId: UUID) {
        guard let tab = store.tabLayoutAtom.tab(tabId) else {
            Self.logger.warning("renameTab presentation ignored after defer: tab \(tabId) not found")
            return
        }

        closeTabRenamePopover(updateState: false)
        tabRenamePopoverState.present(for: tabId)

        guard let tabBarHostingView, tabBarHostingView.window != nil else {
            return
        }

        let popover = NSPopover()
        popover.behavior = .semitransient
        popover.delegate = popoverDelegate
        popover.contentViewController = NSHostingController(
            rootView: TabRenamePopover(
                currentTitle: tabBarAdapter.tabs.first(where: { $0.id == tabId })?.displayTitle ?? tab.name,
                onCommit: { [weak self] name in
                    guard let self else { return }
                    self.dispatchAction(.renameTab(tabId: tabId, name: name))
                    self.closeTabRenamePopover()
                },
                onCancel: { [weak self] in
                    self?.closeTabRenamePopover()
                }
            )
        )
        tabRenamePopover = popover
        if let workspaceWindowId = workspaceWindowId ?? windowLifecycleStore.focusedWindowId
            ?? windowLifecycleStore.keyWindowId
        {
            tabRenameTransientSurfaceToken = atom(\.transientKeyboardSurface).present(
                .tabRename(tabId: tabId),
                workspaceWindowId: workspaceWindowId
            )
        }

        let anchorRect = tabBarHostingView.tabFrameInView(for: tabId) ?? tabBarHostingView.bounds
        popover.show(relativeTo: anchorRect, of: tabBarHostingView, preferredEdge: .minY)
    }

    private func dismissTabRenameTransientSurface() {
        guard let tabRenameTransientSurfaceToken else { return }
        atom(\.transientKeyboardSurface).dismiss(tabRenameTransientSurfaceToken)
        self.tabRenameTransientSurfaceToken = nil
    }

    private func handleTabReorder(fromId: UUID, toIndex: Int) {
        dispatchAction(.reorderTab(tabId: fromId, newIndex: toIndex))
    }

    private func createDragPayload(for tabId: UUID) -> TabDragPayload? {
        guard store.tabLayoutAtom.tab(tabId) != nil else { return nil }
        return TabDragPayload(tabId: tabId)
    }
}
