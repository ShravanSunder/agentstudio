import AppKit
import SwiftUI
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct CommandBarAccessibilityTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    @Test("group header and selected row expose header, identity, action, and selection semantics")
    func groupAndSelectedRowExposeCompleteSemantics() throws {
        let item = CommandBarItem(
            id: "recent-repository",
            title: "agent-studio",
            subtitle: "main",
            group: "Recent Repositories",
            groupPriority: 0,
            action: .activateRecent(
                .repository(repositoryStableKey: String(repeating: "a", count: 16))
            ),
            accessibilityLabel: "agent-studio, main, /tmp/agent-studio",
            accessibilityHint: "Show repository actions"
        )
        let mountedView = mountedView(
            CommandBarResultsList(
                groups: [
                    CommandBarItemGroup(
                        id: "Recent Repositories",
                        name: "Recent Repositories",
                        priority: 0,
                        items: [item]
                    )
                ],
                selectedIndex: 0,
                onSelect: { _ in }
            )
            .frame(width: 500, height: 160)
        )
        defer { mountedView.window.orderOut(nil) }

        let header = try #require(
            findCommandBarAccessibleElement(
                in: mountedView.hostingView,
                identifier: "commandBarGroupHeader.Recent Repositories"
            )
        )
        let row = try #require(
            findCommandBarAccessibleElement(
                in: mountedView.hostingView,
                identifier: "commandBarResultRow.recent-repository"
            )
        )

        #expect(commandBarAccessibilityRole(of: header) == "AXHeading")
        #expect(commandBarAccessibilityLabel(of: row) == "agent-studio, main, /tmp/agent-studio")
        #expect(commandBarAccessibilityHelp(of: row) == "Show repository actions")
        #expect(commandBarAccessibilitySelected(of: row) == true)
    }

    @Test("breadcrumb exposes clickable ancestors and a non-clickable current level")
    func breadcrumbExposesClickableAncestors() throws {
        var selectedBreadcrumbIndex: Int?
        let mountedView = mountedView(
            CommandBarBreadcrumbRow(
                items: [
                    CommandBarBreadcrumbItem(
                        label: "Main",
                        accessibilityLabel: "Main",
                        icon: nil
                    ),
                    CommandBarBreadcrumbItem(
                        label: "actual",
                        accessibilityLabel: "Repository actual",
                        icon: .coloredRepo(
                            colorHex: AppStyles.Shell.Sidebar.accentPaletteHexes[0]
                        )
                    ),
                    CommandBarBreadcrumbItem(
                        label: "actual",
                        accessibilityLabel: "Worktree actual",
                        icon: .checkout(
                            colorHex: AppStyles.Shell.Sidebar.accentPaletteHexes[0],
                            isMain: true
                        )
                    ),
                ],
                onNavigate: { selectedBreadcrumbIndex = $0 }
            )
            .frame(width: 500, height: 28)
        )
        defer { mountedView.window.orderOut(nil) }
        let rootBreadcrumb = try #require(
            findCommandBarAccessibleElement(
                in: mountedView.hostingView,
                identifier: "commandBarBreadcrumb.0"
            )
        )

        #expect(commandBarAccessibilityLabel(of: rootBreadcrumb) == "Navigate to Main")
        #expect(commandBarAccessibilityHelp(of: rootBreadcrumb) == "Return to this Command Bar level")
        commandBarPerformAccessibilityPress(rootBreadcrumb)
        #expect(selectedBreadcrumbIndex == 0)
        #expect(
            findCommandBarAccessibleElement(
                in: mountedView.hostingView,
                identifier: "commandBarBreadcrumb.2"
            ) == nil
        )
    }

    private func mountedView<Content: View>(
        _ content: Content
    ) -> (window: NSWindow, hostingView: NSHostingView<Content>) {
        let hostingView = NSHostingView(rootView: content)
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 500, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        hostingView.layoutSubtreeIfNeeded()
        return (window, hostingView)
    }
}

@MainActor
private func findCommandBarAccessibleElement(
    in root: AnyObject,
    identifier: String,
    visited: inout Set<ObjectIdentifier>
) -> AnyObject? {
    let objectIdentifier = ObjectIdentifier(root)
    guard visited.insert(objectIdentifier).inserted else { return nil }
    if commandBarAccessibilityIdentifier(of: root) == identifier {
        return root
    }
    for child in commandBarAccessibilityChildren(of: root) {
        if let match = findCommandBarAccessibleElement(
            in: child,
            identifier: identifier,
            visited: &visited
        ) {
            return match
        }
    }
    for subview in (root as? NSView)?.subviews ?? [] {
        if let match = findCommandBarAccessibleElement(
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
private func findCommandBarAccessibleElement(
    in root: AnyObject,
    identifier: String
) -> AnyObject? {
    var visited = Set<ObjectIdentifier>()
    return findCommandBarAccessibleElement(
        in: root,
        identifier: identifier,
        visited: &visited
    )
}

@MainActor
private func commandBarAccessibilityIdentifier(of element: AnyObject) -> String? {
    commandBarAccessibilityValue(of: element, selectorName: "accessibilityIdentifier") as? String
}

@MainActor
private func commandBarAccessibilityLabel(of element: AnyObject) -> String? {
    commandBarAccessibilityValue(of: element, selectorName: "accessibilityLabel") as? String
}

@MainActor
private func commandBarAccessibilityHelp(of element: AnyObject) -> String? {
    commandBarAccessibilityValue(of: element, selectorName: "accessibilityHelp") as? String
}

@MainActor
private func commandBarAccessibilityRole(of element: AnyObject) -> String? {
    commandBarAccessibilityValue(of: element, selectorName: "accessibilityRole") as? String
}

@MainActor
private func commandBarAccessibilitySelected(of element: AnyObject) -> Bool? {
    element.isAccessibilitySelected?()
}

@MainActor
private func commandBarAccessibilityChildren(of element: AnyObject) -> [AnyObject] {
    commandBarAccessibilityValue(of: element, selectorName: "accessibilityChildren")
        as? [AnyObject] ?? []
}

@MainActor
private func commandBarAccessibilityValue(
    of element: AnyObject,
    selectorName: String
) -> Any? {
    let selector = NSSelectorFromString(selectorName)
    guard element.responds(to: selector) else { return nil }
    return element.perform(selector)?.takeUnretainedValue()
}

@MainActor
private func commandBarPerformAccessibilityPress(_ element: AnyObject) {
    let selector = NSSelectorFromString("accessibilityPerformPress")
    guard element.responds(to: selector) else { return }
    _ = element.perform(selector)
}
