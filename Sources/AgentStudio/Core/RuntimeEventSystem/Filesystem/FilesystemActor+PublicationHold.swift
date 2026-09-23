import AgentStudioInfrastructure
import Foundation

package struct WatchedFolderPublicationHoldID: Hashable, Sendable {
    let rawValue: UUID
}

/// A released hold still covers every scan whose demand was accepted before release:
/// such a scan may have observed the destination half-built or before a rollback removed
/// it, so its result must not publish the destination even when applied after release.
struct ReleasedWatchedFolderPublicationHold: Sendable {
    let path: String
    /// Per source, the latest scan demand accepted when the hold was released.
    var demandCoverageAtReleaseBySourceID: [FilesystemSourceID: WatchedFolderScanDemandCoverage]
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
        guard let path = watchedFolderScanState.publicationHoldPathsByID.removeValue(forKey: holdID) else {
            return
        }
        let demandCoverageAtRelease = watchedFolderScanState.latestDemandCoverageBySourceID
        guard !demandCoverageAtRelease.isEmpty else { return }
        watchedFolderScanState.releasedPublicationHoldsByID[holdID] = ReleasedWatchedFolderPublicationHold(
            path: path,
            demandCoverageAtReleaseBySourceID: demandCoverageAtRelease
        )
    }

    /// Paths a result from `sourceID` must not publish: every active hold, plus released
    /// holds whose release came after the demand this result covers.
    func publicationHeldPaths(
        forResultFrom sourceID: FilesystemSourceID,
        coverage: WatchedFolderScanDemandCoverage
    ) -> Set<String> {
        var heldPaths = Set(watchedFolderScanState.publicationHoldPathsByID.values)
        for released in watchedFolderScanState.releasedPublicationHoldsByID.values {
            guard let coverageAtRelease = released.demandCoverageAtReleaseBySourceID[sourceID],
                coverageAtRelease.covers(coverage)
            else { continue }
            heldPaths.insert(released.path)
        }
        return heldPaths
    }

    /// Once a source applies a result demanded after release, its released holds no longer
    /// apply to it; a hold with no remaining sources is forgotten.
    func retireReleasedPublicationHolds(
        satisfiedBy coverage: WatchedFolderScanDemandCoverage,
        from sourceID: FilesystemSourceID
    ) {
        for (holdID, released) in watchedFolderScanState.releasedPublicationHoldsByID {
            guard let coverageAtRelease = released.demandCoverageAtReleaseBySourceID[sourceID],
                !coverageAtRelease.covers(coverage)
            else { continue }
            var remaining = released
            remaining.demandCoverageAtReleaseBySourceID.removeValue(forKey: sourceID)
            watchedFolderScanState.releasedPublicationHoldsByID[holdID] =
                remaining.demandCoverageAtReleaseBySourceID.isEmpty ? nil : remaining
        }
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
