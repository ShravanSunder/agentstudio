import AppKit
import SwiftUI
import os.log

private struct PaneInboxCommandTarget {
    let parentPaneId: UUID
    let paneIds: [UUID]
}

@MainActor
final class PaneAuxiliaryCommandController {
    typealias OpenEditorHandler =
        @MainActor (_ id: EditorTargetId, _ path: URL, _ installedTargets: [ExternalEditorTarget]) -> Bool

    private static let logger = Logger(subsystem: "com.agentstudio", category: "PaneAuxiliaryCommandController")

    private let store: WorkspaceStore
    private let windowLifecycleStore: WindowLifecycleAtom
    private let workspaceWindowId: UUID?
    private let viewRegistry: ViewRegistry
    private let paneInboxPresentation: PaneInboxPresentation?
    private let paneNotePresentation: PaneNotePresentation?
    private let installedEditorTargetsProvider: @MainActor () -> [ExternalEditorTarget]
    private let openEditorHandler: OpenEditorHandler
    private let openFinderHandler: @MainActor (URL) -> Bool
    private let copyPathHandler: @MainActor (URL) -> Void
    private let activeMainPaneIdProvider: @MainActor () -> UUID?
    private let visibleActiveDrawerPaneIdProvider: @MainActor (UUID) -> UUID?
    private let workspaceFocusOwnerProvider: @MainActor () -> WorkspaceFocusOwner
    private let focusTargetedPane: @MainActor (UUID) -> Void
    private let fallbackAnchorViewProvider: @MainActor () -> NSView?
    private let popoverDelegateProvider: @MainActor () -> NSPopoverDelegate?
    private var paneNotePopover: NSPopover?

    init(
        store: WorkspaceStore,
        windowLifecycleStore: WindowLifecycleAtom,
        workspaceWindowId: UUID?,
        viewRegistry: ViewRegistry,
        paneInboxPresentation: PaneInboxPresentation?,
        paneNotePresentation: PaneNotePresentation?,
        installedEditorTargetsProvider: @escaping @MainActor () -> [ExternalEditorTarget],
        openEditorHandler: @escaping OpenEditorHandler,
        openFinderHandler: @escaping @MainActor (URL) -> Bool,
        copyPathHandler: @escaping @MainActor (URL) -> Void,
        activeMainPaneIdProvider: @escaping @MainActor () -> UUID?,
        visibleActiveDrawerPaneIdProvider: @escaping @MainActor (UUID) -> UUID?,
        workspaceFocusOwnerProvider: @escaping @MainActor () -> WorkspaceFocusOwner,
        focusTargetedPane: @escaping @MainActor (UUID) -> Void,
        fallbackAnchorViewProvider: @escaping @MainActor () -> NSView?,
        popoverDelegateProvider: @escaping @MainActor () -> NSPopoverDelegate?
    ) {
        self.store = store
        self.windowLifecycleStore = windowLifecycleStore
        self.workspaceWindowId = workspaceWindowId
        self.viewRegistry = viewRegistry
        self.paneInboxPresentation = paneInboxPresentation
        self.paneNotePresentation = paneNotePresentation
        self.installedEditorTargetsProvider = installedEditorTargetsProvider
        self.openEditorHandler = openEditorHandler
        self.openFinderHandler = openFinderHandler
        self.copyPathHandler = copyPathHandler
        self.activeMainPaneIdProvider = activeMainPaneIdProvider
        self.visibleActiveDrawerPaneIdProvider = visibleActiveDrawerPaneIdProvider
        self.workspaceFocusOwnerProvider = workspaceFocusOwnerProvider
        self.focusTargetedPane = focusTargetedPane
        self.fallbackAnchorViewProvider = fallbackAnchorViewProvider
        self.popoverDelegateProvider = popoverDelegateProvider
    }

