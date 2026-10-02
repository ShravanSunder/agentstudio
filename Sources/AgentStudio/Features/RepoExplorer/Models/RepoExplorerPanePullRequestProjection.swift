import AgentStudioCore
import AgentStudioSharedComponents

/// Render the producer's declared summary; never reclassify checks or reviews.
package enum RepoExplorerPanePullRequestProjection {
    package static func make(_ detail: PullRequestSummaryDetail) -> GitPRSummaryChipModel? {
        guard case .summary(let summary) = detail else { return nil }
        let state: PullRequestSummaryStateModel =
            switch summary.state {
            case .needsAttention(let count): .needsAttention(count: count)
            case .running: .running
            case .allGood: .allGood
            case .noInfo: .noInfo
            }
        let model = GitPRSummaryPopoverModel(
            state: state,
            members: summary.members.map { row in
                switch row {
                case .noPullRequest(let id): return .noPullRequest(worktreeId: id)
                case .unknown(let id): return .unknown(worktreeId: id)
                case .pullRequest(let id, let number, let checks, let review):
                    let mappedChecks: PullRequestChecksModel =
                        switch checks {
                        case .passed: .passed
                        case .running: .running
                        case .failed: .failed
                        case .unknown: .unknown
                        }
                    let mappedReview: PullRequestReviewModel =
                        switch review {
                        case .approved: .approved
                        case .changesRequested: .changesRequested
                        case .reviewRequired: .reviewRequired
                        case .unknown: .unknown
                        }
                    return .pullRequest(worktreeId: id, number: number, checks: mappedChecks, review: mappedReview)
                }
            })
        let projection = presentation(model)
        let spec = LocalActionSpec.showPanePullRequestSummary.actionSpec
        let icon: PaneContextControlModel.Icon =
            switch spec.icon {
            case .system(let symbol): .system(symbol.rawValue)
            case .octicon(let symbol): .octicon(symbol.rawValue)
            }
        let status = LocalActionSpec.panePullRequestSummaryStatus(summary.state).actionSpec
        return GitPRSummaryChipModel(
            model: model, presentation: projection,
            control: .init(
                identifier: "pane-context.pull-requests", label: spec.label, icon: icon,
                tooltip: status.controlTooltipRenderValue(provenance: .dynamicData(.stateReadout))))
    }
    package static func presentation(_ model: GitPRSummaryPopoverModel) -> GitPRSummaryPresentationModel {
        let state: PullRequestSummaryState
        let glyph: String?
        let tone: PaneContextChipTone
        switch model.state {
        case .needsAttention(let count):
            state = .needsAttention(count: count)
            glyph = "✗"
            tone = .danger
        case .running:
            state = .running
            glyph = "◌"
            tone = .info
        case .allGood:
            state = .allGood
            glyph = "✓"
            tone = .success
        case .noInfo:
            state = .noInfo
            glyph = nil
            tone = .neutral
        }
        return GitPRSummaryPresentationModel(
            header: LocalActionSpec.panePullRequestSummaryStatus(state).actionSpec.label,
            glyph: glyph, tone: tone, memberCount: model.members.count,
            chipText: "\(model.members.count)\(glyph.map { " " + $0 } ?? "")")
    }
}
