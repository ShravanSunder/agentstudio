import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
@MainActor
struct WorkspaceLauncherProjectorTests {
    @Test
    func project_noRepos_returnsFolderIntakeState() {
        let result = WorkspaceLauncherProjector.project(
            repos: [],
            tabs: [],
            recentTargets: []
        )

        #expect(result.kind == .noFolders)
        #expect(result.recentTargets.isEmpty)
        #expect(result.showsOpenAll == false)
    }

    @Test
    func project_reposButNoTabs_returnsLauncherStateWithRecentTargets() {
        let repo = Repo(name: "agent-studio", repoPath: URL(fileURLWithPath: "/tmp/agent-studio"))
        let target = RecentWorkspaceTarget.forCwd(URL(fileURLWithPath: "/tmp/agent-studio"))

        let result = WorkspaceLauncherProjector.project(
            repos: [repo],
            tabs: [],
            recentTargets: [target]
        )

        #expect(result.kind == .launcher)
        #expect(result.recentTargets == [target])
        #expect(result.showsOpenAll == false)
    }

    @Test
    func project_reposAndTabsPresent_returnsEmptyLauncherModel() {
        let repo = Repo(name: "agent-studio", repoPath: URL(fileURLWithPath: "/tmp/agent-studio"))
        let tab = Tab(paneId: UUID())

        let result = WorkspaceLauncherProjector.project(
            repos: [repo],
            tabs: [tab],
            recentTargets: [.forCwd(URL(fileURLWithPath: "/tmp/agent-studio"))]
        )

        #expect(result.kind == .launcher)
        #expect(result.recentTargets.isEmpty)
        #expect(result.showsOpenAll == false)
    }

    @Test
    func project_launcherCapsAtFiveAndShowsOpenAllForTwoOrMoreTargets() {
        let repo = Repo(name: "agent-studio", repoPath: URL(fileURLWithPath: "/tmp/agent-studio"))
        let targets = (0..<6).map { index in
            RecentWorkspaceTarget.forCwd(URL(fileURLWithPath: "/tmp/project-\(index)"))
        }

        let result = WorkspaceLauncherProjector.project(
            repos: [repo],
            tabs: [],
            recentTargets: targets
        )

        #expect(result.recentTargets.count == 5)
        #expect(result.showsOpenAll == true)
    }
}
