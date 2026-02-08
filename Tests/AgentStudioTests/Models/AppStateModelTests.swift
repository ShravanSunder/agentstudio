import XCTest
import CoreGraphics
@testable import AgentStudio

final class WorkspaceModelTests: XCTestCase {

    // MARK: - Workspace Init Defaults

    func test_workspace_init_defaults() {
        // Act
        let ws = Workspace()

        // Assert
        XCTAssertTrue(ws.repos.isEmpty)
        XCTAssertTrue(ws.openTabs.isEmpty)
        XCTAssertNil(ws.activeTabId)
        XCTAssertEqual(ws.sidebarWidth, 250)
        XCTAssertNil(ws.windowFrame)
        XCTAssertEqual(ws.name, "Default Workspace")
    }

    // MARK: - Workspace Codable

    func test_workspace_codable_empty_roundTrip() throws {
        // Arrange
        let original = Workspace()

        // Act
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Workspace.self, from: data)

        // Assert
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.name, "Default Workspace")
        XCTAssertTrue(decoded.repos.isEmpty)
        XCTAssertTrue(decoded.openTabs.isEmpty)
        XCTAssertNil(decoded.activeTabId)
    }

    func test_workspace_codable_full_roundTrip() throws {
        // Arrange
        let wt = makeWorktree()
        let repo = makeRepo(worktrees: [wt])
        let tab = makeOpenTab(worktreeId: wt.id, repoId: repo.id, order: 0)
        let original = Workspace(
            name: "My Workspace",
            repos: [repo],
            openTabs: [tab],
            activeTabId: tab.id,
            sidebarWidth: 300,
            windowFrame: CGRect(x: 100, y: 200, width: 800, height: 600)
        )

        // Act
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Workspace.self, from: data)

        // Assert
        XCTAssertEqual(decoded.name, "My Workspace")
        XCTAssertEqual(decoded.repos.count, 1)
        XCTAssertEqual(decoded.openTabs.count, 1)
        XCTAssertEqual(decoded.activeTabId, tab.id)
        XCTAssertEqual(decoded.sidebarWidth, 300)
        XCTAssertEqual(decoded.windowFrame, CGRect(x: 100, y: 200, width: 800, height: 600))
    }

    func test_workspace_codable_preservesTimestamps() throws {
        // Arrange
        let created = Date(timeIntervalSince1970: 1_000_000)
        let updated = Date(timeIntervalSince1970: 2_000_000)
        let original = Workspace(createdAt: created, updatedAt: updated)

        // Act
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Workspace.self, from: data)

        // Assert
        XCTAssertEqual(decoded.createdAt.timeIntervalSince1970, created.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(decoded.updatedAt.timeIntervalSince1970, updated.timeIntervalSince1970, accuracy: 0.001)
    }

    // MARK: - OpenTab Init

    func test_openTab_init_defaults() {
        // Act
        let tab = OpenTab(worktreeId: UUID(), repoId: UUID(), order: 0)

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
        XCTAssertEqual(decoded.repoId, original.repoId)
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
        let rId = UUID()
        let tab1 = OpenTab(id: id, worktreeId: wtId, repoId: rId, order: 0)
        let tab2 = OpenTab(id: id, worktreeId: wtId, repoId: rId, order: 0)

        // Assert
        XCTAssertEqual(tab1, tab2)
    }

    func test_openTab_hashable_differentOrderNotEqual() {
        // Arrange
        let id = UUID()
        let wtId = UUID()
        let rId = UUID()
        let tab1 = OpenTab(id: id, worktreeId: wtId, repoId: rId, order: 0)
        let tab2 = OpenTab(id: id, worktreeId: wtId, repoId: rId, order: 1)

        // Assert
        XCTAssertNotEqual(tab1, tab2)
    }

    // MARK: - Repo Codable

    func test_repo_codable_empty_roundTrip() throws {
        // Arrange
        let original = makeRepo()

        // Act
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Repo.self, from: data)

        // Assert
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.name, "test-repo")
        XCTAssertTrue(decoded.worktrees.isEmpty)
    }

    func test_repo_codable_withWorktrees_roundTrip() throws {
        // Arrange
        let wt1 = makeWorktree(name: "main", branch: "main")
        let wt2 = makeWorktree(name: "feature", branch: "feature", agent: .codex, status: .running)
        let original = makeRepo(worktrees: [wt1, wt2])

        // Act
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Repo.self, from: data)

        // Assert
        XCTAssertEqual(decoded.worktrees.count, 2)
        XCTAssertEqual(decoded.worktrees[0].name, "main")
        XCTAssertEqual(decoded.worktrees[1].agent, .codex)
    }

    // MARK: - Repo Init Defaults

    func test_repo_init_defaults() {
        // Act
        let repo = Repo(name: "test", repoPath: URL(fileURLWithPath: "/tmp"))

        // Assert
        XCTAssertTrue(repo.worktrees.isEmpty)
    }
}
