import AgentStudioRepoExplorer
import AppKit

@MainActor
enum SidebarPerformanceProofAccessibility {
    static func selectedRepoGroupingMode(
        in rootView: NSView
    ) -> RepoExplorerGroupingMode? {
        for groupingMode in RepoExplorerGroupingMode.allCases {
            var visited: Set<ObjectIdentifier> = []
            guard
                let element = accessibilityElement(
                    in: rootView,
                    identifier: "repoSidebarGroupingSegment.\(groupingMode.rawValue)",
                    visited: &visited
                )
            else { continue }
            if isAccessibilitySelected(element) { return groupingMode }
        }
        return nil
    }

    private static func isAccessibilitySelected(_ element: AnyObject) -> Bool {
        guard let accessibilityElement = element as? any NSAccessibilityProtocol else { return false }
        return accessibilityElement.isAccessibilitySelected()
    }

    static func firstDescendant<Descendant: NSView>(
        of type: Descendant.Type,
        in rootView: NSView
    ) -> Descendant? {
        if let match = rootView as? Descendant { return match }
        for subview in rootView.subviews {
            if let match = firstDescendant(of: type, in: subview) { return match }
        }
        return nil
    }

    static func isEffectivelyVisible(_ view: NSView) -> Bool {
        guard view.window != nil else { return false }
        var currentView: NSView? = view
        while let candidate = currentView {
            if candidate.isHidden { return false }
            currentView = candidate.superview
        }
        return true
    }

    private static func accessibilityElement(
        in element: AnyObject,
        identifier: String,
        visited: inout Set<ObjectIdentifier>
    ) -> AnyObject? {
        let objectIdentifier = ObjectIdentifier(element)
        guard visited.count < 4096, visited.insert(objectIdentifier).inserted else { return nil }
        if accessibilityIdentifier(of: element) == identifier { return element }
        for child in accessibilityChildren(of: element) {
            if let match = accessibilityElement(
                in: child,
                identifier: identifier,
                visited: &visited
            ) {
                return match
            }
        }
        for subview in (element as? NSView)?.subviews ?? [] {
            if let match = accessibilityElement(
                in: subview,
                identifier: identifier,
                visited: &visited
            ) {
                return match
            }
        }
        return nil
    }

    private static func accessibilityIdentifier(of element: AnyObject) -> String? {
        guard let accessibilityElement = element as? any NSAccessibilityProtocol else { return nil }
        return accessibilityElement.accessibilityIdentifier()
    }

    private static func accessibilityChildren(of element: AnyObject) -> [AnyObject] {
        guard let accessibilityElement = element as? any NSAccessibilityProtocol else { return [] }
        return (accessibilityElement.accessibilityChildren() ?? []).map { $0 as AnyObject }
    }

}
