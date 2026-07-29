import AgentStudioInfrastructure
import AppKit
import SwiftUI

@MainActor
private func ancestorChainDescription(for view: NSView) -> String {
    var nodes: [String] = []
    var current: NSView? = view
    while let currentView = current {
        nodes.append("class=\(type(of: currentView)) id=\(ObjectIdentifier(currentView))")
        current = currentView.superview
    }
    return nodes.joined(separator: " -> ")
}

/// Bridges any PaneHostView (NSView) into SwiftUI.
/// Returns the stable swiftUIContainer — same NSView every time, preventing IOSurface reparenting.
struct PaneViewRepresentable: NSViewRepresentable {
    let paneHost: PaneHostView

    #if DEBUG
        static var onDismantleForTesting: (() -> Void)?
    #endif

    func makeNSView(context: Context) -> NSView {
        RestoreTrace.log(
            "PaneViewRepresentable.makeNSView paneId=\(paneHost.paneId) containerId=\(ObjectIdentifier(paneHost.swiftUIContainer)) hostId=\(ObjectIdentifier(paneHost))"
        )
        return paneHost.swiftUIContainer
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Nothing — container is stable, pane manages itself.
        // Host replacement is handled by .id(paneHost.hostIdentity) on the
        // PaneViewRepresentable call site, which forces SwiftUI to dismantle
        // and recreate when the host instance changes.
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        RestoreTrace.log(
            "PaneViewRepresentable.dismantleNSView viewId=\(ObjectIdentifier(nsView)) superview=\(nsView.superview != nil) window=\(nsView.window != nil) ancestry=\(ancestorChainDescription(for: nsView))"
        )
        #if DEBUG
            onDismantleForTesting?()
        #endif
    }
}

@available(*, deprecated, renamed: "PaneLeafContainer")
typealias TerminalPaneLeaf = PaneLeafContainer
