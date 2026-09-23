import AgentStudioInfrastructure
import Foundation

package struct WatchedFolderPublicationHoldID: Hashable, Sendable {
    let rawValue: UUID
}

/// A creation owner builds a checkout in place; linked-worktree metadata appears
/// before the checkout is complete, so discovery could publish it half-built. A hold
/// withholds that destination from every scan result until the owner releases it,
/// then the owner requests a refresh that publishes the finished checkout. While held,
/// directory churn inside the destination is treated like work inside a known checkout
/// and does not admit scans.
extension FilesystemActor {
    package func holdWatchedFolderPublication(of destination: URL) -> WatchedFolderPublicationHoldID {
        let holdID = WatchedFolderPublicationHoldID(rawValue: UUIDv7.generate())
        watchedFolderScanState.publicationHoldPathsByID[holdID] =
            WatchedFolderPublicationHolds.canonicalPath(destination)
        return holdID
    }

    package func releaseWatchedFolderPublicationHold(_ holdID: WatchedFolderPublicationHoldID) {
        watchedFolderScanState.publicationHoldPathsByID.removeValue(forKey: holdID)
    }
}

enum WatchedFolderPublicationHolds {
    static func canonicalPath(_ url: URL) -> String {
        FilesystemRootOwnership.canonicalizeKernelPath(url.standardizedFileURL.path)
    }

    /// Drops verified checkouts at or under a held path, as if the scan had not seen them.
    static func excludingHeldCheckouts(from result: RepoScannerResult, heldPaths: Set<String>) -> RepoScannerResult {
        guard !heldPaths.isEmpty else { return result }
        func isPublishable(_ entry: RepoScanner.ResolvedGitEntry) -> Bool {
            let entryPath = canonicalPath(entry.path)
            return !heldPaths.contains { entryPath == $0 || entryPath.hasPrefix($0 + "/") }
        }
        switch result {
        case .completeAuthoritative(let scan):
            return .completeAuthoritative(
                CompleteRepoScan(
                    verifiedEntries: scan.verifiedEntries.filter(isPublishable),
                    counts: scan.counts,
                    serviceMetrics: scan.serviceMetrics
                ))
        case .partial(let scan):
            return .partial(
                PartialRepoScan(
                    verifiedEntries: scan.verifiedEntries.filter(isPublishable),
                    failures: scan.failures,
                    counts: scan.counts,
                    serviceMetrics: scan.serviceMetrics
                ))
        case .cancelled(let scan):
            return .cancelled(
                CancelledRepoScan(
                    verifiedEntries: scan.verifiedEntries.filter(isPublishable),
                    counts: scan.counts,
                    serviceMetrics: scan.serviceMetrics
                ))
        case .unavailable, .failed:
            return result
        }
    }
}
