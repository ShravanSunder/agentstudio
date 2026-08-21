@testable import AgentStudioCore

extension PullRequestRepositoryProjection {
    var confirmedFactsByBranch: [String: PullRequestFacts]? {
        switch self {
        case .stable(let presentation), .loading(let presentation, _):
            switch presentation {
            case .unknown:
                return nil
            case .ready(let confirmedFactsByBranch):
                return confirmedFactsByBranch
            case .unavailable(let previousConfirmedFactsByBranch):
                return previousConfirmedFactsByBranch
            }
        }
    }
}
