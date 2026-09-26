import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioTestSupport
import Foundation
import Testing

@Suite("Bridge pane link contract")
struct BridgePaneLinkContractTests {
    private struct Fixture<Outcome: Codable>: Codable {
        let union: String
        let value: Outcome
    }

    @Test("agent contributor key is lossless and canonical")
    func contributorKeyRoundTrip() throws {
        let contributor = BridgeLinkContributor.agent(
            BridgeAgentContributorIdentity(
                provider: try BridgeAgentProviderName("codex"),
                sessionRef: try BridgeAgentSessionRef("session:/%🙂")
            ))

        let key = BridgeLinkContributorKeyCodec.encode(contributor)

        #expect(key == "agent:codex:session%3A%2F%25%F0%9F%99%82")
        #expect(try BridgeLinkContributorKeyCodec.decode(key) == contributor)
        #expect(throws: BridgeLinkIdentityError.invalidEncoding) {
            try BridgeLinkContributorKeyCodec.decode("agent:codex:session%3a")
        }
    }

    @Test("member add union matches every shared fixture")
    func memberAddFixtures() throws {
        try assertFixtures(
            union: "BridgeMemberAddResult", folder: "pane-links", prefix: "member-add",
            cases: [
                ("added-new-item", .added(effect: .newItem)),
                ("added-new-contribution", .added(effect: .newContribution)),
                ("already-present", .alreadyPresent),
                ("refused-unknown-worktree", .refusedUnknownWorktree),
                ("stale-owner", .staleOwner), ("stale-receiver", .staleReceiver),
                ("unsupported-receiver", .unsupportedReceiver),
            ] as [(String, BridgeMemberAddResult)]
        )
    }

    @Test("member remove union matches every shared fixture")
    func memberRemoveFixtures() throws {
        let agent = try fixtureAgent()
        let operationId = try fixtureOperationId()
        try assertFixtures(
            union: "BridgeMemberRemoveResult", folder: "pane-links", prefix: "member-remove",
            cases: [
                ("removed", .removed(removedContributions: [agent])),
                ("already-absent", .alreadyAbsent),
                ("refused-protected-current-directory", .refusedProtectedCurrentDirectory),
                ("refused-not-author", .refusedNotAuthor),
                ("stale-owner", .staleOwner), ("stale-receiver", .staleReceiver),
                ("pending-draft-settlement", .pendingDraftSettlement(operationId: operationId)),
            ] as [(String, BridgeMemberRemoveResult)]
        )
    }

    @Test("pending removal settlement matches every shared fixture")
    func pendingRemovalFixtures() throws {
        let agent = try fixtureAgent()
        try assertFixtures(
            union: "BridgePendingMemberRemovalSettlement", folder: "pane-links",
            prefix: "pending-member-removal",
            cases: [
                ("removed", .removed(removedContributions: [agent])),
                ("already-absent", .alreadyAbsent),
                ("refused-protected-current-directory", .refusedProtectedCurrentDirectory),
                ("refused-not-author", .refusedNotAuthor),
                ("stale-owner", .staleOwner), ("stale-receiver", .staleReceiver),
                ("draft-kept-refused", .draftKept(reason: .refused)),
                ("draft-kept-save-failed", .draftKept(reason: .saveFailed)),
                ("draft-kept-save-outcome-unknown", .draftKept(reason: .saveOutcomeUnknown)),
                ("membership-outcome-unknown", .membershipOutcomeUnknown),
            ] as [(String, BridgePendingMemberRemovalSettlement)]
        )
    }

    @Test("PR reference unions match every shared fixture")
    func pullRequestFixtures() throws {
        try assertFixtures(
            union: "BridgePullRequestReferenceAddResult", folder: "pane-links", prefix: "pr-reference-add",
            cases: [
                ("added-new-item", .added(effect: .newItem)),
                ("added-new-contribution", .added(effect: .newContribution)),
                ("already-present", .alreadyPresent),
                ("stale-owner", .staleOwner), ("stale-receiver", .staleReceiver),
                ("unsupported-receiver", .unsupportedReceiver),
            ] as [(String, BridgePullRequestReferenceAddResult)]
        )
        try assertFixtures(
            union: "BridgePullRequestReferenceRemoveResult", folder: "pane-links", prefix: "pr-reference-remove",
            cases: [
                ("removed", .removed(removedContributions: [try fixtureAgent()])),
                ("already-absent", .alreadyAbsent), ("refused-not-author", .refusedNotAuthor),
                ("stale-owner", .staleOwner), ("stale-receiver", .staleReceiver),
            ] as [(String, BridgePullRequestReferenceRemoveResult)]
        )
    }

    @Test("reveal unions match every shared fixture")
    func revealFixtures() throws {
        try assertFixtures(
            union: "BridgeRevealAdmissionResult", folder: "reveal", prefix: "reveal-admission",
            cases: [
                ("admitted", .admitted(operationId: try fixtureOperationId())),
                ("unsupported-target", .unsupportedTarget),
                ("stale-owner", .staleOwner), ("stale-receiver", .staleReceiver),
            ] as [(String, BridgeRevealAdmissionResult)]
        )
        try assertFixtures(
            union: "BridgeAgentRevealSettlement", folder: "reveal", prefix: "agent-reveal-settlement",
            cases: [
                ("shown", .shown), ("waiting-in-open-view", .waitingInOpenView),
                ("superseded", .superseded), ("unavailable", .unavailable),
                ("not-found", .notFound), ("stale-owner", .staleOwner),
                ("cancelled", .cancelled), ("outcome-unknown", .outcomeUnknown),
            ] as [(String, BridgeAgentRevealSettlement)]
        )
        try assertFixtures(
            union: "BridgeHumanOpenSettlement", folder: "reveal", prefix: "human-open-settlement",
            cases: [
                ("shown", .shown), ("draft-kept-refused", .draftKept(reason: .refused)),
                ("draft-kept-save-failed", .draftKept(reason: .saveFailed)),
                ("draft-kept-save-outcome-unknown", .draftKept(reason: .saveOutcomeUnknown)),
                ("superseded", .superseded), ("unavailable", .unavailable),
                ("outcome-unknown", .outcomeUnknown),
            ] as [(String, BridgeHumanOpenSettlement)]
        )
    }

    @Test("item identity and reveal paths validate before use")
    func valueValidation() throws {
        let worktree = UUIDv7.generate()
        let identity = try ForgePullRequestIdentity(
            host: "GITHUB.COM", owner: "Example", repository: "Source", number: 42
        )
        #expect(identity.host == "github.com")
        #expect(
            try JSONDecoder().decode(
                BridgeLinkItem.self,
                from: JSONEncoder().encode(BridgeLinkItem.pullRequest(identity))
            ) == .pullRequest(identity))
        let target = try BridgeRevealFileTarget(worktree: worktree, relativePath: "src/file.swift", line: 12)
        #expect(
            try JSONDecoder().decode(
                BridgeRevealFileTarget.self, from: JSONEncoder().encode(target)
            ) == target)
        #expect(throws: BridgeLinkIdentityError.invalidRelativePath) {
            try BridgeRevealFileTarget(worktree: worktree, relativePath: "../secret")
        }
        #expect(throws: BridgeLinkIdentityError.invalidLine) {
            try BridgeRevealFileTarget(worktree: worktree, relativePath: "file.swift", line: 0)
        }
    }

    @Test("identity, removal fact and retained Open view fixtures round trip")
    func valueFixtures() throws {
        let root = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let folder = "Tests/BridgeContractFixtures/"
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        let agent = try decoder.decode(
            BridgeLinkContributor.self,
            from: Data(
                contentsOf: root.appending(
                    path: folder + "pane-links/contributor-agent.json"
                )))
        #expect(agent == (try fixtureAgent()))
        for name in ["item-worktree", "item-pull-request"] {
            let item = try decoder.decode(
                BridgeLinkItem.self,
                from: Data(
                    contentsOf: root.appending(
                        path: folder + "pane-links/\(name).json"
                    )))
            #expect(try decoder.decode(BridgeLinkItem.self, from: encoder.encode(item)) == item)
        }
        let fact = try decoder.decode(
            BridgeLinkContributionsRemoved.self,
            from: Data(
                contentsOf: root.appending(
                    path: folder + "pane-links/contributions-removed.json"
                )))
        #expect(fact.removedContributions == [agent])
        #expect(fact.removedBy == .person)
        #expect(try decoder.decode(BridgeLinkContributionsRemoved.self, from: encoder.encode(fact)) == fact)

        let target = try decoder.decode(
            BridgeRevealFileTarget.self,
            from: Data(
                contentsOf: root.appending(
                    path: folder + "reveal/file-target.json"
                )))
        #expect(target.line == 12)
        let dateDecoder = JSONDecoder()
        dateDecoder.dateDecodingStrategy = .iso8601
        let dateEncoder = JSONEncoder()
        dateEncoder.dateEncodingStrategy = .iso8601
        let retained = try dateDecoder.decode(
            BridgeRetainedOpenViewItem.self,
            from: Data(
                contentsOf: root.appending(
                    path: folder + "reveal/retained-open-view-item.json"
                )))
        #expect(retained.target == target)
        #expect(retained.requestedBy == agent)
        #expect(
            try dateDecoder.decode(
                BridgeRetainedOpenViewItem.self, from: dateEncoder.encode(retained)
            ) == retained)
    }

    @Test("membership port accepts only typed worktree and PR identities")
    func membershipPortIdentityTypes() async throws {
        let port: any PaneLinkMembershipPort = PaneLinkPortTypeWitness()
        let receiver = PaneId.generateUUIDv7()
        let worktree: WorktreeId = UUIDv7.generate()
        let reference = try ForgePullRequestIdentity(
            host: "github.com", owner: "example", repository: "source", number: 42
        )

        #expect(
            try await port.addMember(
                receiver: receiver, worktree: worktree, contributor: .person
            ) == .alreadyPresent)
        #expect(
            try await port.removeMember(
                receiver: receiver, worktree: worktree, contributor: .person
            ) == .alreadyAbsent)
        #expect(
            try await port.addPullRequestReference(
                receiver: receiver, reference: reference, contributor: .person
            ) == .alreadyPresent)
        #expect(
            try await port.removePullRequestReference(
                receiver: receiver, reference: reference, contributor: .person
            ) == .alreadyAbsent)
    }

    private func assertFixtures<Outcome: Codable & Equatable>(
        union: String,
        folder: String,
        prefix: String,
        cases: [(String, Outcome)]
    ) throws {
        let root = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        for (name, expected) in cases {
            let data = try Data(
                contentsOf: root.appending(
                    path: "Tests/BridgeContractFixtures/\(folder)/\(prefix)-\(name).json"
                ))
            let fixture = try decoder.decode(Fixture<Outcome>.self, from: data)
            #expect(fixture.union == union)
            #expect(fixture.value == expected)
            let roundTrip = try decoder.decode(Fixture<Outcome>.self, from: encoder.encode(fixture))
            #expect(roundTrip.value == expected)
        }
        let invalid = try Data(
            contentsOf: root.appending(
                path: "Tests/BridgeContractFixtures/\(folder)/invalid-\(prefix).json"
            ))
        #expect(throws: Error.self) { try decoder.decode(Fixture<Outcome>.self, from: invalid) }
    }

    private func fixtureAgent() throws -> BridgeLinkContributor {
        .agent(
            BridgeAgentContributorIdentity(
                provider: try BridgeAgentProviderName("codex"),
                sessionRef: try BridgeAgentSessionRef("session-1")
            ))
    }

    private func fixtureOperationId() throws -> UUID {
        try #require(UUID(uuidString: "019d1f16-ef70-7111-8db1-7681f9f87710"))
    }
}

