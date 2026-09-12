import AgentStudioInfrastructure
import Foundation

package enum WatchedFolderTopologyCoverage: Sendable {
    case authoritative(RepositoryRetentionTime)
    case additive
}

/// Actual validated positives plus explicit authority over the source's negative space.
package struct WatchedFolderTopologyObservation: Sendable {
    package let root: URL
    package let canonicalRoot: URL
    package let registration: FSEventRegistrationToken
    package let entries: [RepoScanner.ResolvedGitEntry]
    package let otherObservedPaths: Set<URL>
    package let coverage: WatchedFolderTopologyCoverage
    package let baselineMembershipRevision: UInt64
    package let incompleteOtherScopes: [URL]
    let demandCoverage: WatchedFolderScanDemandCoverage?

    init(
        root: URL,
        registration: FSEventRegistrationToken,
        entries: [RepoScanner.ResolvedGitEntry],
        otherObservedPaths: Set<URL>,
        coverage: WatchedFolderTopologyCoverage,
        baselineMembershipRevision: UInt64,
        incompleteOtherScopes: [URL],
        demandCoverage: WatchedFolderScanDemandCoverage? = nil,
        canonicalRoot: URL? = nil
    ) {
        self.root = root
        self.canonicalRoot = canonicalRoot ?? root
        self.registration = registration
        self.entries = entries
        self.otherObservedPaths = otherObservedPaths
        self.coverage = coverage
        self.baselineMembershipRevision = baselineMembershipRevision
        self.incompleteOtherScopes = incompleteOtherScopes
        self.demandCoverage = demandCoverage
    }
}
