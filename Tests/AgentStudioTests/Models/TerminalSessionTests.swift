import XCTest
@testable import AgentStudio

final class TerminalSessionTests: XCTestCase {

    // MARK: - Init

    func test_init_defaults() {
        // Arrange
        let source = TerminalSource.floating(workingDirectory: nil, title: "Test")

        // Act
        let session = TerminalSession(source: source)

        // Assert
        XCTAssertNotNil(session.id)
        XCTAssertEqual(session.title, "Terminal")
        XCTAssertNil(session.agent)
        XCTAssertEqual(session.provider, .ghostty)
        XCTAssertEqual(session.lifetime, .persistent)
        XCTAssertEqual(session.residency, .active)
    }

    func test_init_customValues() {
        // Arrange
        let id = UUID()
        let worktreeId = UUID()
        let repoId = UUID()

        // Act
        let session = TerminalSession(
            id: id,
            source: .worktree(worktreeId: worktreeId, repoId: repoId),
            title: "Feature",
            agent: .claude,
            provider: .zmx,
            lifetime: .temporary,
            residency: .backgrounded
        )

        // Assert
        XCTAssertEqual(session.id, id)
        XCTAssertEqual(session.title, "Feature")
        XCTAssertEqual(session.agent, .claude)
        XCTAssertEqual(session.provider, .zmx)
        XCTAssertEqual(session.lifetime, .temporary)
        XCTAssertEqual(session.residency, .backgrounded)
    }

    // MARK: - Convenience Accessors

    func test_worktreeId_worktreeSource_returnsId() {
        // Arrange
        let worktreeId = UUID()
        let session = TerminalSession(
            source: .worktree(worktreeId: worktreeId, repoId: UUID())
        )

        // Assert
        XCTAssertEqual(session.worktreeId, worktreeId)
    }

    func test_worktreeId_floatingSource_returnsNil() {
        // Arrange
        let session = TerminalSession(
            source: .floating(workingDirectory: nil, title: nil)
        )

        // Assert
        XCTAssertNil(session.worktreeId)
    }

    func test_repoId_worktreeSource_returnsId() {
        // Arrange
        let repoId = UUID()
        let session = TerminalSession(
            source: .worktree(worktreeId: UUID(), repoId: repoId)
        )

        // Assert
        XCTAssertEqual(session.repoId, repoId)
    }

    func test_repoId_floatingSource_returnsNil() {
        // Arrange
        let session = TerminalSession(
            source: .floating(workingDirectory: nil, title: nil)
        )

        // Assert
        XCTAssertNil(session.repoId)
    }

    // MARK: - Codable Round-Trip

    func test_codable_worktreeSession_roundTrips() throws {
        // Arrange
        let session = TerminalSession(
            source: .worktree(worktreeId: UUID(), repoId: UUID()),
            title: "Main",
            agent: .claude,
            provider: .zmx,
            lifetime: .persistent,
            residency: .active
        )

        // Act
        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(TerminalSession.self, from: data)

        // Assert
        XCTAssertEqual(decoded.id, session.id)
        XCTAssertEqual(decoded.title, session.title)
        XCTAssertEqual(decoded.agent, session.agent)
        XCTAssertEqual(decoded.provider, session.provider)
        XCTAssertEqual(decoded.lifetime, session.lifetime)
        XCTAssertEqual(decoded.residency, session.residency)
        XCTAssertEqual(decoded.source, session.source)
    }

    func test_codable_floatingSession_roundTrips() throws {
        // Arrange
        let session = TerminalSession(
            source: .floating(workingDirectory: URL(fileURLWithPath: "/tmp"), title: "Scratch"),
            lifetime: .temporary
        )

        // Act
        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(TerminalSession.self, from: data)

        // Assert
        XCTAssertEqual(decoded.id, session.id)
        XCTAssertEqual(decoded.source, session.source)
        XCTAssertNil(decoded.agent)
        XCTAssertEqual(decoded.provider, .ghostty)
        XCTAssertEqual(decoded.lifetime, .temporary)
        XCTAssertEqual(decoded.residency, .active)
    }

