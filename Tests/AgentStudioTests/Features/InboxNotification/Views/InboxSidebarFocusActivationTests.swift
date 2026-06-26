import AppKit
import SwiftUI
import Testing

@testable import AgentStudio

@MainActor
@Suite("InboxNotificationSidebarView focus and activation", .serialized)
struct InboxSidebarFocusActivationTests {
    @Test("publishing non-nil inbox focus flips sidebarHasFocus true")
    func nonNilInboxFocusPublishesTrue() {
        let uiState = WorkspaceSidebarState()
        #expect(uiState.sidebarHasFocus == false)

        InboxSidebarFocusPublisher.publish(focusedField: .search, into: uiState)

        #expect(uiState.sidebarHasFocus == true)
    }

    @Test("publishing nil inbox focus flips sidebarHasFocus false")
    func nilInboxFocusPublishesFalse() {
        let uiState = WorkspaceSidebarState()
        uiState.setSidebarHasFocus(true)

        InboxSidebarFocusPublisher.publish(focusedField: nil, into: uiState)

        #expect(uiState.sidebarHasFocus == false)
    }

    @Test("focus bridge publishes sidebar focus and escape callback through mounted view")
    func focusBridgePublishesMountedViewEvents() async throws {
        let uiState = WorkspaceSidebarState()
        let workspacePaneAtom = WorkspacePaneAtom()
        var didRefocusActivePane = false
        let hostingView = NSHostingView(
            rootView: InboxNotificationSidebarView(
                inboxAtom: InboxNotificationAtom(),
                prefsAtom: InboxNotificationPrefsAtom(),
                uiState: uiState,
                sidebarCache: SidebarCacheState(),
                inboxSidebarState: InboxSidebarState(),
                workspacePaneAtom: workspacePaneAtom,
                repositoryTopologyAtom: RepositoryTopologyAtom(),
                repoCache: RepoCacheAtom(),
                dispatcher: AppCommandDispatcher.shared,
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
            inboxSidebarDescendant(
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
