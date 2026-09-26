import Testing

@testable import AgentStudioCore

@Suite("KeyboardOwner")
struct KeyboardOwnerTests {
    @Test("different sidebar surfaces remain distinct owners")
    func differentSidebarSurfacesRemainDistinctOwners() {
        let inboxOwner = KeyboardOwner.sidebar(.inbox)
        let reposOwner = KeyboardOwner.sidebar(.repos)
        #expect(inboxOwner != reposOwner)
    }
}