    func test_codable_pendingUndo_roundTrips() throws {
        // Arrange
        let expiresAt = Date(timeIntervalSince1970: 2_000_000)
        let session = TerminalSession(
            source: .floating(workingDirectory: nil, title: nil),
            residency: .pendingUndo(expiresAt: expiresAt)
        )

        // Act
        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(TerminalSession.self, from: data)

        // Assert
        XCTAssertEqual(decoded.residency, .pendingUndo(expiresAt: expiresAt))
    }

    // MARK: - lastKnownCWD

    func test_init_lastKnownCWD_defaultsToNil() {
        // Act
        let session = TerminalSession(source: .floating(workingDirectory: nil, title: nil))

        // Assert
        XCTAssertNil(session.lastKnownCWD)
    }

    func test_init_lastKnownCWD_acceptsExplicitValue() {
        // Arrange
        let cwd = URL(fileURLWithPath: "/Users/test/projects")

        // Act
        let session = TerminalSession(
            source: .floating(workingDirectory: nil, title: nil),
            lastKnownCWD: cwd
        )

        // Assert
        XCTAssertEqual(session.lastKnownCWD, cwd)
    }

    func test_codable_lastKnownCWD_roundTrips() throws {
        // Arrange
        let cwd = URL(fileURLWithPath: "/tmp/workspace")
        let session = TerminalSession(
            source: .worktree(worktreeId: UUID(), repoId: UUID()),
            lastKnownCWD: cwd
        )

        // Act
        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(TerminalSession.self, from: data)

        // Assert
        XCTAssertEqual(decoded.lastKnownCWD, cwd)
    }

    func test_codable_lastKnownCWD_nil_roundTrips() throws {
        // Arrange
        let session = TerminalSession(
            source: .floating(workingDirectory: nil, title: nil),
            lastKnownCWD: nil
        )

        // Act
        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(TerminalSession.self, from: data)

        // Assert
        XCTAssertNil(decoded.lastKnownCWD)
    }

    func test_codable_backwardCompat_missingLastKnownCWD_decodesAsNil() throws {
        // Arrange — simulate old persisted JSON without lastKnownCWD field
        let oldJson = """
        {
            "id": "11111111-1111-1111-1111-111111111111",
            "source": {"floating": {"title": "Test"}},
            "title": "Terminal",
            "provider": "ghostty",
            "lifetime": "persistent",
            "residency": {"active": {}}
        }
        """
        let data = oldJson.data(using: .utf8)!

        // Act
        let decoded = try JSONDecoder().decode(TerminalSession.self, from: data)

        // Assert
        XCTAssertNil(decoded.lastKnownCWD)
        XCTAssertEqual(decoded.title, "Terminal")
    }

    // MARK: - Hashable

    func test_hashable_sameFields_areEqual() {
        // Arrange
        let id = UUID()
        let session1 = TerminalSession(
            id: id,
            source: .floating(workingDirectory: nil, title: nil)
        )
        let session2 = TerminalSession(
            id: id,
            source: .floating(workingDirectory: nil, title: nil)
        )

        // Assert
        XCTAssertEqual(session1, session2)
    }

    func test_hashable_differentId_areNotEqual() {
        // Arrange
        let session1 = TerminalSession(
            source: .floating(workingDirectory: nil, title: nil)
        )
        let session2 = TerminalSession(
            source: .floating(workingDirectory: nil, title: nil)
        )

        // Assert
        XCTAssertNotEqual(session1, session2)
    }

    // MARK: - SessionProvider

    func test_sessionProvider_codable_roundTrips() throws {
        // Act
        let ghosttyData = try JSONEncoder().encode(SessionProvider.ghostty)
        let zmxData = try JSONEncoder().encode(SessionProvider.zmx)

        let ghosttyDecoded = try JSONDecoder().decode(SessionProvider.self, from: ghosttyData)
        let zmxDecoded = try JSONDecoder().decode(SessionProvider.self, from: zmxData)

        // Assert
        XCTAssertEqual(ghosttyDecoded, .ghostty)
        XCTAssertEqual(zmxDecoded, .zmx)
    }

    func test_sessionProvider_codable_zmx_roundTrips() throws {
        // Act
        let data = try JSONEncoder().encode(SessionProvider.zmx)
        let decoded = try JSONDecoder().decode(SessionProvider.self, from: data)

        // Assert
        XCTAssertEqual(decoded, .zmx)
        XCTAssertEqual(String(data: data, encoding: .utf8), "\"zmx\"")
    }
}
