import Foundation
import os

struct RepoStatusInput: Sendable {
    let repoId: UUID
    let repoName: String
    let repoPath: URL
    let worktreePaths: [URL]
}

struct WorktreeStatusInput: Sendable {
    let worktreeId: UUID
    let path: URL
    let branch: String
}

struct PullRequestLookupCandidate: Hashable, Sendable {
    let repoSlug: String
    let headRef: String
}

struct SidebarStatusLoadInput: Sendable {
    let repos: [RepoStatusInput]
    let worktrees: [WorktreeStatusInput]
}

struct GitMetadataSnapshot: Sendable {
    let metadataByRepoId: [UUID: RepoIdentityMetadata]
    let statusByWorktreeId: [UUID: GitBranchStatus]
}

enum GitRepositoryInspector {
    private static let logger = Logger(subsystem: "com.agentstudio", category: "SidebarGitRepositoryInspector")
    private static let processExecutor: any ProcessExecutor = DefaultProcessExecutor(timeout: 4)
    private static let metadataConcurrency = 3
    private static let statusConcurrency = 4
    private static let prConcurrency = 6
    private static let commandLookupPrefixes = ["/opt/homebrew/bin", "/usr/local/bin"]

    static func metadataAndStatus(for input: SidebarStatusLoadInput) async -> GitMetadataSnapshot {
        let metadataPairs: [(UUID, RepoIdentityMetadata)] = await boundedConcurrentMap(
            inputs: input.repos,
            limit: metadataConcurrency
        ) { repoInput in
            let metadata = await identity(for: repoInput)
            return (repoInput.repoId, metadata)
        }

        let statusPairs: [(UUID, GitBranchStatus)] = await boundedConcurrentMap(
            inputs: input.worktrees,
            limit: statusConcurrency
        ) { worktreeInput in
            let status = await branchStatus(for: worktreeInput)
            return (worktreeInput.worktreeId, status)
        }

        var metadataByRepoId: [UUID: RepoIdentityMetadata] = [:]
        metadataByRepoId.reserveCapacity(metadataPairs.count)
        for (repoId, metadata) in metadataPairs {
            metadataByRepoId[repoId] = metadata
        }

        var statusByWorktreeId: [UUID: GitBranchStatus] = [:]
        statusByWorktreeId.reserveCapacity(statusPairs.count)
        for (worktreeId, status) in statusPairs {
            statusByWorktreeId[worktreeId] = status
        }

        return GitMetadataSnapshot(
            metadataByRepoId: metadataByRepoId,
            statusByWorktreeId: statusByWorktreeId
        )
    }

    static func prCounts(for worktrees: [WorktreeStatusInput]) async -> [UUID: Int] {
        guard !worktrees.isEmpty else { return [:] }
        guard await isCommandAvailable("gh") else {
            logger.warning("Skipping PR count lookup: 'gh' command unavailable in process environment")
            return [:]
        }

        // Lookup PR counts once per checkout path, then fan results back out to
        // any duplicate worktree IDs that point at the same checkout.
        let uniqueWorktrees = deduplicatedPRLookupWorktrees(worktrees)
        let prPairs: [(String, Int)] = await boundedConcurrentMap(
            inputs: uniqueWorktrees,
            limit: prConcurrency
        ) { worktree in
            guard let prCount = await githubPRCount(for: worktree) else { return nil }
            return (normalizedPRLookupWorktreePath(worktree.path), prCount)
        }

        var countByPath: [String: Int] = [:]
        countByPath.reserveCapacity(prPairs.count)
        for (worktreePath, count) in prPairs {
            countByPath[worktreePath] = count
        }

        var countsByWorktreeId: [UUID: Int] = [:]
        countsByWorktreeId.reserveCapacity(worktrees.count)
        for worktree in worktrees {
            let path = normalizedPRLookupWorktreePath(worktree.path)
            if let count = countByPath[path] {
                countsByWorktreeId[worktree.worktreeId] = count
            }
        }

        logger.debug("Resolved PR counts for \(countsByWorktreeId.count, privacy: .public) worktrees")
        return countsByWorktreeId
    }

    static func deduplicatedPRLookupWorktrees(_ worktrees: [WorktreeStatusInput]) -> [WorktreeStatusInput] {
        var uniqueByPath: [String: WorktreeStatusInput] = [:]
        uniqueByPath.reserveCapacity(worktrees.count)

        for worktree in worktrees {
            let path = normalizedPRLookupWorktreePath(worktree.path)
            if uniqueByPath[path] == nil {
                uniqueByPath[path] = worktree
            }
        }

        return Array(uniqueByPath.values)
    }

