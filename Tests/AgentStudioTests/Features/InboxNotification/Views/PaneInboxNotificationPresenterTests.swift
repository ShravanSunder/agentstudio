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
}
