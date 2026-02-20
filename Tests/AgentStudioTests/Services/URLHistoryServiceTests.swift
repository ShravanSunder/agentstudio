import XCTest

@testable import AgentStudio

/// In-memory storage for testing URLHistoryService without touching UserDefaults.
final class MockURLHistoryStorage: URLHistoryStorage, @unchecked Sendable {
    private var store: [String: Data] = [:]

    func data(forKey key: String) -> Data? {
        store[key]
    }

    func set(_ data: Data?, forKey key: String) {
        store[key] = data
    }
}

@MainActor
final class URLHistoryServiceTests: XCTestCase {

    private func makeService(storage: MockURLHistoryStorage = MockURLHistoryStorage()) -> URLHistoryService {
        URLHistoryService(storage: storage)
    }

    // MARK: - Favorites: Default Seeding

    func test_firstRun_seedsDefaultFavorites() {
        // Arrange & Act
        let service = makeService()

        // Assert — defaults seeded
        XCTAssertEqual(service.favorites.count, 2)
        XCTAssertTrue(service.isFavorite(url: URL(string: "https://github.com")!))
        XCTAssertTrue(service.isFavorite(url: URL(string: "https://google.com")!))
    }

    func test_secondRun_loadsPersistedFavorites() {
        // Arrange — first run seeds defaults
        let storage = MockURLHistoryStorage()
        let first = URLHistoryService(storage: storage)
        first.addFavorite(url: URL(string: "https://custom.com")!, title: "Custom")

        // Act — second run loads from storage
        let second = URLHistoryService(storage: storage)

        // Assert — has 3 favorites (2 defaults + 1 custom)
        XCTAssertEqual(second.favorites.count, 3)
        XCTAssertTrue(second.isFavorite(url: URL(string: "https://custom.com")!))
    }

    // MARK: - Favorites: Add / Remove / Deduplicate

    func test_addFavorite_appendsEntry() {
        // Arrange
        let service = makeService()
        let initialCount = service.favorites.count

        // Act
        service.addFavorite(url: URL(string: "https://linear.app")!, title: "Linear")

        // Assert
        XCTAssertEqual(service.favorites.count, initialCount + 1)
        XCTAssertTrue(service.isFavorite(url: URL(string: "https://linear.app")!))
    }

    func test_addFavorite_deduplicates() {
        // Arrange
        let service = makeService()

        // Act — add same URL twice
        service.addFavorite(url: URL(string: "https://linear.app")!, title: "Linear")
        service.addFavorite(url: URL(string: "https://linear.app")!, title: "Linear 2")

        // Assert — only added once
        let count = service.favorites.filter { $0.url.absoluteString == "https://linear.app" }.count
        XCTAssertEqual(count, 1)
    }

    func test_removeFavorite_removesEntry() {
        // Arrange
        let service = makeService()
        XCTAssertTrue(service.isFavorite(url: URL(string: "https://github.com")!))

        // Act
        service.removeFavorite(url: URL(string: "https://github.com")!)

        // Assert
        XCTAssertFalse(service.isFavorite(url: URL(string: "https://github.com")!))
    }

    func test_removeFavorite_persists() {
        // Arrange
        let storage = MockURLHistoryStorage()
        let first = URLHistoryService(storage: storage)
        first.removeFavorite(url: URL(string: "https://github.com")!)

        // Act — reload from storage
        let second = URLHistoryService(storage: storage)

        // Assert — still removed
        XCTAssertFalse(second.isFavorite(url: URL(string: "https://github.com")!))
    }

    // MARK: - History: Record & Dedup

    func test_record_addsEntry() {
        // Arrange
        let service = makeService()
        XCTAssertEqual(service.entries.count, 0)

        // Act
        service.record(url: URL(string: "https://example.com/page")!, title: "Page")

        // Assert
        XCTAssertEqual(service.entries.count, 1)
        XCTAssertEqual(service.entries[0].title, "Page")
    }

    func test_record_deduplicates_movesToFront() {
        // Arrange
        let service = makeService()
        service.record(url: URL(string: "https://a.com")!, title: "A")
        service.record(url: URL(string: "https://b.com")!, title: "B")
        XCTAssertEqual(service.entries[0].url.absoluteString, "https://b.com")

        // Act — re-record A
        service.record(url: URL(string: "https://a.com")!, title: "A Updated")

        // Assert — A is now first, count unchanged
        XCTAssertEqual(service.entries.count, 2)
        XCTAssertEqual(service.entries[0].url.absoluteString, "https://a.com")
        XCTAssertEqual(service.entries[0].title, "A Updated")
    }

    func test_record_skipsNonHTTP() {
        // Arrange
        let service = makeService()

        // Act
        service.record(url: URL(string: "about:blank")!, title: "Blank")
        service.record(url: URL(string: "file:///tmp/test")!, title: "File")

        // Assert — neither recorded
        XCTAssertEqual(service.entries.count, 0)
    }

    func test_record_usesHostAsFallbackTitle() {
        // Arrange
        let service = makeService()

        // Act
        service.record(url: URL(string: "https://example.com/path")!, title: "")

        // Assert
        XCTAssertEqual(service.entries[0].title, "example.com")
    }

    func test_record_persists() {
        // Arrange
        let storage = MockURLHistoryStorage()
        let first = URLHistoryService(storage: storage)
        first.record(url: URL(string: "https://example.com")!, title: "Ex")

        // Act — reload
        let second = URLHistoryService(storage: storage)

        // Assert
        XCTAssertEqual(second.entries.count, 1)
        XCTAssertEqual(second.entries[0].title, "Ex")
    }

