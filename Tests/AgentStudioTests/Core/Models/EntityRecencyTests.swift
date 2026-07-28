import Foundation
import Testing

@testable import AgentStudio

@Suite("EntityRecency")
struct EntityRecencyTests {
    @Test("application recency accepts only opened repository and worktree identities")
    func applicationRecencyAcceptsOpenedEntities() throws {
        let timestamp = Date(timeIntervalSince1970: 100)
        let repositoryRecency = try ApplicationEntityRecency(
            entity: .repository(repositoryStableKey: "0123456789abcdef"),
            interaction: .opened,
            lastInteractedAt: timestamp
        )
        let worktreeRecency = try ApplicationEntityRecency(
            entity: .worktree(worktreeStableKey: "fedcba9876543210"),
            interaction: .opened,
            lastInteractedAt: timestamp
        )

        #expect(repositoryRecency.entity == .repository(repositoryStableKey: "0123456789abcdef"))
        #expect(worktreeRecency.entity == .worktree(worktreeStableKey: "fedcba9876543210"))
        #expect(repositoryRecency.lastInteractedAt == timestamp)
        #expect(worktreeRecency.interaction == .opened)
    }

    @Test("workspace recency captures the pane and workspace identities")
    func workspaceRecencyCapturesPaneAndWorkspaceIdentities() throws {
        let workspaceID = UUID(uuidString: "019be3be-7c00-7000-8000-000000000001")!
        let paneID = UUID(uuidString: "019be3be-7c00-7000-8000-000000000002")!
        let timestamp = Date(timeIntervalSince1970: 200)

        let paneRecency = try WorkspaceEntityRecency(
            workspaceID: workspaceID,
            entity: .pane(paneID: paneID),
            interaction: .focused,
            lastInteractedAt: timestamp
        )

        #expect(paneRecency.workspaceID == workspaceID)
        #expect(paneRecency.entity == .pane(paneID: paneID))
        #expect(paneRecency.interaction == .focused)
        #expect(paneRecency.lastInteractedAt == timestamp)
    }

    @Test(
        "recency validation rejects malformed stable keys, lifecycle mismatches, and non-finite timestamps",
        arguments: [
            "",
            "ABCDEF0123456789",
            "0123456789abcde",
            "0123456789abcdef0",
            "0123456789abcdeg",
        ]
    )
    func recencyValidationRejectsMalformedStableKeys(repositoryStableKey: String) {
        #expect(throws: EntityRecencyValidationError.self) {
            _ = try ApplicationEntityRecency(
                entity: .repository(repositoryStableKey: repositoryStableKey),
                interaction: .opened,
                lastInteractedAt: Date(timeIntervalSince1970: 100)
            )
        }

        #expect(throws: EntityRecencyValidationError.self) {
            _ = try ApplicationEntityRecency(
                entity: .worktree(worktreeStableKey: "0123456789abcdef"),
                interaction: .focused,
                lastInteractedAt: Date(timeIntervalSince1970: 100)
            )
        }

        #expect(throws: EntityRecencyValidationError.self) {
            _ = try WorkspaceEntityRecency(
                workspaceID: UUID(),
                entity: .pane(paneID: UUID()),
                interaction: .opened,
                lastInteractedAt: Date(timeIntervalSince1970: .infinity)
            )
        }
    }
}
