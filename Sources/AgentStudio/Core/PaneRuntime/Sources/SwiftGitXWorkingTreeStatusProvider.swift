import Foundation
import os

struct SwiftGitXRepositoryStatusSnapshot: Sendable, Equatable {
    let changed: Int
    let staged: Int
    let untracked: Int
    let linesAdded: Int
    let linesDeleted: Int
    let branch: String?
    let aheadCount: Int?
    let behindCount: Int?
    let hasUpstream: Bool?
    let originURL: String?
}

protocol SwiftGitXRepositoryStatusClient: Sendable {
    func status(rootPath: URL) async throws -> SwiftGitXRepositoryStatusSnapshot
}

struct SwiftGitXWorkingTreeStatusProvider: GitWorkingTreeStatusProvider {
    private static let logger = Logger(subsystem: "com.agentstudio", category: "SwiftGitXWorkingTreeStatusProvider")

    private let client: any SwiftGitXRepositoryStatusClient

    init(client: any SwiftGitXRepositoryStatusClient) {
        self.client = client
    }

    func status(for rootPath: URL) async -> GitWorkingTreeStatus? {
        do {
            let snapshot = try await client.status(rootPath: rootPath)
            let summary = GitWorkingTreeSummary(
                changed: snapshot.changed,
                staged: snapshot.staged,
                untracked: snapshot.untracked,
                linesAdded: snapshot.linesAdded,
                linesDeleted: snapshot.linesDeleted,
                aheadCount: snapshot.aheadCount,
                behindCount: snapshot.behindCount,
                hasUpstream: snapshot.hasUpstream
            )

            let originResolution: GitOriginResolution
            if let origin = snapshot.originURL?.trimmingCharacters(in: .whitespacesAndNewlines), !origin.isEmpty {
                originResolution = .resolved(origin)
            } else {
                originResolution = .confirmedAbsent
            }

            return GitWorkingTreeStatus(
                summary: summary,
                branch: snapshot.branch,
                originResolution: originResolution
            )
        } catch {
            Self.logger.error(
                "SwiftGitX status failed for \(rootPath.path, privacy: .public): \(String(describing: error), privacy: .public)"
            )
            return nil
        }
    }
}
