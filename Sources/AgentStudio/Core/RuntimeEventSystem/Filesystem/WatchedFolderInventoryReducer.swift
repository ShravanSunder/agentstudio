import Foundation

enum WatchedFolderInventoryReduction: Equatable, Sendable {
    case authoritativeReplacement(WatchedFolderInventoryMutation)
    case additiveMerge(WatchedFolderInventoryMutation)
    case preserved
}

struct WatchedFolderInventoryMutation: Equatable, Sendable {
    let repoGroups: [RepoScanner.RepoScanGroup]
    let changedRepositories: [DiscoveredRepoTopologyInfo]
    let removedClonePaths: Set<URL>
}

enum WatchedFolderInventoryReducer {
    static func reduce(
        previousGroups: [RepoScanner.RepoScanGroup],
        scannerResult: RepoScannerResult,
        mayReplaceNegativeSpace: Bool
    ) -> WatchedFolderInventoryReduction {
        switch scannerResult {
        case .completeAuthoritative(let complete) where mayReplaceNegativeSpace:
            return .authoritativeReplacement(
                replacement(
                    previousGroups: previousGroups,
                    verifiedEntries: complete.verifiedEntries
                )
            )
        case .completeAuthoritative(let complete):
            return .additiveMerge(
                additiveMerge(
                    previousGroups: previousGroups,
                    verifiedEntries: complete.verifiedEntries
                )
            )
        case .partial(let partial):
            return .additiveMerge(
                additiveMerge(
                    previousGroups: previousGroups,
                    verifiedEntries: partial.verifiedEntries
                )
            )
        case .cancelled(let cancelled):
            return .additiveMerge(
                additiveMerge(
                    previousGroups: previousGroups,
                    verifiedEntries: cancelled.verifiedEntries
                )
            )
        case .unavailable, .failed:
            return .preserved
        }
    }

    private static func replacement(
        previousGroups: [RepoScanner.RepoScanGroup],
        verifiedEntries: [RepoScanner.ResolvedGitEntry]
    ) -> WatchedFolderInventoryMutation {
        let previousByClonePath = groupsByClonePath(previousGroups)
        let nextGroups = normalizedGroups(verifiedEntries)
        let nextByClonePath = groupsByClonePath(nextGroups)
        return mutation(
            previousByClonePath: previousByClonePath,
            nextByClonePath: nextByClonePath,
            removedClonePaths: Set(previousByClonePath.keys).subtracting(nextByClonePath.keys)
        )
    }

    private static func additiveMerge(
        previousGroups: [RepoScanner.RepoScanGroup],
        verifiedEntries: [RepoScanner.ResolvedGitEntry]
    ) -> WatchedFolderInventoryMutation {
        let previousByClonePath = groupsByClonePath(previousGroups)
        let positiveByClonePath = groupsByClonePath(normalizedGroups(verifiedEntries))
        var nextByClonePath = previousByClonePath
        for (clonePath, positiveGroup) in positiveByClonePath {
            guard let previousGroup = previousByClonePath[clonePath] else {
                nextByClonePath[clonePath] = positiveGroup
                continue
            }
            nextByClonePath[clonePath] = RepoScanner.RepoScanGroup(
                clonePath: clonePath,
                linkedWorktreePaths: Array(
                    Set(previousGroup.linkedWorktreePaths)
                        .union(positiveGroup.linkedWorktreePaths)
                ).sorted(by: sortByPath)
            )
        }
        return mutation(
            previousByClonePath: previousByClonePath,
            nextByClonePath: nextByClonePath,
            removedClonePaths: []
        )
    }

    private static func mutation(
        previousByClonePath: [URL: RepoScanner.RepoScanGroup],
        nextByClonePath: [URL: RepoScanner.RepoScanGroup],
        removedClonePaths: Set<URL>
    ) -> WatchedFolderInventoryMutation {
        let nextGroups = nextByClonePath.values.sorted { lhs, rhs in
            sortByPath(lhs.clonePath, rhs.clonePath)
        }
        let changedRepositories = nextGroups.compactMap { group -> DiscoveredRepoTopologyInfo? in
            guard previousByClonePath[group.clonePath] != group else { return nil }
            return DiscoveredRepoTopologyInfo(
                repoPath: group.clonePath,
                linkedWorktrees: .scanned(group.linkedWorktreePaths)
            )
        }
        return WatchedFolderInventoryMutation(
            repoGroups: nextGroups,
            changedRepositories: changedRepositories,
            removedClonePaths: removedClonePaths
        )
    }

    private static func normalizedGroups(
        _ verifiedEntries: [RepoScanner.ResolvedGitEntry]
    ) -> [RepoScanner.RepoScanGroup] {
        RepoScanner.groupResolvedEntries(verifiedEntries)
            .map { group in
                RepoScanner.RepoScanGroup(
                    clonePath: group.clonePath.standardizedFileURL,
                    linkedWorktreePaths: group.linkedWorktreePaths
                        .map(\.standardizedFileURL)
                        .sorted(by: sortByPath)
                )
            }
    }

    private static func groupsByClonePath(
        _ groups: [RepoScanner.RepoScanGroup]
    ) -> [URL: RepoScanner.RepoScanGroup] {
        Dictionary(uniqueKeysWithValues: groups.map { ($0.clonePath, $0) })
    }

    private static func sortByPath(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.path.localizedCaseInsensitiveCompare(rhs.path) == .orderedAscending
    }
}
