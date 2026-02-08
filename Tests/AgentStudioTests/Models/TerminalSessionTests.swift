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
        XCTAssertNotNil(session.containerId)
        XCTAssertEqual(session.title, "Terminal")
        XCTAssertNil(session.agent)
        XCTAssertEqual(session.provider, .ghostty)
        XCTAssertNil(session.providerHandle)
    }

    func test_init_customValues() {
        // Arrange
        let id = UUID()
        let containerId = UUID()
        let worktreeId = UUID()
        let repoId = UUID()

        // Act
        let session = TerminalSession(
            id: id,
            source: .worktree(worktreeId: worktreeId, repoId: repoId),
            containerId: containerId,
            title: "Feature",
            agent: .claude,
            provider: .tmux,
            providerHandle: "agentstudio--abc123"
        )

        // Assert
        XCTAssertEqual(session.id, id)
        XCTAssertEqual(session.containerId, containerId)
        XCTAssertEqual(session.title, "Feature")
        XCTAssertEqual(session.agent, .claude)
        XCTAssertEqual(session.provider, .tmux)
        XCTAssertEqual(session.providerHandle, "agentstudio--abc123")
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
            provider: .tmux,
            providerHandle: "tmux-session-1"
        )

        // Act
        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(TerminalSession.self, from: data)

        // Assert
        XCTAssertEqual(decoded.id, session.id)
        XCTAssertEqual(decoded.containerId, session.containerId)
        XCTAssertEqual(decoded.title, session.title)
        XCTAssertEqual(decoded.agent, session.agent)
        XCTAssertEqual(decoded.provider, session.provider)
        XCTAssertEqual(decoded.providerHandle, session.providerHandle)
        XCTAssertEqual(decoded.source, session.source)
    }

    func test_codable_floatingSession_roundTrips() throws {
        // Arrange
        let session = TerminalSession(
            source: .floating(workingDirectory: URL(fileURLWithPath: "/tmp"), title: "Scratch")
        )

        // Act
        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(TerminalSession.self, from: data)

        // Assert
        XCTAssertEqual(decoded.id, session.id)
        XCTAssertEqual(decoded.source, session.source)
        XCTAssertNil(decoded.agent)
        XCTAssertEqual(decoded.provider, .ghostty)
        XCTAssertNil(decoded.providerHandle)
    }

    // MARK: - Hashable

    func test_hashable_sameFields_areEqual() {
        // Arrange
        let id = UUID()
        let containerId = UUID()
        let session1 = TerminalSession(
            id: id,
            source: .floating(workingDirectory: nil, title: nil),
            containerId: containerId
        )
        let session2 = TerminalSession(
            id: id,
            source: .floating(workingDirectory: nil, title: nil),
            containerId: containerId
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
        let tmuxData = try JSONEncoder().encode(SessionProvider.tmux)

        let ghosttyDecoded = try JSONDecoder().decode(SessionProvider.self, from: ghosttyData)
        let tmuxDecoded = try JSONDecoder().decode(SessionProvider.self, from: tmuxData)

        // Assert
        XCTAssertEqual(ghosttyDecoded, .ghostty)
        XCTAssertEqual(tmuxDecoded, .tmux)
    }
}
