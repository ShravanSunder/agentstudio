import Foundation
import os

enum GitOriginResolution: Sendable, Equatable {
    case awaitingResolution
    case confirmedAbsent
    case resolved(String)
}

struct GitWorkingTreeStatus: Sendable, Equatable {
    let summary: GitWorkingTreeSummary
    let branch: String?
    let originResolution: GitOriginResolution

    init(
        summary: GitWorkingTreeSummary,
        branch: String?,
        originResolution: GitOriginResolution
    ) {
        self.summary = summary
        self.branch = branch
        self.originResolution = originResolution
    }

    init(
        summary: GitWorkingTreeSummary,
        branch: String?,
        origin: String?
    ) {
        self.init(
            summary: summary,
            branch: branch,
            originResolution: origin.map(GitOriginResolution.resolved) ?? .confirmedAbsent
        )
    }

    var origin: String? {
        switch originResolution {
        case .resolved(let origin):
            origin
        case .awaitingResolution, .confirmedAbsent:
            nil
        }
    }
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
            let branchDetails = parseBranchDetails(lines: lines)
            let branch = branchDetails.branch
            let (linesAdded, linesDeleted) = await parseLineDiffCounts(
                rootPath: rootPath,
                processExecutor: processExecutor
            )
            let summary = parseSummary(
                lines: lines,
                linesAdded: linesAdded,
                linesDeleted: linesDeleted,
                aheadCount: branchDetails.aheadCount,
                behindCount: branchDetails.behindCount,
                hasUpstream: branchDetails.hasUpstream
            )
            let originResolution = await parseOrigin(rootPath: rootPath, processExecutor: processExecutor)
            return GitWorkingTreeStatus(
                summary: summary,
                branch: branch,
                originResolution: originResolution
            )
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

    nonisolated private static func parseSummary(
        lines: [String],
        linesAdded: Int,
        linesDeleted: Int,
        aheadCount: Int?,
        behindCount: Int?,
        hasUpstream: Bool?
    ) -> GitWorkingTreeSummary {
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

        return GitWorkingTreeSummary(
            changed: changed,
            staged: staged,
            untracked: untracked,
            linesAdded: linesAdded,
            linesDeleted: linesDeleted,
            aheadCount: aheadCount,
            behindCount: behindCount,
            hasUpstream: hasUpstream
        )
    }

    private struct BranchDetails {
        let branch: String?
        let aheadCount: Int?
        let behindCount: Int?
        let hasUpstream: Bool?
    }

