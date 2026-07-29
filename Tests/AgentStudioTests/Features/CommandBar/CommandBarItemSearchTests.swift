import Foundation
import Testing

@testable import AgentStudioCommandBar

@Suite(.serialized)
struct CommandBarItemSearchTests {
    @Test
    func test_scoreItem_emptyQuery_returnsZero() {
        // Arrange
        let item = makeCommandBarItem(title: "Close Tab")

        // Act
        let score = CommandBarSearch.scoreItem(item, query: "")

        // Assert — empty query matches everything with best score
        #expect(score == 0.0)
    }

    @Test
    func test_scoreItem_matchingTitle_returnsScore() {
        // Arrange
        let item = makeCommandBarItem(title: "Close Tab")

        // Act
        let score = CommandBarSearch.scoreItem(item, query: "close")

        // Assert
        guard let score else {
            Issue.record("Expected score for matching title")
            return
        }
        #expect(score < 0.7)
    }

    @Test
    func test_scoreItem_noMatch_returnsNil() {
        // Arrange
        let item = makeCommandBarItem(title: "Close Tab")

        // Act
        let score = CommandBarSearch.scoreItem(item, query: "xyzzy")

        // Assert
        #expect(score == nil)
    }

    @Test
    func test_scoreItem_matchingKeyword_returnsScore() {
        // Arrange
        let item = makeCommandBarItem(title: "Close Tab", keywords: ["shutdown", "remove"])

        // Act
        let score = CommandBarSearch.scoreItem(item, query: "shut")

        // Assert
        #expect(score != nil)
    }

    @Test
    func test_scoreItem_matchingSubtitle_returnsScore() {
        // Arrange
        let item = makeCommandBarItem(title: "Terminal", subtitle: "main-feature")

        // Act
        let score = CommandBarSearch.scoreItem(item, query: "main")

        // Assert
        #expect(score != nil)
    }

    @Test
    func test_scoreItem_recentBoost_improvedScore() {
        // Arrange
        let item = makeCommandBarItem(id: "recent-item", title: "Close Tab")

        // Act
        let scoreWithoutRecent = CommandBarSearch.scoreItem(item, query: "close", recentIds: [])
        let scoreWithRecent = CommandBarSearch.scoreItem(item, query: "close", recentIds: ["recent-item"])

        // Assert — recent item should score better (lower)
        guard let scoreWithoutRecent else {
            Issue.record("Expected baseline score")
            return
        }
        guard let scoreWithRecent else {
            Issue.record("Expected boosted score")
            return
        }
        #expect(scoreWithRecent < scoreWithoutRecent)
    }

    @Test
    func test_filter_emptyQuery_returnsAllItems() {
        // Arrange
        let items = [
            makeCommandBarItem(id: "a", title: "Close Tab"),
            makeCommandBarItem(id: "b", title: "Split Right"),
        ]

        // Act
        let filtered = CommandBarSearch.filter(items: items, query: "")

        // Assert
        #expect(filtered.count == 2)
    }

    @Test
    func test_filter_matchingQuery_returnsMatchedItemsSorted() {
        // Arrange
        let items = [
            makeCommandBarItem(id: "a", title: "Add Repo"),
            makeCommandBarItem(id: "b", title: "Close Tab"),
            makeCommandBarItem(id: "c", title: "Close Pane"),
        ]

        // Act
        let filtered = CommandBarSearch.filter(items: items, query: "close")

        // Assert — only "Close Tab" and "Close Pane" match
        #expect(filtered.count == 2)
        #expect(filtered.allSatisfy { $0.title.lowercased().contains("close") })
    }

    @Test
    func test_filter_noMatches_returnsEmpty() {
        // Arrange
        let items = [
            makeCommandBarItem(id: "a", title: "Close Tab")
        ]

        // Act
        let filtered = CommandBarSearch.filter(items: items, query: "xyzzy")

        // Assert
        #expect(filtered.isEmpty)
    }
}
