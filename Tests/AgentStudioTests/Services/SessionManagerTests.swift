import XCTest
@testable import AgentStudio

final class SessionManagerTests: XCTestCase {

    // MARK: - Test Data

    private var worktreeA: Worktree!
    private var worktreeB: Worktree!
    private var repo: Repo!
    private var repos: [Repo]!

    override func setUp() {
        super.setUp()
        worktreeA = makeWorktree(name: "main", path: "/tmp/repo/main", branch: "main")
        worktreeB = makeWorktree(name: "feature", path: "/tmp/repo/feature", branch: "feature")
        repo = makeRepo(worktrees: [worktreeA, worktreeB])
        repos = [repo]
    }

    // MARK: - findWorktree(for:in:)

    func test_findWorktree_matchingTab_returnsWorktree() {
        // Arrange
        let tab = makeOpenTab(worktreeId: worktreeA.id, repoId: repo.id)

        // Act
        let result = SessionManager.findWorktree(for: tab, in: repos)

        // Assert
        XCTAssertEqual(result?.id, worktreeA.id)
    }

    func test_findWorktree_wrongRepoId_returnsNil() {
        // Arrange
        let tab = makeOpenTab(worktreeId: worktreeA.id, repoId: UUID())

        // Act
        let result = SessionManager.findWorktree(for: tab, in: repos)

        // Assert
        XCTAssertNil(result)
    }

    func test_findWorktree_wrongWorktreeId_returnsNil() {
        // Arrange
        let tab = makeOpenTab(worktreeId: UUID(), repoId: repo.id)

        // Act
        let result = SessionManager.findWorktree(for: tab, in: repos)

        // Assert
        XCTAssertNil(result)
    }

    func test_findWorktree_emptyRepos_returnsNil() {
        // Arrange
        let tab = makeOpenTab(worktreeId: worktreeA.id, repoId: repo.id)

        // Act
        let result = SessionManager.findWorktree(for: tab, in: [])

        // Assert
        XCTAssertNil(result)
    }

    // MARK: - findRepo(for:in:)

    func test_findRepo_matchingTab_returnsRepo() {
        // Arrange
        let tab = makeOpenTab(worktreeId: worktreeA.id, repoId: repo.id)

        // Act
        let result = SessionManager.findRepo(for: tab, in: repos)

        // Assert
        XCTAssertEqual(result?.id, repo.id)
    }

    func test_findRepo_wrongRepoId_returnsNil() {
        // Arrange
        let tab = makeOpenTab(worktreeId: worktreeA.id, repoId: UUID())

        // Act
        let result = SessionManager.findRepo(for: tab, in: repos)

        // Assert
        XCTAssertNil(result)
    }

    // MARK: - findRepo(containing:in:)

    func test_findRepoContaining_existingWorktree_returnsRepo() {
        // Act
        let result = SessionManager.findRepo(containing: worktreeA, in: repos)

        // Assert
        XCTAssertEqual(result?.id, repo.id)
    }

    func test_findRepoContaining_orphanWorktree_returnsNil() {
        // Arrange
        let orphan = makeWorktree(name: "orphan")

        // Act
        let result = SessionManager.findRepo(containing: orphan, in: repos)

        // Assert
        XCTAssertNil(result)
    }

    // MARK: - mergeWorktrees (static via instance for now)

    func test_mergeWorktrees_newDiscovered_returnedAsIs() {
        // Arrange
        let existing: [Worktree] = []
        let discovered = [makeWorktree(name: "new-feature", path: "/tmp/repo/new", branch: "new")]

        // Act
        let result = SessionManager.mergeWorktrees(existing: existing, discovered: discovered)

        // Assert
        XCTAssertEqual(result.count, 1)
        XCTAssertNil(result[0].agent)
        XCTAssertEqual(result[0].status, .idle)
    }

