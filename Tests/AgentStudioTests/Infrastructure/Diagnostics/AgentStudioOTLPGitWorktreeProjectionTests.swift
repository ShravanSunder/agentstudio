import Foundation
import Testing

@testable import AgentStudio

@Suite
struct AgentStudioOTLPGitWorktreeProjectionTests {
    @Test
    func gitStatusProjectionKeepsScrubbedWorktreeHashAndDropsRawIdentity() {
        let worktreeID = UUID(uuidString: "C994D680-2BFD-4D60-9070-2BD76D3971EE")!
        let rawRootPath = "/Users/shravan/private/repo"
        let record = AgentStudioTraceRecord(
            timeUnixNano: 500,
            severityText: .info,
            body: "performance.git.status",
            traceID: nil,
            spanID: nil,
            parentSpanID: nil,
            resource: [
                "dev.repo.hash": "repo-hash",
                "dev.worktree.hash": "worktree-hash",
                "service.name": "AgentStudio",
            ],
            scope: .init(name: "agentstudio.performance", version: "0.1.0"),
            attributes: [
                "agentstudio.performance.git.status_scope": .string("full"),
                "agentstudio.performance.git.root_path": .string(rawRootPath),
                "agentstudio.worktree.id": .string(worktreeID.uuidString),
            ]
        )

        let projection = AgentStudioOTLPTraceProjection.project(record)
        let renderedProjection = projection.renderedForGitWorktreeAssertions()

        #expect(projection.resource["dev.worktree.hash"] == "worktree-hash")
        #expect(projection.attributes["dev.worktree.hash"] == .string("worktree-hash"))
        #expect(projection.attributes["agentstudio.worktree.id"] == nil)
        #expect(projection.attributes["agentstudio.performance.git.root_path"] == nil)
        #expect(!renderedProjection.contains(worktreeID.uuidString))
        #expect(!renderedProjection.contains(rawRootPath))
    }
}

extension AgentStudioOTLPProjectedLogRecord {
    fileprivate func renderedForGitWorktreeAssertions() -> String {
        [
            body,
            resource.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "),
            attributes.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "),
        ]
        .joined(separator: "\n")
    }
}
