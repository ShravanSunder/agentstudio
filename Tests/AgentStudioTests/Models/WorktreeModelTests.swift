import XCTest
@testable import AgentStudio

final class WorktreeModelTests: XCTestCase {

    // MARK: - WorktreeStatus displayName

    func test_worktreeStatus_displayName_idle() {
        // Assert
        XCTAssertEqual(WorktreeStatus.idle.displayName, "Idle")
    }

    func test_worktreeStatus_displayName_running() {
        // Assert
        XCTAssertEqual(WorktreeStatus.running.displayName, "Running")
    }

    func test_worktreeStatus_displayName_pendingReview() {
        // Assert
        XCTAssertEqual(WorktreeStatus.pendingReview.displayName, "Pending Review")
    }

    func test_worktreeStatus_displayName_error() {
        // Assert
        XCTAssertEqual(WorktreeStatus.error.displayName, "Error")
    }

    func test_worktreeStatus_caseIterable_hasFourCases() {
        // Assert
        XCTAssertEqual(WorktreeStatus.allCases.count, 4)
    }

    // MARK: - AgentType Properties

    func test_agentType_displayName_claude() {
        // Assert
        XCTAssertEqual(AgentType.claude.displayName, "Claude Code")
    }

    func test_agentType_displayName_allCasesNonEmpty() {
        // Assert
        for agent in AgentType.allCases {
            XCTAssertFalse(agent.displayName.isEmpty, "\(agent) displayName should not be empty")
        }
    }

    func test_agentType_shortName_allCasesNonEmpty() {
        // Assert
        for agent in AgentType.allCases {
            XCTAssertFalse(agent.shortName.isEmpty, "\(agent) shortName should not be empty")
        }
    }

    func test_agentType_command_customIsEmpty() {
        // Assert
        XCTAssertEqual(AgentType.custom.command, "")
    }

    func test_agentType_command_nonCustomAreNonEmpty() {
        // Assert
        for agent in AgentType.allCases where agent != .custom {
            XCTAssertFalse(agent.command.isEmpty, "\(agent) command should not be empty")
        }
    }

    func test_agentType_caseIterable_hasFiveCases() {
        // Assert
        XCTAssertEqual(AgentType.allCases.count, 5)
    }

    // MARK: - Worktree Codable

    func test_worktree_codable_roundTrip() throws {
        // Arrange
        let original = makeWorktree(
            name: "feature-x",
            branch: "feature-x",
            agent: .claude,
            status: .running,
            isOpen: true
        )

        // Act
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Worktree.self, from: data)

        // Assert
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.branch, original.branch)
        XCTAssertEqual(decoded.agent, .claude)
        XCTAssertEqual(decoded.status, .running)
        XCTAssertEqual(decoded.isOpen, true)
    }

    func test_worktree_codable_nilOptionals_roundTrip() throws {
        // Arrange
        let original = makeWorktree(agent: nil, lastOpened: nil)

        // Act
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Worktree.self, from: data)

        // Assert
        XCTAssertNil(decoded.agent)
        XCTAssertNil(decoded.lastOpened)
    }

    // MARK: - Worktree Hashable

    func test_worktree_hashable_differentFieldsNotEqual() {
        // Arrange
        let id = UUID()
        let wt1 = makeWorktree(id: id, name: "a")
        let wt2 = makeWorktree(id: id, name: "b")

        // Assert
        XCTAssertNotEqual(wt1, wt2)
    }

    // MARK: - Worktree Init Defaults

    func test_worktree_init_defaults() {
        // Act
        let wt = Worktree(name: "test", path: URL(fileURLWithPath: "/tmp/test"), branch: "main")

        // Assert
        XCTAssertNil(wt.agent)
        XCTAssertEqual(wt.status, .idle)
        XCTAssertFalse(wt.isOpen)
        XCTAssertNil(wt.lastOpened)
    }
}
