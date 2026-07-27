struct WorktrunkService {
    func createWorktree(executor: any ProcessExecutor) async throws {
        _ = try await executor.execute(
            command: "wt",
            args: ["switch", "--create", "feature"],
            cwd: nil,
            environment: nil
        )
    }
}

func badGitCLIFallback(executor: any ProcessExecutor) async throws {
    _ = try await executor.execute(
        command: "git",
        args: ["worktree", "add", "feature"],
        cwd: nil,
        environment: nil
    )
}

enum BadStartupPhase {
    case checkWorktrunkDependency
}
