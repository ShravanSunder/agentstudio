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

        #expect(atom.peek() == filter)
        #expect(atom.consume() == filter)
        #expect(atom.peek() == nil)
        #expect(atom.consume() == nil)
    }

    @Test("clear removes the pending one-shot filter")
    func clearRemovesPendingFilter() {
        let atom = InboxFilterDraftAtom()
        atom.set(.repo(id: UUID()))

        atom.clear()

        #expect(atom.peek() == nil)
    }
}
