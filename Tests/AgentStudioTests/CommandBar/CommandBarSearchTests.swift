import XCTest

@testable import AgentStudio

final class CommandBarSearchTests: XCTestCase {

    // MARK: - Fuzzy Match — Basic Matching

    func test_fuzzyMatch_exactMatch_returnsLowScore() {
        // Act
        let result = CommandBarSearch.fuzzyMatch(pattern: "Close Tab", in: "Close Tab")

        // Assert
        XCTAssertNotNil(result)
        XCTAssertLessThan(result!.score, 0.3)
    }

    func test_fuzzyMatch_prefixMatch_returnsLowScore() {
        // Act
        let result = CommandBarSearch.fuzzyMatch(pattern: "clo", in: "Close Tab")

        // Assert
        XCTAssertNotNil(result)
        XCTAssertLessThan(result!.score, 0.5)
    }

    func test_fuzzyMatch_caseInsensitive_matches() {
        // Act
        let result = CommandBarSearch.fuzzyMatch(pattern: "close", in: "Close Tab")

        // Assert
        XCTAssertNotNil(result)
    }

    func test_fuzzyMatch_noMatch_returnsNil() {
        // Act
        let result = CommandBarSearch.fuzzyMatch(pattern: "xyz", in: "Close Tab")

        // Assert
        XCTAssertNil(result)
    }

    func test_fuzzyMatch_emptyPattern_returnsZeroScore() {
        // Act
        let result = CommandBarSearch.fuzzyMatch(pattern: "", in: "Close Tab")

        // Assert
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.score, 0.0)
        XCTAssertTrue(result!.matchedRanges.isEmpty)
    }

    func test_fuzzyMatch_emptyText_returnsNil() {
        // Act
        let result = CommandBarSearch.fuzzyMatch(pattern: "a", in: "")

        // Assert
        XCTAssertNil(result)
    }

    // MARK: - Fuzzy Match — Scoring Quality

    func test_fuzzyMatch_consecutiveChars_scoreBetterThanScattered() {
        // Act
        let consecutive = CommandBarSearch.fuzzyMatch(pattern: "sp", in: "Split Right")
        let scattered = CommandBarSearch.fuzzyMatch(pattern: "st", in: "Split Right")

        // Assert — both match, but consecutive should score better (lower)
        XCTAssertNotNil(consecutive)
        XCTAssertNotNil(scattered)
        XCTAssertLessThan(consecutive!.score, scattered!.score)
    }

    func test_fuzzyMatch_wordStartMatch_scoresBetter() {
        // Act
        let wordStart = CommandBarSearch.fuzzyMatch(pattern: "sr", in: "Split Right")
        let midWord = CommandBarSearch.fuzzyMatch(pattern: "pi", in: "Split Right")

        // Assert — word start (S + R) should score better
        XCTAssertNotNil(wordStart)
        XCTAssertNotNil(midWord)
        XCTAssertLessThan(wordStart!.score, midWord!.score)
    }

    // MARK: - Fuzzy Match — Ranges

    func test_fuzzyMatch_returnsMatchedRanges() {
        // Act
        let result = CommandBarSearch.fuzzyMatch(pattern: "ct", in: "Close Tab")

        // Assert
        XCTAssertNotNil(result)
        XCTAssertFalse(result!.matchedRanges.isEmpty)
    }

    func test_fuzzyMatch_consecutiveChars_coalesceIntoSingleRange() {
        // Act
        let result = CommandBarSearch.fuzzyMatch(pattern: "Clo", in: "Close Tab")

        // Assert — "Clo" should produce 1 contiguous range
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.matchedRanges.count, 1)
    }

    func test_fuzzyMatch_scatteredChars_produceMultipleRanges() {
        // Act
        let result = CommandBarSearch.fuzzyMatch(pattern: "ct", in: "Close Tab")

        // Assert — "C" and "T" are non-contiguous → 2 ranges
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.matchedRanges.count, 2)
    }

    // MARK: - Score Item

    func test_scoreItem_emptyQuery_returnsZero() {
        // Arrange
        let item = makeCommandBarItem(title: "Close Tab")

        // Act
        let score = CommandBarSearch.scoreItem(item, query: "")

        // Assert — empty query matches everything with best score
        XCTAssertEqual(score, 0.0)
    }

    func test_scoreItem_matchingTitle_returnsScore() {
        // Arrange
        let item = makeCommandBarItem(title: "Close Tab")

        // Act
        let score = CommandBarSearch.scoreItem(item, query: "close")

        // Assert
        XCTAssertNotNil(score)
        XCTAssertLessThan(score!, 0.7)
    }

    func test_scoreItem_noMatch_returnsNil() {
        // Arrange
        let item = makeCommandBarItem(title: "Close Tab")

        // Act
        let score = CommandBarSearch.scoreItem(item, query: "xyzzy")

        // Assert
        XCTAssertNil(score)
    }

    func test_scoreItem_matchingKeyword_returnsScore() {
        // Arrange
        let item = makeCommandBarItem(title: "Close Tab", keywords: ["shutdown", "remove"])

        // Act
        let score = CommandBarSearch.scoreItem(item, query: "shut")

        // Assert
        XCTAssertNotNil(score)
    }

    func test_scoreItem_matchingSubtitle_returnsScore() {
        // Arrange
        let item = makeCommandBarItem(title: "Terminal", subtitle: "main-feature")

        // Act
        let score = CommandBarSearch.scoreItem(item, query: "main")

        // Assert
        XCTAssertNotNil(score)
    }

    func test_scoreItem_recentBoost_improvedScore() {
        // Arrange
        let item = makeCommandBarItem(id: "recent-item", title: "Close Tab")

        // Act
        let scoreWithoutRecent = CommandBarSearch.scoreItem(item, query: "close", recentIds: [])
        let scoreWithRecent = CommandBarSearch.scoreItem(item, query: "close", recentIds: ["recent-item"])

        // Assert — recent item should score better (lower)
        XCTAssertNotNil(scoreWithoutRecent)
        XCTAssertNotNil(scoreWithRecent)
        XCTAssertLessThan(scoreWithRecent!, scoreWithoutRecent!)
    }

    // MARK: - Filter

    func test_filter_emptyQuery_returnsAllItems() {
        // Arrange
        let items = [
            makeCommandBarItem(id: "a", title: "Close Tab"),
            makeCommandBarItem(id: "b", title: "Split Right"),
        ]

        // Act
        let filtered = CommandBarSearch.filter(items: items, query: "")

        // Assert
        XCTAssertEqual(filtered.count, 2)
    }

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
        XCTAssertEqual(filtered.count, 2)
        XCTAssertTrue(filtered.allSatisfy { $0.title.lowercased().contains("close") })
    }

    func test_filter_noMatches_returnsEmpty() {
        // Arrange
        let items = [
            makeCommandBarItem(id: "a", title: "Close Tab")
        ]

        // Act
        let filtered = CommandBarSearch.filter(items: items, query: "xyzzy")

        // Assert
        XCTAssertTrue(filtered.isEmpty)
    }
}