    static func normalizedPRLookupWorktreePath(_ path: URL) -> String {
        path.standardizedFileURL.resolvingSymlinksInPath().path
    }

    static func isGitRepository(at url: URL) -> Bool {
        let dotGit = url.appending(path: ".git").path
        if FileManager.default.fileExists(atPath: dotGit) {
            return true
        }
        return runSync(command: "git", args: ["-C", url.path, "rev-parse", "--is-inside-work-tree"]) == "true"
    }

    private static func identity(for repo: RepoStatusInput) async -> RepoIdentityMetadata {
        let normalizedRepoPath = repo.repoPath.standardizedFileURL.path
        let lastPathComponent =
            repo.repoPath.lastPathComponent.isEmpty ? repo.repoName : repo.repoPath.lastPathComponent
        let parentFolderURL = repo.repoPath.deletingLastPathComponent()
        let parentFolderName =
            parentFolderURL.lastPathComponent.isEmpty ? parentFolderURL.path : parentFolderURL.lastPathComponent
        let folderCwd = normalizedRepoPath
        let normalizedWorktreeCwds = repo.worktreePaths.map { $0.standardizedFileURL.path }

        let commonDir = await git(args: ["-C", repo.repoPath.path, "rev-parse", "--git-common-dir"])
            .flatMap { canonicalizeGitPath($0, relativeTo: repo.repoPath) }

        let upstreamRemote = await git(args: ["-C", repo.repoPath.path, "remote", "get-url", "upstream"])
        let originRemote = await git(args: ["-C", repo.repoPath.path, "remote", "get-url", "origin"])
        let remoteURL = upstreamRemote ?? originRemote

        let normalizedRemote = remoteURL.flatMap(normalizeRemoteURL)
        let remoteSlug = normalizedRemote.flatMap { extractRemoteSlug(from: $0) }
        let organizationName = remoteSlug.flatMap(extractOrganizationName(from:))
        let remoteRepoName = remoteSlug.flatMap(extractRepoName(from:)) ?? lastPathComponent
        let displayName = makeRepoDisplayName(fallbackName: lastPathComponent, remoteSlug: remoteSlug)

        if let normalizedRemote {
            return RepoIdentityMetadata(
                groupKey: "remote:\(normalizedRemote)",
                displayName: displayName,
                repoName: remoteRepoName,
                worktreeCommonDirectory: commonDir,
                folderCwd: folderCwd,
                parentFolder: parentFolderName,
                organizationName: organizationName,
                originRemote: originRemote,
                upstreamRemote: upstreamRemote,
                lastPathComponent: lastPathComponent,
                worktreeCwds: normalizedWorktreeCwds,
                remoteFingerprint: normalizedRemote,
                remoteSlug: remoteSlug
            )
        }

        if let commonDir {
            return RepoIdentityMetadata(
                groupKey: "common:\(commonDir.lowercased())",
                displayName: displayName,
                repoName: remoteRepoName,
                worktreeCommonDirectory: commonDir,
                folderCwd: folderCwd,
                parentFolder: parentFolderName,
                organizationName: organizationName,
                originRemote: originRemote,
                upstreamRemote: upstreamRemote,
                lastPathComponent: lastPathComponent,
                worktreeCwds: normalizedWorktreeCwds,
                remoteFingerprint: nil,
                remoteSlug: nil
            )
        }

        return RepoIdentityMetadata(
            groupKey: "path:\(normalizedRepoPath)",
            displayName: displayName,
            repoName: remoteRepoName,
            worktreeCommonDirectory: nil,
            folderCwd: folderCwd,
            parentFolder: parentFolderName,
            organizationName: organizationName,
            originRemote: originRemote,
            upstreamRemote: upstreamRemote,
            lastPathComponent: lastPathComponent,
            worktreeCwds: normalizedWorktreeCwds,
            remoteFingerprint: nil,
            remoteSlug: nil
        )
    }

