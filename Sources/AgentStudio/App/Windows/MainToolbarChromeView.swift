import AgentStudioInfrastructure
import AppKit
import SwiftUI

enum MainToolbarControl: String, CaseIterable {
    case watchFolder = "watchFolderToolbarControl"
    case managementLayer = "managementLayerToolbarControl"
    case arrangement = "arrangementToolbarControl"
    case selectTab = "selectTabToolbarControl"
    case newTab = "newTabToolbarControl"

    var viewIdentifier: NSUserInterfaceItemIdentifier {
        NSUserInterfaceItemIdentifier(rawValue)
    }
}

/// AppKit-owned host for the app's composed tab chrome.
///
/// The toolbar item owns placement and overflow. This view only supplies the
/// existing tab surface as one flexible item. Window-drag handling lives on
/// `DraggableTabBarHostingView` itself, which owns the tab-pill hit testing
/// needed to tell a drag gesture apart from a tab click.
final class MainToolbarChromeView: NSView {
    static let viewIdentifier = NSUserInterfaceItemIdentifier("workspaceTabsToolbarControl")

    private let tabBarHostingView: DraggableTabBarHostingView

    init(tabBarHostingView: DraggableTabBarHostingView) {
        self.tabBarHostingView = tabBarHostingView
        super.init(
            frame: NSRect(
                x: 0,
                y: 0,
                width: 160,
                height: AppStyles.Shell.TabBar.height
            )
        )

        identifier = Self.viewIdentifier
        wantsLayer = true
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        tabBarHostingView.translatesAutoresizingMaskIntoConstraints = false
        tabBarHostingView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        tabBarHostingView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(tabBarHostingView)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
            tabBarHostingView.topAnchor.constraint(
                equalTo: topAnchor,
                constant: AppStyles.Shell.TabBar.stripCenterlineOffset
            ),
            tabBarHostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            tabBarHostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            tabBarHostingView.bottomAnchor.constraint(
                equalTo: bottomAnchor,
                constant: AppStyles.Shell.TabBar.stripCenterlineOffset
            ),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }
}

/// Hosts SwiftUI toolbar-control content and snaps its frame to the nearest
/// backing-store pixel boundary after every layout pass.
///
/// NSToolbar positions and sizes a custom item's view through its own internal
/// layout, not through App-owned constraints, and can land that frame at a
/// fractional point (e.g. when centering a fixed-height control within a
/// non-integral toolbar row). A fractional origin spreads hairline strokes —
/// circle and capsule outlines in these controls — across two physical pixels
/// instead of one, rendering as a visibly smeared edge on one side of the
/// shape. Re-aligning after every layout pass tolerates the toolbar re-framing
/// this view on subsequent passes.
final class ToolbarControlHostingView<Content: View>: NSHostingView<Content> {
    override func layout() {
        super.layout()
        guard let superview else { return }
        let aligned = superview.backingAlignedRect(frame, options: .alignAllEdgesNearest)
        if aligned != frame {
            frame = aligned
        }
    }
}
