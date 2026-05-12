import AppKit
import Foundation
import SwiftUI
import Testing

@testable import AgentStudio

@MainActor
@Suite("PaneInboxNotificationPopover")
struct PaneInboxNotificationPopoverTests {
    @Test("popover filters to pane-scope notifications not dismissed from pane inbox")
    func popoverFiltersRelevantNotifications() {
        let parentPaneId = UUID()
        let drawerChildPaneId = UUID()
        let parentVisible = makeNotification(paneId: parentPaneId, title: "Parent")
        let childVisible = makeNotification(paneId: drawerChildPaneId, title: "Child")
        let dismissed = makeNotification(
            paneId: drawerChildPaneId,
            title: "Dismissed",
            isDismissedFromPaneInbox: true
        )
        let unrelated = makeNotification(paneId: UUID(), title: "Other")

        let relevant = PaneInboxNotificationPopover.relevantNotifications(
            paneIds: [parentPaneId, drawerChildPaneId],
            notifications: [dismissed, unrelated, parentVisible, childVisible]
        )

        #expect(relevant.map(\.title) == ["Parent", "Child"])
    }

    @Test("popover hides read and pane-dismissed notifications before capping")
    func popoverFiltersUnreadActivePaneNotificationsBeforeCapping() {
        let paneId = UUID()
        let newestRead = makeNotification(
            paneId: paneId,
            title: "Read",
            timestamp: Date(timeIntervalSince1970: 200),
            isRead: true
        )
        let newestDismissed = makeNotification(
            paneId: paneId,
            title: "Dismissed",
            timestamp: Date(timeIntervalSince1970: 190),
            isDismissedFromPaneInbox: true
        )
        let unreadNotifications = (0..<30).map { index in
            makeNotification(
                paneId: paneId,
                title: "Unread \(index)",
                timestamp: Date(timeIntervalSince1970: TimeInterval(100 - index))
            )
        }

        let relevant = PaneInboxNotificationPopover.relevantNotifications(
            paneIds: [paneId],
            notifications: [newestRead, newestDismissed] + unreadNotifications
        )

        #expect(relevant.count == AppPolicies.PaneInbox.maxVisibleNotifications)
        #expect(relevant.allSatisfy { !$0.isRead && !$0.isDismissedFromPaneInbox })
        #expect(relevant.first?.title == "Unread 0")
        #expect(relevant.last?.title == "Unread 24")
    }

    @Test("popover includes drawer child notification from resolved parent pane scope")
    func popoverIncludesDrawerChildNotificationFromParentScope() {
        let parentPaneId = UUIDv7.generate()
        let drawerChildPaneId = UUIDv7.generate()
        let panes = makePaneLookup(parentPaneId: parentPaneId, drawerPaneId: drawerChildPaneId)
        let scope = PaneInboxScopeResolver.resolve(
            anchorPaneId: parentPaneId,
            pane: { panes[$0] }
        )
        let childNotification = makeNotification(paneId: drawerChildPaneId, title: "Drawer child")
        let unrelated = makeNotification(paneId: UUID(), title: "Other")

        let relevant = PaneInboxNotificationPopover.relevantNotifications(
            paneIds: scope.paneIds,
            notifications: [unrelated, childNotification]
        )

        #expect(scope.parentPaneId == parentPaneId)
        #expect(scope.paneIds == [parentPaneId, drawerChildPaneId])
        #expect(relevant.map(\.id) == [childNotification.id])
    }

    @Test("popover includes parent notification from resolved drawer child scope")
    func popoverIncludesParentNotificationFromDrawerChildScope() {
        let parentPaneId = UUIDv7.generate()
        let drawerChildPaneId = UUIDv7.generate()
        let panes = makePaneLookup(parentPaneId: parentPaneId, drawerPaneId: drawerChildPaneId)
        let scope = PaneInboxScopeResolver.resolve(
            anchorPaneId: drawerChildPaneId,
            pane: { panes[$0] }
        )
        let parentNotification = makeNotification(paneId: parentPaneId, title: "Parent")
        let childNotification = makeNotification(paneId: drawerChildPaneId, title: "Drawer child")

        let relevant = PaneInboxNotificationPopover.relevantNotifications(
            paneIds: scope.paneIds,
            notifications: [parentNotification, childNotification]
        )

        #expect(scope.parentPaneId == parentPaneId)
        #expect(scope.paneIds == [parentPaneId, drawerChildPaneId])
        #expect(relevant.map(\.id) == [parentNotification.id, childNotification.id])
    }

    @Test("keyboardItems maps relevant notifications to selectable popover items")
    func keyboardItemsForRelevantNotifications() {
        let paneId = UUID()
        let first = makeNotification(id: UUID(), paneId: paneId, title: "First")
        let second = makeNotification(id: UUID(), paneId: paneId, title: "Second")

        let keyboardItems = PaneInboxNotificationPopover.keyboardItems(
            for: [first, second]
        )

        #expect(keyboardItems.map(\.id) == [first.id, second.id])
        #expect(keyboardItems.map(\.shortcutNumber) == [1, 2])
        #expect(keyboardItems.allSatisfy { !$0.supportsAuxiliaryAction })
    }

