import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioCommandBar

@MainActor
@Suite(.serialized)
struct CommandBarSearchFieldPolicyTests {
    init() {
        installTestCoreAtomsIfNeeded()
    }

    @Test("repository counts and path ancestors are display only")
    func repositoryDisplayTextDoesNotMatch() async {
        let repository = Repo(
            id: UUIDv7.generate(),
            name: "atlas",
            repoPath: URL(filePath: "/tmp/ancestor-only/atlas")
        )
        let row = CommandBarDataSource.repoRootItem(
            repo: repository,
            presenceByWorktreeId: [:],
            group: CommandBarDataSource.Group.repos,
            groupPriority: CommandBarDataSource.Priority.repos
        )

        let nameMatches = await searchCommandBarItemIds([row], query: "atlas")
        let repoLabelMatches = await searchCommandBarItemIds([row], query: "repo")
        let ancestorMatches = await searchCommandBarItemIds([row], query: "ancestor-only")
        #expect(nameMatches == [row.id])
        #expect(repoLabelMatches.isEmpty)
        #expect(ancestorMatches.isEmpty)
    }

    @Test("subtitle and undeclared keywords do not make an action searchable")
    func nestedActionSearchesTitleOnly() async {
        let row = CommandBarItem(
            id: "copy-path",
            title: "Copy Path",
            subtitle: "/tmp/ancestor-only/atlas",
            group: "Path",
            groupPriority: 1,
            keywords: ["ancestor-only", "atlas"],
            action: .custom({})
        )

        let titleMatches = await searchCommandBarItemIds([row], query: "copy")
        let ancestorMatches = await searchCommandBarItemIds([row], query: "ancestor-only")
        #expect(titleMatches == [row.id])
        #expect(ancestorMatches.isEmpty)
    }
}
