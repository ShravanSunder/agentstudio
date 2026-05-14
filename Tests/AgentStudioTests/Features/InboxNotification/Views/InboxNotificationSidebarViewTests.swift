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

    @Test("clear action dispatches the clear read inbox command")
    func clearActionDispatchesClearReadInboxCommand() {
        let previousRouter = CommandDispatcher.shared.appCommandRouter
        let previousHandler = CommandDispatcher.shared.handler
        defer {
            CommandDispatcher.shared.appCommandRouter = previousRouter
            CommandDispatcher.shared.handler = previousHandler
        }

        let router = MockAppCommandRouter()
        router.appCommands = [.clearReadInboxNotifications]
        CommandDispatcher.shared.appCommandRouter = router
        CommandDispatcher.shared.handler = nil
        let view = InboxNotificationSidebarView(
            inboxAtom: InboxNotificationAtom(),
            prefsAtom: InboxNotificationPrefsAtom(),
            uiState: UIStateAtom(),
            sidebarCache: SidebarCacheAtom(),
            inboxFilterDraft: InboxFilterDraftAtom(),
            workspacePaneAtom: WorkspacePaneAtom(),
            dispatcher: .shared,
            onRefocusActivePane: {}
        )

        view.clearReadInboxNotifications()

        #expect(router.handledCommands == [.clearReadInboxNotifications])
    }

    @Test("mounted inbox sidebar clear button dispatches clear read command")
    func mountedInboxSidebarClearButtonDispatchesClearReadCommand() async throws {
        let previousRouter = CommandDispatcher.shared.appCommandRouter
        let previousHandler = CommandDispatcher.shared.handler
        defer {
            CommandDispatcher.shared.appCommandRouter = previousRouter
            CommandDispatcher.shared.handler = previousHandler
        }

        let router = MockAppCommandRouter()
        router.appCommands = [.clearReadInboxNotifications]
        CommandDispatcher.shared.appCommandRouter = router
        CommandDispatcher.shared.handler = nil
        let hostingView = NSHostingView(
            rootView: InboxNotificationSidebarView(
                inboxAtom: InboxNotificationAtom(),
                prefsAtom: InboxNotificationPrefsAtom(),
                uiState: UIStateAtom(),
                sidebarCache: SidebarCacheAtom(),
                inboxFilterDraft: InboxFilterDraftAtom(),
                workspacePaneAtom: WorkspacePaneAtom(),
                dispatcher: .shared,
                onRefocusActivePane: {}
            )
            .frame(width: 360, height: 420)
        )
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 360, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        hostingView.layoutSubtreeIfNeeded()

        let clearButton = try #require(
            findAccessibleElement(in: hostingView, identifier: "inboxSidebarClearButton")
        )

        #expect(accessibleElementCount(in: hostingView, identifier: "inboxSidebarClearButton") == 1)
        pressAccessibleElement(clearButton)
        #expect(router.handledCommands == [.clearReadInboxNotifications])
    }

    @Test("inbox header controls use distinct symbols and grouped row indentation")
    func inboxHeaderControlsUseDistinctSymbolsAndGroupedRowIndentation() {
        #expect(InboxSidebarHeader.sortIconName == "arrow.up.arrow.down.circle")
        #expect(InboxSidebarHeader.groupIconName == "square.stack.3d.up")
        #expect(InboxSidebarHeader.filterIconName == "line.3.horizontal.decrease.circle")
        #expect(InboxSidebarHeader.sortIconName != InboxSidebarHeader.groupIconName)
        #expect(InboxSidebarHeader.groupIconName != InboxSidebarHeader.filterIconName)
        #expect(InboxSidebarContent.rowLeadingInset(isGrouped: false) == 0)
        #expect(
            InboxSidebarContent.rowLeadingInset(isGrouped: true)
                == AppStyles.Shell.Sidebar.groupChildRowLeadingInset
        )
    }

    @Test("repo grouped inbox and repo explorer use shared repo header chrome")
    @MainActor
    func repoGroupedInboxAndRepoExplorerUseSharedRepoHeaderChrome() {
        #expect(
            InboxNotificationGroupHeader.chromePolicy(for: .repo(organizationName: "askluna"))
                == .repoGroupHeader
        )
        #expect(InboxNotificationGroupHeader.chromePolicy(for: .plain) == .plainSectionHeader)
        #expect(RepoExplorerView.groupHeaderChromePolicy == .repoGroupHeader)
        #expect(SidebarRepoGroupHeader<EmptyView>.chromePolicy == .repoGroupHeader)
        #expect(SidebarRepoGroupHeader<EmptyView>.leadingInset == AppStyles.Shell.Sidebar.listRowLeadingInset)
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
            kind: .layout(drawer: Drawer(paneIds: [drawerPaneId], activeChildId: drawerPaneId))
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

@MainActor
private func findAccessibleElement(in root: AnyObject, identifier: String) -> AnyObject? {
    var visited: Set<ObjectIdentifier> = []
    return findAccessibleElement(in: root, identifier: identifier, visited: &visited)
}

@MainActor
private func findAccessibleElement(
    in element: AnyObject,
    identifier: String,
    visited: inout Set<ObjectIdentifier>
) -> AnyObject? {
    let objectIdentifier = ObjectIdentifier(element)
    guard visited.insert(objectIdentifier).inserted else { return nil }

    if accessibilityIdentifier(of: element) == identifier {
        return element
    }

    for child in accessibilityChildren(of: element) {
        if let match = findAccessibleElement(in: child, identifier: identifier, visited: &visited) {
            return match
        }
    }

    for subview in (element as? NSView)?.subviews ?? [] {
        if let match = findAccessibleElement(in: subview, identifier: identifier, visited: &visited) {
            return match
        }
    }

    return nil
}

private func accessibilityIdentifier(of element: AnyObject) -> String? {
    let selector = NSSelectorFromString("accessibilityIdentifier")
    guard element.responds(to: selector) else { return nil }
    return element.perform(selector)?.takeUnretainedValue() as? String
}

private func accessibilityChildren(of element: AnyObject) -> [AnyObject] {
    let selector = NSSelectorFromString("accessibilityChildren")
    guard element.responds(to: selector) else { return [] }
    return element.perform(selector)?.takeUnretainedValue() as? [AnyObject] ?? []
}

private func pressAccessibleElement(_ element: AnyObject) {
    let selector = NSSelectorFromString("accessibilityPerformPress")
    guard element.responds(to: selector) else { return }
    _ = element.perform(selector)
}

@MainActor
private func accessibleElementCount(in root: AnyObject, identifier: String) -> Int {
    var visited: Set<ObjectIdentifier> = []
    return accessibleElementCount(in: root, identifier: identifier, visited: &visited)
}

@MainActor
private func accessibleElementCount(
    in element: AnyObject,
    identifier: String,
    visited: inout Set<ObjectIdentifier>
) -> Int {
    let objectIdentifier = ObjectIdentifier(element)
    guard visited.insert(objectIdentifier).inserted else { return 0 }

    let currentCount = accessibilityIdentifier(of: element) == identifier ? 1 : 0
    let childCount = accessibilityChildren(of: element).reduce(0) { count, child in
        count + accessibleElementCount(in: child, identifier: identifier, visited: &visited)
    }
    let subviewCount = ((element as? NSView)?.subviews ?? []).reduce(0) { count, subview in
        count + accessibleElementCount(in: subview, identifier: identifier, visited: &visited)
    }
    return currentCount + childCount + subviewCount
}
