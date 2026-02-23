import Foundation

struct RepoStatusInput: Sendable {
    let repoId: UUID
    let repoName: String
    let repoPath: URL
}

struct WorktreeStatusInput: Sendable {
    let worktreeId: UUID
    let path: URL
    let branch: String
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
    private static let processExecutor: any ProcessExecutor = DefaultProcessExecutor(timeout: 4)
    private static let metadataConcurrency = 3
    private static let statusConcurrency = 4
    private static let prConcurrency = 1

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
        guard await isCommandAvailable("gh") else { return [:] }

        let prPairs: [(UUID, Int)] = await boundedConcurrentMap(
            inputs: worktrees,
            limit: prConcurrency
        ) { worktree in
            guard let prCount = await githubPRCount(for: worktree) else { return nil }
            return (worktree.worktreeId, prCount)
        }

        var countsByWorktreeId: [UUID: Int] = [:]
        countsByWorktreeId.reserveCapacity(prPairs.count)
        for (worktreeId, count) in prPairs {
            countsByWorktreeId[worktreeId] = count
        }
        return countsByWorktreeId
    }

    static func isGitRepository(at url: URL) -> Bool {
        let dotGit = url.appending(path: ".git").path
        if FileManager.default.fileExists(atPath: dotGit) {
            return true
        }
        return runSync(command: "git", args: ["-C", url.path, "rev-parse", "--is-inside-work-tree"]) == "true"
    }

    private static func identity(for repo: RepoStatusInput) async -> RepoIdentityMetadata {
        let commonDir = await git(args: ["-C", repo.repoPath.path, "rev-parse", "--git-common-dir"])
            .flatMap { canonicalizeGitPath($0, relativeTo: repo.repoPath) }

        let upstreamRemote = await git(args: ["-C", repo.repoPath.path, "remote", "get-url", "upstream"])
        let originRemote = await git(args: ["-C", repo.repoPath.path, "remote", "get-url", "origin"])
        let remoteURL = upstreamRemote ?? originRemote

        let normalizedRemote = remoteURL.flatMap(normalizeRemoteURL)
        let remoteSlug = normalizedRemote.flatMap { extractRemoteSlug(from: $0) }

        if let normalizedRemote {
            return RepoIdentityMetadata(
                groupKey: "remote:\(normalizedRemote)",
                displayName: remoteSlug ?? repo.repoName,
                remoteFingerprint: normalizedRemote,
                remoteSlug: remoteSlug
            )
        }

        if let commonDir {
            return RepoIdentityMetadata(
                groupKey: "common:\(commonDir.lowercased())",
                displayName: repo.repoName,
                remoteFingerprint: nil,
                remoteSlug: nil
            )
        }

        return RepoIdentityMetadata(
            groupKey: "path:\(repo.repoPath.standardizedFileURL.path)",
            displayName: repo.repoName,
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
        let remoteURL = upstreamRemote ?? originRemote

        guard
            let remoteURL,
            let normalized = normalizeRemoteURL(remoteURL),
            normalized.hasPrefix("github.com/"),
            let remoteSlug = extractRemoteSlug(from: normalized)
        else {
            return nil
        }

        guard
            let output = await run(
                command: "gh",
                args: [
                    "pr", "list",
                    "--repo", remoteSlug,
                    "--head", worktree.branch,
                    "--state", "open",
                    "--json", "number",
                    "--limit", "50",
                ])
        else { return nil }

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

    private static func isCommandAvailable(_ command: String) async -> Bool {
        await run(command: "which", args: [command]) != nil
    }

    private static func git(args: [String]) async -> String? {
        await run(command: "git", args: args)
    }

    private static func run(command: String, args: [String]) async -> String? {
        do {
            let result = try await processExecutor.execute(
                command: command,
                args: args,
                cwd: nil,
                environment: nil
            )
            guard result.succeeded else { return nil }
            let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        } catch {
            return nil
        }
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
        if let path = env["PATH"] {
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(path)"
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
}
