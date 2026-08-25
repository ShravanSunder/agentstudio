import Foundation
import Testing

@testable import AgentStudioTestSupport

@Suite("InboxRetirementArchitectureTests")
struct InboxRetirementArchitectureTests {
    @Test("dormant Inbox owners carry the canonical retirement contract")
    func dormantInboxOwnersCarryCanonicalRetirementContract() throws {
        let retirementContract = """
            /// Inbox presentation and ingestion are intentionally retired.
            /// Source and persisted rows remain only for a later data-safe removal.
            /// Do not reconnect these owners to App, command, toolbar, shortcut, IPC, or runtime-bus composition without a new product decision.
            """
        let dormantOwnerDeclarations = [
            (
                "Sources/AgentStudio/Features/InboxNotification/State/MainActor/Persistence/InboxNotificationStore.swift",
                "package final class InboxNotificationStore"
            ),
            (
                "Sources/AgentStudio/Features/InboxNotification/Views/InboxNotificationSidebarView.swift",
                "package struct InboxNotificationSidebarView"
            ),
            (
                "Sources/AgentStudio/Features/InboxNotification/Routing/InboxNotificationRouter.swift",
                "package final class InboxNotificationRouter"
            ),
        ]

        for (path, declaration) in dormantOwnerDeclarations {
            let source = try sourceFile(path)
            #expect(
                source.contains("\(retirementContract)\n@MainActor\n\(declaration)"),
                "Missing canonical retirement contract at \(path)'s owner entrypoint"
            )
        }
    }

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

    @Test("performance diagnostics and Repo Explorer contain no retained Inbox execution seams")
    func performanceDiagnosticsAndRepoExplorerContainNoInboxExecutionSeams() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let appBootRoot = projectRoot.appending(path: "Sources/AgentStudio/App/Boot")
        let startupDiagnosticSources = try FileManager.default.contentsOfDirectory(
            at: appBootRoot,
            includingPropertiesForKeys: nil
        )
        .filter {
            $0.pathExtension == "swift"
                && $0.lastPathComponent.contains("StartupDiagnostic")
        }
        .map { try String(contentsOf: $0, encoding: .utf8) }
        let repoExplorerView = try sourceFile(
            "Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView.swift"
        )
        let worktreeRow = try sourceFile(
            "Sources/AgentStudio/Features/RepoExplorer/RepoExplorerWorktreeRow.swift"
        )
        let retiredProjectionPath = projectRoot.appending(
            path: "Sources/AgentStudio/App/Panes/WorkspaceNotificationCountProjection.swift"
        )

        for startupDiagnosticSource in startupDiagnosticSources {
            #expect(!startupDiagnosticSource.contains("AgentStudioInboxNotification"))
            #expect(!startupDiagnosticSource.contains("runInboxSidebarProjectionProof"))
            #expect(!startupDiagnosticSource.contains("atomStore.inboxNotification"))
            #expect(!startupDiagnosticSource.contains("InboxNotification("))
            #expect(!startupDiagnosticSource.contains("InboxNotificationListProjectionWorker"))
        }
        #expect(!repoExplorerView.contains("onShowNotificationsForWorktree"))
        #expect(!repoExplorerView.contains("unreadCount"))
        #expect(!worktreeRow.contains("onUnreadPillTap"))
        #expect(!worktreeRow.contains("unreadCount"))
        #expect(!FileManager.default.fileExists(atPath: retiredProjectionPath.path))
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
