import Foundation
import Testing

@testable import AgentStudio

@Suite("InboxFilter")
struct InboxFilterTests {
    @Test("codable preserves filter variant and id")
    func codablePreservesFilterVariantAndId() throws {
        let worktreeId = UUID()
        let encoded = try JSONEncoder().encode(InboxFilter.worktree(id: worktreeId))
        let decoded = try JSONDecoder().decode(InboxFilter.self, from: encoded)

        #expect(decoded == .worktree(id: worktreeId))
    }
}
