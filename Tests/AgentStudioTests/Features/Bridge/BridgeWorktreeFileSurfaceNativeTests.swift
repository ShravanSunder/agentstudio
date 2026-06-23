import Foundation
import Testing

@testable import AgentStudio

struct BridgeWorktreeFileSurfaceNativeTests {
    @Test("native provider maps git status into worktree status patch frame")
    func nativeProviderMapsGitStatusIntoWorktreeStatusPatchFrame() throws {
        let sourceIdentity = makeSourceIdentity()
        let status = GitWorkingTreeStatus(
            summary: GitWorkingTreeSummary(
                changed: 4,
                staged: 2,
                untracked: 3,
                aheadCount: 5,
                behindCount: 1
            ),
            branch: "feature/native-provider",
            origin: "git@example.com:repo/project.git"
        )

        let frame = BridgeWorktreeFileSurfaceClassifier.statusPatchFrame(
            request: BridgeWorktreeStatusPatchBuildRequest(
                source: sourceIdentity,
                streamId: "worktree:pane-1",
                sequence: 8,
                status: status
            )
        )

        #expect(frame.kind == "delta")
        #expect(frame.frameKind == "worktree.statusPatch")
        #expect(frame.source == sourceIdentity)
        #expect(frame.patch.staged == 2)
        #expect(frame.patch.unstaged == 4)
        #expect(frame.patch.untracked == 3)
        #expect(frame.patch.branchName == "feature/native-provider")
        #expect(frame.patch.ahead == 5)
        #expect(frame.patch.behind == 1)
    }

    @Test("native provider classifies file changes into invalidations")
    func nativeProviderClassifiesFileChangesIntoInvalidations() throws {
        let sourceIdentity = makeSourceIdentity()
        let changeset = FileChangeset(
            worktreeId: UUID(uuidString: "00000000-0000-0000-0000-000000000401")!,
            rootPath: URL(fileURLWithPath: "/tmp/repo"),
            paths: ["Sources/App/View.swift", ".git/index", "README.md"],
            containsGitInternalChanges: true,
            timestamp: .now,
            batchSeq: 9
        )

        let frames = BridgeWorktreeFileSurfaceClassifier.fileInvalidationFrames(
            request: BridgeWorktreeFileChangesetClassificationRequest(
                source: sourceIdentity,
                streamId: "worktree:pane-1",
                firstSequence: 9,
                changeset: changeset
            )
        )

        #expect(frames.map(\.sequence) == [9, 10])
        #expect(frames.map(\.invalidation.path) == ["Sources/App/View.swift", "README.md"])
        #expect(frames.allSatisfy { $0.invalidation.reason == .contentChanged })
        #expect(frames.allSatisfy { $0.source == sourceIdentity })
    }

    @Test("native provider classifies git-internal-only changes as status invalidation")
    func nativeProviderClassifiesGitInternalOnlyChangesAsStatusInvalidation() throws {
        let sourceIdentity = makeSourceIdentity()
        let changeset = FileChangeset(
            worktreeId: UUID(uuidString: "00000000-0000-0000-0000-000000000401")!,
            rootPath: URL(fileURLWithPath: "/tmp/repo"),
            paths: [".git/index"],
            containsGitInternalChanges: true,
            timestamp: .now,
            batchSeq: 10
        )

        let frames = BridgeWorktreeFileSurfaceClassifier.fileInvalidationFrames(
            request: BridgeWorktreeFileChangesetClassificationRequest(
                source: sourceIdentity,
                streamId: "worktree:pane-1",
                firstSequence: 10,
                changeset: changeset
            )
        )

        #expect(frames.isEmpty)

        let statusFrame = BridgeWorktreeFileSurfaceClassifier.statusInvalidatedFrame(
            request: BridgeWorktreeStatusInvalidationBuildRequest(
                source: sourceIdentity,
                streamId: "worktree:pane-1",
                sequence: 10,
                changeset: changeset
            )
        )

        #expect(statusFrame.patch.path == nil)
        #expect(statusFrame.patch.status == "gitStatusChanged")
    }

    @Test("native provider boundary does not expose review package lineage")
    func nativeProviderBoundaryDoesNotExposeReviewPackageLineage() throws {
        let snapshot = BridgeWorktreeFileSurfaceFrameBuilder.snapshot(
            request: BridgeWorktreeFileSnapshotBuildRequest(
                paneId: "pane-1",
                source: makeSourceIdentity(),
                requestSelector: nil,
                streamId: "worktree:pane-1",
                sequence: 0,
                treePathCount: 10,
                treeEstimatedTotalHeightPixels: nil,
                treeWindowStartIndex: 0,
                treeWindowRowCount: 10,
                treeRowHeightPixels: 22,
                includeStatusDescriptor: true
            )
        )
        let encoded = String(data: try JSONEncoder().encode(snapshot), encoding: .utf8) ?? ""

        #expect(encoded.contains("BridgeReviewPackage") == false)
        #expect(encoded.contains("review-package") == false)
        #expect(encoded.contains("packageId") == false)
        #expect(encoded.contains("worktree-file"))
    }

    private func makeSourceIdentity() -> BridgeWorktreeFileSurfaceSourceIdentity {
        BridgeWorktreeFileSurfaceSourceIdentity(
            sourceId: "worktree-source-1",
            repoId: "repo-1",
            worktreeId: "worktree-1",
            subscriptionGeneration: 3,
            sourceCursor: "cursor-3",
            rootRevisionToken: "root-token-1"
        )
    }
}
