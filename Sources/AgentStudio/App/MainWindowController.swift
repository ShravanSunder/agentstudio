import AppKit

/// Main window controller for AgentStudio
class MainWindowController: NSWindowController {
    private var splitViewController: MainSplitViewController?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "AgentStudio"
        window.titlebarAppearsTransparent = false
        window.titleVisibility = .visible
        window.minSize = NSSize(width: 800, height: 500)

        // Center on screen
        window.center()

        // Restore frame if saved
        window.setFrameAutosaveName("MainWindow")

        self.init(window: window)

        // Create and set content view controller
        let splitVC = MainSplitViewController()
        self.splitViewController = splitVC
        window.contentViewController = splitVC

        // Set up toolbar
        setupToolbar()
    }

    // MARK: - Toolbar

    private func setupToolbar() {
        let toolbar = NSToolbar(identifier: "MainToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window?.toolbar = toolbar
        window?.toolbarStyle = .unified
    }

    // MARK: - Actions

    func toggleSidebar() {
        splitViewController?.toggleSidebar(nil)
    }
}

// MARK: - NSToolbarDelegate

extension MainWindowController: NSToolbarDelegate {
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [
            .toggleSidebar,
            .flexibleSpace,
            .addProject,
            .refresh
        ]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch itemIdentifier {
        case .toggleSidebar:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Toggle Sidebar"
            item.paletteLabel = "Toggle Sidebar"
            item.toolTip = "Toggle Sidebar"
            item.isBordered = true
            item.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: "Toggle Sidebar")
            item.action = #selector(toggleSidebarAction)
            item.target = self
            return item

        case .addProject:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Add Project"
            item.paletteLabel = "Add Project"
            item.toolTip = "Add a project"
            item.isBordered = true
            item.image = NSImage(systemSymbolName: "folder.badge.plus", accessibilityDescription: "Add Project")
            item.action = #selector(addProjectAction)
            item.target = self
            return item

        case .refresh:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Refresh"
            item.paletteLabel = "Refresh"
            item.toolTip = "Refresh worktrees"
            item.isBordered = true
            item.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh")
            item.action = #selector(refreshAction)
            item.target = self
            return item

        default:
            return nil
        }
    }

    @objc private func toggleSidebarAction() {
        toggleSidebar()
    }

    @objc private func addProjectAction() {
        NotificationCenter.default.post(name: .addProjectRequested, object: nil)
    }

    @objc private func refreshAction() {
        NotificationCenter.default.post(name: .refreshWorktreesRequested, object: nil)
    }
}

// MARK: - Toolbar Item Identifiers

extension NSToolbarItem.Identifier {
    static let addProject = NSToolbarItem.Identifier("addProject")
    static let refresh = NSToolbarItem.Identifier("refresh")
}