    func handlePaneLocationCommand(_ command: AppCommand) -> Bool {
        switch command {
        case .openPaneLocationInBookmarkedEditor:
            guard let targetPath = selectedPaneManagementContext()?.targetPath else { return false }
            let installedTargets = installedEditorTargetsProvider()
            var resolution = ExternalEditorTarget.resolveBookmarkedOrDefault(
                bookmarkedEditorId: atom(\.editorChooser).bookmarkedEditorId,
                installedTargets: installedTargets
            )
            if case .bookmarkedEditorNotInstalled = resolution {
                // A saved bookmark that is no longer installed should heal back to
                // the implicit default launch order on the same key press.
                atom(\.editorChooser).setBookmarkedEditor(nil)
                resolution = ExternalEditorTarget.resolveBookmarkedOrDefault(
                    bookmarkedEditorId: nil,
                    installedTargets: installedTargets
                )
            }
            guard case .resolved(let target) = resolution else { return false }
            return openEditorHandler(target.id, targetPath, installedTargets)
        case .openPaneLocationInFinder:
            guard let targetPath = selectedPaneManagementContext()?.targetPath else { return false }
            return openFinderHandler(targetPath)
        case .openPaneLocationInEditorMenu:
            guard let activePaneId = activePaneIdForChooserRequest() else { return false }
            if atom(\.editorChooser).openForPaneId == activePaneId {
                atom(\.editorChooser).setOpenEditorPane(nil)
                return true
            }
            atom(\.editorChooser).setAvailableTargets(installedEditorTargetsProvider())
            atom(\.editorChooser).setOpenEditorPane(activePaneId)
            return true
        case .editPaneNote:
            guard let paneId = activeMainPaneCommandTarget() else { return false }
            if let paneNotePresentation {
                paneNotePresentation.present(paneId)
            } else {
                requestPaneNotePresentation(for: paneId)
            }
            return true
        case .copyCurrentPanePath:
            guard let path = activeMainPanePath() else { return false }
            copyPathHandler(path)
            return true
        default:
            return false
        }
    }

    func handlePaneInboxCommand(_ command: AppCommand) -> Bool {
        guard let paneInboxPresentation, let target = activePaneInboxTarget() else { return false }
        switch command {
        case .showPaneInboxNotifications:
            paneInboxPresentation.toggle(target.parentPaneId, target.paneIds)
            return true
        case .clearPaneInboxNotifications:
            paneInboxPresentation.clear(target.parentPaneId, target.paneIds)
            return true
        default:
            return false
        }
    }

    func handleTargetedPaneInboxCommand(
        _ command: AppCommand,
        target targetId: UUID,
        targetType: SearchItemType
    ) -> Bool {
        guard isPaneInboxCommand(command), isPaneInboxTargetType(targetType) else { return false }
        guard let paneInboxPresentation, let target = paneInboxTarget(anchorPaneId: targetId) else { return true }

        switch command {
        case .showPaneInboxNotifications:
            focusTargetedPane(targetId)
            paneInboxPresentation.toggle(target.parentPaneId, target.paneIds)
        case .clearPaneInboxNotifications:
            paneInboxPresentation.clear(target.parentPaneId, target.paneIds)
        default:
            break
        }
        return true
    }

    func canExecuteTargetedPaneInboxCommand(
        _ command: AppCommand,
        target: UUID,
        targetType: SearchItemType
    ) -> Bool? {
        guard isPaneInboxCommand(command), isPaneInboxTargetType(targetType) else { return nil }
        return paneInboxPresentation != nil && paneInboxTarget(anchorPaneId: target) != nil
    }

    func canExecuteDirectCommand(_ command: AppCommand) -> Bool? {
        switch command {
        case .showPaneInboxNotifications, .clearPaneInboxNotifications:
            return paneInboxPresentation != nil && activePaneInboxTarget() != nil
        case .openPaneLocationInBookmarkedEditor,
            .openPaneLocationInFinder,
            .openPaneLocationInEditorMenu:
            return selectedPaneManagementContext()?.targetPath != nil
        case .editPaneNote:
            return activeMainPaneCommandTarget() != nil
        case .copyCurrentPanePath:
            return activeMainPanePath() != nil
        default:
            return nil
        }
    }

    func handlePopoverDidClose(_ notification: Notification) -> Bool {
        guard let popover = paneNotePopover,
            notification.object as? NSPopover === popover
        else {
            return false
        }

        popover.delegate = nil
        paneNotePopover = nil
        return true
    }

    private func activePaneInboxTarget() -> PaneInboxCommandTarget? {
        guard let parentPaneId = activePaneInboxParentPaneId() else { return nil }
        return paneInboxTarget(anchorPaneId: parentPaneId)
    }

    private func paneInboxTarget(anchorPaneId: UUID) -> PaneInboxCommandTarget? {
        guard store.paneAtom.pane(anchorPaneId) != nil else { return nil }
        let scope = PaneInboxScopeResolver.resolve(
            anchorPaneId: anchorPaneId,
            pane: { store.paneAtom.pane($0) }
        )
        guard store.tabLayoutAtom.tabContaining(paneId: scope.parentPaneId) != nil else {
            return nil
        }
        return PaneInboxCommandTarget(parentPaneId: scope.parentPaneId, paneIds: scope.paneIds)
    }

