import Foundation

struct BridgeWorktreeStatusPatchBuildRequest: Sendable {
    let source: BridgeWorktreeFileSurfaceSourceIdentity
    let streamId: String
    let sequence: Int
    let status: GitWorkingTreeStatus
}

struct BridgeWorktreeFileChangesetClassificationRequest: Sendable {
    let source: BridgeWorktreeFileSurfaceSourceIdentity
    let streamId: String
    let firstSequence: Int
    let changeset: FileChangeset
    let latestDescriptorsByPath: [String: BridgeWorktreeFileDescriptor]
}

struct BridgeWorktreeStatusInvalidationBuildRequest: Sendable {
    let source: BridgeWorktreeFileSurfaceSourceIdentity
    let streamId: String
    let sequence: Int
    let changeset: FileChangeset
}

enum BridgeWorktreeFileSurfaceClassifier {
    static func statusPatchFrame(
        request: BridgeWorktreeStatusPatchBuildRequest
    ) -> BridgeWorktreeStatusPatchFrame {
        BridgeWorktreeStatusPatchFrame(
            streamId: request.streamId,
            sequence: request.sequence,
            source: request.source,
            patch: BridgeWorktreeStatusPatch(
                counts: BridgeWorktreeStatusPatchCounts(
                    staged: request.status.summary.staged,
                    unstaged: request.status.summary.changed,
                    untracked: request.status.summary.untracked
                ),
                branchFacts: BridgeWorktreeStatusPatchBranchFacts(
                    branchName: request.status.branch,
                    ahead: request.status.summary.aheadCount,
                    behind: request.status.summary.behindCount
                )
            )
        )
    }

    static func fileInvalidationFrames(
        request: BridgeWorktreeFileChangesetClassificationRequest
    ) -> [BridgeWorktreeFileInvalidatedFrame] {
        request.changeset.paths
            .filter { !isGitInternalPath($0) }
            .enumerated()
            .map { offset, path in
                let latestDescriptor = request.latestDescriptorsByPath[path]
                return BridgeWorktreeFileSurfaceFrameBuilder.fileInvalidated(
                    request: BridgeWorktreeFileInvalidationBuildRequest(
                        source: request.source,
                        streamId: request.streamId,
                        sequence: request.firstSequence + offset,
                        path: path,
                        fileId: latestDescriptor?.fileId,
                        reason: .contentChanged,
                        contentHandleIds: latestDescriptor.map { [$0.contentHandle] },
                        latestDescriptor: latestDescriptor
                    )
                )
            }
    }

    static func statusInvalidatedFrame(
        request: BridgeWorktreeStatusInvalidationBuildRequest
    ) -> BridgeWorktreeStatusPatchFrame {
        BridgeWorktreeStatusPatchFrame(
            streamId: request.streamId,
            sequence: request.sequence,
            source: request.source,
            patch: BridgeWorktreeStatusPatch(
                status: "gitStatusChanged",
                counts: BridgeWorktreeStatusPatchCounts(
                    staged: nil,
                    unstaged: nil,
                    untracked: nil
                ),
                branchFacts: BridgeWorktreeStatusPatchBranchFacts(
                    branchName: nil,
                    ahead: nil,
                    behind: nil
                )
            )
        )
    }

    private static func isGitInternalPath(_ path: String) -> Bool {
        path == ".git" || path.hasPrefix(".git/")
    }
}
