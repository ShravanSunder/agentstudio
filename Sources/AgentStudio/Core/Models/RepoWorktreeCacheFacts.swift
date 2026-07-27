import Foundation

package struct RepoWorktreeCacheFacts: Equatable, Sendable {
    package var enrichment: WorktreeEnrichment?
    package var pullRequestCount: Int?

    package init(
        enrichment: WorktreeEnrichment? = nil,
        pullRequestCount: Int? = nil
    ) {
        self.enrichment = enrichment
        self.pullRequestCount = pullRequestCount
    }

    package static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.hasSameCacheContent(as: rhs)
    }

    package func hasSameCacheContent(as other: Self) -> Bool {
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
