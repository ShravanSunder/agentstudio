package enum PullRequestSummaryFold {
    package static func summarize(members: [PullRequestMemberRow]) -> PullRequestSummaryDetail {
        guard members.count >= 2 else { return .notApplicable }

        var attentionCount = 0
        var hasRunningChecks = false
        var hasPassingChecks = false

        for member in members {
            switch member {
            case .noPullRequest, .unknown:
                continue
            case .pullRequest(_, _, let checks, let review):
                if checks == .failed || review == .changesRequested {
                    attentionCount += 1
                }
                hasRunningChecks = hasRunningChecks || checks == .running
                hasPassingChecks = hasPassingChecks || checks == .passed
            }
        }

        let state: PullRequestSummaryState
        if attentionCount > 0 {
            state = .needsAttention(count: attentionCount)
        } else if hasRunningChecks {
            state = .running
        } else if hasPassingChecks {
            state = .allGood
        } else {
            state = .noInfo
        }

        return .summary(PullRequestSummary(state: state, members: members))
    }
}
