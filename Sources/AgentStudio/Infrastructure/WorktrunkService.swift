import Foundation

/// Service for interacting with worktrunk (wt) CLI for worktree management
final class WorktrunkService: Sendable {
    static let shared = WorktrunkService()

    private init() {}

    // MARK: - Installation Check

    /// Check if worktrunk (wt) is installed
    var isInstalled: Bool {
        let paths = [
            "/opt/homebrew/bin/wt",
            "/usr/local/bin/wt",
        ]
        return paths.contains { FileManager.default.fileExists(atPath: $0) }
    }

    /// Get the homebrew install command
    var installCommand: String {
        "brew install worktrunk"
    }

    // MARK: - Worktree Discovery

    /// Discovers all worktrees for a repository using worktrunk
    func discoverWorktrees(for projectPath: URL, repoId: UUID) -> [Worktree] {
        let gitWorktrees = discoverWithGit(projectPath: projectPath, repoId: repoId)

        // Try worktrunk first (preferred)
        if let worktrees = discoverWithWorktrunk(projectPath: projectPath, repoId: repoId, gitWorktrees: gitWorktrees) {
            return worktrees
        }

        // Fallback to raw git worktree command
        return gitWorktrees
    }

    /// Discover worktrees using `wt list --format=json`
    private func discoverWithWorktrunk(projectPath: URL, repoId: UUID, gitWorktrees: [Worktree]) -> [Worktree]? {
        let result = shell("wt", args: ["list", "--format=json"], cwd: projectPath)

        guard result.exitCode == 0, !result.output.isEmpty else {
            return nil
        }

        // Parse JSON output from worktrunk
        guard let data = result.output.data(using: .utf8),
            let entries = try? JSONDecoder().decode([WorktrunkEntry].self, from: data)
        else {
            return nil
        }

        // `wt list` can include entries from many repos. Use git's authoritative
        // worktree paths for this repo to keep mapping deterministic.
        guard !gitWorktrees.isEmpty else { return nil }
        return mergeWorktrunkEntries(entries, orderedBy: gitWorktrees)
    }

    func mergeWorktrunkEntries(_ entries: [WorktrunkEntry], orderedBy gitWorktrees: [Worktree]) -> [Worktree] {
        guard !gitWorktrees.isEmpty else { return [] }
        guard let repoId = gitWorktrees.first?.repoId else { return [] }

        var entryByCanonicalPath: [String: WorktrunkEntry] = [:]
        entryByCanonicalPath.reserveCapacity(entries.count)
        for entry in entries {
            let canonicalPath = canonicalPathString(URL(fileURLWithPath: entry.path))
            entryByCanonicalPath[canonicalPath] = entry
        }

        var merged: [Worktree] = []
        merged.reserveCapacity(gitWorktrees.count)
        var matchedEntries = 0

        for (index, gitWorktree) in gitWorktrees.enumerated() {
            let canonicalGitPath = canonicalPathString(gitWorktree.path)
            guard let entry = entryByCanonicalPath[canonicalGitPath] else {
                merged.append(
                    Worktree(
                        repoId: repoId,
                        name: gitWorktree.name,
                        path: gitWorktree.path,
                        isMainWorktree: index == 0
                    ))
                continue
            }

            matchedEntries += 1
            let normalizedBranch = normalizeBranch(entry.branch)
            let branchName = normalizedBranch.isEmpty ? gitWorktree.name : normalizedBranch
            let worktreeName = branchName.components(separatedBy: "/").last ?? gitWorktree.name
            merged.append(
                Worktree(
                    repoId: repoId,
                    name: worktreeName.isEmpty ? gitWorktree.name : worktreeName,
                    path: URL(fileURLWithPath: entry.path),
                    isMainWorktree: index == 0
                ))
        }

        if matchedEntries == 0 {
            return gitWorktrees.enumerated().map { index, worktree in
                Worktree(
                    repoId: repoId,
                    name: worktree.name,
                    path: worktree.path,
                    isMainWorktree: index == 0
                )
            }
        }

        return merged
    }

