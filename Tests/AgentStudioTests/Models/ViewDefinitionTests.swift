import XCTest
@testable import AgentStudio

final class ViewDefinitionTests: XCTestCase {

    // MARK: - Init

    func test_init_defaults() {
        // Act
        let view = ViewDefinition(name: "Main", kind: .main)

        // Assert
        XCTAssertNotNil(view.id)
        XCTAssertEqual(view.name, "Main")
        XCTAssertEqual(view.kind, .main)
        XCTAssertTrue(view.tabs.isEmpty)
        XCTAssertNil(view.activeTabId)
    }

    func test_init_withTabs() {
        // Arrange
        let tab1 = Tab(sessionId: UUID())
        let tab2 = Tab(sessionId: UUID())

        // Act
        let view = ViewDefinition(
            name: "Dev",
            kind: .saved,
            tabs: [tab1, tab2],
            activeTabId: tab1.id
        )

        // Assert
        XCTAssertEqual(view.tabs.count, 2)
        XCTAssertEqual(view.activeTabId, tab1.id)
    }

    // MARK: - Derived: allSessionIds

    func test_allSessionIds_emptyTabs() {
        // Arrange
        let view = ViewDefinition(name: "Empty", kind: .main)

        // Assert
        XCTAssertTrue(view.allSessionIds.isEmpty)
    }

    func test_allSessionIds_singleTab() {
        // Arrange
        let sessionId = UUID()
        let tab = Tab(sessionId: sessionId)
        let view = ViewDefinition(name: "Main", kind: .main, tabs: [tab])

        // Assert
        XCTAssertEqual(view.allSessionIds, [sessionId])
    }

    func test_allSessionIds_multipleTabs() {
        // Arrange
        let session1 = UUID()
        let session2 = UUID()
        let session3 = UUID()
        let tab1 = Tab(sessionId: session1)
        let layout = Layout(sessionId: session2)
            .inserting(sessionId: session3, at: session2, direction: .horizontal, position: .after)
        let tab2 = Tab(layout: layout, activeSessionId: session2)

        let view = ViewDefinition(
            name: "Dev",
            kind: .main,
            tabs: [tab1, tab2]
        )

        // Assert
        XCTAssertEqual(view.allSessionIds, [session1, session2, session3])
    }

    // MARK: - ViewKind

    func test_viewKind_main_equatable() {
        XCTAssertEqual(ViewKind.main, ViewKind.main)
        XCTAssertNotEqual(ViewKind.main, ViewKind.saved)
    }

    func test_viewKind_worktree_equatable() {
        let id = UUID()
        XCTAssertEqual(ViewKind.worktree(worktreeId: id), ViewKind.worktree(worktreeId: id))
        XCTAssertNotEqual(ViewKind.worktree(worktreeId: id), ViewKind.worktree(worktreeId: UUID()))
    }

    func test_viewKind_dynamic_equatable() {
        let repoId = UUID()
        XCTAssertEqual(
            ViewKind.dynamic(rule: .byRepo(repoId: repoId)),
            ViewKind.dynamic(rule: .byRepo(repoId: repoId))
        )
        XCTAssertNotEqual(
            ViewKind.dynamic(rule: .byAgent(.claude)),
            ViewKind.dynamic(rule: .byAgent(.codex))
        )
    }

    // MARK: - DynamicViewRule

    func test_dynamicViewRule_byRepo() {
        let repoId = UUID()
        let rule = DynamicViewRule.byRepo(repoId: repoId)
        XCTAssertEqual(rule, .byRepo(repoId: repoId))
    }

    func test_dynamicViewRule_byAgent() {
        let rule = DynamicViewRule.byAgent(.claude)
        XCTAssertEqual(rule, .byAgent(.claude))
    }

    func test_dynamicViewRule_custom() {
        let rule = DynamicViewRule.custom(name: "test-filter")
        XCTAssertEqual(rule, .custom(name: "test-filter"))
    }

    // MARK: - Codable Round-Trip

    func test_codable_mainView_roundTrips() throws {
        // Arrange
        let sessionId = UUID()
        let tab = Tab(sessionId: sessionId)
        let view = ViewDefinition(
            name: "Main",
            kind: .main,
            tabs: [tab],
            activeTabId: tab.id
        )

        // Act
        let data = try JSONEncoder().encode(view)
        let decoded = try JSONDecoder().decode(ViewDefinition.self, from: data)

        // Assert
        XCTAssertEqual(decoded.id, view.id)
        XCTAssertEqual(decoded.name, "Main")
        XCTAssertEqual(decoded.kind, .main)
        XCTAssertEqual(decoded.tabs.count, 1)
        XCTAssertEqual(decoded.activeTabId, tab.id)
        XCTAssertEqual(decoded.allSessionIds, [sessionId])
    }

    func test_codable_worktreeView_roundTrips() throws {
        // Arrange
        let worktreeId = UUID()
        let view = ViewDefinition(
            name: "Feature",
            kind: .worktree(worktreeId: worktreeId)
        )

        // Act
        let data = try JSONEncoder().encode(view)
        let decoded = try JSONDecoder().decode(ViewDefinition.self, from: data)

        // Assert
        XCTAssertEqual(decoded.kind, .worktree(worktreeId: worktreeId))
    }

    func test_codable_dynamicView_roundTrips() throws {
        // Arrange
        let repoId = UUID()
        let view = ViewDefinition(
            name: "By Repo",
            kind: .dynamic(rule: .byRepo(repoId: repoId))
        )

        // Act
        let data = try JSONEncoder().encode(view)
        let decoded = try JSONDecoder().decode(ViewDefinition.self, from: data)

        // Assert
        XCTAssertEqual(decoded.kind, .dynamic(rule: .byRepo(repoId: repoId)))
    }

    func test_codable_savedView_roundTrips() throws {
        // Arrange
        let view = ViewDefinition(name: "Saved Layout", kind: .saved)

        // Act
        let data = try JSONEncoder().encode(view)
        let decoded = try JSONDecoder().decode(ViewDefinition.self, from: data)

        // Assert
        XCTAssertEqual(decoded.kind, .saved)
        XCTAssertEqual(decoded.name, "Saved Layout")
    }

    // MARK: - Hashable

    func test_hashable_sameId_areEqual() {
        let id = UUID()
        let view1 = ViewDefinition(id: id, name: "A", kind: .main)
        let view2 = ViewDefinition(id: id, name: "A", kind: .main)
        XCTAssertEqual(view1, view2)
    }
}
