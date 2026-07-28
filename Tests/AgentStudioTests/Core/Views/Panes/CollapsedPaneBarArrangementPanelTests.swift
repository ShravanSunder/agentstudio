import AppKit
import SwiftUI
import Testing

@testable import AgentStudio

@MainActor
@Suite("Collapsed pane bar Arrangements", .serialized)
struct CollapsedPaneBarArrangementPanelTests {
    @Test("minimized-bar Arrangements forwards Pane Zoom and remains open")
    func minimizedBarArrangementsForwardsPaneZoom() async throws {
        installTestAtomRegistryIfNeeded()
        let atoms = AtomScope.store
        let store = WorkspaceStore(
            identityAtom: atoms.workspaceIdentity,
            windowMemoryAtom: atoms.workspaceWindowMemory,
            repositoryTopologyAtom: atoms.workspaceRepositoryTopology,
            paneAtom: atoms.workspacePane,
            tabLayoutAtom: atoms.workspaceTabLayout,
            mutationCoordinator: atoms.workspaceMutationCoordinator
        )
        let pane = store.createPane()
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)
        store.setActiveTab(tab.id)
        var zoomTargets: [UUID?] = []
        let actionDispatcher = PaneTabActionDispatcher(
            dispatch: { _ in },
            shouldHandleSplitDragPayload: { _ in false },
            shouldAcceptDrop: { _, _, _, _ in false },
            handleDrop: { _, _, _, _ in }
        )
        let hostingView = NSHostingView(
            rootView: CollapsedPaneBar(
                paneId: pane.id,
                tabId: tab.id,
                closeTransitionCoordinator: PaneCloseTransitionCoordinator(),
                actionDispatcher: actionDispatcher,
                onFocus: {},
                onToggleZoom: { zoomTargets.append($0) }
            )
        )
        hostingView.frame = CGRect(x: 0, y: 0, width: CollapsedPaneBar.barWidth, height: 500)
        let window = NSWindow(contentViewController: NSViewController())
        window.contentView = hostingView
        window.setContentSize(hostingView.frame.size)
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        hostingView.layoutSubtreeIfNeeded()
        window.contentView?.layoutSubtreeIfNeeded()

        let arrangementsButton = try #require(
            findAccessibilityElement(
                in: hostingView,
                identifier: "collapsed-pane-bar-arrangements"
            )
        )
        #expect(performAccessibilityPress(arrangementsButton))

        await eventually("minimized-bar Arrangements popover should mount") {
            findAccessibilityElement(
                in: NSApp.windows.compactMap(\.contentView),
                identifier: "arrangement-panel-pane-\(pane.id.uuidString)-zoom"
            ) != nil
        }
        let zoomButton = try #require(
            findAccessibilityElement(
                in: NSApp.windows.compactMap(\.contentView),
                identifier: "arrangement-panel-pane-\(pane.id.uuidString)-zoom"
            )
        )

        #expect(performAccessibilityPress(zoomButton))
        #expect(zoomTargets == [pane.id])
        for _ in 0..<10 {
            await Task.yield()
        }
        #expect(
            findAccessibilityElement(
                in: NSApp.windows.compactMap(\.contentView),
                identifier: "arrangement-panel-pane-\(pane.id.uuidString)-zoom"
            ) != nil
        )
    }
}

@MainActor
private func findAccessibilityElement(
    in roots: [NSView],
    identifier: String
) -> AnyObject? {
    for root in roots {
        if let match = findAccessibilityElement(in: root, identifier: identifier) {
            return match
        }
    }
    return nil
}

@MainActor
private func findAccessibilityElement(
    in root: AnyObject,
    identifier: String,
    visited: inout Set<ObjectIdentifier>
) -> AnyObject? {
    guard visited.insert(ObjectIdentifier(root)).inserted else {
        return nil
    }
    let identifierSelector = NSSelectorFromString("accessibilityIdentifier")
    if root.responds(to: identifierSelector),
        let currentIdentifier = root.perform(identifierSelector)?.takeUnretainedValue() as? String,
        currentIdentifier == identifier
    {
        return root
    }

    let childrenSelector = NSSelectorFromString("accessibilityChildren")
    if root.responds(to: childrenSelector),
        let children = root.perform(childrenSelector)?.takeUnretainedValue() as? [AnyObject]
    {
        for child in children {
            if let match = findAccessibilityElement(
                in: child,
                identifier: identifier,
                visited: &visited
            ) {
                return match
            }
        }
    }

    for subview in (root as? NSView)?.subviews ?? [] {
        if let match = findAccessibilityElement(
            in: subview,
            identifier: identifier,
            visited: &visited
        ) {
            return match
        }
    }
    return nil
}

@MainActor
private func findAccessibilityElement(
    in root: AnyObject,
    identifier: String
) -> AnyObject? {
    var visited: Set<ObjectIdentifier> = []
    return findAccessibilityElement(
        in: root,
        identifier: identifier,
        visited: &visited
    )
}

@MainActor
private func performAccessibilityPress(_ element: AnyObject) -> Bool {
    if let view = element as? NSView {
        return view.accessibilityPerformPress()
    }
    if let accessibilityElement = element as? NSAccessibilityElement {
        return accessibilityElement.accessibilityPerformPress()
    }
    return false
}
