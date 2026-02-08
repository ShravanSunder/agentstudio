import XCTest
@testable import AgentStudio

final class TabTests: XCTestCase {

    // MARK: - Init

    func test_init_singleSession() {
        // Arrange
        let sessionId = UUID()

        // Act
        let tab = Tab(sessionId: sessionId)

        // Assert
        XCTAssertEqual(tab.sessionIds, [sessionId])
        XCTAssertEqual(tab.activeSessionId, sessionId)
        XCTAssertFalse(tab.isSplit)
    }

    func test_init_customId() {
        // Arrange
        let tabId = UUID()
        let sessionId = UUID()

        // Act
        let tab = Tab(id: tabId, sessionId: sessionId)

        // Assert
        XCTAssertEqual(tab.id, tabId)
    }

    func test_init_withLayout() {
        // Arrange
        let sessionA = UUID()
        let sessionB = UUID()
        let layout = Layout(sessionId: sessionA)
            .inserting(sessionId: sessionB, at: sessionA, direction: .horizontal, position: .after)

        // Act
        let tab = Tab(layout: layout, activeSessionId: sessionA)

        // Assert
        XCTAssertEqual(tab.sessionIds, [sessionA, sessionB])
        XCTAssertEqual(tab.activeSessionId, sessionA)
        XCTAssertTrue(tab.isSplit)
    }

    // MARK: - Derived Properties

    func test_sessionIds_matchesLayout() {
        // Arrange
        let sessionA = UUID()
        let sessionB = UUID()
        let sessionC = UUID()
        let layout = Layout(sessionId: sessionA)
            .inserting(sessionId: sessionB, at: sessionA, direction: .horizontal, position: .after)
            .inserting(sessionId: sessionC, at: sessionB, direction: .vertical, position: .after)

        // Act
        let tab = Tab(layout: layout, activeSessionId: sessionA)

        // Assert
        XCTAssertEqual(tab.sessionIds, [sessionA, sessionB, sessionC])
    }

    func test_isSplit_singleSession_false() {
        // Arrange
        let tab = Tab(sessionId: UUID())

        // Assert
        XCTAssertFalse(tab.isSplit)
    }

    func test_isSplit_multipleSessions_true() {
        // Arrange
        let sessionA = UUID()
        let sessionB = UUID()
        let layout = Layout(sessionId: sessionA)
            .inserting(sessionId: sessionB, at: sessionA, direction: .horizontal, position: .after)

        // Act
        let tab = Tab(layout: layout, activeSessionId: sessionA)

        // Assert
        XCTAssertTrue(tab.isSplit)
    }

    // MARK: - Codable Round-Trip

    func test_codable_singleSession_roundTrips() throws {
        // Arrange
        let sessionId = UUID()
        let tab = Tab(sessionId: sessionId)

        // Act
        let data = try JSONEncoder().encode(tab)
        let decoded = try JSONDecoder().decode(Tab.self, from: data)

        // Assert
        XCTAssertEqual(decoded.id, tab.id)
        XCTAssertEqual(decoded.sessionIds, [sessionId])
        XCTAssertEqual(decoded.activeSessionId, sessionId)
    }

    func test_codable_splitLayout_roundTrips() throws {
        // Arrange
        let sessionA = UUID()
        let sessionB = UUID()
        let layout = Layout(sessionId: sessionA)
            .inserting(sessionId: sessionB, at: sessionA, direction: .horizontal, position: .after)
        let tab = Tab(layout: layout, activeSessionId: sessionB)

        // Act
        let data = try JSONEncoder().encode(tab)
        let decoded = try JSONDecoder().decode(Tab.self, from: data)

        // Assert
        XCTAssertEqual(decoded.id, tab.id)
        XCTAssertEqual(decoded.sessionIds, [sessionA, sessionB])
        XCTAssertEqual(decoded.activeSessionId, sessionB)
        XCTAssertTrue(decoded.isSplit)
    }

    func test_codable_nilActiveSession_roundTrips() throws {
        // Arrange
        let tab = Tab(layout: Layout(), activeSessionId: nil)

        // Act
        let data = try JSONEncoder().encode(tab)
        let decoded = try JSONDecoder().decode(Tab.self, from: data)

        // Assert
        XCTAssertNil(decoded.activeSessionId)
    }

    // MARK: - Hashable

    func test_hashable_sameId_areEqual() {
        // Arrange
        let tabId = UUID()
        let sessionId = UUID()
        let tab1 = Tab(id: tabId, sessionId: sessionId)
        let tab2 = Tab(id: tabId, sessionId: sessionId)

        // Assert
        XCTAssertEqual(tab1, tab2)
    }
}
