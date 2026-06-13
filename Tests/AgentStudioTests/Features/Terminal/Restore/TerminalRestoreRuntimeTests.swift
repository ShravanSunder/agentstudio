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
            launchDirectory: worktree.path,
            provider: .zmx,
            facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path)
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
            launchDirectory: worktree.path,
            provider: .zmx,
            facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path)
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
            launchDirectory: launchDirectory,
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
    func zmxSessionId_usesStoredSpawnAnchor_whenPaneRoamsToAnotherWorktree() throws {
        // zmx-session-anchor plan T3: session identity is a spawn-time anchor.
        // A pane can roam through live facets, but attach/diagnostics must keep
        // using the stored id for the shell that already exists.
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
            launchDirectory: worktreeA.path,
            provider: .zmx,
            facets: PaneContextFacets(repoId: repoA.id, worktreeId: worktreeA.id, cwd: worktreeA.path)
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

        let expectedSpawnSessionId = ZmxBackend.sessionId(
            repoStableKey: repoA.stableKey,
            worktreeStableKey: worktreeA.stableKey,
            paneId: bornPane.id
        )
        let roamedFacetDerivedSessionId = ZmxBackend.sessionId(
            repoStableKey: repoB.stableKey,
            worktreeStableKey: worktreeB.stableKey,
            paneId: bornPane.id
        )

        #expect(
            sessionId == expectedSpawnSessionId
        )
        #expect(
            sessionId != roamedFacetDerivedSessionId
        )

        let attachCommand = try #require(runtime.zmxAttachCommand(for: roamedPane, store: store))
        let diagnostics = try #require(runtime.zmxAttachDiagnostics(for: roamedPane, store: store))

        #expect(attachCommand.contains(expectedSpawnSessionId))
        #expect(!attachCommand.contains(roamedFacetDerivedSessionId))
        #expect(diagnostics.sessionId == expectedSpawnSessionId)
    }

    @Test
    func zmxSessionId_ignoresStoredAnchor_whenItDoesNotMatchPane() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-restore-invalid-anchor-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let store = WorkspaceStore(persistor: WorkspacePersistor(workspacesDir: tempDir))
        let repo = store.addRepo(at: tempDir)
        let worktree = try #require(repo.worktrees.first)
        let pane = store.createPane(
            launchDirectory: worktree.path,
            provider: .zmx,
            facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path)
        )
        let foreignSessionId = ZmxBackend.sessionId(
            repoStableKey: repo.stableKey,
            worktreeStableKey: worktree.stableKey,
            paneId: UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!
        )
        _ = store.paneAtom.setTerminalZmxSessionId(pane.id, sessionId: foreignSessionId)
        let paneWithInvalidStoredAnchor = try #require(store.paneAtom.pane(pane.id))

        let runtime = TerminalRestoreRuntime(
            sessionConfiguration: SessionConfiguration(
                isEnabled: true,
                zmxPath: "/tmp/fake-zmx",
                zmxDir: "/tmp/fake-zmx-dir",
                healthCheckInterval: 30,
                maxCheckpointAge: 60
            )
        )

        let sessionId = runtime.zmxSessionId(for: paneWithInvalidStoredAnchor, store: store)

        let expectedDerivedSessionId = ZmxBackend.sessionId(
            repoStableKey: repo.stableKey,
            worktreeStableKey: worktree.stableKey,
            paneId: pane.id
        )
        #expect(sessionId == expectedDerivedSessionId)
        #expect(sessionId != foreignSessionId)
    }

    @Test
    func zmxSessionId_preservesStoredDrawerAnchor_whenDrawerPaneWasDetachedToLayout() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-restore-detached-drawer-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let store = WorkspaceStore(persistor: WorkspacePersistor(workspacesDir: tempDir))
        let repo = store.addRepo(at: tempDir)
        let worktree = try #require(repo.worktrees.first)
        let parentPane = store.createPane(
            launchDirectory: worktree.path,
            provider: .zmx,
            facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path)
        )
        let drawerPane = try #require(store.addDrawerPane(to: parentPane.id))
        let storedDrawerSessionId = try #require(drawerPane.terminalState?.zmxSessionId)

        let detachedPane = try #require(store.paneAtom.detachDrawerPane(drawerPane.id, from: parentPane.id))
        let runtime = TerminalRestoreRuntime(
            sessionConfiguration: SessionConfiguration(
                isEnabled: true,
                zmxPath: "/tmp/fake-zmx",
                zmxDir: "/tmp/fake-zmx-dir",
                healthCheckInterval: 30,
                maxCheckpointAge: 60
            )
        )

        let sessionId = runtime.zmxSessionId(for: detachedPane, store: store)

        #expect(sessionId == storedDrawerSessionId)
        #expect(
            sessionId
                != ZmxBackend.sessionId(
                    repoStableKey: repo.stableKey,
                    worktreeStableKey: worktree.stableKey,
                    paneId: detachedPane.id
                ))
    }

    @Test
    func zmxAttachCommand_isNil_whenSessionRestoreIsDisabled() {
        let store = WorkspaceStore()
        let pane = store.createPane(
            launchDirectory: FileManager.default.homeDirectoryForCurrentUser,
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
