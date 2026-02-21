import Testing
import Foundation

@testable import AgentStudio

@Suite(.serialized)
final class TerminalSourceTests {

    // MARK: - Equatable

    @Test

    func test_worktreeSource_sameIds_equal() {
        // Arrange
        let wtId = UUID()
        let repoId = UUID()
        let s1 = TerminalSource.worktree(worktreeId: wtId, repoId: repoId)
        let s2 = TerminalSource.worktree(worktreeId: wtId, repoId: repoId)

        // Assert
        #expect(s1 == s2)
    }

    @Test

    func test_worktreeSource_differentIds_notEqual() {
        // Arrange
        let s1 = TerminalSource.worktree(worktreeId: UUID(), repoId: UUID())
        let s2 = TerminalSource.worktree(worktreeId: UUID(), repoId: UUID())

        // Assert
        #expect(s1 != s2)
    }

    @Test

    func test_floatingSource_sameValues_equal() {
        // Arrange
        let dir = URL(fileURLWithPath: "/tmp/test")
        let s1 = TerminalSource.floating(workingDirectory: dir, title: "My Terminal")
        let s2 = TerminalSource.floating(workingDirectory: dir, title: "My Terminal")

        // Assert
        #expect(s1 == s2)
    }

    @Test

    func test_floatingSource_differentTitles_notEqual() {
        // Arrange
        let s1 = TerminalSource.floating(workingDirectory: nil, title: "A")
        let s2 = TerminalSource.floating(workingDirectory: nil, title: "B")

        // Assert
        #expect(s1 != s2)
    }

    @Test

    func test_worktreeAndFloating_notEqual() {
        // Arrange
        let s1 = TerminalSource.worktree(worktreeId: UUID(), repoId: UUID())
        let s2 = TerminalSource.floating(workingDirectory: nil, title: nil)

        // Assert
        #expect(s1 != s2)
    }

    // MARK: - Hashable

    @Test

    func test_worktreeSource_hashable_sameIds_sameHash() {
        // Arrange
        let wtId = UUID()
        let repoId = UUID()
        let s1 = TerminalSource.worktree(worktreeId: wtId, repoId: repoId)
        let s2 = TerminalSource.worktree(worktreeId: wtId, repoId: repoId)

        // Assert
        #expect(s1.hashValue == s2.hashValue)
    }

    @Test

    func test_source_usableInSet() {
        // Arrange
        let wtId = UUID()
        let repoId = UUID()
        let source = TerminalSource.worktree(worktreeId: wtId, repoId: repoId)

        // Act
        var set: Set<TerminalSource> = []
        set.insert(source)
        set.insert(source)  // duplicate

        // Assert
        #expect(set.count == 1)
    }

    // MARK: - Codable

    @Test

    func test_worktreeSource_codable_roundTrip() throws {
        // Arrange
        let wtId = UUID()
        let repoId = UUID()
        let original = TerminalSource.worktree(worktreeId: wtId, repoId: repoId)

        // Act
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TerminalSource.self, from: data)

        // Assert
        #expect(decoded == original)
    }

    @Test

    func test_floatingSource_codable_roundTrip() throws {
        // Arrange
        let dir = URL(fileURLWithPath: "/Users/test/Documents")
        let original = TerminalSource.floating(workingDirectory: dir, title: "Dev Shell")

        // Act
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TerminalSource.self, from: data)

        // Assert
        #expect(decoded == original)
    }

    @Test

    func test_floatingSource_codable_nilValues_roundTrip() throws {
        // Arrange
        let original = TerminalSource.floating(workingDirectory: nil, title: nil)

        // Act
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TerminalSource.self, from: data)

        // Assert
        #expect(decoded == original)
    }
}
