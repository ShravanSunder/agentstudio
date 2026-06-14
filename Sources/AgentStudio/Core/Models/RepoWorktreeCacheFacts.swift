import Foundation

struct RepoWorktreeCacheFacts: Equatable, Sendable {
    var enrichment: WorktreeEnrichment?
    var pullRequestCount: Int?

    init(
        enrichment: WorktreeEnrichment? = nil,
        pullRequestCount: Int? = nil
    ) {
        self.enrichment = enrichment
        self.pullRequestCount = pullRequestCount
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.hasSameCacheContent(as: rhs)
    }

    func hasSameCacheContent(as other: Self) -> Bool {
        let enrichmentMatches =
            switch (enrichment, other.enrichment) {
            case (.none, .none):
                true
            case (.some(let lhs), .some(let rhs)):
                lhs.hasSameCacheContent(as: rhs)
            case (.some, .none), (.none, .some):
                false
            }
        return enrichmentMatches && pullRequestCount == other.pullRequestCount
    }
}