    func test_mergeWorktrees_matchingPath_preservesExistingState() {
        // Arrange
        let sharedPath = "/tmp/repo/feature"
        let existing = [makeWorktree(
            name: "feature",
            path: sharedPath,
            branch: "feature",
            agent: .claude,
            status: .running
        )]
        let discovered = [makeWorktree(
            name: "feature-renamed",
            path: sharedPath,
            branch: "feature-v2"
        )]

        // Act
        let result = SessionManager.mergeWorktrees(existing: existing, discovered: discovered)

        // Assert
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].id, existing[0].id)
        XCTAssertEqual(result[0].agent, .claude)
        XCTAssertEqual(result[0].status, .running)
        XCTAssertEqual(result[0].name, "feature-renamed")
        XCTAssertEqual(result[0].branch, "feature-v2")
    }

    func test_mergeWorktrees_existingRemovedFromDisk_notInResult() {
        // Arrange
        let existing = [
            makeWorktree(name: "old", path: "/tmp/repo/old", branch: "old"),
        ]
        let discovered: [Worktree] = []

        // Act
        let result = SessionManager.mergeWorktrees(existing: existing, discovered: discovered)

        // Assert
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - addTabRecord

    func test_addTabRecord_newId_appendsTab() {
        // Arrange
        var tabs: [OpenTab] = []
        let id = UUID(), wtId = UUID(), repoId = UUID()

        // Act
        let result = SessionManager.addTabRecord(id: id, worktreeId: wtId, repoId: repoId, to: &tabs)

        // Assert
        XCTAssertEqual(tabs.count, 1)
        XCTAssertEqual(result.id, id)
        XCTAssertEqual(result.worktreeId, wtId)
        XCTAssertEqual(result.repoId, repoId)
        XCTAssertEqual(result.order, 0)
    }

    func test_addTabRecord_duplicateId_returnsExisting() {
        // Arrange
        let id = UUID()
        var tabs = [makeOpenTab(id: id, worktreeId: UUID(), repoId: UUID(), order: 0)]

        // Act
        let result = SessionManager.addTabRecord(id: id, worktreeId: UUID(), repoId: UUID(), to: &tabs)

        // Assert
        XCTAssertEqual(tabs.count, 1)
        XCTAssertEqual(result.id, id)
    }

    func test_addTabRecord_setsOrderToCount() {
        // Arrange
        var tabs = [
            makeOpenTab(order: 0),
            makeOpenTab(order: 1),
        ]

        // Act
        let result = SessionManager.addTabRecord(id: UUID(), worktreeId: UUID(), repoId: UUID(), to: &tabs)

        // Assert
        XCTAssertEqual(result.order, 2)
        XCTAssertEqual(tabs.count, 3)
    }

    // MARK: - removeTabRecord

    func test_removeTabRecord_existingId_removesAndReindexes() {
        // Arrange
        let id1 = UUID(), id2 = UUID(), id3 = UUID()
        var tabs = [
            makeOpenTab(id: id1, order: 0),
            makeOpenTab(id: id2, order: 1),
            makeOpenTab(id: id3, order: 2),
        ]

        // Act
        SessionManager.removeTabRecord(id2, from: &tabs)

        // Assert
        XCTAssertEqual(tabs.count, 2)
        XCTAssertNil(tabs.first(where: { $0.id == id2 }))
        XCTAssertEqual(tabs[0].order, 0)
        XCTAssertEqual(tabs[1].order, 1)
    }

    func test_removeTabRecord_unknownId_noChange() {
        // Arrange
        var tabs = [makeOpenTab(order: 0)]

        // Act
        SessionManager.removeTabRecord(UUID(), from: &tabs)

        // Assert
        XCTAssertEqual(tabs.count, 1)
    }

    // MARK: - closeTabById

    func test_closeTabById_activeTab_updatesActiveId() {
        // Arrange
        let id1 = UUID(), id2 = UUID()
        var tabs = [
            makeOpenTab(id: id1, order: 0),
            makeOpenTab(id: id2, order: 1),
        ]
        var activeTabId: UUID? = id1

        // Act
        SessionManager.closeTabById(id1, tabs: &tabs, activeTabId: &activeTabId)

        // Assert
        XCTAssertEqual(tabs.count, 1)
        XCTAssertEqual(activeTabId, id2)
    }

    func test_closeTabById_nonActiveTab_preservesActiveId() {
        // Arrange
        let id1 = UUID(), id2 = UUID()
        var tabs = [
            makeOpenTab(id: id1, order: 0),
            makeOpenTab(id: id2, order: 1),
        ]
        var activeTabId: UUID? = id1

        // Act
        SessionManager.closeTabById(id2, tabs: &tabs, activeTabId: &activeTabId)

        // Assert
        XCTAssertEqual(tabs.count, 1)
        XCTAssertEqual(activeTabId, id1)
    }

    func test_closeTabById_lastTab_setsActiveIdNil() {
        // Arrange
        let id = UUID()
        var tabs = [makeOpenTab(id: id, order: 0)]
        var activeTabId: UUID? = id

        // Act
        SessionManager.closeTabById(id, tabs: &tabs, activeTabId: &activeTabId)

        // Assert
        XCTAssertTrue(tabs.isEmpty)
        XCTAssertNil(activeTabId)
    }

    func test_closeTabById_reindexesOrder() {
        // Arrange
        let id1 = UUID(), id2 = UUID(), id3 = UUID()
        var tabs = [
            makeOpenTab(id: id1, order: 0),
            makeOpenTab(id: id2, order: 1),
            makeOpenTab(id: id3, order: 2),
        ]
        var activeTabId: UUID? = id3

        // Act
        SessionManager.closeTabById(id1, tabs: &tabs, activeTabId: &activeTabId)

        // Assert
        XCTAssertEqual(tabs.count, 2)
        XCTAssertEqual(tabs[0].order, 0)
        XCTAssertEqual(tabs[1].order, 1)
        XCTAssertEqual(activeTabId, id3)
    }

    // MARK: - syncTabOrder

    func test_syncTabOrder_reordersMatchingTabs() {
        // Arrange
        let id1 = UUID(), id2 = UUID(), id3 = UUID()
        var tabs = [
            makeOpenTab(id: id1, order: 0),
            makeOpenTab(id: id2, order: 1),
            makeOpenTab(id: id3, order: 2),
        ]

        // Act — reverse order
        SessionManager.syncTabOrder(tabIds: [id3, id2, id1], tabs: &tabs)

        // Assert
        XCTAssertEqual(tabs.first(where: { $0.id == id3 })?.order, 0)
        XCTAssertEqual(tabs.first(where: { $0.id == id2 })?.order, 1)
        XCTAssertEqual(tabs.first(where: { $0.id == id1 })?.order, 2)
    }

    func test_syncTabOrder_unknownIds_ignored() {
        // Arrange
        let id1 = UUID()
        var tabs = [makeOpenTab(id: id1, order: 0)]

        // Act
        SessionManager.syncTabOrder(tabIds: [UUID(), id1], tabs: &tabs)

        // Assert
        XCTAssertEqual(tabs.first(where: { $0.id == id1 })?.order, 1)
    }

    func test_syncTabOrder_emptyTabIds_noChange() {
        // Arrange
        let id1 = UUID()
        var tabs = [makeOpenTab(id: id1, order: 5)]

        // Act
        SessionManager.syncTabOrder(tabIds: [], tabs: &tabs)

        // Assert
        XCTAssertEqual(tabs[0].order, 5)
    }
}