    nonisolated private static func parseBranchDetails(lines: [String]) -> BranchDetails {
        guard let branchLine = lines.first(where: { $0.hasPrefix("## ") }) else {
            return BranchDetails(branch: nil, aheadCount: nil, behindCount: nil, hasUpstream: nil)
        }
        let raw = String(branchLine.dropFirst(3))
        guard !raw.hasPrefix("HEAD") else {
            return BranchDetails(branch: nil, aheadCount: nil, behindCount: nil, hasUpstream: nil)
        }

        let hasUpstream = raw.contains("...")
        var aheadCount: Int?
        var behindCount: Int?
        if let bracketStart = raw.firstIndex(of: "["),
            let bracketEnd = raw[bracketStart...].firstIndex(of: "]"),
            bracketEnd > bracketStart
        {
            let syncPayload = String(raw[raw.index(after: bracketStart)..<bracketEnd])
            aheadCount = captureFirstInt(in: syncPayload, pattern: #"ahead (\d+)"#)
            behindCount = captureFirstInt(in: syncPayload, pattern: #"behind (\d+)"#)
            if aheadCount == nil && behindCount == nil && hasUpstream {
                aheadCount = 0
                behindCount = 0
            }
        } else if hasUpstream {
            aheadCount = 0
            behindCount = 0
        }

        let branch: String
        if let branchRange = raw.range(of: "...") {
            branch = String(raw[..<branchRange.lowerBound])
            return BranchDetails(
                branch: branch,
                aheadCount: aheadCount,
                behindCount: behindCount,
                hasUpstream: hasUpstream
            )
        }
        if let suffixRange = raw.range(of: " ") {
            branch = String(raw[..<suffixRange.lowerBound])
            return BranchDetails(
                branch: branch,
                aheadCount: aheadCount,
                behindCount: behindCount,
                hasUpstream: hasUpstream
            )
        }
        branch = raw
        return BranchDetails(
            branch: branch,
            aheadCount: aheadCount,
            behindCount: behindCount,
            hasUpstream: hasUpstream
        )
    }

    @concurrent
    nonisolated private static func parseLineDiffCounts(
        rootPath: URL,
        processExecutor: any ProcessExecutor
    ) async -> (Int, Int) {
        do {
            let result = try await processExecutor.execute(
                command: "git",
                args: [
                    "-C", rootPath.path,
                    "diff",
                    "--shortstat",
                    "HEAD",
                    "--",
                ],
                cwd: nil,
                environment: nil
            )
            guard result.succeeded else {
                let stderrPreview = result.stderr.isEmpty ? "<empty>" : result.stderr
                let stdoutPreview = result.stdout.isEmpty ? "<empty>" : result.stdout
                Self.logger.debug(
                    """
                    git diff --shortstat failed for \(rootPath.path, privacy: .public) \
                    exitCode=\(result.exitCode, privacy: .public) \
                    stderr=\(stderrPreview, privacy: .public) \
                    stdout=\(stdoutPreview, privacy: .public)
                    """
                )
                return (0, 0)
            }
            let shortstat = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !shortstat.isEmpty else { return (0, 0) }
            let added = captureFirstInt(in: shortstat, pattern: #"(\d+) insertions?\(\+\)"#) ?? 0
            let deleted = captureFirstInt(in: shortstat, pattern: #"(\d+) deletions?\(-\)"#) ?? 0
            return (added, deleted)
        } catch {
            Self.logger.debug(
                "git diff --shortstat failed for \(rootPath.path, privacy: .public): \(String(describing: error), privacy: .public)"
            )
            return (0, 0)
        }
    }

    nonisolated private static func captureFirstInt(in text: String, pattern: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else { return nil }
        guard match.numberOfRanges > 1 else { return nil }
        let valueRange = match.range(at: 1)
        guard let swiftRange = Range(valueRange, in: text) else { return nil }
        return Int(text[swiftRange])
    }

    @concurrent
    nonisolated private static func parseOrigin(
        rootPath: URL,
        processExecutor: any ProcessExecutor
    ) async -> GitOriginResolution {
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
                // git config exits 1 when key is missing (expected: no origin remote configured)
                // or when config lookup fails; keep both observable for diagnostics.
                if result.exitCode == 1 {
                    let stderrPreview = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !stderrPreview.isEmpty {
                        Self.logger.debug(
                            "git origin lookup returned exit 1 for \(rootPath.path, privacy: .public): \(stderrPreview, privacy: .public)"
                        )
                    }
                } else {
                    let stderrPreview = result.stderr.isEmpty ? "<empty>" : result.stderr
                    let stdoutPreview = result.stdout.isEmpty ? "<empty>" : result.stdout
                    Self.logger.warning(
                        """
                        git config --get remote.origin.url failed for \(rootPath.path, privacy: .public) \
                        exitCode=\(result.exitCode, privacy: .public) \
                        stderr=\(stderrPreview, privacy: .public) \
                        stdout=\(stdoutPreview, privacy: .public)
                        """
                    )
                }
                return .confirmedAbsent
            }

            let origin = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            return origin.isEmpty ? .confirmedAbsent : .resolved(origin)
        } catch {
            Self.logger.warning(
                "git origin lookup failed for \(rootPath.path, privacy: .public): \(String(describing: error), privacy: .public)"
            )
            return .awaitingResolution
        }
    }
}
