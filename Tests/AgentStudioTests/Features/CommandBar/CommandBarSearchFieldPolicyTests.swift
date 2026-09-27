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
    func repositoryDisplayTextDoesNotMatch() {
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

        #expect(CommandBarSearch.filter(items: [row], query: "atlas").map(\.id) == [row.id])
        let repoLabelMatches = CommandBarSearch.filter(items: [row], query: "repo")
        let ancestorMatches = CommandBarSearch.filter(items: [row], query: "ancestor-only")
        #expect(repoLabelMatches.isEmpty)
        #expect(ancestorMatches.isEmpty)
    }

    @Test("subtitle and undeclared keywords do not make an action searchable")
    func nestedActionSearchesTitleOnly() {
        let row = CommandBarItem(
            id: "copy-path",
            title: "Copy Path",
            subtitle: "/tmp/ancestor-only/atlas",
            group: "Path",
            groupPriority: 1,
            keywords: ["ancestor-only", "atlas"],
            action: .custom({})
        )

        #expect(CommandBarSearch.filter(items: [row], query: "copy").map(\.id) == [row.id])
        let ancestorMatches = CommandBarSearch.filter(items: [row], query: "ancestor-only")
        #expect(ancestorMatches.isEmpty)
    }
}
