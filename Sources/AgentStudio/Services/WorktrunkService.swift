import Foundation

/// Service for interacting with worktrunk (wt) CLI for worktree management
final class WorktrunkService {
    static let shared = WorktrunkService()

    private init() {}

    // MARK: - Installation Check

    /// Check if worktrunk (wt) is installed
    var isInstalled: Bool {
        let paths = [
            "/opt/homebrew/bin/wt",
            "/usr/local/bin/wt"
        ]
        return paths.contains { FileManager.default.fileExists(atPath: $0) }
    }

    /// Get the homebrew install command
    var installCommand: String {
        "brew install shravansunder/tap/worktrunk"
    }

    // MARK: - Worktree Discovery

    /// Discovers all worktrees for a repository using worktrunk
    func discoverWorktrees(for projectPath: URL) -> [Worktree] {
        let projectName = projectPath.lastPathComponent
            .replacingOccurrences(of: ".wt", with: "")
            .replacingOccurrences(of: ".git", with: "")

        // Try worktrunk first (preferred)
        if let worktrees = discoverWithWorktrunk(projectName: projectName, projectPath: projectPath) {
            return worktrees
        }

        // Fallback to raw git worktree command
        return discoverWithGit(projectPath: projectPath)
    }

    /// Discover worktrees using `wt list --format=json`
    private func discoverWithWorktrunk(projectName: String, projectPath: URL) -> [Worktree]? {
        let result = shell("wt", args: ["list", "--format=json"], cwd: projectPath)

        guard result.exitCode == 0, !result.output.isEmpty else {
            return nil
        }

        // Parse JSON output from worktrunk
        guard let data = result.output.data(using: .utf8),
              let entries = try? JSONDecoder().decode([WorktrunkEntry].self, from: data) else {
            return nil
        }

        // Filter entries belonging to this project
        let filtered = entries.filter { entry in
            entry.path.contains(projectName)
        }

        return filtered.map { entry in
            let pathURL = URL(fileURLWithPath: entry.path)
            let name = entry.branch.replacingOccurrences(of: "refs/heads/", with: "")
                .components(separatedBy: "/").last ?? entry.branch

            return Worktree(
                name: name,
                path: pathURL,
                branch: entry.branch
            )
        }
    }

    /// Fallback: discover worktrees using raw git command
    private func discoverWithGit(projectPath: URL) -> [Worktree] {
        let result = shell("git", args: ["-C", projectPath.path, "worktree", "list", "--porcelain"])

        guard result.exitCode == 0 else {
            return []
        }

        return parseGitWorktreeList(result.output)
    }

    /// Parse `git worktree list --porcelain` output
    func parseGitWorktreeList(_ output: String) -> [Worktree] {
        var worktrees: [Worktree] = []
        var currentPath: String?
        var currentBranch: String?

        for line in output.components(separatedBy: "\n") {
            if line.hasPrefix("worktree ") {
                // Save previous worktree if complete
                if let path = currentPath {
                    let pathURL = URL(fileURLWithPath: path)
                    let name = pathURL.lastPathComponent
                    let branch = currentBranch ?? name

                    worktrees.append(Worktree(
                        name: name,
                        path: pathURL,
                        branch: branch
                    ))
                }

                currentPath = String(line.dropFirst(9))
                currentBranch = nil
            } else if line.hasPrefix("branch ") {
                currentBranch = String(line.dropFirst(7))
                    .replacingOccurrences(of: "refs/heads/", with: "")
            }
        }

        // Don't forget the last one
        if let path = currentPath {
            let pathURL = URL(fileURLWithPath: path)
            let name = pathURL.lastPathComponent
            let branch = currentBranch ?? name

            worktrees.append(Worktree(
                name: name,
                path: pathURL,
                branch: branch
            ))
        }

        return worktrees
    }

    // MARK: - Worktree Management

    /// Create a new worktree using worktrunk
    func createWorktree(name: String, in projectPath: URL, baseBranch: String? = nil) -> Result<Worktree, WorktrunkError> {
        var args = ["switch", "-c", name]
        if let base = baseBranch {
            args.append(contentsOf: ["--base", base])
        }

        let result = shell("wt", args: args, cwd: projectPath)

        guard result.exitCode == 0 else {
            return .failure(.commandFailed(result.error.isEmpty ? result.output : result.error))
        }

        // Discover the newly created worktree
        let worktrees = discoverWorktrees(for: projectPath)
        if let newWorktree = worktrees.first(where: { $0.name == name || $0.branch.hasSuffix(name) }) {
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

    private func shell(_ command: String, args: [String], cwd: URL? = nil) -> (exitCode: Int, output: String, error: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + args

        if let cwd {
            process.currentDirectoryURL = cwd
        }

        // Inherit user's PATH to find wt and git
        var environment = ProcessInfo.processInfo.environment
        if let path = environment["PATH"] {
            environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(path)"
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