    private static func branchStatus(for worktree: WorktreeStatusInput) async -> GitBranchStatus {
        let dirtyOutput = await git(args: [
            "-C", worktree.path.path,
            "status",
            "--porcelain",
            "--untracked-files=normal",
        ])
        let isDirty = !(dirtyOutput?.isEmpty ?? true)
        let diffShortstat = await git(args: [
            "-C", worktree.path.path,
            "diff",
            "--shortstat",
            "HEAD",
            "--",
        ])
        let (linesAdded, linesDeleted) = parseLineDiffCounts(from: diffShortstat)

        let upstream = await git(args: [
            "-C", worktree.path.path,
            "rev-parse",
            "--abbrev-ref",
            "--symbolic-full-name",
            "@{upstream}",
        ])

        let syncState: GitBranchStatus.SyncState
        if upstream == nil {
            syncState = .noUpstream
        } else if let countsRaw = await git(args: [
            "-C", worktree.path.path,
            "rev-list",
            "--left-right",
            "--count",
            "HEAD...@{upstream}",
        ]) {
            let components =
                countsRaw
                .split(whereSeparator: { $0 == "\t" || $0 == " " })
                .compactMap { Int($0) }
            if components.count == 2 {
                let ahead = components[0]
                let behind = components[1]
                if ahead > 0 && behind > 0 {
                    syncState = .diverged(ahead: ahead, behind: behind)
                } else if ahead > 0 {
                    syncState = .ahead(ahead)
                } else if behind > 0 {
                    syncState = .behind(behind)
                } else {
                    syncState = .synced
                }
            } else {
                syncState = .unknown
            }
        } else {
            syncState = .unknown
        }

        return GitBranchStatus(
            isDirty: isDirty,
            syncState: syncState,
            prCount: nil,
            linesAdded: linesAdded,
            linesDeleted: linesDeleted
        )
    }

    private static func parseLineDiffCounts(from shortstat: String?) -> (Int, Int) {
        guard let shortstat else { return (0, 0) }
        guard !shortstat.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return (0, 0) }

        let added = captureFirstInt(in: shortstat, pattern: #"(\\d+) insertions?\(\+\)"#) ?? 0
        let deleted = captureFirstInt(in: shortstat, pattern: #"(\\d+) deletions?\(-\)"#) ?? 0
        return (added, deleted)
    }

    private static func captureFirstInt(in text: String, pattern: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else { return nil }
        guard match.numberOfRanges > 1 else { return nil }
        let valueRange = match.range(at: 1)
        guard let swiftRange = Range(valueRange, in: text) else { return nil }
        return Int(text[swiftRange])
    }

    private static func githubPRCount(for worktree: WorktreeStatusInput) async -> Int? {
        let upstreamRemote = await git(args: ["-C", worktree.path.path, "remote", "get-url", "upstream"])
        let originRemote = await git(args: ["-C", worktree.path.path, "remote", "get-url", "origin"])
        let upstreamNormalized = upstreamRemote.flatMap(normalizeRemoteURL)
        let originNormalized = originRemote.flatMap(normalizeRemoteURL)
        let upstreamSlug = githubRemoteSlug(from: upstreamNormalized)
        let originSlug = githubRemoteSlug(from: originNormalized)

        // Prefer live branch state from git at this worktree path so PR counts
        // remain accurate even when cached worktree metadata is stale.
        let liveBranch = await git(args: ["-C", worktree.path.path, "rev-parse", "--abbrev-ref", "HEAD"])
        let candidateBranches = [liveBranch, worktree.branch]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "HEAD" }
        guard !candidateBranches.isEmpty else { return nil }

        var lookupCandidates: [PullRequestLookupCandidate] = []
        for branch in candidateBranches {
            lookupCandidates.append(
                contentsOf: pullRequestLookupCandidates(
                    branch: branch,
                    upstreamRepoSlug: upstreamSlug,
                    originRepoSlug: originSlug
                ))
        }
        var seen = Set<PullRequestLookupCandidate>()
        lookupCandidates = lookupCandidates.filter { seen.insert($0).inserted }
        guard !lookupCandidates.isEmpty else { return nil }

        var lastResolvedCount: Int?
        for candidate in lookupCandidates {
            guard let count = await githubPRCount(repoSlug: candidate.repoSlug, headRef: candidate.headRef) else {
                continue
            }
            if count > 0 {
                return count
            }
            lastResolvedCount = count
        }

        return lastResolvedCount
    }

    static func pullRequestLookupCandidates(
        branch rawBranch: String,
        upstreamRepoSlug: String?,
        originRepoSlug: String?
    ) -> [PullRequestLookupCandidate] {
        let branch =
            rawBranch
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "refs/heads/", with: "")
        guard !branch.isEmpty else { return [] }

        var candidates: [PullRequestLookupCandidate] = []
        candidates.reserveCapacity(3)

