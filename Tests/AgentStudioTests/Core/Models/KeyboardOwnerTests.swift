import Testing

@testable import AgentStudio

@Suite("KeyboardOwner")
struct KeyboardOwnerTests {
    @Test("equality across cases")
    func equality() {
        let otherWindow = KeyboardOwner.otherWindow
        let managementLayer = KeyboardOwner.managementLayer
        let inboxOwner = KeyboardOwner.sidebar(.inbox)
        let reposOwner = KeyboardOwner.sidebar(.repos)
        let mainWindowChain = KeyboardOwner.mainWindowChain

        #expect(otherWindow == KeyboardOwner.otherWindow)
        #expect(managementLayer == KeyboardOwner.managementLayer)
        #expect(inboxOwner == KeyboardOwner.sidebar(.inbox))
        #expect(reposOwner == KeyboardOwner.sidebar(.repos))
        #expect(mainWindowChain == KeyboardOwner.mainWindowChain)

        #expect(inboxOwner != reposOwner)
        #expect(otherWindow != managementLayer)
        #expect(mainWindowChain != inboxOwner)
    }

    @Test("pattern matches .sidebar with associated surface")
    func patternMatchSidebar() {
        let owner = KeyboardOwner.sidebar(.inbox)

        switch owner {
        case .sidebar(let surface):
            #expect(surface == .inbox)
        default:
            Issue.record("expected .sidebar case")
        }
    }
}
