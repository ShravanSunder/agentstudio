import AppKit
import Foundation

struct RepoPresentationGroup: Identifiable {
    let id: String
    let repoTitle: String
    let organizationName: String?
    let repos: [RepoPresentationItem]

    var checkoutCount: Int {
        repos.reduce(0) { $0 + $1.worktrees.count }
    }
}

struct RepoPresentationItem: Identifiable, Hashable {
    let id: UUID
    let name: String
    let repoPath: URL
    let stableKey: String
    var worktrees: [Worktree]

    init(
        id: UUID,
        name: String,
        repoPath: URL,
        stableKey: String,
        worktrees: [Worktree]
    ) {
        self.id = id
        self.name = name
        self.repoPath = repoPath
        self.stableKey = stableKey
        self.worktrees = worktrees
    }

    init(repo: Repo) {
        self.init(
            id: repo.id,
            name: repo.name,
            repoPath: repo.repoPath,
            stableKey: repo.stableKey,
            worktrees: repo.worktrees
        )
    }
}

struct RepoIdentityMetadata: Sendable {
    let groupKey: String
    let displayName: String
    let repoName: String
    let worktreeCommonDirectory: String?
    let folderCwd: String
    let parentFolder: String
    let organizationName: String?
    let originRemote: String?
    let upstreamRemote: String?
    let lastPathComponent: String
    let worktreeCwds: [String]
    let remoteFingerprint: String?
    let remoteSlug: String?
}

enum RepoPresentationGrouping {
    struct ColorPreset {
        let name: String
        let hex: String
    }

    private struct OwnerCandidate {
        let repoId: UUID
        let repoWorktreeCount: Int
        let repoPathMatchesWorktree: Bool
        let isMainWorktree: Bool
        let stableTieBreaker: String
    }

    static let automaticPaletteHexes: [String] = AppStyle.accentPaletteHexes

    static let colorPresets: [ColorPreset] = [
        ColorPreset(name: "Yellow", hex: "#F5C451"),
        ColorPreset(name: "Sky", hex: "#58C4FF"),
        ColorPreset(name: "Violet", hex: "#A78BFA"),
        ColorPreset(name: "Green", hex: "#4ADE80"),
        ColorPreset(name: "Orange", hex: "#FB923C"),
        ColorPreset(name: "Pink", hex: "#F472B6"),
    ]

    static func colorHexForCheckoutIndex(_ index: Int, seed: String) -> String {
        if index < automaticPaletteHexes.count {
            return automaticPaletteHexes[index]
        }

        return generatedColorHex(seed: seed)
    }