        if let upstreamRepoSlug {
            candidates.append(PullRequestLookupCandidate(repoSlug: upstreamRepoSlug, headRef: branch))

            if let upstreamOwner = ownerFromRepoSlug(upstreamRepoSlug),
                let originOwner = ownerFromRepoSlug(originRepoSlug),
                upstreamOwner.lowercased() != originOwner.lowercased()
            {
                candidates.append(
                    PullRequestLookupCandidate(
                        repoSlug: upstreamRepoSlug,
                        headRef: "\(originOwner):\(branch)"
                    ))
            }
        }

        if let originRepoSlug {
            candidates.append(PullRequestLookupCandidate(repoSlug: originRepoSlug, headRef: branch))
        }

        var seen = Set<PullRequestLookupCandidate>()
        return candidates.filter { seen.insert($0).inserted }
    }

    private static func githubRemoteSlug(from normalizedRemote: String?) -> String? {
        guard
            let normalizedRemote,
            normalizedRemote.hasPrefix("github.com/")
        else {
            return nil
        }
        return extractRemoteSlug(from: normalizedRemote)
    }

    private static func ownerFromRepoSlug(_ slug: String?) -> String? {
        guard let slug else { return nil }
        let components = slug.split(separator: "/").map(String.init).filter { !$0.isEmpty }
        guard components.count >= 2 else { return nil }
        return components.dropLast().joined(separator: "/")
    }

    private static func githubPRCount(repoSlug: String, headRef: String) async -> Int? {
        if let output = await run(
            command: "gh",
            args: [
                "pr", "list",
                "--repo", repoSlug,
                "--head", headRef,
                "--state", "open",
                "--json", "number",
                "--limit", "50",
            ])
        {
            if let count = parsePullRequestArrayCount(from: output) {
                return count
            }
            logger.warning(
                "gh PR response parse failed for repo=\(repoSlug, privacy: .public) head=\(headRef, privacy: .public)"
            )
        } else {
            logger.debug(
                "Falling back to GitHub REST PR lookup for \(repoSlug, privacy: .public) head=\(headRef, privacy: .public)"
            )
        }

        return await githubPRCountViaREST(repoSlug: repoSlug, headRef: headRef)
    }

    private static func githubPRCountViaREST(repoSlug: String, headRef: String) async -> Int? {
        var components = URLComponents(string: "https://api.github.com/repos/\(repoSlug)/pulls")
        components?.queryItems = [
            URLQueryItem(name: "head", value: headRef),
            URLQueryItem(name: "state", value: "open"),
            URLQueryItem(name: "per_page", value: "100"),
        ]

        guard let requestURL = components?.url else { return nil }

        var args = [
            "-sS",
            "-L",
            "--connect-timeout", "2",
            "--max-time", "4",
            "-H", "Accept: application/vnd.github+json",
            "-H", "X-GitHub-Api-Version: 2022-11-28",
        ]

        // If user has a token in environment, forward it for private repos /
        // higher rate limits. Fallback remains unauthenticated for public repos.
        let environment = ProcessInfo.processInfo.environment
        if let token = environment["GH_TOKEN"] ?? environment["GITHUB_TOKEN"],
            !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            args.append(contentsOf: ["-H", "Authorization: Bearer \(token)"])
        }

        args.append(requestURL.absoluteString)

        guard let output = await run(command: "curl", args: args) else { return nil }
        if let count = parsePullRequestArrayCount(from: output) {
            return count
        }
        logger.warning(
            "GitHub REST PR response parse failed for repo=\(repoSlug, privacy: .public) head=\(headRef, privacy: .public)"
        )
        return nil
    }

    private static func parsePullRequestArrayCount(from output: String) -> Int? {
        guard let data = output.data(using: .utf8) else { return nil }
        guard let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        return array.count
    }

    private static func canonicalizeGitPath(_ rawPath: String, relativeTo repoPath: URL) -> String? {
        guard !rawPath.isEmpty else { return nil }
        if rawPath.hasPrefix("/") {
            return URL(fileURLWithPath: rawPath).standardizedFileURL.path
        }
        return
            repoPath
            .appending(path: rawPath)
            .standardizedFileURL
            .path
    }

    private static func normalizeRemoteURL(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("git@") {
            let withoutPrefix = trimmed.replacingOccurrences(of: "git@", with: "")
            let normalized = withoutPrefix.replacingOccurrences(
                of: ":", with: "/", options: .literal, range: withoutPrefix.range(of: ":"))
            return
                normalized
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                .replacingOccurrences(of: ".git", with: "")
                .lowercased()
        }

        if let url = URL(string: trimmed), let host = url.host {
            let path = url.path
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                .replacingOccurrences(of: ".git", with: "")
            return "\(host.lowercased())/\(path)"
        }

        return
            trimmed
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .replacingOccurrences(of: ".git", with: "")
            .lowercased()
    }

    private static func extractRemoteSlug(from normalizedRemote: String) -> String? {
        guard let slashIndex = normalizedRemote.firstIndex(of: "/") else { return nil }
        let slug = String(normalizedRemote[normalizedRemote.index(after: slashIndex)...])
        return slug.isEmpty ? nil : slug
    }

    private static func extractOrganizationName(from remoteSlug: String) -> String? {
        let components =
            remoteSlug
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty }
        guard components.count >= 2 else { return nil }
        let organization = components.dropLast().joined(separator: "/")
        return organization.isEmpty ? nil : organization
    }

    private static func extractRepoName(from remoteSlug: String) -> String? {
        let components =
            remoteSlug
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty }
        return components.last
    }

    static func makeRepoDisplayName(fallbackName: String, remoteSlug: String?) -> String {
        guard let remoteSlug else { return fallbackName }

        let components =
            remoteSlug
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty }

        guard components.count >= 2 else { return fallbackName }

        let repoComponent = components.last ?? fallbackName
        let organization = components.dropLast().joined(separator: "/")
        guard !organization.isEmpty else { return fallbackName }

        return "\(repoComponent) · \(organization)"
    }

    private static func isCommandAvailable(_ command: String) async -> Bool {
        if await run(command: "which", args: [command]) != nil {
            return true
        }
        return commandLookupPrefixes.contains { prefix in
            FileManager.default.isExecutableFile(atPath: "\(prefix)/\(command)")
        }
    }

    private static func git(args: [String]) async -> String? {
        await run(command: "git", args: args)
    }

    private static func run(command: String, args: [String]) async -> String? {
        for executable in commandCandidates(for: command) {
            do {
                let result = try await processExecutor.execute(
                    command: executable,
                    args: args,
                    cwd: nil,
                    environment: nil
                )
                guard result.succeeded else {
                    if command == "gh" {
                        logger.warning(
                            "gh command failed: executable=\(executable, privacy: .public) args=\(args.joined(separator: " "), privacy: .public) stderr=\(result.stderr, privacy: .public)"
                        )
                    }
                    continue
                }
                let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            } catch {
                if command == "gh" {
                    logger.warning(
                        "gh command threw: executable=\(executable, privacy: .public) args=\(args.joined(separator: " "), privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                    )
                }
                continue
            }
        }

        return nil
    }

    private static func runSync(command: String, args: [String]) -> String? {
        guard let output = runProcess(command: command, args: args) else { return nil }
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func boundedConcurrentMap<Input: Sendable, Output: Sendable>(
        inputs: [Input],
        limit: Int,
        transform: @escaping @Sendable (Input) async -> Output?
    ) async -> [Output] {
        guard !inputs.isEmpty else { return [] }
        let concurrency = Swift.min(Swift.max(limit, 1), inputs.count)
        var iterator = inputs.makeIterator()

        return await withTaskGroup(of: Output?.self) { group in
            for _ in 0..<concurrency {
                guard let input = iterator.next() else { break }
                group.addTask {
                    await transform(input)
                }
            }

            var outputs: [Output] = []
            outputs.reserveCapacity(inputs.count)

            while let output = await group.next() {
                if let output {
                    outputs.append(output)
                }

                if let nextInput = iterator.next() {
                    group.addTask {
                        await transform(nextInput)
                    }
                }
            }

            return outputs
        }
    }

    private static func runProcess(command: String, args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + args

        var env = ProcessInfo.processInfo.environment
        let inheritedPath = env["PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let basePath = (inheritedPath?.isEmpty == false) ? inheritedPath! : "/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(basePath)"
        let inheritedHome = env["HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if inheritedHome?.isEmpty != false {
            env["HOME"] = FileManager.default.homeDirectoryForCurrentUser.path
        }
        process.environment = env

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    private static func commandCandidates(for command: String) -> [String] {
        guard !command.contains("/") else { return [command] }

        var candidates = [command]
        for prefix in commandLookupPrefixes {
            let candidate = "\(prefix)/\(command)"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                candidates.append(candidate)
            }
        }

        var seen = Set<String>()
        return candidates.filter { seen.insert($0).inserted }
    }
}