    private func normalizeBranch(_ rawBranch: String) -> String {
        rawBranch
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "refs/heads/", with: "")
    }

    private func canonicalPathString(_ path: URL) -> String {
        path.standardizedFileURL.resolvingSymlinksInPath().path
    }

    /// Fallback: discover worktrees using raw git command
    private func discoverWithGit(projectPath: URL, repoId: UUID) -> [Worktree] {
        let result = shell("git", args: ["-C", projectPath.path, "worktree", "list", "--porcelain"])

        guard result.exitCode == 0 else {
            return []
        }

        return parseGitWorktreeList(result.output, repoId: repoId)
    }

    /// Parse `git worktree list --porcelain` output
    func parseGitWorktreeList(_ output: String, repoId: UUID) -> [Worktree] {
        var worktrees: [Worktree] = []
        var currentPath: String?

        for line in output.components(separatedBy: "\n") {
            if line.hasPrefix("worktree ") {
                // Save previous worktree if complete
                if let path = currentPath {
                    let pathURL = URL(fileURLWithPath: path)
                    let name = pathURL.lastPathComponent

                    worktrees.append(
                        Worktree(
                            repoId: repoId,
                            name: name,
                            path: pathURL,
                            isMainWorktree: worktrees.isEmpty
                        ))
                }

                currentPath = String(line.dropFirst(9))
            } else if line.hasPrefix("branch ") {
                // Branch data parsed but not stored on Worktree model;
                // enrichment pipeline provides it via GitProjector → bus → cache.
            }
        }

        // Don't forget the last one
        if let path = currentPath {
            let pathURL = URL(fileURLWithPath: path)
            let name = pathURL.lastPathComponent

            worktrees.append(
                Worktree(
                    repoId: repoId,
                    name: name,
                    path: pathURL,
                    isMainWorktree: worktrees.isEmpty
                ))
        }

        return worktrees
    }

    // MARK: - Worktree Management

    /// Create a new worktree using worktrunk
    func createWorktree(name: String, in projectPath: URL, repoId: UUID, baseBranch: String? = nil) -> Result<
        Worktree, WorktrunkError
    > {
        var args = ["switch", "-c", name]
        if let base = baseBranch {
            args.append(contentsOf: ["--base", base])
        }

        let result = shell("wt", args: args, cwd: projectPath)

        guard result.exitCode == 0 else {
            return .failure(.commandFailed(result.error.isEmpty ? result.output : result.error))
        }

        // Discover the newly created worktree
        let worktrees = discoverWorktrees(for: projectPath, repoId: repoId)
        if let newWorktree = worktrees.first(where: { $0.name == name }) {
            return .success(newWorktree)
        }

        return .failure(.worktreeNotFound)
    }

    /// Remove a worktree using worktrunk
    func removeWorktree(_ worktree: Worktree) -> Result<Void, WorktrunkError> {
        let result = shell("wt", args: ["remove", worktree.name], cwd: worktree.path.deletingLastPathComponent())

        guard result.exitCode == 0 else {
            return .failure(.commandFailed(result.error.isEmpty ? result.output : result.error))
        }

        return .success(())
    }

    // MARK: - Shell Helper

    private func shell(_ command: String, args: [String], cwd: URL? = nil) -> (
        exitCode: Int, output: String, error: String
    ) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + args

        if let cwd {
            process.currentDirectoryURL = cwd
        }

        // Inherit user's PATH to find wt and git
        var environment = ProcessInfo.processInfo.environment
        let inheritedPath = environment["PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let basePath = (inheritedPath?.isEmpty == false) ? inheritedPath! : "/usr/bin:/bin:/usr/sbin:/sbin"
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(basePath)"
        let inheritedHome = environment["HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if inheritedHome?.isEmpty != false {
            environment["HOME"] = FileManager.default.homeDirectoryForCurrentUser.path
        }
        process.environment = environment

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

            return (
                Int(process.terminationStatus),
                String(data: outputData, encoding: .utf8) ?? "",
                String(data: errorData, encoding: .utf8) ?? ""
            )
        } catch {
            return (-1, "", error.localizedDescription)
        }
    }
}

// MARK: - Worktrunk JSON Models

/// JSON entry from `wt list --format=json`
struct WorktrunkEntry: Codable {
    let path: String
    let branch: String
    let head: String?
    let status: String?

    init(path: String, branch: String, head: String?, status: String?) {
        self.path = path
        self.branch = branch
        self.head = head
        self.status = status
    }

    enum CodingKeys: String, CodingKey {
        case path
        case branch
        case head
        case status
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.path = try container.decode(String.self, forKey: .path)
        self.branch = try container.decode(String.self, forKey: .branch)
        self.head = try container.decodeIfPresent(String.self, forKey: .head)
        self.status = try container.decodeIfPresent(String.self, forKey: .status)
    }
}

// MARK: - Errors

enum WorktrunkError: Error, LocalizedError {
    case commandFailed(String)
    case worktreeNotFound
    case notAGitRepository

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            return "Command failed: \(message)"
        case .worktreeNotFound:
            return "Worktree not found after creation"
        case .notAGitRepository:
            return "Not a git repository"
        }
    }
}
