import Foundation

@testable import AgentStudio

@MainActor
enum InboxNotificationIntegrationHarness {
    struct Fixture {
        let bus: EventBus<RuntimeEnvelope>
        let inboxAtom: InboxNotificationAtom
        let prefsAtom: InboxNotificationPrefsAtom
        let topologyAtom: RepositoryTopologyAtom
        let paneAtom: WorkspacePaneAtom
        let tabLayout: WorkspaceTabLayoutAtom
        let windowLifecycle: WindowLifecycleAtom
        let managementLayer: ManagementLayerAtom
        let attendedPane: AttendedPaneDerived
        let tracker: PaneFocusTracker
        let router: InboxNotificationRouter

        @MainActor
        func shutdown() async {
            await router.stop()
            await tracker.stop()
        }
    }

    static func makeFixture() async -> Fixture {
        let bus = EventBus<RuntimeEnvelope>()
        let inboxAtom = InboxNotificationAtom()
        let prefsAtom = InboxNotificationPrefsAtom()
        let topologyAtom = RepositoryTopologyAtom()
        let paneAtom = WorkspacePaneAtom(repositoryTopologyAtom: topologyAtom)
        let tabLayout = WorkspaceTabLayoutAtom()
        let windowLifecycle = WindowLifecycleAtom()
        let managementLayer = ManagementLayerAtom()
        let attendedPane = AttendedPaneDerived(
            tabLayout: tabLayout,
            windowLifecycle: windowLifecycle,
            managementLayer: managementLayer
        )
        let tracker = PaneFocusTracker(attendedPane: attendedPane)
        let router = InboxNotificationRouter(
            bus: bus,
            inboxAtom: inboxAtom,
            prefsAtom: prefsAtom,
            paneAtom: paneAtom,
            tabLayout: tabLayout,
            attendedPane: attendedPane,
            focusTracker: tracker
        )
        await router.start()

        return Fixture(
            bus: bus,
            inboxAtom: inboxAtom,
            prefsAtom: prefsAtom,
            topologyAtom: topologyAtom,
            paneAtom: paneAtom,
            tabLayout: tabLayout,
            windowLifecycle: windowLifecycle,
            managementLayer: managementLayer,
            attendedPane: attendedPane,
            tracker: tracker,
            router: router
        )
    }

    @discardableResult
    static func addPane(
        _ paneId: PaneId,
        to fixture: Fixture,
        content: PaneContent = .terminal(
            TerminalState(
                provider: .zmx,
                lifetime: .persistent,
                zmxSessionID: .generateUUIDv7()
            )
        ),
        contentType: PaneContentType = .terminal,
        repoId: UUID? = nil,
        repoName: String? = nil,
        worktreeId: UUID? = nil,
        worktreeName: String? = nil
    ) -> UUID {
        if let repoId, let worktreeId {
            let repoName = repoName ?? "Repo"
            let worktreeName = worktreeName ?? "Worktree"
            let repoPath = URL(filePath: "/tmp/\(repoName)")
            let worktree = Worktree(
                id: worktreeId,
                repoId: repoId,
                name: worktreeName,
                path: repoPath.appending(path: worktreeName)
            )
            let repo = Repo(
                id: repoId,
                name: repoName,
                repoPath: repoPath,
                worktrees: [worktree]
            )
            let repos = fixture.topologyAtom.repos.filter { $0.id != repoId } + [repo]
            guard
                case .prepared(let replacement) = RepositoryTopologyReplacement.prepare(
                    repositories: repos,
                    watchedPaths: [],
                    unavailableRepositoryIDs: []
                )
            else {
                preconditionFailure("notification integration fixture produced invalid repository topology")
            }
            fixture.topologyAtom.replaceTopology(replacement)
        }

        let metadata = PaneMetadata(
            paneId: paneId,
            contentType: contentType,
            title: "Integration Pane",
            facets: PaneContextFacets(
                repoId: repoId,
                repoName: repoName,
                worktreeId: worktreeId,
                worktreeName: worktreeName
            ),
            checkoutRef: "main"
        )
        fixture.paneAtom.addPane(
            Pane(
                id: paneId.uuid,
                content: content,
                metadata: metadata
            )
        )

        let arrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: paneId.uuid)
        )
        let tab = Tab(
            name: "Tab",
            panes: [paneId.uuid],
            arrangements: [arrangement],
            activeArrangementId: arrangement.id,
            activePaneId: paneId.uuid
        )
        fixture.tabLayout.appendTab(tab)
        return tab.id
    }
}
