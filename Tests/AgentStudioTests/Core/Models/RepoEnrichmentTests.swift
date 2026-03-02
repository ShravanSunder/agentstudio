import Foundation
import Testing

@testable import AgentStudio

@Suite("RepoEnrichment")
struct RepoEnrichmentTests {
    @Test("unresolved carries repoId only")
    func unresolvedCarriesRepoIdOnly() {
        let repoId = UUID()
        let enrichment = RepoEnrichment.unresolved(repoId: repoId)

        #expect(enrichment.repoId == repoId)
        #expect(enrichment.identity == nil)
        #expect(enrichment.raw == nil)
    }

    @Test("resolved exposes raw origin and derived identity")
    func resolvedExposesRawAndIdentity() {
        let repoId = UUID()
        let enrichment = RepoEnrichment.resolved(
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

    @Test("resolved with nil origin represents local-only repo")
    func resolvedWithNilOriginRepresentsLocalOnlyRepo() {
        let enrichment = RepoEnrichment.resolved(
            repoId: UUID(),
            raw: RawRepoOrigin(origin: nil, upstream: nil),
            identity: RepoIdentity(
                groupKey: "local:agent-studio",
                remoteSlug: nil,
                organizationName: nil,
                displayName: "agent-studio"
            ),
            updatedAt: Date()
        )

        #expect(enrichment.origin == nil)
        #expect(enrichment.remoteSlug == nil)
        #expect(enrichment.groupKey == "local:agent-studio")
    }

    @Test("codable round-trip preserves unresolved and resolved cases")
    func codableRoundTrip() throws {
        let unresolved = RepoEnrichment.unresolved(repoId: UUID())
        let resolved = RepoEnrichment.resolved(
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

        let unresolvedData = try encoder.encode(unresolved)
        let resolvedData = try encoder.encode(resolved)

        #expect(try decoder.decode(RepoEnrichment.self, from: unresolvedData) == unresolved)
        #expect(try decoder.decode(RepoEnrichment.self, from: resolvedData) == resolved)
    }
}
