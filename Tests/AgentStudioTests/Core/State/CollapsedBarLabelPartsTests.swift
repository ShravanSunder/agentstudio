import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
final class CollapsedBarLabelPartsTests {

    private var registry: AtomRegistry!
    private var store: WorkspaceStore!

    init() {
        registry = AtomRegistry()
        store = WorkspaceStore(
            metadataAtom: registry.workspaceMetadata,
            repositoryTopologyAtom: registry.workspaceRepositoryTopology,
            paneAtom: registry.workspacePane,
            tabLayoutAtom: registry.workspaceTabLayout,
            persistor: WorkspacePersistor(
                workspacesDir: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            )
        )
    }

    @Test
    func floatingPaneWithCwd_returnsFolderPart() {
        AtomScope.$override.withValue(registry) {
            let cwdURL = URL(fileURLWithPath: "/Users/dev/my-project")
            let pane = store.createPane(source: .floating(launchDirectory: cwdURL, title: nil))

            let derived = PaneDisplayDerived()
            let parts = derived.collapsedBarLabelParts(for: pane.id)

            #expect(parts.count == 1)
            #expect(parts[0].icon == .system("folder"))
            #expect(parts[0].text == "my-project")
        }
    }

    @Test
    func floatingPaneWithoutCwd_returnsTerminalFallback() {
        AtomScope.$override.withValue(registry) {
            let pane = store.createPane(source: .floating(launchDirectory: nil, title: nil))

            let derived = PaneDisplayDerived()
            let parts = derived.collapsedBarLabelParts(for: pane.id)

            #expect(parts.count == 1)
            #expect(parts[0].icon == .system("terminal"))
        }
    }

    @Test
    func worktreeBackedPane_returnsRepoWorktreeAndBranchParts() {
        AtomScope.$override.withValue(registry) {
            let repo = store.addRepo(at: URL(filePath: "/tmp/agent-studio-collapsed-label"))
            let worktree = makeWorktree(
                repoId: repo.id,
                name: "feature-name",
                path: "/tmp/agent-studio-collapsed-label/feature-name"
            )
            store.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])
            atom(\.repoCache).setWorktreeEnrichment(
                WorktreeEnrichment(worktreeId: worktree.id, repoId: repo.id, branch: "feature/rotated-label")
            )

            let pane = store.createPane(
                source: .worktree(worktreeId: worktree.id, repoId: repo.id, launchDirectory: worktree.path),
                title: "Ignored",
                facets: PaneContextFacets(
                    repoId: repo.id,
                    repoName: repo.name,
                    worktreeId: worktree.id,
                    worktreeName: worktree.name,
                    cwd: worktree.path
                )
            )

            let parts = PaneDisplayDerived().collapsedBarLabelParts(for: pane.id)
            let expectedRepoPart = CollapsedBarLabelPart(
                icon: .octicon("octicon-repo"),
                text: repo.name,
                weight: .semibold
            )
            let expectedWorktreePart = CollapsedBarLabelPart(
                icon: .octicon("octicon-git-worktree"),
                text: worktree.path.lastPathComponent,
                weight: .regular
            )
            let expectedBranchPart = CollapsedBarLabelPart(
                icon: .octicon("octicon-git-branch"),
                text: "feature/rotated-label",
                weight: .regular
            )

            #expect(parts.count == 3)
            #expect(parts[0] == expectedRepoPart)
            #expect(parts[1] == expectedWorktreePart)
            #expect(parts[2] == expectedBranchPart)
        }
    }

    @Test
    func metadataAssociatedWebview_returnsRepoWorktreeAndBranchParts() {
        AtomScope.$override.withValue(registry) {
            let repo = store.addRepo(at: URL(filePath: "/tmp/agent-studio-webview-label"))
            let worktree = makeWorktree(
                repoId: repo.id,
                name: "feature-web",
                path: "/tmp/agent-studio-webview-label/feature-web"
            )
            store.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])
            atom(\.repoCache).setWorktreeEnrichment(
                WorktreeEnrichment(worktreeId: worktree.id, repoId: repo.id, branch: "feature/webview-context")
            )

            let pane = store.createPane(
                content: .webview(WebviewState(url: URL(string: "https://example.com/pr/123")!)),
                metadata: PaneMetadata(
                    contentType: .browser,
                    source: .floating(launchDirectory: worktree.path, title: "Review"),
                    title: "Review",
                    facets: PaneContextFacets(
                        repoId: repo.id,
                        repoName: repo.name,
                        worktreeId: worktree.id,
                        worktreeName: worktree.name,
                        cwd: worktree.path
                    )
                )
            )

            let parts = PaneDisplayDerived().collapsedBarLabelParts(for: pane.id)

            #expect(parts.count == 3)
            #expect(parts[0].text == repo.name)
            #expect(parts[1].text == worktree.name)
            #expect(parts[2].text == "feature/webview-context")
        }
    }

    @Test
    func cwdResolvedWorkspace_returnsRepoWorktreeAndBranchParts() {
        AtomScope.$override.withValue(registry) {
            let repo = store.addRepo(at: URL(filePath: "/tmp/agent-studio-cwd-label"))
            let worktree = makeWorktree(
                repoId: repo.id,
                name: "cwd-lookup",
                path: "/tmp/agent-studio-cwd-label/cwd-lookup"
            )
            store.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])
            atom(\.repoCache).setWorktreeEnrichment(
                WorktreeEnrichment(worktreeId: worktree.id, repoId: repo.id, branch: "feature/cwd-fallback")
            )

            let pane = store.createPane(
                source: .floating(
                    launchDirectory: worktree.path.appending(path: "Sources"),
                    title: "Lookup"
                ),
                title: "Lookup",
                facets: PaneContextFacets(cwd: worktree.path.appending(path: "Sources"))
            )

            let parts = PaneDisplayDerived().collapsedBarLabelParts(for: pane.id)

            #expect(parts.count == 3)
            #expect(parts[0].text == repo.name)
            #expect(parts[1].text == worktree.name)
            #expect(parts[2].text == "feature/cwd-fallback")
        }
    }
}