    static func buildGroups(
        repos: [RepoPresentationItem],
        metadataByRepoId: [UUID: RepoIdentityMetadata]
    ) -> [RepoPresentationGroup] {
        let grouped = Dictionary(grouping: repos) { repo in
            metadataByRepoId[repo.id]?.groupKey ?? "path:\(repo.repoPath.standardizedFileURL.path)"
        }

        return grouped.compactMap { groupKey, groupRepos in
            let deduplicatedRepos = dedupeReposByCheckoutCwd(groupRepos)
            guard !deduplicatedRepos.isEmpty else { return nil }

            let firstRepoId = deduplicatedRepos.first?.id ?? groupRepos.first?.id
            let metadata = firstRepoId.flatMap { metadataByRepoId[$0] }
            let repoTitle =
                metadata?.repoName
                ?? metadata?.lastPathComponent
                ?? deduplicatedRepos.first?.name
                ?? "Repository"
            return RepoPresentationGroup(
                id: groupKey,
                repoTitle: repoTitle,
                organizationName: metadata?.organizationName,
                repos: deduplicatedRepos.sorted {
                    $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
            )
        }
        .sorted { lhs, rhs in
            let leftTitle = lhs.organizationName.map { "\(lhs.repoTitle)\($0)" } ?? lhs.repoTitle
            let rightTitle = rhs.organizationName.map { "\(rhs.repoTitle)\($0)" } ?? rhs.repoTitle
            return leftTitle.localizedCaseInsensitiveCompare(rightTitle) == .orderedAscending
        }
    }

    private static func generatedColorHex(seed: String) -> String {
        let hash = seed.unicodeScalars.reduce(0) { partial, scalar in
            (partial &* 33 &+ Int(scalar.value)) & 0x7fff_ffff
        }
        let hue = CGFloat(hash % 360) / 360.0
        let saturation: CGFloat = 0.58
        let brightness: CGFloat = 0.94
        return NSColor(calibratedHue: hue, saturation: saturation, brightness: brightness, alpha: 1.0).hexString
    }

    private static func dedupeReposByCheckoutCwd(_ repos: [RepoPresentationItem]) -> [RepoPresentationItem] {
        var ownerByCwd: [String: OwnerCandidate] = [:]

        for repo in repos {
            for worktree in repo.worktrees {
                let checkoutCwd = normalizedCwdPath(worktree.path)
                let candidate = OwnerCandidate(
                    repoId: repo.id,
                    repoWorktreeCount: repo.worktrees.count,
                    repoPathMatchesWorktree: normalizedCwdPath(repo.repoPath) == checkoutCwd,
                    isMainWorktree: worktree.isMainWorktree,
                    stableTieBreaker: "\(repo.id.uuidString)|\(worktree.id.uuidString)"
                )

                if let existing = ownerByCwd[checkoutCwd] {
                    if shouldPrefer(candidate: candidate, over: existing) {
                        ownerByCwd[checkoutCwd] = candidate
                    }
                } else {
                    ownerByCwd[checkoutCwd] = candidate
                }
            }
        }

        var deduplicatedRepos: [RepoPresentationItem] = []
        for repo in repos {
            guard !repo.worktrees.isEmpty else { continue }

            var seenWorktreeCwds: Set<String> = []
            let deduplicatedWorktrees = repo.worktrees.filter { worktree in
                let checkoutCwd = normalizedCwdPath(worktree.path)
                guard !seenWorktreeCwds.contains(checkoutCwd) else { return false }
                seenWorktreeCwds.insert(checkoutCwd)
                return ownerByCwd[checkoutCwd]?.repoId == repo.id
            }

            guard !deduplicatedWorktrees.isEmpty else { continue }

            var updated = repo
            updated.worktrees = deduplicatedWorktrees
            deduplicatedRepos.append(updated)
        }

        return deduplicatedRepos
    }

    private static func shouldPrefer(candidate: OwnerCandidate, over existing: OwnerCandidate) -> Bool {
        if candidate.repoWorktreeCount != existing.repoWorktreeCount {
            return candidate.repoWorktreeCount > existing.repoWorktreeCount
        }
        if candidate.repoPathMatchesWorktree != existing.repoPathMatchesWorktree {
            return candidate.repoPathMatchesWorktree
        }
        if candidate.isMainWorktree != existing.isMainWorktree {
            return candidate.isMainWorktree
        }
        return candidate.stableTieBreaker.localizedCaseInsensitiveCompare(existing.stableTieBreaker)
            == .orderedAscending
    }

    private static func normalizedCwdPath(_ url: URL) -> String {
        url.standardizedFileURL.path
    }
}

enum RepoPresentationColoring {
    static func buildRepoMetadata(
        repos: [RepoPresentationItem],
        repoEnrichmentByRepoId: [UUID: RepoEnrichment]
    ) -> [UUID: RepoIdentityMetadata] {
        var metadataByRepoId: [UUID: RepoIdentityMetadata] = [:]
        metadataByRepoId.reserveCapacity(repos.count)

        for repo in repos {
            let enrichment = repoEnrichmentByRepoId[repo.id]
            let normalizedRepoPath = repo.repoPath.standardizedFileURL.path

            let groupKey: String
            let displayName: String
            let organizationName: String?
            let originRemote: String?
            let upstreamRemote: String?
            let remoteSlug: String?

            switch enrichment {
            case .resolvedRemote(_, let raw, let identity, _):
                groupKey = identity.groupKey
                displayName = identity.displayName
                organizationName = identity.organizationName
                originRemote = raw.origin
                upstreamRemote = raw.upstream
                remoteSlug = identity.remoteSlug
            case .resolvedLocal(_, let identity, _):
                groupKey = identity.groupKey
                displayName = identity.displayName
                organizationName = identity.organizationName
                originRemote = nil
                upstreamRemote = nil
                remoteSlug = identity.remoteSlug
            case .awaitingOrigin, nil:
                groupKey = "path:\(normalizedRepoPath)"
                displayName = repo.name
                organizationName = nil
                originRemote = nil
                upstreamRemote = nil
                remoteSlug = nil
            }

            metadataByRepoId[repo.id] = RepoIdentityMetadata(
                groupKey: groupKey,
                displayName: displayName,
                repoName: displayName,
                worktreeCommonDirectory: nil,
                folderCwd: normalizedRepoPath,
                parentFolder: repo.repoPath.deletingLastPathComponent().lastPathComponent,
                organizationName: organizationName,
                originRemote: originRemote,
                upstreamRemote: upstreamRemote,
                lastPathComponent: repo.repoPath.lastPathComponent,
                worktreeCwds: repo.worktrees.map { $0.path.standardizedFileURL.path },
                remoteFingerprint: originRemote,
                remoteSlug: remoteSlug
            )
        }

        return metadataByRepoId
    }

    static func checkoutColorHex(
        for repo: RepoPresentationItem,
        in group: RepoPresentationGroup,
        checkoutColorOverrides: [String: String] = [:]
    ) -> String {
        let overrideKey = repo.id.uuidString
        if let hex = checkoutColorOverrides[overrideKey],
            let nsColor = NSColor(hex: hex)
        {
            return nsColor.hexString
        }

        let orderedFamilies = group.repos.sorted { lhs, rhs in
            lhs.stableKey.localizedCaseInsensitiveCompare(rhs.stableKey) == .orderedAscending
        }

        guard orderedFamilies.count > 1 else {
            return RepoPresentationGrouping.automaticPaletteHexes[0]
        }

        guard let familyIndex = orderedFamilies.firstIndex(where: { $0.id == repo.id }) else {
            return RepoPresentationGrouping.automaticPaletteHexes[0]
        }

        return RepoPresentationGrouping.colorHexForCheckoutIndex(
            familyIndex,
            seed: "\(group.id)|\(repo.stableKey)|\(repo.id.uuidString)"
        )
    }
}
