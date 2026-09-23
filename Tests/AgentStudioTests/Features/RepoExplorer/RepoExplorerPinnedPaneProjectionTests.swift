import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioRepoExplorer

@MainActor
@Suite("Pinned raw snapshot projection", .serialized)
struct RepoExplorerPinnedPaneProjectionTests {
    @Test("all pane content kinds and drawer children participate; inactive and unowned panes do not")
    func eligibleMembershipAndSnapshotIsolation() async throws {
        try await withAsyncTestCoreAtoms { atoms in
            let store = WorkspaceStore(
                identityAtom: atoms.workspaceIdentity,
                windowMemoryAtom: atoms.workspaceWindowMemory,
                repositoryTopologyAtom: atoms.workspaceRepositoryTopology,
                paneAtom: atoms.workspacePane,
                tabLayoutAtom: atoms.workspaceTabLayout,
                mutationCoordinator: atoms.workspaceMutationCoordinator,
                startsObserving: false
            )
            let terminal = store.createPane(title: "Alpha")
            let bridge = try #require(
                store.paneAtom.createPane(
                    content: .bridgePanel(BridgePaneState(panelKind: .fileViewer, source: nil)),
                    metadata: PaneMetadata(
                        contentType: .diff, launchDirectory: URL(filePath: "/tmp"), title: "Bridge", isPinned: true)
                ))
            let browser = try #require(
                store.paneAtom.createPane(
                    content: .webview(WebviewState(url: URL(string: "https://example.test")!)),
                    metadata: PaneMetadata(contentType: .browser, title: "Browser", isPinned: true)
                ))
            let code = try #require(
                store.paneAtom.createPane(
                    content: .codeViewer(
                        CodeViewerState(filePath: URL(filePath: "/tmp/pinned.swift"), scrollToLine: nil)),
                    metadata: PaneMetadata(contentType: .codeViewer, title: "Code", isPinned: true)
                ))
            let backgrounded = store.createPane(title: "Background", residency: .backgrounded)
            let unpinned = store.createPane(title: "Unpinned")
            let unowned = store.createPane(title: "Unowned")
            for pane in [terminal, backgrounded, unowned] {
                #expect(atoms.workspaceMutationCoordinator.setPanePinned(pane.id, isPinned: true))
            }
            for pane in [terminal, bridge, browser, code, backgrounded, unpinned] {
                store.appendTab(Tab(paneId: pane.id))
            }
            let drawer = try #require(store.addDrawerPane(to: terminal.id))
            #expect(atoms.workspaceMutationCoordinator.setPanePinned(drawer.id, isPinned: true))
            let prefs = RepoExplorerSidebarPrefsAtom(sidebarState: atoms.workspaceSidebarState)
            let captured = RepoExplorerPinnedPaneProjectionRequest(
                coreAtoms: atoms, sidebarPreferences: prefs,
                referenceDate: Date(timeIntervalSince1970: 1_000_000)
            )
            let expected = Set([terminal.id, bridge.id, browser.id, code.id, drawer.id])
            #expect(Set(try await RepoExplorerPinnedPaneProjector.project(captured)) == expected)

            #expect(atoms.workspaceMutationCoordinator.setPanePinned(bridge.id, isPinned: false))
            #expect(atoms.workspaceMutationCoordinator.backgroundPane(browser.id))
            let fresh = RepoExplorerPinnedPaneProjectionRequest(
                coreAtoms: atoms, sidebarPreferences: prefs,
                referenceDate: Date(timeIntervalSince1970: 1_000_000)
            )
            #expect(Set(try await RepoExplorerPinnedPaneProjector.project(captured)) == expected)
            #expect(
                Set(try await RepoExplorerPinnedPaneProjector.project(fresh)) == Set([terminal.id, code.id, drawer.id]))
        }
    }

    @Test("drawer placeholder and content title normalization match sidebar sorting")
    func titleNormalizationMatchesSidebar() {
        #expect(
            RepoExplorerPaneTitleNormalizer.normalizedTitle(
                liveTitle: " Drawer ", cwd: nil, shellExecutablePath: "/bin/fish", isDrawer: true
            ) == "zsh")
        #expect(
            RepoExplorerPaneTitleNormalizer.normalizedTitle(
                liveTitle: "/tmp/work", cwd: URL(filePath: "/tmp/work"), shellExecutablePath: "/bin/fish"
            ) == "fish")
        #expect(
            RepoExplorerPaneTitleNormalizer.normalizedTitle(
                liveTitle: " Review ", cwd: nil, shellExecutablePath: nil
            ) == "Review")
    }
}
