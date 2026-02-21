import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
final class WorktreeModelTests {

    // MARK: - WorktreeStatus displayName

    @Test

    func test_worktreeStatus_displayName_idle() {
        // Assert
        #expect(WorktreeStatus.idle.displayName == "Idle")
    }

    @Test

    func test_worktreeStatus_displayName_running() {
        // Assert
        #expect(WorktreeStatus.running.displayName == "Running")
    }

    @Test

    func test_worktreeStatus_displayName_pendingReview() {
        // Assert
        #expect(WorktreeStatus.pendingReview.displayName == "Pending Review")
    }

    @Test

    func test_worktreeStatus_displayName_error() {
        // Assert
        #expect(WorktreeStatus.error.displayName == "Error")
    }

    @Test

    func test_worktreeStatus_caseIterable_hasFourCases() {
        // Assert
        #expect(WorktreeStatus.allCases.count == 4)
    }

    // MARK: - AgentType Properties

    @Test

    func test_agentType_displayName_claude() {
        // Assert
        #expect(AgentType.claude.displayName == "Claude Code")
    }

    @Test

    func test_agentType_displayName_allCasesNonEmpty() {
        // Assert
        for agent in AgentType.allCases {
            #expect(!(agent.displayName.isEmpty))
        }
    }

    @Test

    func test_agentType_shortName_allCasesNonEmpty() {
        // Assert
        for agent in AgentType.allCases {
            #expect(!(agent.shortName.isEmpty))
        }
    }

    @Test

    func test_agentType_command_customIsEmpty() {
        // Assert
        #expect(AgentType.custom.command.isEmpty)
    }

    @Test

    func test_agentType_command_nonCustomAreNonEmpty() {
        // Assert
        for agent in AgentType.allCases where agent != .custom {
            #expect(!(agent.command.isEmpty))
        }
    }

    @Test

    func test_agentType_caseIterable_hasFiveCases() {
        // Assert
        #expect(AgentType.allCases.count == 5)
    }

    // MARK: - Worktree Codable

    @Test

    func test_worktree_codable_roundTrip() throws {
        // Arrange
        let original = makeWorktree(
            name: "feature-x",
            branch: "feature-x",
            agent: .claude,
            status: .running
        )

        // Act
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Worktree.self, from: data)

        // Assert
        #expect(decoded.id == original.id)
        #expect(decoded.name == original.name)
        #expect(decoded.branch == original.branch)
        #expect(decoded.agent == .claude)
        #expect(decoded.status == .running)
    }

    @Test

    func test_worktree_codable_nilOptionals_roundTrip() throws {
        // Arrange
        let original = makeWorktree(agent: nil)

        // Act
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Worktree.self, from: data)

        // Assert
        #expect((decoded.agent) == nil)
    }

    // MARK: - Worktree Hashable

    @Test

    func test_worktree_hashable_differentFieldsNotEqual() {
        // Arrange
        let id = UUID()
        let wt1 = makeWorktree(id: id, name: "a")
        let wt2 = makeWorktree(id: id, name: "b")

        // Assert
        #expect(wt1 != wt2)
    }

    // MARK: - Worktree Init Defaults

    @Test

    func test_worktree_init_defaults() {
        // Act
        let wt = Worktree(name: "test", path: URL(fileURLWithPath: "/tmp/test"), branch: "main")

        // Assert
        #expect((wt.agent) == nil)
        #expect(wt.status == .idle)
    }
}
