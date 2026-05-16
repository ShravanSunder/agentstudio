import AppKit
import Foundation

@testable import AgentStudio

func makeSourceNotification(
    paneId: UUID = UUID(),
    repoId: UUID? = nil,
    repoName: String? = nil,
    worktreeName: String? = nil,
    paneDisplayLabel: String? = nil,
    tabDisplayLabel: String? = nil
) -> InboxNotification {
    InboxNotification(
        id: UUID(),
        timestamp: Date(timeIntervalSince1970: 100),
        kind: .agentRpc,
        title: "Done",
        body: nil,
        source: .pane(
            .init(
                paneId: paneId,
                tabDisplayLabel: tabDisplayLabel,
                repoId: repoId,
                repoName: repoName,
                worktreeName: worktreeName,
                paneDisplayLabel: paneDisplayLabel
            )
        ),
        isRead: false,
        isDismissedFromPaneInbox: false
    )
}

@MainActor
func inboxSidebarDescendant(in view: NSView, identifier: String) -> NSView? {
    if view.identifier?.rawValue == identifier {
        return view
    }

    for subview in view.subviews {
        if let match = inboxSidebarDescendant(in: subview, identifier: identifier) {
            return match
        }
    }

    return nil
}

@MainActor
func inboxSidebarAccessibleElement(in root: AnyObject, identifier: String) -> AnyObject? {
    var visited: Set<ObjectIdentifier> = []
    return inboxSidebarAccessibleElement(in: root, identifier: identifier, visited: &visited)
}

@MainActor
func inboxSidebarAccessibleElementCount(in root: AnyObject, identifier: String) -> Int {
    var visited: Set<ObjectIdentifier> = []
    return inboxSidebarAccessibleElementCount(in: root, identifier: identifier, visited: &visited)
}

@MainActor
func inboxSidebarAccessibleElementLabels(in root: AnyObject, identifier: String) -> [String] {
    var visited: Set<ObjectIdentifier> = []
    return inboxSidebarAccessibleElementLabels(in: root, identifier: identifier, visited: &visited)
}

func inboxSidebarAccessibilityLabel(of element: AnyObject) -> String? {
    let selector = NSSelectorFromString("accessibilityLabel")
    guard element.responds(to: selector) else { return nil }
    return element.perform(selector)?.takeUnretainedValue() as? String
}

func pressInboxSidebarAccessibleElement(_ element: AnyObject) {
    let selector = NSSelectorFromString("accessibilityPerformPress")
    guard element.responds(to: selector) else { return }
    _ = element.perform(selector)
}

@MainActor
private func inboxSidebarAccessibleElement(
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
        if let match = inboxSidebarAccessibleElement(in: child, identifier: identifier, visited: &visited) {
            return match
        }
    }

    for subview in (element as? NSView)?.subviews ?? [] {
        if let match = inboxSidebarAccessibleElement(in: subview, identifier: identifier, visited: &visited) {
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

@MainActor
private func inboxSidebarAccessibleElementLabels(
    in element: AnyObject,
    identifier: String,
    visited: inout Set<ObjectIdentifier>
) -> [String] {
    let objectIdentifier = ObjectIdentifier(element)
    guard visited.insert(objectIdentifier).inserted else { return [] }

    let currentLabel: [String]
    if accessibilityIdentifier(of: element) == identifier, let label = inboxSidebarAccessibilityLabel(of: element) {
        currentLabel = [label]
    } else {
        currentLabel = []
    }

    let childLabels = accessibilityChildren(of: element).flatMap { child in
        inboxSidebarAccessibleElementLabels(in: child, identifier: identifier, visited: &visited)
    }
    let subviewLabels = ((element as? NSView)?.subviews ?? []).flatMap { subview in
        inboxSidebarAccessibleElementLabels(in: subview, identifier: identifier, visited: &visited)
    }
    return currentLabel + childLabels + subviewLabels
}

@MainActor
private func inboxSidebarAccessibleElementCount(
    in element: AnyObject,
    identifier: String,
    visited: inout Set<ObjectIdentifier>
) -> Int {
    let objectIdentifier = ObjectIdentifier(element)
    guard visited.insert(objectIdentifier).inserted else { return 0 }

    let currentCount = accessibilityIdentifier(of: element) == identifier ? 1 : 0
    let childCount = accessibilityChildren(of: element).reduce(0) { count, child in
        count + inboxSidebarAccessibleElementCount(in: child, identifier: identifier, visited: &visited)
    }
    let subviewCount = ((element as? NSView)?.subviews ?? []).reduce(0) { count, subview in
        count + inboxSidebarAccessibleElementCount(in: subview, identifier: identifier, visited: &visited)
    }
    return currentCount + childCount + subviewCount
}
