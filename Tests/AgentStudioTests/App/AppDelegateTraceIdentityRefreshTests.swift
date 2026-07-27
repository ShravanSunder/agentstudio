import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct AppDelegateTraceIdentityRefreshTests {
    @Test("App projection maps Core topology to primitive trace identity")
    func appProjectionMapsCoreTopologyToPrimitiveTraceIdentity() {
        let repoId = UUID()
        let worktreeId = UUID()
        let repoPath = URL(fileURLWithPath: "/tmp/trace-identity-repo")
        let worktreePath = repoPath.appending(path: "worktree")
        let repo = Repo(
            id: repoId,
            name: "Trace Identity Repo",
            repoPath: repoPath,
            worktrees: [
                Worktree(
                    id: worktreeId,
                    repoId: repoId,
                    name: "Trace Identity Worktree",
                    path: worktreePath
                )
            ]
        )

        let snapshot = AgentStudioTraceIdentitySnapshot.from(
            repos: [repo],
            panes: [],
            worktreeEnrichments: [
                worktreeId: WorktreeEnrichment(
                    worktreeId: worktreeId,
                    repoId: repoId,
                    branch: "  feature/trace-projection  "
                )
            ]
        )

        #expect(
            snapshot.worktreeIdentitiesByWorktreeId[worktreeId]
                == AgentStudioTraceWorktreeIdentity(
                    repoHash: repo.stableKey,
                    worktreeHash: repo.worktrees[0].stableKey,
                    branch: "feature/trace-projection"
                )
        )
        #expect(snapshot.paneWorktreeIdsByPaneId.isEmpty)
    }

    @Test("concurrent producer requests share one pre-capture refresh")
    func concurrentProducerRequestsShareOneFleetCapture() async {
        let traceRuntime = AgentStudioTraceRuntime.fromEnvironment([
            "AGENTSTUDIO_TRACE_TAGS": "off"
        ])
        let appDelegate = AppDelegate(
            traceRuntime: traceRuntime,
            startupTraceRecorder: AgentStudioStartupTraceRecorder(traceRuntime: traceRuntime)
        )
        appDelegate.atomStore = makeTestAtomRegistry()
        appDelegate.store = WorkspaceStore()
        let initialFleetCaptureCount = appDelegate.traceIdentityFleetCaptureCount

        appDelegate.requestTraceIdentityRefresh()
        appDelegate.requestTraceIdentityRefresh()
        await appDelegate.waitForTraceIdentityRefreshIdle()

        #expect(appDelegate.traceIdentityFleetCaptureCount == initialFleetCaptureCount + 1)
    }
}
