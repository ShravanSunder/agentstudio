import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import Testing

@Suite("Pull-request summary fold")
struct PullRequestSummaryFoldTests {
    @Test(
        "Every ordered member-state pair follows the summary table", arguments: MemberScenario.all, MemberScenario.all)
    func everyMemberStatePair(first: MemberScenario, second: MemberScenario) {
        let members = [first.row(), second.row()]

        let result = PullRequestSummaryFold.summarize(members: members)

        #expect(
            result
                == .summary(PullRequestSummary(state: expectedPair(first.evidence, second.evidence), members: members)))
    }

    @Test("Fewer than two linked worktrees has no summary", arguments: MemberScenario.all)
    func singleMemberIsNotApplicable(scenario: MemberScenario) {
        #expect(PullRequestSummaryFold.summarize(members: [scenario.row()]) == .notApplicable)
    }

    @Test("An empty link set has no summary")
    func emptyMembersAreNotApplicable() {
        #expect(PullRequestSummaryFold.summarize(members: []) == .notApplicable)
    }

    @Test("Failing checks and changes requested count the same member once")
    func attentionCountsMembersOnce() {
        let members: [PullRequestMemberRow] = [
            .pullRequest(worktreeId: UUIDv7.generate(), number: 1, checks: .failed, review: .changesRequested),
            .pullRequest(worktreeId: UUIDv7.generate(), number: 2, checks: .unknown, review: .changesRequested),
            .pullRequest(worktreeId: UUIDv7.generate(), number: 3, checks: .failed, review: .approved),
            .noPullRequest(worktreeId: UUIDv7.generate()),
            .unknown(worktreeId: UUIDv7.generate()),
        ]

        #expect(
            PullRequestSummaryFold.summarize(members: members)
                == .summary(PullRequestSummary(state: .needsAttention(count: 3), members: members)))
    }

    @Test("Attention wins over running and passing members")
    func attentionHasHighestPrecedence() {
        let members: [PullRequestMemberRow] = [
            .pullRequest(worktreeId: UUIDv7.generate(), number: 1, checks: .passed, review: .approved),
            .pullRequest(worktreeId: UUIDv7.generate(), number: 2, checks: .running, review: .unknown),
            .pullRequest(worktreeId: UUIDv7.generate(), number: 3, checks: .unknown, review: .changesRequested),
        ]

        #expect(
            PullRequestSummaryFold.summarize(members: members)
                == .summary(PullRequestSummary(state: .needsAttention(count: 1), members: members)))
    }

    @Test("Summary retains every member in link order with exact identities and PR numbers")
    func summaryPreservesMemberRows() {
        let members: [PullRequestMemberRow] = [
            .unknown(worktreeId: UUIDv7.generate()),
            .pullRequest(worktreeId: UUIDv7.generate(), number: 412, checks: .passed, review: .reviewRequired),
            .noPullRequest(worktreeId: UUIDv7.generate()),
        ]

        #expect(
            PullRequestSummaryFold.summarize(members: members)
                == .summary(PullRequestSummary(state: .allGood, members: members)))
    }

    private func expectedPair(_ first: MemberEvidence, _ second: MemberEvidence) -> PullRequestSummaryState {
        // An explicit oracle matrix, independent of the production member inspection.
        switch (first, second) {
        case (.attention, .attention): .needsAttention(count: 2)
        case (.attention, .running), (.attention, .passing), (.attention, .neutral),
            (.running, .attention), (.passing, .attention), (.neutral, .attention):
            .needsAttention(count: 1)
        case (.running, .running), (.running, .passing), (.running, .neutral),
            (.passing, .running), (.neutral, .running):
            .running
        case (.passing, .passing), (.passing, .neutral), (.neutral, .passing): .allGood
        case (.neutral, .neutral): .noInfo
        }
    }
}

enum MemberEvidence: Sendable {
    case attention
    case running
    case passing
    case neutral
}

struct MemberScenario: Sendable {
    enum RowKind: Sendable {
        case noPullRequest
        case unknown
        case pullRequest(PullRequestCheckStatus, PullRequestReviewStatus)
    }

    let name: String
    let kind: RowKind
    let evidence: MemberEvidence

    func row() -> PullRequestMemberRow {
        let worktreeId = UUIDv7.generate()
        switch kind {
        case .noPullRequest: return .noPullRequest(worktreeId: worktreeId)
        case .unknown: return .unknown(worktreeId: worktreeId)
        case .pullRequest(let checks, let review):
            return .pullRequest(worktreeId: worktreeId, number: 1, checks: checks, review: review)
        }
    }

    static let all: [Self] = [
        Self(name: "no PR", kind: .noPullRequest, evidence: .neutral),
        Self(name: "unknown member", kind: .unknown, evidence: .neutral),
        Self(name: "passed approved", kind: .pullRequest(.passed, .approved), evidence: .passing),
        Self(name: "passed changes requested", kind: .pullRequest(.passed, .changesRequested), evidence: .attention),
        Self(name: "passed review required", kind: .pullRequest(.passed, .reviewRequired), evidence: .passing),
        Self(name: "passed unknown review", kind: .pullRequest(.passed, .unknown), evidence: .passing),
        Self(name: "running approved", kind: .pullRequest(.running, .approved), evidence: .running),
        Self(name: "running changes requested", kind: .pullRequest(.running, .changesRequested), evidence: .attention),
        Self(name: "running review required", kind: .pullRequest(.running, .reviewRequired), evidence: .running),
        Self(name: "running unknown review", kind: .pullRequest(.running, .unknown), evidence: .running),
        Self(name: "failed approved", kind: .pullRequest(.failed, .approved), evidence: .attention),
        Self(name: "failed changes requested", kind: .pullRequest(.failed, .changesRequested), evidence: .attention),
        Self(name: "failed review required", kind: .pullRequest(.failed, .reviewRequired), evidence: .attention),
        Self(name: "failed unknown review", kind: .pullRequest(.failed, .unknown), evidence: .attention),
        Self(name: "unknown checks approved", kind: .pullRequest(.unknown, .approved), evidence: .neutral),
        Self(
            name: "unknown checks changes requested", kind: .pullRequest(.unknown, .changesRequested),
            evidence: .attention),
        Self(name: "unknown checks review required", kind: .pullRequest(.unknown, .reviewRequired), evidence: .neutral),
        Self(name: "unknown checks unknown review", kind: .pullRequest(.unknown, .unknown), evidence: .neutral),
    ]
}
