import Foundation
import os

struct GitStatusSnapshot: Sendable {
    let summary: GitStatusSummary
    let branch: String?
}

protocol GitStatusProvider: Sendable {
    func status(for rootPath: URL) async -> GitStatusSnapshot?
}

struct ShellGitStatusProvider: GitStatusProvider {
    private static let logger = Logger(subsystem: "com.agentstudio", category: "FilesystemGitStatus")

    private let processExecutor: any ProcessExecutor

    init(processExecutor: any ProcessExecutor = DefaultProcessExecutor(timeout: 2)) {
        self.processExecutor = processExecutor
    }

    func status(for rootPath: URL) async -> GitStatusSnapshot? {
        await Self.computeStatus(rootPath: rootPath, processExecutor: processExecutor)
    }

    @concurrent
    nonisolated private static func computeStatus(
        rootPath: URL,
        processExecutor: any ProcessExecutor
    ) async -> GitStatusSnapshot? {
        do {
            let result = try await processExecutor.execute(
                command: "git",
                args: [
                    "-C", rootPath.path,
                    "status",
                    "--porcelain=v1",
                    "--branch",
                    "--untracked-files=normal",
                ],
                cwd: nil,
                environment: nil
            )

            guard result.succeeded else {
                return nil
            }

            let lines = result.stdout
                .split(whereSeparator: \.isNewline)
                .map(String.init)
            let branch = parseBranch(lines: lines)
            let summary = parseSummary(lines: lines)
            return GitStatusSnapshot(summary: summary, branch: branch)
        } catch {
            Self.logger.error(
                "git status execution failed for \(rootPath.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    nonisolated private static func parseSummary(lines: [String]) -> GitStatusSummary {
        var changed = 0
        var staged = 0
        var untracked = 0

        for line in lines {
            guard !line.hasPrefix("##") else { continue }
            guard line.count >= 2 else { continue }
            let first = line[line.startIndex]
            let second = line[line.index(after: line.startIndex)]

            if first == "?" && second == "?" {
                untracked += 1
                continue
            }

            if first != " " {
                staged += 1
            }
            if second != " " {
                changed += 1
            }
        }

        return GitStatusSummary(changed: changed, staged: staged, untracked: untracked)
    }

    nonisolated private static func parseBranch(lines: [String]) -> String? {
        guard let branchLine = lines.first(where: { $0.hasPrefix("## ") }) else {
            return nil
        }
        let raw = String(branchLine.dropFirst(3))
        guard !raw.hasPrefix("HEAD") else { return nil }

        if let branchRange = raw.range(of: "...") {
            return String(raw[..<branchRange.lowerBound])
        }
        if let suffixRange = raw.range(of: " ") {
            return String(raw[..<suffixRange.lowerBound])
        }
        return raw
    }
}

struct StubGitStatusProvider: GitStatusProvider {
    let handler: @Sendable (URL) async -> GitStatusSnapshot?

    init(handler: @escaping @Sendable (URL) async -> GitStatusSnapshot? = { _ in nil }) {
        self.handler = handler
    }

    func status(for rootPath: URL) async -> GitStatusSnapshot? {
        await handler(rootPath)
    }
}

extension GitStatusProvider where Self == StubGitStatusProvider {
    static func stub(
        _ handler: @escaping @Sendable (URL) async -> GitStatusSnapshot? = { _ in nil }
    ) -> StubGitStatusProvider {
        StubGitStatusProvider(handler: handler)
    }
}
