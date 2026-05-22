import AppKit
import Foundation
import SwiftUI
import Testing

@testable import AgentStudio

@MainActor
@Suite("PaneInboxNotificationPopover", .serialized)
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

    @Test("unread mode hides read and pane-dismissed notifications before capping")
    func unreadModeFiltersUnreadActivePaneNotificationsBeforeCapping() {
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
            notifications: [newestRead, newestDismissed] + unreadNotifications,
            filterMode: .unread
        )

        #expect(relevant.count == AppPolicies.PaneInbox.maxVisibleNotifications)
        #expect(relevant.allSatisfy { !$0.isRead && !$0.isDismissedFromPaneInbox })
        #expect(relevant.first?.title == "Unread 0")
        #expect(relevant.last?.title == "Unread 24")
    }

    @Test("all mode includes read and pane-dismissed notifications before capping")
    func allModeIncludesReadAndPaneDismissedNotificationsBeforeCapping() {
        let paneId = UUID()
        let read = makeNotification(
            paneId: paneId,
            title: "Read",
            timestamp: Date(timeIntervalSince1970: 300),
            isRead: true
        )
        let dismissed = makeNotification(
            paneId: paneId,
            title: "Dismissed",
            timestamp: Date(timeIntervalSince1970: 290),
            isDismissedFromPaneInbox: true
        )
        let scopedNotifications = (0..<30).map { index in
            makeNotification(
                paneId: paneId,
                title: "Scoped \(index)",
                timestamp: Date(timeIntervalSince1970: TimeInterval(100 - index))
            )
        }
        let unrelated = makeNotification(
            paneId: UUID(),
            title: "Other",
            timestamp: Date(timeIntervalSince1970: 400)
        )

        let relevant = PaneInboxNotificationPopover.relevantNotifications(
            paneIds: [paneId],
            notifications: [unrelated, read, dismissed] + scopedNotifications,
            filterMode: .all
        )

        #expect(relevant.count == AppPolicies.PaneInbox.maxVisibleNotifications)
        #expect(relevant.map(\.title).prefix(2) == ["Read", "Dismissed"])
        #expect(relevant.contains { $0.title == "Other" } == false)
        #expect(relevant.last?.title == "Scoped 22")
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
        let presentationAtom = PaneInboxPresentationAtom()
        var didClose = false
        inboxAtom.append(notification)

        let popover = PaneInboxNotificationPopover(
            parentPaneId: parentPaneId,
            workspaceWindowId: nil,
            paneIds: [parentPaneId],
            inboxAtom: inboxAtom,
            presentationAtom: presentationAtom,
            onActivate: { _ in },
            onFocusPane: { _ in },
            onClear: {},
            onClose: { didClose = true }
        )

        _ = popover.body
        popover.onClose()

        #expect(didClose)
        #expect(inboxAtom.notifications.first?.isRead == false)
        #expect(inboxAtom.notifications.first?.isDismissedFromPaneInbox == false)
    }

    @Test("mounted pane inbox clear button clears through local window scoped closure")
    func mountedPaneInboxClearButtonClearsThroughLocalWindowScopedClosure() async throws {
        let parentPaneId = UUID()
        let notification = makeNotification(paneId: parentPaneId, title: "Clearable")
        let inboxAtom = InboxNotificationAtom()
        let commandHandler = PaneInboxCommandHandlerProbe()
        inboxAtom.append(notification)
        var didClearLocally = false

        try await withIsolatedCommandDispatcher(
            configure: {
                CommandDispatcher.shared.handler = commandHandler
                CommandDispatcher.shared.appCommandRouter = nil
            },
            body: {
                let hostingView = NSHostingView(
                    rootView: PaneInboxNotificationPopover(
                        parentPaneId: parentPaneId,
                        workspaceWindowId: nil,
                        paneIds: [parentPaneId],
                        inboxAtom: inboxAtom,
                        presentationAtom: PaneInboxPresentationAtom(),
                        onActivate: { _ in },
                        onFocusPane: { _ in },
                        onClear: {
                            didClearLocally = true
                            inboxAtom.clearPaneInbox(paneIds: [parentPaneId])
                        },
                        onClose: {}
                    )
                    .frame(width: 360, height: 240)
                )
                let window = NSWindow(
                    contentRect: CGRect(x: 0, y: 0, width: 360, height: 240),
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

                pressAccessibleElement(clearButton)

                #expect(didClearLocally)
                #expect(commandHandler.executedTargets.isEmpty)
                #expect(inboxAtom.notifications.first?.isRead == true)
                #expect(inboxAtom.notifications.first?.isDismissedFromPaneInbox == true)
            }
        )
    }

    @Test("mounted pane inbox row activation focuses through local window scoped closure")
    func mountedPaneInboxRowActivationFocusesThroughLocalWindowScopedClosure() async throws {
        let parentPaneId = UUID()
        let notification = makeNotification(paneId: parentPaneId, title: "Focusable")
        let inboxAtom = InboxNotificationAtom()
        let commandHandler = PaneInboxCommandHandlerProbe()
        inboxAtom.append(notification)
        var activatedNotificationIds: [UUID] = []
        var locallyFocusedPaneIds: [UUID] = []
        var didClose = false

        try await withIsolatedCommandDispatcher(
            configure: {
                CommandDispatcher.shared.handler = commandHandler
                CommandDispatcher.shared.appCommandRouter = nil
            },
            body: {
                let hostingView = NSHostingView(
                    rootView: PaneInboxNotificationPopover(
                        parentPaneId: parentPaneId,
                        workspaceWindowId: nil,
                        paneIds: [parentPaneId],
                        inboxAtom: inboxAtom,
                        presentationAtom: PaneInboxPresentationAtom(),
                        onActivate: { activatedNotificationIds.append($0.id) },
                        onFocusPane: { locallyFocusedPaneIds.append($0) },
                        onClear: {},
                        onClose: { didClose = true }
                    )
                    .frame(width: 360, height: 240)
                )
                let window = NSWindow(
                    contentRect: CGRect(x: 0, y: 0, width: 360, height: 240),
                    styleMask: [.titled, .closable],
                    backing: .buffered,
                    defer: false
                )
                window.contentView = hostingView
                window.makeKeyAndOrderFront(nil)
                defer { window.orderOut(nil) }
                hostingView.layoutSubtreeIfNeeded()

                let row = try #require(
                    findAccessibleElement(
                        in: hostingView,
                        identifier: "paneInboxNotificationRow.\(notification.id.uuidString)"
                    )
                )

                pressAccessibleElement(row)

                #expect(activatedNotificationIds == [notification.id])
                #expect(locallyFocusedPaneIds == [parentPaneId])
                #expect(commandHandler.executedTargets.isEmpty)
                #expect(inboxAtom.notifications.first?.isRead == true)
                #expect(inboxAtom.notifications.first?.isDismissedFromPaneInbox == true)
                #expect(didClose)
            }
        )
    }

    @Test("mounted pane inbox row accessibility label uses display fallback")
    func mountedPaneInboxRowAccessibilityLabelUsesDisplayFallback() throws {
        let parentPaneId = UUID()
        let notification = makeNotification(paneId: parentPaneId, title: "   ", body: "Body fallback")
        let inboxAtom = InboxNotificationAtom()
        inboxAtom.append(notification)

        let hostingView = NSHostingView(
            rootView: PaneInboxNotificationPopover(
                parentPaneId: parentPaneId,
                workspaceWindowId: nil,
                paneIds: [parentPaneId],
                inboxAtom: inboxAtom,
                presentationAtom: PaneInboxPresentationAtom(),
                onActivate: { _ in },
                onFocusPane: { _ in },
                onClear: {},
                onClose: {}
            )
            .frame(width: 360, height: 240)
        )
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 360, height: 240),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        hostingView.layoutSubtreeIfNeeded()

        let row = try #require(
            findAccessibleElement(
                in: hostingView,
                identifier: "paneInboxNotificationRow.\(notification.id.uuidString)"
            )
        )

        #expect(accessibilityLabel(of: row) == "Body fallback")
    }

    @Test("popover uses repo-matched background")
    func popoverUsesRepoMatchedBackground() {
        #expect(PaneInboxNotificationPopover.surfaceBackground == .windowBackgroundColor)
    }

    @Test("pane inbox row uses same metadata leading alignment as global inbox")
    func paneInboxRowUsesSameMetadataLeadingAlignmentAsGlobalInbox() {
        #expect(PaneInboxNotificationPopover.rowChromePolicy == .sidebarRowShell)
        #expect(InboxRow.metadataLine(text: "Pane").reservesIconColumn == false)
    }

    private func makeNotification(
        id: UUID = UUID(),
        paneId: UUID?,
        title: String = "Notification",
        body: String? = nil,
        timestamp: Date? = nil,
        isRead: Bool = false,
        isDismissedFromPaneInbox: Bool = false
    ) -> InboxNotification {
        InboxNotification(
            id: id,
            timestamp: timestamp ?? Date(timeIntervalSince1970: isDismissedFromPaneInbox ? 50 : 100),
            kind: .agentRpc,
            title: title,
            body: body,
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
private final class PaneInboxCommandHandlerProbe: WorkspaceCommandHandling {
    var executedCommands: [AppCommand] = []
    var executedTargets: [(command: AppCommand, target: UUID, targetType: SearchItemType)] = []

    func execute(_ command: AppCommand) {
        executedCommands.append(command)
    }

    func execute(_ command: AppCommand, target: UUID, targetType: SearchItemType) {
        executedTargets.append((command, target, targetType))
    }

    func canExecute(_: AppCommand) -> Bool {
        true
    }

    func canExecute(_: AppCommand, target _: UUID, targetType _: SearchItemType) -> Bool {
        true
    }

    func executeExtractPaneToTab(tabId _: UUID, paneId _: UUID, targetTabIndex _: Int?) {}

    func executeMovePaneToTab(sourcePaneId _: UUID, sourceTabId _: UUID?, targetTabId _: UUID) {}
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

private func accessibilityLabel(of element: AnyObject) -> String? {
    let selector = NSSelectorFromString("accessibilityLabel")
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
