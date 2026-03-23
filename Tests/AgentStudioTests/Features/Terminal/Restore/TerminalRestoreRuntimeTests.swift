import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct TerminalRestoreRuntimeTests {
    @Test
    func zmxSessionId_usesWorktreeIdentity_forTopLevelPane() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-restore-runtime-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = WorkspaceStore(persistor: WorkspacePersistor(workspacesDir: tempDir))
        let repo = store.addRepo(at: tempDir)
        let worktree = try #require(repo.worktrees.first)
        let pane = store.createPane(
            source: .worktree(worktreeId: worktree.id, repoId: repo.id),
            provider: .zmx
        )
        let runtime = TerminalRestoreRuntime(
            sessionConfiguration: SessionConfiguration(
                isEnabled: true,
                backgroundRestorePolicy: .existingSessionsOnly,
                zmxPath: "/tmp/fake-zmx",
                zmxDir: "/tmp/fake-zmx-dir",
                healthCheckInterval: 30,
                maxCheckpointAge: 60
            )
        )

        let sessionId = runtime.zmxSessionId(for: pane, store: store)

        #expect(
            sessionId
                == ZmxBackend.sessionId(
                    repoStableKey: repo.stableKey,
                    worktreeStableKey: worktree.stableKey,
                    paneId: pane.id
                )
        )
    }

    @Test
    func zmxSessionId_usesDrawerIdentity_forDrawerPane() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-restore-runtime-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = WorkspaceStore(persistor: WorkspacePersistor(workspacesDir: tempDir))
        let repo = store.addRepo(at: tempDir)
        let worktree = try #require(repo.worktrees.first)
        let parentPane = store.createPane(
            source: .worktree(worktreeId: worktree.id, repoId: repo.id),
            provider: .zmx
        )
        let drawerPane = try #require(store.addDrawerPane(to: parentPane.id))
        let runtime = TerminalRestoreRuntime(
            sessionConfiguration: SessionConfiguration(
                isEnabled: true,
                backgroundRestorePolicy: .existingSessionsOnly,
                zmxPath: "/tmp/fake-zmx",
                zmxDir: "/tmp/fake-zmx-dir",
                healthCheckInterval: 30,
                maxCheckpointAge: 60
            )
        )

        let sessionId = runtime.zmxSessionId(for: drawerPane, store: store)

        #expect(
            sessionId
                == ZmxBackend.drawerSessionId(
                    parentPaneId: parentPane.id,
                    drawerPaneId: drawerPane.id
                )
        )
    }

    @Test
    func zmxSessionId_usesFloatingWorkingDirectory_whenCwdExists() {
        let store = WorkspaceStore()
        let workingDirectory = FileManager.default.homeDirectoryForCurrentUser.appending(path: "tmp")
        let pane = store.createPane(
            source: .floating(workingDirectory: workingDirectory, title: nil),
            provider: .zmx
        )
        let runtime = TerminalRestoreRuntime(
            sessionConfiguration: SessionConfiguration(
                isEnabled: true,
                backgroundRestorePolicy: .existingSessionsOnly,
                zmxPath: "/tmp/fake-zmx",
                zmxDir: "/tmp/fake-zmx-dir",
                healthCheckInterval: 30,
                maxCheckpointAge: 60
            )
        )

        let sessionId = runtime.zmxSessionId(for: pane, store: store)

        #expect(
            sessionId
                == ZmxBackend.floatingSessionId(
                    workingDirectory: workingDirectory,
                    paneId: pane.id
                )
        )
    }

    @Test
    func zmxSessionId_fallsBackToHomeDirectory_forFloatingPaneWithoutCwd() {
        let store = WorkspaceStore()
        let pane = store.createPane(
            source: .floating(workingDirectory: nil, title: nil),
            provider: .zmx
        )
        let runtime = TerminalRestoreRuntime(
            sessionConfiguration: SessionConfiguration(
                isEnabled: true,
                backgroundRestorePolicy: .existingSessionsOnly,
                zmxPath: "/tmp/fake-zmx",
                zmxDir: "/tmp/fake-zmx-dir",
                healthCheckInterval: 30,
                maxCheckpointAge: 60
            )
        )

        let sessionId = runtime.zmxSessionId(for: pane, store: store)

        #expect(
            sessionId
                == ZmxBackend.floatingSessionId(
                    workingDirectory: FileManager.default.homeDirectoryForCurrentUser,
                    paneId: pane.id
                )
        )
    }
}
