import Foundation
import Testing

@testable import AgentStudio

@Suite
struct AgentStudioTraceIdentityStoreTests {
    @Test
    func worktreeIdAddsSafeRepoWorktreeHashAndBranchResource() async {
        let worktreeId = UUID()
        let repoId = UUID()
        let store = AgentStudioTraceIdentityStore()
        await store.update(
            AgentStudioTraceIdentitySnapshot(
                worktreeIdentitiesByWorktreeId: [
                    worktreeId: AgentStudioTraceWorktreeIdentity(
                        repoHash: "repo-hash",
                        worktreeHash: "worktree-hash",
                        branch: "feature/otel"
                    )
                ],
                paneWorktreeIdsByPaneId: [:]
            )
        )

        let resource = await store.resourceAttributes(
            for: [
                "agentstudio.repo.id": .string(repoId.uuidString),
                "agentstudio.worktree.id": .string(worktreeId.uuidString),
            ],
            baseResource: ["service.name": "AgentStudio"]
        )

        #expect(resource["service.name"] == "AgentStudio")
        #expect(resource["dev.repo.name"] == nil)
        #expect(resource["dev.repo.hash"] == "repo-hash")
        #expect(resource["dev.worktree.hash"] == "worktree-hash")
        #expect(resource["dev.branch.name"] == "feature/otel")
        #expect(resource["agentstudio.repo.id"] == nil)
        #expect(resource["agentstudio.worktree.id"] == nil)
    }

    @Test
    func paneIdCanResolveSafeWorktreeIdentity() async {
        let paneId = UUID()
        let worktreeId = UUID()
        let store = AgentStudioTraceIdentityStore()
        await store.update(
            AgentStudioTraceIdentitySnapshot(
                worktreeIdentitiesByWorktreeId: [
                    worktreeId: AgentStudioTraceWorktreeIdentity(
                        repoHash: "repo-hash",
                        worktreeHash: "worktree-hash",
                        branch: "main"
                    )
                ],
                paneWorktreeIdsByPaneId: [
                    paneId: worktreeId
                ]
            )
        )

        let resource = await store.resourceAttributes(
            for: [
                "agentstudio.pane.id": .string(paneId.uuidString)
            ],
            baseResource: [:]
        )

        #expect(resource["dev.repo.hash"] == "repo-hash")
        #expect(resource["dev.worktree.hash"] == "worktree-hash")
        #expect(resource["dev.branch.name"] == "main")
        #expect(resource["agentstudio.pane.id"] == nil)
    }

    @Test
    func startupRecordWithoutWorkspaceIdentityDoesNotInventWorktreeAttributes() async {
        let store = AgentStudioTraceIdentityStore()

        let resource = await store.resourceAttributes(
            for: [
                "agentstudio.trace.tag": .string("app.startup")
            ],
            baseResource: ["service.name": "AgentStudio"]
        )

        #expect(resource["service.name"] == "AgentStudio")
        #expect(resource["dev.repo.hash"] == nil)
        #expect(resource["dev.worktree.hash"] == nil)
        #expect(resource["dev.branch.name"] == nil)
    }
}
