import AppKit
import SwiftUI
import Testing

@testable import AgentStudio

@MainActor
@Suite("InboxNotificationSidebarView")
struct InboxNotificationSidebarViewTests {
    @Test("preseeded filter draft is consumed when the inbox mounts")
    func preseededFilterDraftIsConsumedOnMount() async {
        let inboxFilterDraft = InboxFilterDraftAtom()
        inboxFilterDraft.set(.worktree(id: UUID()))
        let hostingView = NSHostingView(
            rootView: InboxNotificationSidebarView(
                inboxAtom: InboxNotificationAtom(),
                prefsAtom: InboxNotificationPrefsAtom(),
                uiState: UIStateAtom(),
                sidebarCache: SidebarCacheAtom(),
                inboxFilterDraft: inboxFilterDraft,
                workspacePaneAtom: WorkspacePaneAtom(),
                dispatcher: CommandDispatcher.shared,
                onRefocusActivePane: {}
            )
            .frame(width: 320, height: 420)
        )

        hostingView.layoutSubtreeIfNeeded()

        await assertEventuallyMain("mounted inbox should consume pending filter draft") {
            inboxFilterDraft.peek() == nil
        }
    }

    @Test("root key router maps documented option and command shortcuts")
    func rootKeyRouterMapsShortcuts() {
        #expect(
            InboxSidebarKeyboardRouter.rootAction(
                characters: "f",
                key: "f",
                modifiers: .option
            ) == .focusSearch
        )
        #expect(
            InboxSidebarKeyboardRouter.rootAction(
                characters: "g",
                key: "g",
                modifiers: .option
            ) == .toggleGroupingMenu
        )
        #expect(
            InboxSidebarKeyboardRouter.rootAction(
                characters: "s",
                key: "s",
                modifiers: .option
            ) == .toggleSort
        )
        #expect(
            InboxSidebarKeyboardRouter.rootAction(
                characters: "",
                key: .downArrow,
                modifiers: .option
            ) == .moveGroupBoundary(.next)
        )
        #expect(
            InboxSidebarKeyboardRouter.rootAction(
                characters: "",
                key: .upArrow,
                modifiers: .option
            ) == .moveGroupBoundary(.previous)
        )
        #expect(
            InboxSidebarKeyboardRouter.rootAction(
                characters: "",
                key: .downArrow,
                modifiers: .command
            ) == .moveEnd(.last)
        )
        #expect(
            InboxSidebarKeyboardRouter.rootAction(
                characters: "",
                key: .upArrow,
                modifiers: .command
            ) == .moveEnd(.first)
        )
    }

    @Test("row key router maps activation and read toggle shortcuts")
    func rowKeyRouterMapsShortcuts() {
        #expect(InboxSidebarKeyboardRouter.rowAction(key: .return) == .activate)
        #expect(InboxSidebarKeyboardRouter.rowAction(key: .space) == .toggleRead)
        #expect(InboxSidebarKeyboardRouter.rowAction(key: "x") == .ignored)
    }

    @Test("focus bridge publishes sidebar focus and escape callback through mounted view")
    func focusBridgePublishesMountedViewEvents() async throws {
        let uiState = UIStateAtom()
        let workspacePaneAtom = WorkspacePaneAtom()
        var didRefocusActivePane = false
        let hostingView = NSHostingView(
            rootView: InboxNotificationSidebarView(
                inboxAtom: InboxNotificationAtom(),
                prefsAtom: InboxNotificationPrefsAtom(),
                uiState: uiState,
                sidebarCache: SidebarCacheAtom(),
                inboxFilterDraft: InboxFilterDraftAtom(),
                workspacePaneAtom: workspacePaneAtom,
                dispatcher: CommandDispatcher.shared,
                onRefocusActivePane: { didRefocusActivePane = true }
            )
            .frame(width: 320, height: 420)
        )
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 320, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        let otherResponder = NSView(frame: .zero)
        window.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()

        let focusBridge = try #require(
            findDescendant(
                in: hostingView,
                identifier: InboxNotificationSidebarView.focusTargetIdentifier.rawValue
            )
        )

        #expect(uiState.sidebarHasFocus == false)
        #expect(window.makeFirstResponder(focusBridge))
        await Task.yield()
        #expect(uiState.sidebarHasFocus == true)

        focusBridge.cancelOperation(nil)
        #expect(didRefocusActivePane == true)

        #expect(window.makeFirstResponder(otherResponder))
        await Task.yield()
        #expect(uiState.sidebarHasFocus == false)
    }

    @Test("activation resolver flashes stale rows instead of dispatching dead panes")
    func activationResolverFlashesStaleRows() {
        let notification = InboxNotification(
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: 100),
            kind: .agentRpc,
            title: "Done",
            body: nil,
            source: .pane(
                .init(
                    paneId: UUID(),
                    worktreeId: UUID(),
                    worktreeName: "main"
                )
            ),
            isRead: false,
            isDismissedFromPaneInbox: false
        )

        let outcome = InboxSidebarActivationResolver.resolve(
            notification: notification,
            workspacePaneAtom: WorkspacePaneAtom()
        )

        #expect(outcome == .flashRow(notification.id))
    }

    @Test("activation resolver focuses live pane rows")
    func activationResolverFocusesLivePane() {
        let paneId = PaneId()
        let notification = InboxNotification(
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: 100),
            kind: .agentRpc,
            title: "Done",
            body: nil,
            source: .pane(.init(paneId: paneId.uuid)),
            isRead: false,
            isDismissedFromPaneInbox: false
        )
        let workspacePaneAtom = WorkspacePaneAtom()
        workspacePaneAtom.addPane(
            Pane(
                id: paneId.uuid,
                content: .terminal(TerminalState(provider: .zmx, lifetime: .persistent)),
                metadata: PaneMetadata(
                    paneId: paneId,
                    contentType: .terminal,
                    source: .floating(launchDirectory: nil, title: nil),
                    title: "Pane"
                )
            )
        )

        let outcome = InboxSidebarActivationResolver.resolve(
            notification: notification,
            workspacePaneAtom: workspacePaneAtom
        )

        #expect(outcome == .focusPane(paneId.uuid))
    }

    @Test("activation resolver focuses live drawer child pane rows")
    func activationResolverFocusesLiveDrawerChildPane() {
        let parentPaneId = UUIDv7.generate()
        let drawerPaneId = UUIDv7.generate()
        let notification = InboxNotification(
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: 100),
            kind: .commandFinished,
            title: "Done",
            body: nil,
            source: .pane(.init(paneId: drawerPaneId)),
            isRead: false,
            isDismissedFromPaneInbox: false
        )
        let workspacePaneAtom = WorkspacePaneAtom()
        let parentPane = Pane(
            id: parentPaneId,
            content: .terminal(TerminalState(provider: .zmx, lifetime: .persistent)),
            metadata: PaneMetadata(
                paneId: PaneId(uuid: parentPaneId),
                contentType: .terminal,
                source: .floating(launchDirectory: nil, title: nil),
                title: "Parent"
            ),
            kind: .layout(drawer: Drawer(paneIds: [drawerPaneId]))
        )
        let drawerPane = Pane(
            id: drawerPaneId,
            content: .terminal(TerminalState(provider: .zmx, lifetime: .persistent)),
            metadata: PaneMetadata(
                paneId: PaneId(uuid: drawerPaneId),
                contentType: .terminal,
                source: .floating(launchDirectory: nil, title: nil),
                title: "Drawer"
            ),
            kind: .drawerChild(parentPaneId: parentPaneId)
        )
        workspacePaneAtom.addPane(parentPane)
        workspacePaneAtom.addPane(drawerPane)

        let outcome = InboxSidebarActivationResolver.resolve(
            notification: notification,
            workspacePaneAtom: workspacePaneAtom
        )

        #expect(outcome == .focusPane(drawerPaneId))
    }
}

@MainActor
private func findDescendant(in view: NSView, identifier: String) -> NSView? {
    if view.identifier?.rawValue == identifier {
        return view
    }

    for subview in view.subviews {
        if let match = findDescendant(in: subview, identifier: identifier) {
            return match
        }
    }

    return nil
}
