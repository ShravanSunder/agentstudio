enum ForgePresentationFacts {
    static func confirmedFacts(
        in presentation: PullRequestStablePresentation
    ) -> [String: PullRequestFacts]? {
        switch presentation {
        case .unknown:
            nil
        case .ready(let confirmedFactsByBranch):
            confirmedFactsByBranch
        case .unavailable(let previousConfirmedFactsByBranch):
            previousConfirmedFactsByBranch
        }
    }

    static func removingConfirmedBranches(
        _ branches: Set<String>,
        from presentation: PullRequestStablePresentation
    ) -> PullRequestStablePresentation {
        switch presentation {
        case .unknown:
            return .unknown
        case .ready(var confirmedFactsByBranch):
            for branch in branches {
                confirmedFactsByBranch.removeValue(forKey: branch)
            }
            return .ready(confirmedFactsByBranch: confirmedFactsByBranch)
        case .unavailable(.some(var previousConfirmedFactsByBranch)):
            for branch in branches {
                previousConfirmedFactsByBranch.removeValue(forKey: branch)
            }
            return .unavailable(
                previousConfirmedFactsByBranch: previousConfirmedFactsByBranch
            )
        case .unavailable(.none):
            return .unavailable(previousConfirmedFactsByBranch: nil)
        }
    }

    static func normalizedBranch(_ branch: String?) -> String? {
        guard let branch, !branch.isEmpty else { return nil }
        return branch
    }
}
