import Foundation
import Testing

@testable import AgentStudioTestSupport

@Suite("InboxRetirementArchitectureTests")
struct InboxRetirementArchitectureTests {
    @Test("application sidebar composition is Repo Explorer only")
    func applicationSidebarCompositionIsRepoExplorerOnly() throws {
        let source = try sourceFile("Sources/AgentStudio/App/Windows/SidebarSurfaceHost.swift")

        #expect(!source.contains("import AgentStudioInboxNotification"))
        #expect(!source.contains("InboxNotificationSidebarView("))
        #expect(!source.contains("InboxNotificationAtom"))
        #expect(!source.contains("InboxNotificationPrefsAtom"))
        #expect(!source.contains("InboxSidebarState"))
        #expect(!source.contains("onShowNotificationsForWorktree"))
        #expect(!source.contains("rollUpAlertCount"))
        #expect(!source.contains("showNotifications("))
    }

    @Test("workspace boot does not activate Inbox persistence or routing")
    func workspaceBootDoesNotActivateInboxPersistenceOrRouting() throws {
        let workspaceBoot = try sourceFile("Sources/AgentStudio/App/Boot/AppDelegate+WorkspaceBoot.swift")
        let inboxBoot = try sourceFile("Sources/AgentStudio/App/Boot/AppDelegate+InboxNotificationBoot.swift")

        #expect(!workspaceBoot.contains("bootLoadInboxNotificationStore()"))
        #expect(!workspaceBoot.contains("bootStartInboxNotificationRouter("))
        #expect(!inboxBoot.contains("func bootStartTerminalActivityRouter("))
        #expect(inboxBoot.contains("Inbox presentation and ingestion are intentionally retired"))
    }

    @Test("active workspace settings do not read or write Inbox preferences")
    func activeWorkspaceSettingsDoNotReadOrWriteInboxPreferences() throws {
        let settingsStore = try sourceFile(
            "Sources/AgentStudio/App/Coordination/WorkspaceSettingsStore.swift"
        )
        let datastore = try sourceFile(
            "Sources/AgentStudio/Core/State/SQLite/WorkspaceSQLiteDatastore.swift"
        )

        #expect(!settingsStore.contains("InboxNotificationPrefsAtom"))
        #expect(!settingsStore.contains("inboxNotificationPrefs"))
        #expect(!datastore.contains("replaceInboxNotificationPreferences"))
    }

    @Test("window pane and projection composition expose no Inbox presentation")
    func appCompositionExposesNoInboxPresentation() throws {
        let mainWindow = try sourceFile("Sources/AgentStudio/App/Windows/MainWindowController.swift")
        let mainSplit = try sourceFile("Sources/AgentStudio/App/Windows/MainSplitViewController.swift")
        let tabBar = try sourceFile("Sources/AgentStudio/App/Panes/TabBar/TabBarAdapter.swift")
        let launcher = try sourceFile("Sources/AgentStudio/App/Panes/WorkspaceLauncherProjector.swift")

        #expect(!mainWindow.contains(".inboxSidebar"))
        #expect(!mainWindow.contains("showInboxToolbarAction"))
        #expect(!mainSplit.contains("makePaneInboxPresentation()"))
        #expect(!tabBar.contains("attentionLane"))
        #expect(!launcher.contains("notificationCount"))
    }

    @Test("App IPC sidebar composition is repository-only")
    func appIPCSidebarCompositionIsRepositoryOnly() throws {
        let adapter = try sourceFile(
            "Sources/AgentStudio/App/IPCComposition/AgentStudioIPCSidebarAdapter.swift"
        )
        let appIPC = try sourceFile("Sources/AgentStudio/App/Boot/AppDelegate+IPC.swift")

        #expect(!adapter.contains("InboxNotificationPrefsAtom"))
        #expect(!adapter.contains("case .inbox"))
        #expect(!appIPC.contains("inboxPrefs:"))
    }

    @Test("authoritative architecture contracts record Inbox retirement")
    func authoritativeArchitectureContractsRecordInboxRetirement() throws {
        let requiredStatements = [
            ("docs/architecture/commands/command_specs.md", "intentionally retained but retired"),
            ("docs/architecture/commands/ipc.md", "Retained Inbox command identities are not exposed"),
            ("docs/architecture/hosting/appkit_swiftui_architecture.md", "sole stable sidebar keyboard surface"),
            ("docs/architecture/state/workspace_data_architecture.md", "dormant. Normal boot"),
            ("docs/architecture/state/atom_persistence_boundaries.md", "not activated by App boot"),
            ("docs/architecture/structure/component_architecture.md", "no active App owner loads"),
            ("docs/architecture/README.md", "dormant retained Inbox rows"),
        ]

        for (path, statement) in requiredStatements {
            #expect(try sourceFile(path).contains(statement), "Missing retirement contract in \(path)")
        }
    }

    private func sourceFile(_ relativePath: String) throws -> String {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        return try String(
            contentsOf: projectRoot.appending(path: relativePath),
            encoding: .utf8
        )
    }
}
