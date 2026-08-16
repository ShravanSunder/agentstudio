import AgentStudioInfrastructure
import AgentStudioTestSupport
import Foundation
import Observation
import Testing

@testable import AgentStudioCore

@MainActor
@Suite(.serialized)
struct PaneDisplayDerivedTests {
    init() {
        installTestCoreAtomsIfNeeded()
    }

    @Test
    func worktreeBackedPane_usesRepoBranchAndFolderLabel() throws {
        try withTestCoreAtoms { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
            let repo = store.addRepo(at: URL(filePath: "/tmp/agent-studio"))
            let mainWorktree = try #require(repo.worktrees.single)
            let worktree = makeWorktree(
                repoId: repo.id,
                name: "feature-name",
                path: "/tmp/agent-studio/feature-name"
            )
            store.reconcileDiscoveredWorktrees(repo.id, worktrees: [mainWorktree, worktree])
            atoms.repoCache.setWorktreeEnrichment(
                WorktreeEnrichment(worktreeId: worktree.id, repoId: repo.id, branch: "feature/pane-labels")
            )

            let pane = store.createPane(
                launchDirectory: worktree.path,
                title: "Ignored Terminal Title",
                facets: PaneContextFacets(
                    repoId: repo.id,
                    repoName: "agent-studio",
                    worktreeId: worktree.id,
                    worktreeName: "feature-name",
                    cwd: URL(fileURLWithPath: "/tmp/agent-studio/feature-name/src")
                )
            )

            let parts = atom(\.paneDisplay).displayParts(for: pane)

            #expect(parts.primaryLabel == "agent-studio | feature/pane-labels | feature-name")
        }
    }

    @Test
    func floatingPane_usesCwdFolderFallback() {
        withTestCoreAtoms { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
            let pane = store.createPane(
                launchDirectory: URL(fileURLWithPath: "/tmp/project-dev"),
                title: "ignored",
                facets: PaneContextFacets(cwd: URL(fileURLWithPath: "/tmp/project-dev"))
            )

            let parts = atom(\.paneDisplay).displayParts(for: pane)

            #expect(parts.primaryLabel == "project-dev")
        }
    }

    @Test("dangling stored association renders unassociated without CWD fallback")
    func danglingStoredAssociationRendersUnassociatedWithoutCWDFallback() throws {
        try withTestCoreAtoms { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
            let liveRepo = store.addRepo(at: URL(filePath: "/tmp/dangling-association-live"))
            let liveWorktree = try #require(liveRepo.worktrees.single)
            let pane = Pane(
                id: PaneId.generateUUIDv7().uuid,
                content: .terminal(
                    TerminalState(
                        provider: .zmx,
                        lifetime: .persistent,
                        zmxSessionID: .generateUUIDv7()
                    )
                ),
                metadata: PaneMetadata(
                    launchDirectory: liveWorktree.path,
                    title: "Dangling",
                    facets: PaneContextFacets(
                        repoId: UUIDv7.generate(),
                        worktreeId: UUIDv7.generate(),
                        cwd: liveWorktree.path
                    )
                )
            )
            #expect(store.paneAtom.insertRestoredPane(pane))

            let renderedPane = try #require(store.pane(pane.id))

            #expect(renderedPane.repoId == nil)
            #expect(renderedPane.worktreeId == nil)
            #expect(renderedPane.metadata.cwd?.standardizedFileURL.path == liveWorktree.path.path)
        }
    }