private actor PaneLinkPortTypeWitness: PaneLinkMembershipPort {
    func addMember(
        receiver _: PaneId, worktree _: WorktreeId, contributor _: BridgeLinkContributor
    ) async throws -> BridgeMemberAddResult { .alreadyPresent }

    func removeMember(
        receiver _: PaneId, worktree _: WorktreeId, contributor _: BridgeLinkContributor
    ) async throws -> BridgeMemberRemoveResult { .alreadyAbsent }

    func awaitPendingMemberRemoval(
        receiver _: PaneId, operationId _: UUID
    ) async throws -> BridgePendingMemberRemovalSettlement { .alreadyAbsent }

    func addPullRequestReference(
        receiver _: PaneId, reference _: ForgePullRequestIdentity, contributor _: BridgeLinkContributor
    ) async throws -> BridgePullRequestReferenceAddResult { .alreadyPresent }

    func removePullRequestReference(
        receiver _: PaneId, reference _: ForgePullRequestIdentity, contributor _: BridgeLinkContributor
    ) async throws -> BridgePullRequestReferenceRemoveResult { .alreadyAbsent }

    func membershipFacts() async -> AsyncStream<BridgeLinkContributionsRemoved> {
        let (stream, continuation) = AsyncStream.makeStream(
            of: BridgeLinkContributionsRemoved.self,
            bufferingPolicy: BridgeLinkMembershipFactBuffering.policy
        )
        continuation.finish()
        return stream
    }
}