    // MARK: - History: 2-Week Pruning

    func test_record_prunesExpiredEntries() {
        // Arrange
        let service = makeService()
        let threeWeeksAgo = Calendar.current.date(byAdding: .day, value: -21, to: Date())!
        let oldEntry = URLHistoryEntry(
            url: URL(string: "https://old.com")!,
            title: "Old",
            lastVisited: threeWeeksAgo
        )
        // Inject expired entry directly
        service.record(url: URL(string: "https://recent.com")!, title: "Recent")
        // Manually inject an old entry for testing
        var entries = service.entries
        entries.append(oldEntry)
        // We can't directly set entries, so let's test via the load path instead

        // Use storage approach: persist an old entry, then record something new
        let storage = MockURLHistoryStorage()
        let encoder = JSONEncoder()
        let oldEntries = [oldEntry]
        let data = try! encoder.encode(oldEntries)
        storage.set(data, forKey: "com.agentstudio.urlHistory")

        let svc = URLHistoryService(storage: storage)

        // Assert — old entry pruned on load
        XCTAssertEqual(svc.entries.count, 0, "Entries older than 2 weeks should be pruned on load")
    }

    func test_recentEntry_notPruned() {
        // Arrange
        let storage = MockURLHistoryStorage()
        let recentEntry = URLHistoryEntry(
            url: URL(string: "https://recent.com")!,
            title: "Recent",
            lastVisited: Date()
        )
        let data = try! JSONEncoder().encode([recentEntry])
        storage.set(data, forKey: "com.agentstudio.urlHistory")

        // Act
        let service = URLHistoryService(storage: storage)

        // Assert — recent entry preserved
        XCTAssertEqual(service.entries.count, 1)
    }

    // MARK: - Clear History

    func test_clearHistory_removesAllEntries() {
        // Arrange
        let service = makeService()
        service.record(url: URL(string: "https://a.com")!, title: "A")
        service.record(url: URL(string: "https://b.com")!, title: "B")
        XCTAssertEqual(service.entries.count, 2)

        // Act
        service.clearHistory()

        // Assert
        XCTAssertEqual(service.entries.count, 0)
    }

    // MARK: - Query: recentSites excludes favorites

    func test_recentSites_excludesFavorites() {
        // Arrange
        let service = makeService()
        // Record a URL that's also a favorite
        service.record(url: URL(string: "https://github.com")!, title: "GitHub")
        // Record a non-favorite URL
        service.record(url: URL(string: "https://stackoverflow.com")!, title: "SO")

        // Act
        let recent = service.recentSites()

        // Assert — github.com excluded (it's a favorite), SO included
        XCTAssertTrue(recent.contains { $0.url.absoluteString == "https://stackoverflow.com" })
        XCTAssertFalse(recent.contains { $0.url.absoluteString == "https://github.com" })
    }

    func test_recentSites_respectsLimit() {
        // Arrange
        let service = makeService()
        for i in 0..<20 {
            service.record(url: URL(string: "https://site\(i).com")!, title: "Site \(i)")
        }

        // Act
        let recent = service.recentSites(limit: 5)

        // Assert
        XCTAssertEqual(recent.count, 5)
    }

    // MARK: - Query: allSearchable combines favorites + history

    func test_allSearchable_favoritesThenHistory() {
        // Arrange
        let service = makeService()
        service.record(url: URL(string: "https://stackoverflow.com")!, title: "SO")

        // Act
        let all = service.allSearchable()

        // Assert — favorites come first (GitHub, Google), then history
        XCTAssertEqual(all.first?.url.absoluteString, "https://github.com")
        XCTAssertTrue(all.contains { $0.url.absoluteString == "https://stackoverflow.com" })
    }

    func test_allSearchable_dedupesFavoritesFromHistory() {
        // Arrange
        let service = makeService()
        service.record(url: URL(string: "https://github.com")!, title: "GitHub")

        // Act
        let all = service.allSearchable()

        // Assert — github.com appears once (as favorite), not duplicated from history
        let githubCount = all.filter { $0.url.absoluteString == "https://github.com" }.count
        XCTAssertEqual(githubCount, 1)
    }

    // MARK: - Query: suggestions

    func test_suggestions_emptyQuery_returnsFavoritesAndHistory() {
        // Arrange
        let service = makeService()
        service.record(url: URL(string: "https://example.com")!, title: "Example")

        // Act
        let suggestions = service.suggestions(for: "")

        // Assert — favorites first, then history, capped at 8
        XCTAssertTrue(suggestions.count <= 8)
        XCTAssertEqual(suggestions[0].url.absoluteString, "https://github.com")
    }

    func test_record_capsAtMaxEntries() {
        // Arrange
        let service = makeService()

        // Act — record 105 entries
        for i in 0..<105 {
            service.record(url: URL(string: "https://site\(i).com")!, title: "Site \(i)")
        }

        // Assert — capped at 100
        XCTAssertEqual(service.entries.count, 100)
        // Most recent entry should be first
        XCTAssertEqual(service.entries[0].url.absoluteString, "https://site104.com")
    }

    func test_suggestions_filtersByQuery() {
        // Arrange
        let service = makeService()
        service.record(url: URL(string: "https://stackoverflow.com")!, title: "Stack Overflow")

        // Act
        let suggestions = service.suggestions(for: "stack")

        // Assert — only Stack Overflow matches
        XCTAssertTrue(suggestions.contains { $0.title == "Stack Overflow" })
        XCTAssertFalse(suggestions.contains { $0.url.absoluteString == "https://google.com" })
    }
}
