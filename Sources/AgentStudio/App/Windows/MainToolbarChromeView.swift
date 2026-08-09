import AgentStudioInfrastructure
import AppKit

enum MainToolbarControl: String, CaseIterable {
    case worktree = "worktreeToolbarControl"
    case inbox = "inboxToolbarControl"
    case watchFolder = "watchFolderToolbarControl"
    case managementLayer = "managementLayerToolbarControl"
    case arrangement = "arrangementToolbarControl"
    case selectTab = "selectTabToolbarControl"
    case newTab = "newTabToolbarControl"

    var viewIdentifier: NSUserInterfaceItemIdentifier {
        NSUserInterfaceItemIdentifier(rawValue)
    }
}

/// AppKit-owned host for the app's composed tab and window-drag chrome.
///
/// The toolbar item owns placement and overflow. This view only supplies the
/// existing tab surface and its explicit draggable gap as one flexible item.
final class MainToolbarChromeView: NSView {
    static let viewIdentifier = NSUserInterfaceItemIdentifier("workspaceTabsToolbarControl")

    private let tabBarHostingView: DraggableTabBarHostingView
    private let dragRegionView = ShellChromeDragRegionView()

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

        dragRegionView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dragRegionView, positioned: .above, relativeTo: tabBarHostingView)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: AppStyles.Shell.TabBar.height),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
            tabBarHostingView.topAnchor.constraint(equalTo: topAnchor),
            tabBarHostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            tabBarHostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            tabBarHostingView.heightAnchor.constraint(equalToConstant: AppStyles.Shell.TabBar.height),
            dragRegionView.topAnchor.constraint(equalTo: topAnchor),
            dragRegionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            dragRegionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            dragRegionView.heightAnchor.constraint(
                equalToConstant: AppStyles.Shell.Chrome.windowDragRegionHeight
            ),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }
}
