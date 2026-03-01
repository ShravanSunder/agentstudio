import Testing

@testable import AgentStudio

@Suite("RemoteIdentityNormalizer")
struct RemoteIdentityNormalizerTests {
    @Test("normalizes github ssh and https variants to same slug")
    func normalizesGitHubVariantsToSameSlug() {
        let ssh = RemoteIdentityNormalizer.normalize("git@github.com:anthropics/claude.git")
        let https = RemoteIdentityNormalizer.normalize("https://github.com/anthropics/claude")
        let sshProtocol = RemoteIdentityNormalizer.normalize("ssh://git@github.com/anthropics/claude.git")

        #expect(ssh?.remoteSlug == "anthropics/claude")
        #expect(https?.remoteSlug == "anthropics/claude")
        #expect(sshProtocol?.remoteSlug == "anthropics/claude")
        #expect(ssh?.groupKey == https?.groupKey)
        #expect(ssh?.groupKey == sshProtocol?.groupKey)
    }

    @Test("extracts organization and display name from normalized slug")
    func extractsOrganizationAndDisplayName() {
        let identity = RemoteIdentityNormalizer.normalize("git@github.com:myorg/my-repo.git")

        #expect(identity?.organizationName == "myorg")
        #expect(identity?.displayName == "my-repo")
        #expect(identity?.groupKey == "remote:myorg/my-repo")
    }

    @Test("returns nil for empty or unrecognized remotes")
    func returnsNilForInvalidInput() {
        #expect(RemoteIdentityNormalizer.normalize("") == nil)
        #expect(RemoteIdentityNormalizer.normalize("   ") == nil)
        #expect(RemoteIdentityNormalizer.normalize("not-a-url") == nil)
    }

    @Test("extractSlug stays backward compatible with previous forge slug parsing")
    func extractSlugCompatibility() {
        #expect(RemoteIdentityNormalizer.extractSlug("git@github.com:org/repo.git") == "org/repo")
        #expect(RemoteIdentityNormalizer.extractSlug("https://github.com/org/repo") == "org/repo")
        #expect(RemoteIdentityNormalizer.extractSlug("ssh://git@github.com/org/repo.git") == "org/repo")
        #expect(RemoteIdentityNormalizer.extractSlug("http://github.com/org/repo") == "org/repo")
    }

    @Test("localIdentity builds deterministic local grouping")
    func localIdentityBuildsDeterministicGrouping() {
        let identity = RemoteIdentityNormalizer.localIdentity(repoName: "agent-studio")

        #expect(identity.groupKey == "local:agent-studio")
        #expect(identity.displayName == "agent-studio")
        #expect(identity.remoteSlug == nil)
        #expect(identity.organizationName == nil)
    }
}
