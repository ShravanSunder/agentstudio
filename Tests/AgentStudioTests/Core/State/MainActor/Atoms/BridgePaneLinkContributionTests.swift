import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import Testing

@Suite("Bridge pane link contributions")
struct BridgePaneLinkContributionTests {
    @Test("duplicate author is idempotent and another author retains the member")
    func twoAuthors() throws {
        let worktreeId = UUIDv7.generate()
        let alice = try BridgeLinkContributor.agent(
            BridgeAgentContributorIdentity(
                provider: BridgeAgentProviderName("codex"),
                sessionRef: BridgeAgentSessionRef("alice:one")
            )
        )
        let bob = try BridgeLinkContributor.agent(
            BridgeAgentContributorIdentity(
                provider: BridgeAgentProviderName("codex"),
                sessionRef: BridgeAgentSessionRef("bob/two")
            )
        )
        let addedAt = Date(timeIntervalSince1970: 100)
        let (first, firstResult) = BridgeNavigationRules.addingMemberContribution(
            worktreeId, contributor: alice, addedAt: addedAt, to: .empty
        )
        #expect(firstResult == .added(effect: .newItem))
        let (second, secondResult) = BridgeNavigationRules.addingMemberContribution(
            worktreeId, contributor: bob, addedAt: addedAt, to: first
        )
        #expect(secondResult == .added(effect: .newContribution))
        let (_, duplicateResult) = BridgeNavigationRules.addingMemberContribution(
            worktreeId, contributor: alice, addedAt: Date(), to: second
        )
        #expect(duplicateResult == .alreadyPresent)
        #expect(second.effectiveMemberWorktreeIds == [worktreeId])
        #expect(second.committedMemberLinks[0].contributions.map(\.addedBy) == [alice, bob])

        let removed = BridgeNavigationRules.removingMemberContribution(
            worktreeId, contributor: alice, from: second,
            protectedWorktreeId: nil, memberRootsByWorktreeId: [:]
        )
        guard case .removed(let third, let effect, _) = removed else {
            Issue.record("Expected own contribution removal")
            return
        }
        #expect(effect == nil, "A remaining author keeps effective membership and avoids the draft barrier")
        #expect(third.committedMemberLinks[0].contributions.map(\.addedBy) == [bob])
        #expect(
            BridgeNavigationRules.removingMemberContribution(
                worktreeId, contributor: alice, from: third,
                protectedWorktreeId: nil, memberRootsByWorktreeId: [:]
            ) == .refusedNotAuthor
        )
        let personRemoval = BridgeNavigationRules.removingMemberContribution(
            worktreeId, contributor: .person, from: third,
            protectedWorktreeId: nil, memberRootsByWorktreeId: [:]
        )
        guard case .removed(let empty, let finalEffect, let removedContributions) = personRemoval else {
            Issue.record("Expected person to remove effective link")
            return
        }
        #expect(finalEffect != nil)
        #expect(removedContributions == [bob])
        #expect(empty.committedMemberLinks.isEmpty)
        #expect(
            BridgeNavigationRules.removingMemberContribution(
                worktreeId, contributor: bob, from: empty,
                protectedWorktreeId: nil, memberRootsByWorktreeId: [:]
            ) == .alreadyAbsent
        )
    }

    @Test("contributor key percent encoding is lossless and canonical")
    func keyCodec() throws {
        let contributor = try BridgeLinkContributor.agent(
            BridgeAgentContributorIdentity(
                provider: BridgeAgentProviderName("claude-code"),
                sessionRef: BridgeAgentSessionRef("a:b/%🙂")
            )
        )
        let key = BridgeLinkContributorKeyCodec.encode(contributor)
        #expect(key == "agent:claude-code:a%3Ab%2F%25%F0%9F%99%82")
        #expect(try BridgeLinkContributorKeyCodec.decode(key) == contributor)
        #expect(throws: BridgeLinkIdentityError.invalidEncoding) {
            try BridgeLinkContributorKeyCodec.decode("agent:claude-code:a%3ab")
        }
    }

    @Test("a delayed committed link keeps a newer independent UI choice")
    func committedLinkReconcilesWithLaterUI() throws {
        let worktreeId = UUIDv7.generate()
        let (committed, _) = BridgeNavigationRules.addingMemberContribution(
            worktreeId, contributor: .person, addedAt: Date(timeIntervalSince1970: 10), to: .empty
        )
        var laterUI = BridgeNavigationRecord.empty
        laterUI.surface = .review
        let merged = BridgeNavigationRules.reconcilingCommittedLinks(
            committed, with: laterUI, removedWorktreeId: nil, memberRootsByWorktreeId: [:]
        )
        #expect(merged.effectiveMemberWorktreeIds == [worktreeId])
        #expect(merged.surface == .review)
    }

    @Test("committed member removal clears a later selection under that member")
    func removedMemberInvalidatesLaterSelection() throws {
        let worktreeId = UUIDv7.generate()
        let location = try #require(BridgeDocumentLocation(canonicalPath: "/tmp/member/file.swift"))
        let document = BridgeOpenedDocument(location: location, provenance: nil)
        var laterUI = BridgeNavigationRecord(committedMemberLinks: [
            BridgeMemberLink(
                worktreeId: worktreeId,
                contributions: [
                    BridgeLinkContribution(
                        addedBy: .app, addedAt: Date(timeIntervalSince1970: 1)
                    )
                ]
            )
        ])
        laterUI.openedDocuments = [document]
        laterUI.selectedFilesDocument = location
        laterUI.filesFilter = .member(worktreeId: worktreeId)
        laterUI.reviewSelection = .member(worktreeId: worktreeId)
        let merged = BridgeNavigationRules.reconcilingCommittedLinks(
            .empty, with: laterUI, removedWorktreeId: worktreeId,
            memberRootsByWorktreeId: [worktreeId: "/tmp/member"]
        )
        #expect(merged.openedDocuments.isEmpty)
        #expect(merged.selectedFilesDocument == nil)
        #expect(merged.filesFilter == .allMembers)
        #expect(merged.reviewSelection == .unselected)
    }
}
