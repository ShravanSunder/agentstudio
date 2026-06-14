import AgentStudioGit
import Foundation
import os

typealias AgentStudioGitStatusReader =
    @Sendable (
        URL,
        AgentStudioGit.GitStatusOptions
    ) async throws -> AgentStudioGit.GitStatusSnapshot

struct AgentStudioGitWorkingTreeStatusProvider: GitWorkingTreeStatusProvider {
    private static let logger = Logger(subsystem: "com.agentstudio", category: "AgentStudioGitWorkingTree")

    private let statusReader: AgentStudioGitStatusReader
    private let timeout: Duration

    init(
        client: any AgentStudioGit.AgentStudioGitLocalClient = AgentStudioGit.LibGit2AgentStudioGitLocalClient(),
        timeout: Duration = AppPolicies.GitRefresh.defaultSDKReadTimeout
    ) {
        self.init(timeout: timeout) { worktreePath, options in
            try await client.status(for: worktreePath, options: options)
        }
    }

    init(
        timeout: Duration = AppPolicies.GitRefresh.defaultSDKReadTimeout,
        statusReader: @escaping AgentStudioGitStatusReader
    ) {
        self.statusReader = statusReader
        self.timeout = timeout
    }

    func status(for rootPath: URL) async -> GitWorkingTreeStatus? {
        await Self.computeStatus(rootPath: rootPath, timeout: timeout, statusReader: statusReader)
    }

    @concurrent
    nonisolated private static func computeStatus(
        rootPath: URL,
        timeout: Duration,
        statusReader: @escaping AgentStudioGitStatusReader
    ) async -> GitWorkingTreeStatus? {
        do {
            let snapshot = try await withTimeout(timeout) {
                try await statusReader(
                    rootPath,
                    AgentStudioGit.GitStatusOptions(includeIgnored: false, includeUntracked: true)
                )
            }
            return map(snapshot)
        } catch {
            logger.error(
                """
                AgentStudioGit status failed for \(rootPath.path, privacy: .public): \
                \(String(describing: error), privacy: .public)
                """
            )
            return nil
        }
    }

    nonisolated private static func withTimeout<ReturnValue: Sendable>(
        _ timeout: Duration,
        operation: @Sendable @escaping () async throws -> ReturnValue
    ) async throws -> ReturnValue {
        try await withThrowingTaskGroup(of: ReturnValue.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw AgentStudioGitSDKTimeoutError.timedOut
            }

            guard let result = try await group.next() else {
                throw AgentStudioGitSDKTimeoutError.timedOut
            }
            group.cancelAll()
            return result
        }
    }

    nonisolated private static func map(_ snapshot: AgentStudioGit.GitStatusSnapshot) -> GitWorkingTreeStatus {
        GitWorkingTreeStatus(
            summary: mapSummary(snapshot.summary, headKind: snapshot.head.kind),
            branch: mapBranch(snapshot.head),
            originResolution: mapOrigin(snapshot.originResolution)
        )
    }

    nonisolated private static func mapSummary(
        _ summary: AgentStudioGit.GitStatusSummary,
        headKind: AgentStudioGit.GitHeadKind
    ) -> GitWorkingTreeSummary {
        let syncCounts = mapSyncCounts(summary, headKind: headKind)
        return GitWorkingTreeSummary(
            changed: summary.unstagedFileCount,
            staged: summary.stagedFileCount,
            untracked: summary.untrackedFileCount,
            linesAdded: summary.linesAdded,
            linesDeleted: summary.linesDeleted,
            aheadCount: syncCounts.aheadCount,
            behindCount: syncCounts.behindCount,
            hasUpstream: syncCounts.hasUpstream
        )
    }

    nonisolated private static func mapSyncCounts(
        _ summary: AgentStudioGit.GitStatusSummary,
        headKind: AgentStudioGit.GitHeadKind
    ) -> (aheadCount: Int?, behindCount: Int?, hasUpstream: Bool?) {
        guard headKind == .branch else {
            return (aheadCount: nil, behindCount: nil, hasUpstream: nil)
        }
        guard summary.hasUpstream else {
            return (aheadCount: nil, behindCount: nil, hasUpstream: false)
        }
        if summary.aheadCount == 0, summary.behindCount == 0 {
            return (aheadCount: 0, behindCount: 0, hasUpstream: true)
        }
        return (
            aheadCount: summary.aheadCount > 0 ? summary.aheadCount : nil,
            behindCount: summary.behindCount > 0 ? summary.behindCount : nil,
            hasUpstream: true
        )
    }

    nonisolated private static func mapBranch(_ head: AgentStudioGit.GitHeadSnapshot) -> String? {
        guard head.kind == .branch else { return nil }
        return head.shortName
    }

    nonisolated private static func mapOrigin(
        _ originResolution: AgentStudioGit.GitOriginResolution
    ) -> GitOriginResolution {
        switch originResolution {
        case .awaitingResolution:
            .awaitingResolution
        case .confirmedAbsent:
            .confirmedAbsent
        case .resolved(let remote):
            .resolved(remote.rawURL)
        }
    }
}

private enum AgentStudioGitSDKTimeoutError: Error {
    case timedOut
}
