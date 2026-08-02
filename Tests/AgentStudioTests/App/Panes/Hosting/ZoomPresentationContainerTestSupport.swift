import AppKit

@testable import AgentStudio
@testable import AgentStudioSharedComponents

@MainActor
struct ZoomPresentationContainerFixture {
    let sourcePaneId: UUID
    let companionPaneId: UUID
    let viewRegistry: ViewRegistry
    let sourcePaneSlot: ViewRegistry.PaneViewSlot
    let companionPaneSlot: ViewRegistry.PaneViewSlot
    let sourcePaneHost: PaneHostView
    let companionPaneHost: PaneHostView
    let recorder: ZoomPresentationContainerActionRecorder
}

struct MountedToolbarState {
    let accessibilityIdentifiers: [String]
    let toolbarControlFrames: [String: CGRect]
}

struct MountedPaneLeafState {
    let contentHeight: CGFloat
    let accessibilityIdentifiers: [String]
    let toolbarControlFrames: [String: CGRect]
}

@MainActor
final class ZoomPresentationContainerActionRecorder {
    private(set) var viewerSourcePaneIds: [UUID] = []
    private(set) var zoomSourcePaneIds: [UUID] = []

    func recordViewer(sourcePaneId: UUID) {
        viewerSourcePaneIds.append(sourcePaneId)
    }

    func recordZoom(sourcePaneId: UUID) {
        zoomSourcePaneIds.append(sourcePaneId)
    }
}

@MainActor
func zoomTestAccessibilityIdentifiers(in root: AnyObject) -> [String] {
    var identifiers: [String] = []
    var visited: Set<ObjectIdentifier> = []
    collectAccessibilityIdentifiers(
        in: root,
        identifiers: &identifiers,
        visited: &visited
    )
    return identifiers
}

@MainActor
private func collectAccessibilityIdentifiers(
    in element: AnyObject,
    identifiers: inout [String],
    visited: inout Set<ObjectIdentifier>
) {
    let objectIdentifier = ObjectIdentifier(element)
    guard visited.insert(objectIdentifier).inserted else { return }

    let identifierSelector = NSSelectorFromString("accessibilityIdentifier")
    if element.responds(to: identifierSelector),
        let identifier = element.perform(identifierSelector)?.takeUnretainedValue() as? String
    {
        identifiers.append(identifier)
    }

    let childrenSelector = NSSelectorFromString("accessibilityChildren")
    if element.responds(to: childrenSelector),
        let children = element.perform(childrenSelector)?.takeUnretainedValue() as? [AnyObject]
    {
        for child in children {
            collectAccessibilityIdentifiers(
                in: child,
                identifiers: &identifiers,
                visited: &visited
            )
        }
    }

    for subview in (element as? NSView)?.subviews ?? [] {
        collectAccessibilityIdentifiers(
            in: subview,
            identifiers: &identifiers,
            visited: &visited
        )
    }
}

@MainActor
func zoomTestAccessibilityPressBridgeView(
    in root: NSView,
    identifier: String
) -> AccessibilityPressBridgeView? {
    if let bridgeView = root as? AccessibilityPressBridgeView,
        bridgeView.accessibilityIdentifier() == identifier
    {
        return bridgeView
    }
    for subview in root.subviews {
        if let bridgeView = zoomTestAccessibilityPressBridgeView(
            in: subview,
            identifier: identifier
        ) {
            return bridgeView
        }
    }
    return nil
}

@MainActor
func zoomTestToolbarControlFrames(in root: NSView) -> [String: CGRect] {
    var frames: [String: CGRect] = [:]
    collectToolbarControlFrames(in: root, relativeTo: root, frames: &frames)
    return frames
}

@MainActor
private func collectToolbarControlFrames(
    in view: NSView,
    relativeTo root: NSView,
    frames: inout [String: CGRect]
) {
    if let bridgeView = view as? AccessibilityPressBridgeView {
        let identifier = bridgeView.accessibilityIdentifier()
        if identifier.hasPrefix("paneSurfaceToolbar.") {
            frames[identifier] = bridgeView.convert(bridgeView.bounds, to: root)
        }
    }

    for subview in view.subviews {
        collectToolbarControlFrames(
            in: subview,
            relativeTo: root,
            frames: &frames
        )
    }
}