    @Test("pane note appears after location parts in collapsed label parts")
    func paneNoteAppearsAfterLocationPartsInCollapsedLabelParts() {
        withTestCoreAtoms { atoms in
            let paneId = PaneId.generateUUIDv7().uuid
            var metadata = PaneMetadata(
                launchDirectory: URL(fileURLWithPath: "/tmp/project-dev/agent-studio"),
                title: "Terminal"
            )
            metadata.updateNote("release smoke")
            #expect(
                atoms.workspacePane.insertRestoredPane(
                    Pane(
                        id: paneId,
                        content: .terminal(
                            TerminalState(
                                provider: .zmx,
                                lifetime: .persistent,
                                zmxSessionID: .generateUUIDv7()
                            )
                        ),
                        metadata: metadata)))

            let parts = PaneDisplayDerived().collapsedBarLabelParts(for: paneId)

            #expect(parts.map(\.text) == ["agent-studio", "release smoke"])
            #expect(parts.last?.icon == .system("long.text.page.and.pencil"))
            #expect(parts.last?.weight == .semibold)
        }
    }

    @Test("pane note participates in pane keywords")
    func paneNoteParticipatesInPaneKeywords() {
        var metadata = PaneMetadata(title: "Terminal")
        metadata.updateNote("gondolin auth logs")
        let pane = Pane(
            id: PaneId.generateUUIDv7().uuid,
            content: .terminal(
                TerminalState(
                    provider: .zmx,
                    lifetime: .persistent,
                    zmxSessionID: .generateUUIDv7()
                )
            ),
            metadata: metadata
        )

        let keywords = PaneDisplayDerived().paneKeywords(for: pane)

        #expect(keywords.contains("gondolin auth logs"))
    }

    @Test
    func accentColorHex_returnsStablePaletteEntry_forRepoBackedPane() throws {
        try withTestCoreAtoms { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
            let repo = store.addRepo(at: URL(filePath: "/tmp/agent-studio-colors"))
            let mainWorktree = try #require(repo.worktrees.single)
            let worktree = makeWorktree(
                repoId: repo.id,
                name: "main",
                path: "/tmp/agent-studio-colors/main"
            )
            store.reconcileDiscoveredWorktrees(repo.id, worktrees: [mainWorktree, worktree])
            let pane = store.createPane(
                launchDirectory: worktree.path,
                title: "Color",
                facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path),
            )

            let first = atom(\.paneDisplay).accentColorHex(for: pane.id)
            let second = atom(\.paneDisplay).accentColorHex(for: pane.id)

            #expect(first == second)
            #expect(first != nil)
            #expect(AppStyles.Shell.Sidebar.accentPaletteHexes.contains(first!))
        }
    }

    @Test
    func accentColorHexTracksKeyedRepoEnrichmentChanges() throws {
        try withTestCoreAtoms { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
            let repo = store.addRepo(at: URL(filePath: "/tmp/agent-studio-color-tracking"))
            let mainWorktree = try #require(repo.worktrees.single)
            let worktree = makeWorktree(
                repoId: repo.id,
                name: "main",
                path: "/tmp/agent-studio-color-tracking/main"
            )
            store.reconcileDiscoveredWorktrees(repo.id, worktrees: [mainWorktree, worktree])
            let pane = store.createPane(
                launchDirectory: worktree.path,
                title: "Color",
                facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path),
            )
            let invalidationCounter = PaneDisplayInvalidationCounter()

            withObservationTracking {
                _ = atom(\.paneDisplay).accentColorHex(for: pane.id)
            } onChange: {
                invalidationCounter.record()
            }

            atoms.repoCache.setRepoEnrichment(
                .resolvedLocal(
                    repoId: repo.id,
                    identity: RemoteIdentityNormalizer.localIdentity(repoName: "agent-studio-color-tracking"),
                    updatedAt: Date()
                )
            )

            #expect(invalidationCounter.count == 1)
        }
    }

    @Test
    func accentColorHex_returnsNil_forPaneWithoutRepo() {
        withTestCoreAtoms { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
            let pane = store.createPane()

            #expect(atom(\.paneDisplay).accentColorHex(for: pane.id) == nil)
        }
    }

    @Test
    func accentColorHex_matchesSidebarFamilyColoring_forGroupedRepos() throws {
        try withTestCoreAtoms { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
            let repoA = store.addRepo(at: URL(filePath: "/tmp/agent-studio-main"))
            let repoB = store.addRepo(at: URL(filePath: "/tmp/agent-studio-fork"))
            let mainWorktreeA = try #require(repoA.worktrees.single)
            let mainWorktreeB = try #require(repoB.worktrees.single)
            let worktreeA = makeWorktree(
                repoId: repoA.id,
                name: "main",
                path: "/tmp/agent-studio-main/main"
            )
            let worktreeB = makeWorktree(
                repoId: repoB.id,
                name: "main",
                path: "/tmp/agent-studio-fork/main"
            )
            store.reconcileDiscoveredWorktrees(repoA.id, worktrees: [mainWorktreeA, worktreeA])
            store.reconcileDiscoveredWorktrees(repoB.id, worktrees: [mainWorktreeB, worktreeB])

            let sharedIdentity = RepoIdentity(
                groupKey: "remote:askluna/agent-studio",
                remoteSlug: "askluna/agent-studio",
                organizationName: "askluna",
                displayName: "agent-studio"
            )
            atoms.repoCache.setRepoEnrichment(
                .resolvedRemote(
                    repoId: repoA.id,
                    raw: RawRepoOrigin(origin: "git@github.com:askluna/agent-studio.git", upstream: nil),
                    identity: sharedIdentity,
                    updatedAt: Date()
                )
            )
            atoms.repoCache.setRepoEnrichment(
                .resolvedRemote(
                    repoId: repoB.id,
                    raw: RawRepoOrigin(origin: "git@github.com:askluna/agent-studio.git", upstream: nil),
                    identity: sharedIdentity,
                    updatedAt: Date()
                )
            )

            let paneA = store.createPane(
                launchDirectory: worktreeA.path,
                title: "Main",
                facets: PaneContextFacets(repoId: repoA.id, worktreeId: worktreeA.id, cwd: worktreeA.path),
            )
            let paneB = store.createPane(
                launchDirectory: worktreeB.path,
                title: "Fork",
                facets: PaneContextFacets(repoId: repoB.id, worktreeId: worktreeB.id, cwd: worktreeB.path),
            )

            let sidebarRepos = [RepoPresentationItem(repo: repoA), RepoPresentationItem(repo: repoB)]
            let metadata = RepoPresentationColoring.buildRepoMetadata(
                repos: sidebarRepos,
                repoEnrichmentByRepoId: atoms.repoCache.repoEnrichmentByRepoId
            )
            let group = try #require(
                RepoPresentationGrouping.buildGroups(repos: sidebarRepos, metadataByRepoId: metadata).first
            )

            let expectedA = RepoPresentationColoring.checkoutColorHex(for: sidebarRepos[0], in: group)
            let expectedB = RepoPresentationColoring.checkoutColorHex(for: sidebarRepos[1], in: group)
            let actualA = atom(\.paneDisplay).accentColorHex(for: paneA.id)
            let actualB = atom(\.paneDisplay).accentColorHex(for: paneB.id)

            #expect(actualA == expectedA)
            #expect(actualB == expectedB)
            #expect(actualA != actualB)
        }
    }
}

private final class PaneDisplayInvalidationCounter: @unchecked Sendable {
    private(set) var count = 0

    func record() {
        count += 1
    }
}
