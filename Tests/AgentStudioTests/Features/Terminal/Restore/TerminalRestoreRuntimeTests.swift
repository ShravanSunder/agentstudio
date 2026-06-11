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
            source: .worktree(worktreeId: worktree.id, repoId: repo.id, launchDirectory: worktree.path),
            provider: .zmx
        )
        let runtime = TerminalRestoreRuntime(
            sessionConfiguration: SessionConfiguration(
                isEnabled: true,
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
            source: .worktree(worktreeId: worktree.id, repoId: repo.id, launchDirectory: worktree.path),
            provider: .zmx
        )
        let drawerPane = try #require(store.addDrawerPane(to: parentPane.id))
        let runtime = TerminalRestoreRuntime(
            sessionConfiguration: SessionConfiguration(
                isEnabled: true,
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
        let launchDirectory = FileManager.default.homeDirectoryForCurrentUser.appending(path: "tmp")
        let pane = store.createPane(
            source: .floating(launchDirectory: launchDirectory, title: nil),
            provider: .zmx
        )
        let runtime = TerminalRestoreRuntime(
            sessionConfiguration: SessionConfiguration(
                isEnabled: true,
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
                    launchDirectory: launchDirectory,
                    paneId: pane.id
                )
        )
    }

    @Test
    func zmxSessionId_fallsBackToHomeDirectory_forFloatingPaneWithoutCwd() {
        let store = WorkspaceStore()
        let pane = store.createPane(
            source: .floating(launchDirectory: nil, title: nil),
            provider: .zmx
        )
        let runtime = TerminalRestoreRuntime(
            sessionConfiguration: SessionConfiguration(
                isEnabled: true,
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
                    launchDirectory: FileManager.default.homeDirectoryForCurrentUser,
                    paneId: pane.id
                )
        )
    }

    @Test
    func zmxSessionId_followsLiveFacets_whenPaneRoamsToAnotherWorktree() throws {
        // Characterization of CURRENT behavior (zmx-session-anchor plan T0):
        // session identity is re-derived from LIVE facets at attach time, so a
        // pane that roamed (cwd into another worktree) resolves to a session id
        // under the NEW worktree — abandoning the shell it actually spawned in.
        // T3 flips this test: a stored spawn-time id must win over derivation.
        let tempDirA = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-restore-roam-a-\(UUID().uuidString)")
        let tempDirB = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-restore-roam-b-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: tempDirA)
            try? FileManager.default.removeItem(at: tempDirB)
        }

        let store = WorkspaceStore(persistor: WorkspacePersistor(workspacesDir: tempDirA))
        let repoA = store.addRepo(at: tempDirA)
        let worktreeA = try #require(repoA.worktrees.first)
        let repoB = store.addRepo(at: tempDirB)
        let worktreeB = try #require(repoB.worktrees.first)
        let bornPane = store.createPane(
            source: .worktree(worktreeId: worktreeA.id, repoId: repoA.id, launchDirectory: worktreeA.path),
            provider: .zmx
        )

        // Roam: the live facet rewrite that PaneCoordinator performs on cwd change.
        _ = store.paneAtom.updatePaneCWDAndResolvedContext(
            bornPane.id,
            cwd: worktreeB.path,
            resolvedContext: (repo: repoB, worktree: worktreeB)
        )
        let roamedPane = try #require(store.paneAtom.pane(bornPane.id))

        let runtime = TerminalRestoreRuntime(
            sessionConfiguration: SessionConfiguration(
                isEnabled: true,
                zmxPath: "/tmp/fake-zmx",
                zmxDir: "/tmp/fake-zmx-dir",
                healthCheckInterval: 30,
                maxCheckpointAge: 60
            )
        )

        let sessionId = runtime.zmxSessionId(for: roamedPane, store: store)

        // CURRENT (pre-anchor) behavior: derivation follows worktree B.
        #expect(
            sessionId
                == ZmxBackend.sessionId(
                    repoStableKey: repoB.stableKey,
                    worktreeStableKey: worktreeB.stableKey,
                    paneId: bornPane.id
                )
        )
        // The session the shell actually lives in is keyed under worktree A.
        #expect(
            sessionId
                != ZmxBackend.sessionId(
                    repoStableKey: repoA.stableKey,
                    worktreeStableKey: worktreeA.stableKey,
                    paneId: bornPane.id
                )
        )
    }

    @Test
    func zmxAttachCommand_isNil_whenSessionRestoreIsDisabled() {
        let store = WorkspaceStore()
        let pane = store.createPane(
            source: .floating(launchDirectory: FileManager.default.homeDirectoryForCurrentUser, title: nil),
            provider: .zmx
        )
        let runtime = TerminalRestoreRuntime(
            sessionConfiguration: SessionConfiguration(
                isEnabled: false,
                zmxPath: "/tmp/fake-zmx",
                zmxDir: "/tmp/fake-zmx-dir",
                healthCheckInterval: 30,
                maxCheckpointAge: 60
            )
        )

        #expect(runtime.zmxAttachCommand(for: pane, store: store) == nil)
        #expect(runtime.zmxAttachDiagnostics(for: pane, store: store) == nil)
    }
}
