import AppKit
import SwiftUI

/// Main window controller for AgentStudio
class MainWindowController: NSWindowController {
    private var splitViewController: MainSplitViewController?
    private var sidebarAccessory: NSTitlebarAccessoryViewController?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "AgentStudio"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
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

        // Set up titlebar and toolbar
        setupTitlebarAccessory()
        setupToolbar()
    }

    // MARK: - Titlebar Accessory

    private func setupTitlebarAccessory() {
        // Sidebar toggle button - fixed position next to traffic lights (standard macOS pattern)
        let toggleButton = NSButton(frame: NSRect(x: 0, y: 0, width: 36, height: 28))
        toggleButton.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: "Toggle Sidebar")
        toggleButton.bezelStyle = .accessoryBarAction
        toggleButton.isBordered = false
        toggleButton.target = self
        toggleButton.action = #selector(toggleSidebarAction)
        toggleButton.toolTip = "Toggle Sidebar (⌘\\)"

        let accessoryVC = NSTitlebarAccessoryViewController()
        accessoryVC.view = toggleButton
        accessoryVC.layoutAttribute = .left

        window?.addTitlebarAccessoryViewController(accessoryVC)
        self.sidebarAccessory = accessoryVC
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

    @objc private func toggleSidebarAction() {
        toggleSidebar()
    }
}

// MARK: - NSToolbarDelegate

extension MainWindowController: NSToolbarDelegate {
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [
            .flexibleSpace,
            .addRepo
        ]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch itemIdentifier {
        case .addRepo:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Add Repo"
            item.paletteLabel = "Add Repo"
            item.toolTip = "Add a repo (⌘⇧O)"
            item.isBordered = true
            item.image = NSImage(systemSymbolName: "folder.badge.plus", accessibilityDescription: "Add Repo")
            item.action = #selector(addRepoAction)
            item.target = self
            return item

        default:
            return nil
        }
    }

    @objc private func addRepoAction() {
        NotificationCenter.default.post(name: .addRepoRequested, object: nil)
    }
}

// MARK: - Toolbar Item Identifiers

extension NSToolbarItem.Identifier {
    static let addRepo = NSToolbarItem.Identifier("addRepo")
}
