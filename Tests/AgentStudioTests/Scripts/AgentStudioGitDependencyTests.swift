import Foundation
import Testing

@Suite("AgentStudioGit dependency wiring")
struct AgentStudioGitDependencyTests {
    @Test("AgentStudioGit resolves through remote SwiftPM package and hosted libgit2 artifact")
    func agentStudioGitUsesRemotePackageAndHostedArtifact() throws {
        let expectedAgentStudioGitRevision = "20d38d42f36ce0de73e366a3784dba8f5a745e5f"
        let packageManifest = try String(contentsOfFile: "Package.swift", encoding: .utf8)
        let packageResolved = try String(contentsOfFile: "Package.resolved", encoding: .utf8)
        let miseConfig = try String(contentsOfFile: ".mise.toml", encoding: .utf8)
        let ciWorkflow = try String(contentsOfFile: ".github/workflows/ci.yml", encoding: .utf8)
        let releaseWorkflow = try String(contentsOfFile: ".github/workflows/release.yml", encoding: .utf8)

        #expect(!packageManifest.contains(#".package(path: "../agentstudio-git")"#))
        #expect(packageManifest.contains(#"url: "https://github.com/ShravanSunder/agentstudio-git.git""#))
        #expect(packageManifest.contains("revision: \"\(expectedAgentStudioGitRevision)\""))
        #expect(packageResolved.contains(#""location" : "https://github.com/ShravanSunder/agentstudio-git.git""#))
        #expect(packageResolved.contains("\"revision\" : \"\(expectedAgentStudioGitRevision)\""))

        for configuration in [miseConfig, ciWorkflow, releaseWorkflow] {
            #expect(!configuration.contains("AGENTSTUDIO_GIT_ALLOW_LIBGIT2_BINARY_URL"))
            #expect(!configuration.contains("AGENTSTUDIO_GIT_LIBGIT2_BINARY_URL"))
            #expect(!configuration.contains("AGENTSTUDIO_GIT_LIBGIT2_BINARY_CHECKSUM"))
        }
    }
}
