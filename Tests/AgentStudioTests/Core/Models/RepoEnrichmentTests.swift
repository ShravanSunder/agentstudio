import Foundation
import Testing

@testable import AgentStudio

@Suite("RepoEnrichment")
struct RepoEnrichmentTests {
    @Test("awaitingOrigin carries repoId only")
    func awaitingOriginCarriesRepoIdOnly() {
        let repoId = UUID()
        let enrichment = RepoEnrichment.awaitingOrigin(repoId: repoId)

        #expect(enrichment.repoId == repoId)
        #expect(enrichment.identity == nil)
        #expect(enrichment.raw == nil)
    }

    @Test("resolvedRemote exposes raw origin and derived identity")
    func resolvedRemoteExposesRawAndIdentity() {
        let repoId = UUID()
        let enrichment = RepoEnrichment.resolvedRemote(
            repoId: repoId,
            raw: RawRepoOrigin(origin: "git@github.com:acme/agent-studio.git", upstream: nil),
            identity: RepoIdentity(
                groupKey: "remote:acme/agent-studio",
                remoteSlug: "acme/agent-studio",
                organizationName: "acme",
                displayName: "agent-studio"
            ),
            updatedAt: Date()
        )

        #expect(enrichment.repoId == repoId)
        #expect(enrichment.origin == "git@github.com:acme/agent-studio.git")
        #expect(enrichment.groupKey == "remote:acme/agent-studio")
        #expect(enrichment.organizationName == "acme")
        #expect(enrichment.displayName == "agent-studio")
    }

    @Test("resolvedLocal has identity but no raw origin")
    func resolvedLocalHasIdentityButNoRawOrigin() {
        let repoId = UUID()
        let identity = RepoIdentity(
            groupKey: "local:agent-studio",
            remoteSlug: nil,
            organizationName: nil,
            displayName: "agent-studio"
        )
        let enrichment = RepoEnrichment.resolvedLocal(
            repoId: repoId,
            identity: identity,
            updatedAt: Date()
        )

        #expect(enrichment.repoId == repoId)
        #expect(enrichment.raw == nil)
        #expect(enrichment.identity == identity)
        #expect(enrichment.origin == nil)
        #expect(enrichment.remoteSlug == nil)
        #expect(enrichment.groupKey == "local:agent-studio")
    }

    @Test("codable round-trip preserves awaitingOrigin, resolvedLocal, and resolvedRemote")
    func codableRoundTrip() throws {
        let awaitingOrigin = RepoEnrichment.awaitingOrigin(repoId: UUID())
        let resolvedLocal = RepoEnrichment.resolvedLocal(
            repoId: UUID(),
            identity: RepoIdentity(
                groupKey: "local:agent-studio",
                remoteSlug: nil,
                organizationName: nil,
                displayName: "agent-studio"
            ),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let resolvedRemote = RepoEnrichment.resolvedRemote(
            repoId: UUID(),
            raw: RawRepoOrigin(origin: "https://github.com/acme/agent-studio", upstream: nil),
            identity: RepoIdentity(
                groupKey: "remote:acme/agent-studio",
                remoteSlug: "acme/agent-studio",
                organizationName: "acme",
                displayName: "agent-studio"
            ),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let awaitingOriginData = try encoder.encode(awaitingOrigin)
        let resolvedLocalData = try encoder.encode(resolvedLocal)
        let resolvedRemoteData = try encoder.encode(resolvedRemote)

        #expect(try decoder.decode(RepoEnrichment.self, from: awaitingOriginData) == awaitingOrigin)
        #expect(try decoder.decode(RepoEnrichment.self, from: resolvedLocalData) == resolvedLocal)
        #expect(try decoder.decode(RepoEnrichment.self, from: resolvedRemoteData) == resolvedRemote)
    }
}
