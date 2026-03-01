import Foundation

enum FilesystemTestGitRepo {
    static func create(named prefix: String) throws -> URL {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appending(path: "tmp")
            .appending(path: "filesystem-git-tests")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let repoURL = root.appending(path: "\(prefix)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)
        try runGit(at: repoURL, args: ["init"])
        try runGit(at: repoURL, args: ["config", "user.email", "luna-tests@example.com"])
        try runGit(at: repoURL, args: ["config", "user.name", "Luna Tests"])
        try runGit(at: repoURL, args: ["config", "commit.gpgsign", "false"])
        try runGit(at: repoURL, args: ["config", "tag.gpgsign", "false"])
        return repoURL
    }

    static func seedTrackedAndUntrackedChanges(at repoURL: URL) throws {
        let trackedFileURL = repoURL.appending(path: "tracked.txt")
        let untrackedFileURL = repoURL.appending(path: "untracked.txt")

        try "initial\n".write(to: trackedFileURL, atomically: true, encoding: .utf8)
        try runGit(at: repoURL, args: ["add", "tracked.txt"])
        try runGit(at: repoURL, args: ["commit", "-m", "Initial commit"])

        try "initial\nupdated\n".write(to: trackedFileURL, atomically: true, encoding: .utf8)
        try "new file\n".write(to: untrackedFileURL, atomically: true, encoding: .utf8)
    }

    static func destroy(_ repoURL: URL) {
        try? FileManager.default.removeItem(at: repoURL)
    }

    private static func runGit(at repoURL: URL, args: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", repoURL.path] + args

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let stderrData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrText = String(data: stderrData, encoding: .utf8) ?? ""
            throw NSError(
                domain: "FilesystemTestGitRepo",
                code: Int(process.terminationStatus),
                userInfo: [
                    NSLocalizedDescriptionKey: "git command failed (\(args.joined(separator: " "))): \(stderrText)"
                ]
            )
        }
    }
}
