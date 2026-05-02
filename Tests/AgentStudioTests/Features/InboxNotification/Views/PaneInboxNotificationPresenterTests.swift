import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("PaneInboxNotificationPresenter")
struct PaneInboxNotificationPresenterTests {
    @Test("open request stores pane ids")
    func openRequestStoresPaneIds() {
        let presenter = PaneInboxNotificationPresenter()
        let parentPaneId = UUID()
        let paneIds = [UUID(), UUID()]

        presenter.open(parentPaneId: parentPaneId, paneIds: paneIds)

        #expect(presenter.request?.parentPaneId == parentPaneId)
        #expect(presenter.request?.paneIds == paneIds)
        #expect(presenter.request?.intent == .open)
    }

    @Test("toggle closes the same pane inbox target")
    func toggleSamePendingTargetClearsRequest() {
        let presenter = PaneInboxNotificationPresenter()
        let parentPaneId = UUID()
        let childPaneId = UUID()

        presenter.toggle(parentPaneId: parentPaneId, paneIds: [parentPaneId, childPaneId])
        #expect(presenter.request?.parentPaneId == parentPaneId)

        presenter.toggle(parentPaneId: parentPaneId, paneIds: [parentPaneId, childPaneId])
        #expect(presenter.request == nil)
    }

    @Test("toggle sends close request for an already presented target")
    func togglePresentedTargetSendsCloseRequest() {
        let presenter = PaneInboxNotificationPresenter()
        let parentPaneId = UUID()
        let childPaneId = UUID()
        let paneIds = [parentPaneId, childPaneId]

        presenter.setPresented(parentPaneId: parentPaneId, paneIds: paneIds, isPresented: true)
        presenter.toggle(parentPaneId: parentPaneId, paneIds: paneIds)

        #expect(presenter.request?.parentPaneId == parentPaneId)
        #expect(presenter.request?.paneIds == paneIds)
        #expect(presenter.request?.intent == .close)
    }

    @Test("dismissed target can be opened again")
    func dismissedTargetCanBeOpenedAgain() {
        let presenter = PaneInboxNotificationPresenter()
        let parentPaneId = UUID()
        let paneIds = [parentPaneId]

        presenter.setPresented(parentPaneId: parentPaneId, paneIds: paneIds, isPresented: true)
        presenter.setPresented(parentPaneId: parentPaneId, paneIds: paneIds, isPresented: false)
        presenter.toggle(parentPaneId: parentPaneId, paneIds: paneIds)

        #expect(presenter.request?.intent == .open)
    }

    @Test("toggle replaces a different pane inbox target")
    func toggleDifferentTargetReplaces() {
        let presenter = PaneInboxNotificationPresenter()
        let firstParentPaneId = UUID()
        let secondParentPaneId = UUID()

        presenter.toggle(parentPaneId: firstParentPaneId, paneIds: [firstParentPaneId])
        presenter.toggle(parentPaneId: secondParentPaneId, paneIds: [secondParentPaneId])

        #expect(presenter.request?.parentPaneId == secondParentPaneId)
        #expect(presenter.request?.paneIds == [secondParentPaneId])
    }
}
