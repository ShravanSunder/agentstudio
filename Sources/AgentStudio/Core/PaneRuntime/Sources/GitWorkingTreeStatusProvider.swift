import Foundation
import os

struct GitWorkingTreeStatus: Sendable, Equatable {
    let summary: GitWorkingTreeSummary
    let branch: String?
    let origin: String?
}

protocol GitWorkingTreeStatusProvider: Sendable {
    func status(for rootPath: URL) async -> GitWorkingTreeStatus?
}

struct ShellGitWorkingTreeStatusProvider: GitWorkingTreeStatusProvider {
    private static let logger = Logger(subsystem: "com.agentstudio", category: "FilesystemGitWorkingTree")

    private let processExecutor: any ProcessExecutor

    init(processExecutor: any ProcessExecutor = DefaultProcessExecutor(timeout: 2)) {
        self.processExecutor = processExecutor
    }

    func status(for rootPath: URL) async -> GitWorkingTreeStatus? {
        await Self.computeStatus(rootPath: rootPath, processExecutor: processExecutor)
    }

    @concurrent
    nonisolated private static func computeStatus(
        rootPath: URL,
        processExecutor: any ProcessExecutor
    ) async -> GitWorkingTreeStatus? {
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
                let stderrPreview = result.stderr.isEmpty ? "<empty>" : result.stderr
                let stdoutPreview = result.stdout.isEmpty ? "<empty>" : result.stdout
                Self.logger.error(
                    """
                    git status failed for \(rootPath.path, privacy: .public) \
                    exitCode=\(result.exitCode, privacy: .public) \
                    stderr=\(stderrPreview, privacy: .public) \
                    stdout=\(stdoutPreview, privacy: .public)
                    """
                )
                return nil
            }

            let lines = result.stdout
                .split(whereSeparator: \.isNewline)
                .map(String.init)
            let branch = parseBranch(lines: lines)
            let summary = parseSummary(lines: lines)
            let origin = await parseOrigin(rootPath: rootPath, processExecutor: processExecutor)
            return GitWorkingTreeStatus(summary: summary, branch: branch, origin: origin)
        } catch let processError as ProcessError {
            switch processError {
            case .timedOut(_, let seconds):
                Self.logger.error(
                    "git status timed out for \(rootPath.path, privacy: .public) after \(seconds, privacy: .public)s"
                )
            }
            return nil
        } catch {
            Self.logger.error(
                "git status launch/processing failed for \(rootPath.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    nonisolated private static func parseSummary(lines: [String]) -> GitWorkingTreeSummary {
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

        return GitWorkingTreeSummary(changed: changed, staged: staged, untracked: untracked)
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

    @concurrent
    nonisolated private static func parseOrigin(
        rootPath: URL,
        processExecutor: any ProcessExecutor
    ) async -> String? {
        do {
            let result = try await processExecutor.execute(
                command: "git",
                args: [
                    "-C", rootPath.path,
                    "config",
                    "--get",
                    "remote.origin.url",
                ],
                cwd: nil,
                environment: nil
            )

            guard result.succeeded else {
                return nil
            }

            let origin = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            return origin.isEmpty ? nil : origin
        } catch {
            return nil
        }
    }
}

struct StubGitWorkingTreeStatusProvider: GitWorkingTreeStatusProvider {
    let handler: @Sendable (URL) async -> GitWorkingTreeStatus?

    init(handler: @escaping @Sendable (URL) async -> GitWorkingTreeStatus? = { _ in nil }) {
        self.handler = handler
    }

    func status(for rootPath: URL) async -> GitWorkingTreeStatus? {
        await handler(rootPath)
    }
}

extension GitWorkingTreeStatusProvider where Self == StubGitWorkingTreeStatusProvider {
    static func stub(
        _ handler: @escaping @Sendable (URL) async -> GitWorkingTreeStatus? = { _ in nil }
    ) -> StubGitWorkingTreeStatusProvider {
        StubGitWorkingTreeStatusProvider(handler: handler)
    }
}
