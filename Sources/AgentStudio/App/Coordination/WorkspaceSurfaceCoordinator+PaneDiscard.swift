import AgentStudioCore
import AppKit
import Foundation

extension WorkspaceSurfaceCoordinator {
    func executeDiscardBackgroundedPane(paneId: UUID) async throws {
        guard store.paneAtom.pane(paneId)?.residency == .backgrounded else { return }
        try await store.discardPane(
            target: .backgroundedPane(paneID: paneId), time: try await undoClock(),
            willPublish: { [self] removedIDs in
                for removedID in removedIDs {
                    retireZoomCompanion(forSourcePane: removedID)
                    teardownView(for: removedID)
                }
            },
            didPublish: { [self] removedIDs in
                for removedID in removedIDs { viewRegistry.retireSlot(for: removedID) }
                signalTerminalSessionCleanup()
            })
    }

    func executeDiscardDrawerPane(parentPaneId: UUID, drawerPaneId: UUID) async throws {
        guard store.paneAtom.pane(drawerPaneId)?.parentPaneId == parentPaneId else { return }
        let closingHost = viewRegistry.view(for: drawerPaneId)
        let window = closingHost?.window ?? viewRegistry.view(for: parentPaneId)?.window
        let originalResponder = window?.firstResponder
        let closingPaneOwnedFocus: Bool
        if let responderView = originalResponder as? NSView, let closingHost {
            closingPaneOwnedFocus = responderView === closingHost || responderView.isDescendant(of: closingHost)
        } else {
            closingPaneOwnedFocus = window == nil
        }
        var restoreFocus = false
        try await store.discardPane(
            target: .drawerPane(parentID: parentPaneId, paneID: drawerPaneId), time: try await undoClock(),
            willPublish: { [self] removedIDs in
                restoreFocus = closingPaneOwnedFocus && window?.firstResponder === originalResponder
                if restoreFocus {
                    prepareDrawerFocusForDiscard(parentPaneId: parentPaneId, drawerPaneId: drawerPaneId)
                }
                for removedID in removedIDs { teardownView(for: removedID) }
            },
            didPublish: { [self] removedIDs in
                for removedID in removedIDs { viewRegistry.retireSlot(for: removedID) }
                signalTerminalSessionCleanup()
                guard restoreFocus else { return }
                if let activeID = arrangementView.drawerView(forParent: parentPaneId)?.activeChildId {
                    focusVisiblePaneHost(activeID)
                } else if store.paneAtom.pane(parentPaneId)?.drawer?.paneIds.isEmpty == true {
                    _ = clearFirstResponderToWindowContent(for: parentPaneId)
                } else {
                    focusVisiblePaneHost(parentPaneId)
                }
            })
    }

    private func prepareDrawerFocusForDiscard(parentPaneId: UUID, drawerPaneId: UUID) {
        let view = arrangementView.drawerView(forParent: parentPaneId)
        guard let drawer = store.paneAtom.pane(parentPaneId)?.drawer,
            view?.activeChildId == drawerPaneId
        else { return }
        let minimized = view?.minimizedPaneIds ?? []
        if let fallbackID = drawer.paneIds.first(where: { $0 != drawerPaneId && !minimized.contains($0) }) {
            focusVisiblePaneHost(fallbackID)
        } else if !drawer.paneIds.contains(where: { $0 != drawerPaneId }) {
            _ = clearFirstResponderToWindowContent(for: parentPaneId)
        } else {
            focusVisiblePaneHost(parentPaneId)
        }
    }
}
