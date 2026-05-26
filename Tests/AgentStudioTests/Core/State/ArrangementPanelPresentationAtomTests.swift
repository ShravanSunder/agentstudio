import Foundation
import Testing

@testable import AgentStudio

@Suite("ArrangementPanelPresentationAtom")
@MainActor
struct ArrangementPanelPresentationAtomTests {
    @Test("present creates one-shot request scoped to window and tab")
    func presentCreatesOneShotRequest() {
        let atom = ArrangementPanelPresentationAtom()
        let windowId = UUID()
        let tabId = UUID()

        let request = atom.present(tabId: tabId, workspaceWindowId: windowId)

        #expect(atom.pendingRequest?.id == request.id)
        #expect(atom.pendingRequest?.tabId == tabId)
        #expect(atom.pendingRequest?.workspaceWindowId == windowId)
    }

    @Test("consume only clears matching request")
    func consumeOnlyClearsMatchingRequest() {
        let atom = ArrangementPanelPresentationAtom()
        let request = atom.present(tabId: UUID(), workspaceWindowId: UUID())

        atom.consume(ArrangementPanelPresentationRequest(tabId: UUID(), workspaceWindowId: UUID()))
        #expect(atom.pendingRequest?.id == request.id)

        atom.consume(request)
        #expect(atom.pendingRequest == nil)
    }
}
