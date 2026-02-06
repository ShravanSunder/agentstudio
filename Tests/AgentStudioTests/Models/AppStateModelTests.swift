import XCTest
import CoreGraphics
@testable import AgentStudio

final class AppStateModelTests: XCTestCase {

    // MARK: - AppState Init Defaults

    func test_appState_init_defaults() {
        // Act
        let state = AppState()

        // Assert
        XCTAssertTrue(state.projects.isEmpty)
        XCTAssertTrue(state.openTabs.isEmpty)
        XCTAssertNil(state.activeTabId)
        XCTAssertEqual(state.sidebarWidth, 250)
        XCTAssertNil(state.windowFrame)
    }

    // MARK: - AppState Codable

    func test_appState_codable_empty_roundTrip() throws {
        // Arrange
        let original = AppState()

        // Act
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AppState.self, from: data)

        // Assert
        XCTAssertTrue(decoded.projects.isEmpty)
        XCTAssertTrue(decoded.openTabs.isEmpty)
        XCTAssertNil(decoded.activeTabId)
    }

    func test_appState_codable_full_roundTrip() throws {
        // Arrange
        let wt = makeWorktree()
        let project = makeProject(worktrees: [wt])
        let tab = makeOpenTab(worktreeId: wt.id, projectId: project.id, order: 0)
        let original = AppState(
            projects: [project],
            openTabs: [tab],
            activeTabId: tab.id,
            sidebarWidth: 300,
            windowFrame: CGRect(x: 100, y: 200, width: 800, height: 600)
        )

        // Act
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AppState.self, from: data)

        // Assert
        XCTAssertEqual(decoded.projects.count, 1)
        XCTAssertEqual(decoded.openTabs.count, 1)
        XCTAssertEqual(decoded.activeTabId, tab.id)
        XCTAssertEqual(decoded.sidebarWidth, 300)
        XCTAssertEqual(decoded.windowFrame, CGRect(x: 100, y: 200, width: 800, height: 600))
    }

    // MARK: - OpenTab Init

    func test_openTab_init_defaults() {
        // Act
        let tab = OpenTab(worktreeId: UUID(), projectId: UUID(), order: 0)

        // Assert
        XCTAssertNil(tab.splitTreeData)
        XCTAssertNil(tab.activePaneId)
    }

    // MARK: - OpenTab Codable

    func test_openTab_codable_roundTrip() throws {
        // Arrange
        let paneId = UUID()
        let treeData = Data([0x01, 0x02, 0x03])
        let original = makeOpenTab(
            order: 5,
            splitTreeData: treeData,
            activePaneId: paneId
        )

        // Act
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(OpenTab.self, from: data)

        // Assert
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.worktreeId, original.worktreeId)
        XCTAssertEqual(decoded.projectId, original.projectId)
        XCTAssertEqual(decoded.order, 5)
        XCTAssertEqual(decoded.splitTreeData, treeData)
        XCTAssertEqual(decoded.activePaneId, paneId)
    }

    func test_openTab_codable_nilOptionals_roundTrip() throws {
        // Arrange
        let original = makeOpenTab(splitTreeData: nil, activePaneId: nil)

        // Act
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(OpenTab.self, from: data)

        // Assert
        XCTAssertNil(decoded.splitTreeData)
        XCTAssertNil(decoded.activePaneId)
    }

    // MARK: - OpenTab Hashable

    func test_openTab_hashable_identicalTabsEqual() {
        // Arrange
        let id = UUID()
        let wtId = UUID()
        let pId = UUID()
        let tab1 = OpenTab(id: id, worktreeId: wtId, projectId: pId, order: 0)
        let tab2 = OpenTab(id: id, worktreeId: wtId, projectId: pId, order: 0)

        // Assert
        XCTAssertEqual(tab1, tab2)
    }

    func test_openTab_hashable_differentOrderNotEqual() {
        // Arrange
        let id = UUID()
        let wtId = UUID()
        let pId = UUID()
        let tab1 = OpenTab(id: id, worktreeId: wtId, projectId: pId, order: 0)
        let tab2 = OpenTab(id: id, worktreeId: wtId, projectId: pId, order: 1)

        // Assert
        XCTAssertNotEqual(tab1, tab2)
    }

    // MARK: - Project Codable

    func test_project_codable_empty_roundTrip() throws {
        // Arrange
        let original = makeProject()

        // Act
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Project.self, from: data)

        // Assert
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.name, "test-project")
        XCTAssertTrue(decoded.worktrees.isEmpty)
    }

    func test_project_codable_withWorktrees_roundTrip() throws {
        // Arrange
        let wt1 = makeWorktree(name: "main", branch: "main")
        let wt2 = makeWorktree(name: "feature", branch: "feature", agent: .codex, status: .running)
        let original = makeProject(worktrees: [wt1, wt2])

        // Act
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Project.self, from: data)

        // Assert
        XCTAssertEqual(decoded.worktrees.count, 2)
        XCTAssertEqual(decoded.worktrees[0].name, "main")
        XCTAssertEqual(decoded.worktrees[1].agent, .codex)
    }

    // MARK: - Project Init Defaults

    func test_project_init_defaults() {
        // Act
        let project = Project(name: "test", repoPath: URL(fileURLWithPath: "/tmp"))

        // Assert
        XCTAssertTrue(project.worktrees.isEmpty)
    }
}