    private func isPaneInboxCommand(_ command: AppCommand) -> Bool {
        command == .showPaneInboxNotifications || command == .clearPaneInboxNotifications
    }

    private func isPaneInboxTargetType(_ targetType: SearchItemType) -> Bool {
        targetType == .pane || targetType == .floatingTerminal
    }

    private func activePaneInboxParentPaneId() -> UUID? {
        guard let activePaneId = activeMainPaneIdProvider(),
            let activePane = store.paneAtom.pane(activePaneId)
        else {
            return nil
        }

        return activePane.parentPaneId ?? activePane.id
    }

    private func selectedPaneManagementContext() -> PaneManagementContext? {
        guard let paneId = selectedPaneIdForLocationCommands() else {
            return nil
        }

        return PaneManagementContext.project(
            paneId: paneId,
            store: store,
            notificationCountForWorktree: { worktreeId in
                WorkspaceNotificationCountProjection.unreadCount(
                    worktreeId: worktreeId,
                    inboxAtom: atom(\.inboxNotification)
                )
            }
        )
    }

    private func activeMainPaneCommandTarget() -> UUID? {
        guard case .mainPane(let paneId) = workspaceFocusOwnerProvider(),
            let activePaneId = paneId ?? activeMainPaneIdProvider(),
            let pane = store.paneAtom.pane(activePaneId),
            pane.parentPaneId == nil
        else {
            return nil
        }

        return activePaneId
    }

    private func requestPaneNotePresentation(for paneId: UUID) {
        guard store.paneAtom.pane(paneId) != nil else {
            Self.logger.warning("editPaneNote presentation ignored: pane \(paneId) not found")
            return
        }

        RunLoop.main.perform(inModes: [.default]) { [weak self] in
            MainActor.assumeIsolated {
                self?.presentPaneNotePopover(for: paneId)
            }
        }
    }

    private func presentPaneNotePopover(for paneId: UUID) {
        guard let pane = store.paneAtom.pane(paneId) else {
            Self.logger.warning("editPaneNote presentation ignored after defer: pane \(paneId) not found")
            return
        }

        closePaneNotePopover()
        guard let fallbackAnchorView = fallbackAnchorViewProvider() else { return }

        let resolvedWindowId =
            workspaceWindowId ?? windowLifecycleStore.focusedWindowId
            ?? windowLifecycleStore.keyWindowId
        let popover = NSPopover()
        popover.behavior = .semitransient
        popover.delegate = popoverDelegateProvider()
        popover.contentViewController = NSHostingController(
            rootView: PaneNotePopover(
                currentNote: pane.metadata.note,
                onCommit: { [weak self] note in
                    guard let self else { return }
                    self.store.paneAtom.updatePaneNote(paneId, note: note)
                    self.closePaneNotePopover()
                },
                onCancel: { [weak self] in
                    self?.closePaneNotePopover()
                }
            )
            .transientKeyboardSurface(
                .paneNote(paneId: paneId),
                workspaceWindowId: resolvedWindowId,
                onDismiss: { [weak self] in
                    self?.closePaneNotePopover()
                }
            )
        )
        paneNotePopover = popover

        let anchorView = viewRegistry.view(for: paneId) ?? fallbackAnchorView
        popover.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .minY)
    }

    private func closePaneNotePopover() {
        let popover = paneNotePopover
        paneNotePopover = nil
        popover?.delegate = nil
        popover?.close()
    }

    private func activeMainPanePath() -> URL? {
        guard let paneId = activeMainPaneCommandTarget(),
            let pane = store.paneAtom.pane(paneId)
        else {
            return nil
        }

        return pane.metadata.cwd ?? pane.metadata.launchDirectory
    }

    private func activePaneIdForChooserRequest() -> UUID? {
        selectedPaneIdForLocationCommands()
    }

    private func selectedPaneIdForLocationCommands() -> UUID? {
        guard let parentPaneId = activeMainPaneIdProvider() else {
            return nil
        }

        if let drawerPaneId = visibleActiveDrawerPaneIdProvider(parentPaneId) {
            return drawerPaneId
        }

        return parentPaneId
    }
}