    @Test("keyboardItems keeps every notification navigable while capping numbered shortcuts")
    func keyboardItemsKeepsEveryNotificationNavigableWhileCappingNumberedShortcuts() {
        let paneId = UUID()
        let notifications = (0..<(AppPolicies.SelectablePopover.maxNumberedShortcuts + 3)).map { index in
            makeNotification(id: UUID(), paneId: paneId, title: "Notification \(index)")
        }

        let keyboardItems = PaneInboxNotificationPopover.keyboardItems(for: notifications)

        #expect(keyboardItems.count == notifications.count)
        #expect(keyboardItems.map(\.id) == notifications.map(\.id))
        #expect(
            keyboardItems.map(\.shortcutNumber)
                == Array(1...AppPolicies.SelectablePopover.maxNumberedShortcuts).map(Optional.some)
                + Array(repeating: nil, count: 3)
        )
    }

    @Test("presenting and closing popover does not mark notifications read or dismissed")
    func presentingAndClosingPopoverDoesNotMarkNotificationsReadOrDismissed() {
        let parentPaneId = UUID()
        let notification = makeNotification(paneId: parentPaneId, title: "Passive")
        let inboxAtom = InboxNotificationAtom()
        var didClose = false
        inboxAtom.append(notification)

        let popover = PaneInboxNotificationPopover(
            parentPaneId: parentPaneId,
            paneIds: [parentPaneId],
            inboxAtom: inboxAtom,
            dispatcher: CommandDispatcher.shared,
            onActivate: { _ in },
            onClose: { didClose = true }
        )

        _ = popover.body
        popover.onClose()

        #expect(didClose)
        #expect(inboxAtom.notifications.first?.isRead == false)
        #expect(inboxAtom.notifications.first?.isDismissedFromPaneInbox == false)
    }

    @Test("clearNotifications dispatches targeted pane inbox clear command")
    func clearNotificationsDispatchesTargetedPaneInboxClearCommand() {
        let previousRouter = CommandDispatcher.shared.appCommandRouter
        let previousHandler = CommandDispatcher.shared.handler
        defer {
            CommandDispatcher.shared.appCommandRouter = previousRouter
            CommandDispatcher.shared.handler = previousHandler
        }

        let parentPaneId = UUID()
        let commandHandler = MockCommandHandler()
        commandHandler.targetedCanExecuteResult = true
        CommandDispatcher.shared.appCommandRouter = nil
        CommandDispatcher.shared.handler = commandHandler
        let popover = PaneInboxNotificationPopover(
            parentPaneId: parentPaneId,
            paneIds: [parentPaneId, UUID()],
            inboxAtom: InboxNotificationAtom(),
            dispatcher: .shared,
            onActivate: { _ in },
            onClose: {}
        )

        popover.clearNotifications()

        #expect(commandHandler.executedCommands.count == 1)
        #expect(commandHandler.executedCommands.first?.0 == .clearPaneInboxNotifications)
        #expect(commandHandler.executedCommands.first?.1 == parentPaneId)
        #expect(commandHandler.executedCommands.first?.2 == .pane)
    }

    @Test("mounted pane inbox clear button dispatches targeted clear command")
    func mountedPaneInboxClearButtonDispatchesTargetedClearCommand() async throws {
        let previousRouter = CommandDispatcher.shared.appCommandRouter
        let previousHandler = CommandDispatcher.shared.handler
        defer {
            CommandDispatcher.shared.appCommandRouter = previousRouter
            CommandDispatcher.shared.handler = previousHandler
        }

        let parentPaneId = UUID()
        let commandHandler = MockCommandHandler()
        commandHandler.targetedCanExecuteResult = true
        CommandDispatcher.shared.appCommandRouter = nil
        CommandDispatcher.shared.handler = commandHandler
        let hostingView = NSHostingView(
            rootView: PaneInboxNotificationPopover(
                parentPaneId: parentPaneId,
                paneIds: [parentPaneId],
                inboxAtom: InboxNotificationAtom(),
                dispatcher: .shared,
                onActivate: { _ in },
                onClose: {}
            )
        )
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 520, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        hostingView.layoutSubtreeIfNeeded()

        let clearButton = try #require(
            findAccessibleElement(in: hostingView, identifier: "paneInboxClearButton")
        )

        #expect(accessibleElementCount(in: hostingView, identifier: "paneInboxClearButton") == 1)
        pressAccessibleElement(clearButton)
        #expect(commandHandler.executedCommands.count == 1)
        #expect(commandHandler.executedCommands.first?.0 == .clearPaneInboxNotifications)
        #expect(commandHandler.executedCommands.first?.1 == parentPaneId)
        #expect(commandHandler.executedCommands.first?.2 == .pane)
    }

    @Test("pane inbox rows participate in shared hover behavior")
    func paneInboxRowsParticipateInSharedHoverBehavior() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let source = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/Features/InboxNotification/Views/PaneInboxNotificationPopover.swift"
            ),
            encoding: .utf8
        )

        #expect(source.contains("PaneInboxNotificationRow("))
        #expect(source.contains(".onHover { hovering in"))
        #expect(source.contains("isHovered: false") == false)
    }

    private func makeNotification(
        id: UUID = UUID(),
        paneId: UUID?,
        title: String = "Notification",
        timestamp: Date? = nil,
        isRead: Bool = false,
        isDismissedFromPaneInbox: Bool = false
    ) -> InboxNotification {
        InboxNotification(
            id: id,
            timestamp: timestamp ?? Date(timeIntervalSince1970: isDismissedFromPaneInbox ? 50 : 100),
            kind: .agentRpc,
            title: title,
            body: nil,
            source: paneId.map { .pane(.init(paneId: $0)) } ?? .global,
            isRead: isRead,
            isDismissedFromPaneInbox: isDismissedFromPaneInbox
        )
    }

    private func makePaneLookup(parentPaneId: UUID, drawerPaneId: UUID) -> [UUID: Pane] {
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

        return [
            parentPane.id: parentPane,
            drawerPane.id: drawerPane,
        ]
    }
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
