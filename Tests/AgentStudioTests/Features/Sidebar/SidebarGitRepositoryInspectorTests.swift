import Testing

@testable import AgentStudio

@Suite(.serialized)
struct SidebarGitRepositoryInspectorTests {

    @Test
    func makeRepoDisplayName_formatsRepoAndOrganization() {
        let title = GitRepositoryInspector.makeRepoDisplayName(
            fallbackName: "local-folder-name",
            remoteSlug: "shravansunder/agent-studio"
        )

        #expect(title == "agent-studio · shravansunder")
    }

    @Test
    func makeRepoDisplayName_formatsNestedOrganizationPath() {
        let title = GitRepositoryInspector.makeRepoDisplayName(
            fallbackName: "local-folder-name",
            remoteSlug: "company/platform/agent-studio"
        )

        #expect(title == "agent-studio · company/platform")
    }

    @Test
    func makeRepoDisplayName_fallsBackToFolderNameWhenOrgMissing() {
        let title = GitRepositoryInspector.makeRepoDisplayName(
            fallbackName: "askluna-finance",
            remoteSlug: "agent-studio"
        )

        #expect(title == "askluna-finance")
    }

    @Test
    func makeRepoDisplayName_fallsBackToFolderNameWhenRemoteMissing() {
        let title = GitRepositoryInspector.makeRepoDisplayName(
            fallbackName: "askluna-finance",
            remoteSlug: nil
        )

        #expect(title == "askluna-finance")
    }
}
