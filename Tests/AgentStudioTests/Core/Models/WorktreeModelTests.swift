import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
final class WorktreeModelTests {

    // MARK: - Worktree Codable

    @Test

    func test_worktree_codable_roundTrip() throws {
        // Arrange
        let original = makeWorktree(
            name: "feature-x"
        )

        // Act
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Worktree.self, from: data)

        // Assert
        #expect(decoded.id == original.id)
        #expect(decoded.name == original.name)
        #expect(decoded.repoId == original.repoId)
    }

    @Test

    func test_worktree_codable_defaultValues_roundTrip() throws {
        // Arrange
        let original = makeWorktree()

        // Act
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Worktree.self, from: data)

        // Assert
        #expect(decoded.id == original.id)
        #expect(decoded.repoId == original.repoId)
        #expect(decoded.name == original.name)
        #expect(decoded.path == original.path)
        #expect(decoded.isMainWorktree == original.isMainWorktree)
    }

    // MARK: - Strict Decode

    @Test
    func decode_missingRepoId_throws() throws {
        // Arrange — JSON with no repoId key
        let json = """
            {"id":"11111111-1111-1111-1111-111111111111","name":"main","path":"/tmp/repo","isMainWorktree":true}
            """
        let data = Data(json.utf8)

        // Act & Assert — decoder must reject missing repoId
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Worktree.self, from: data)
        }
    }

    @Test
    func decode_missingIsMainWorktree_throws() throws {
        // Arrange — JSON with no isMainWorktree key
        let json = """
            {"id":"11111111-1111-1111-1111-111111111111","repoId":"22222222-2222-2222-2222-222222222222","name":"main","path":"/tmp/repo"}
            """
        let data = Data(json.utf8)

        // Act & Assert — decoder must reject missing isMainWorktree
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Worktree.self, from: data)
        }
    }

    // MARK: - Worktree Hashable

    @Test

    func test_worktree_hashable_differentFieldsNotEqual() {
        // Arrange
        let id = UUID()
        let wt1 = makeWorktree(id: id, name: "a")
        let wt2 = makeWorktree(id: id, name: "b")

        // Assert
        #expect(wt1 != wt2)
    }

    // MARK: - Worktree Init Defaults

    @Test

    func test_worktree_init_defaults() {
        // Act
        let wt = Worktree(repoId: UUID(), name: "test", path: URL(fileURLWithPath: "/tmp/test"))

        // Assert
        #expect(wt.isMainWorktree == false)
    }
}
