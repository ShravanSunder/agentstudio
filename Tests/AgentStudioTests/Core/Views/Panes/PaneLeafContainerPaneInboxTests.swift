import AppKit
import SwiftUI
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct PaneLeafContainerPaneInboxTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    @Test("pane leaf consumes matching pending pane inbox request on appear")
    func paneLeafConsumesMatchingPendingPaneInboxRequestOnAppear() async {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-pane-inbox-leaf-test-\(UUID().uuidString)")
        let store = WorkspaceStore(persistor: WorkspacePersistor(workspacesDir: tempDir))
        store.restore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let pane = store.createPane()
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)
        store.setActiveTab(tab.id)

        let request = PaneInboxRequest(
            id: UUID(),
            parentPaneId: pane.id,
            paneIds: [pane.id],
            intent: .open
        )
        var pendingRequest: PaneInboxRequest? = request
        var presentedScopes: [(parentPaneId: UUID, paneIds: [UUID], isPresented: Bool)] = []

        let presentation = PaneInboxPresentation(
            unreadCount: { _ in 0 },
            clear: { _, _ in },
            open: { _, _ in },
            openRollUpAlerts: { _, _ in },
            toggle: { _, _ in },
            setPresented: { parentPaneId, paneIds, isPresented in
                presentedScopes.append(
                    (parentPaneId: parentPaneId, paneIds: paneIds, isPresented: isPresented)
                )
            },
            pendingRequest: { pendingRequest },
            clearRequest: { requestToClear in
                if pendingRequest == requestToClear {
                    pendingRequest = nil
                }
            },
            popoverContent: { _, _, _, _ in AnyView(Text("Pane inbox")) },
            pruneFilterModes: { _ in }
        )
        let hostingView = NSHostingView(
            rootView: PaneLeafContainer(
                paneHost: PaneHostView(paneId: pane.id),
                tabId: tab.id,
                isActive: true,
                isSplit: false,
                isSplitResizing: false,
                store: store,
                repoCache: RepoCacheAtom(),
                closeTransitionCoordinator: PaneCloseTransitionCoordinator(),
                actionDispatcher: makeNoOpPaneActionDispatcher(),
                onPaneFocusTrigger: { _ in },
                onOpenPaneGitHub: { _ in },
                paneInboxPresentation: presentation,
                workspaceWindowId: nil
            )
            .frame(width: 360, height: 240)
        )
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 360, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }

        hostingView.layoutSubtreeIfNeeded()

        await eventually("pane inbox request should be consumed when the leaf appears") {
            pendingRequest == nil
                && presentedScopes.contains {
                    $0.parentPaneId == pane.id && $0.paneIds == [pane.id] && $0.isPresented
                }
        }
    }

    private func makeNoOpPaneActionDispatcher() -> PaneTabActionDispatcher {
        PaneTabActionDispatcher(
            dispatch: { _ in },
            shouldHandleSplitDragPayload: { _ in false },
            shouldAcceptDrop: { _, _, _, _ in false },
            handleDrop: { _, _, _, _ in }
        )
    }
}
