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
    }

    @Test("toggle closes the same pane inbox target")
    func toggleSameTargetCloses() {
        let presenter = PaneInboxNotificationPresenter()
        let parentPaneId = UUID()
        let childPaneId = UUID()

        presenter.toggle(parentPaneId: parentPaneId, paneIds: [parentPaneId, childPaneId])
        #expect(presenter.request?.parentPaneId == parentPaneId)

        presenter.toggle(parentPaneId: parentPaneId, paneIds: [parentPaneId, childPaneId])
        #expect(presenter.request == nil)
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
