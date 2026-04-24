import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("InboxFilterDraftAtom")
struct InboxFilterDraftAtomTests {
    @Test("consume returns pending filter once")
    func consumeReturnsPendingFilterOnce() {
        let atom = InboxFilterDraftAtom()
        let filter = InboxFilter.worktree(id: UUID())

        atom.set(filter)

        #expect(atom.consume() == filter)
        #expect(atom.consume() == nil)
    }
}
