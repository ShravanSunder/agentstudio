import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore

@MainActor
@Suite("AppDelegate persistence recovery")
struct AppDelegatePersistenceRecoveryTests {
    @Test("recovery diagnostics do not create or buffer retired Inbox notifications")
    func recoveryDiagnosticsDoNotCreateRetiredInboxNotifications() {
        let delegate = AppDelegate()
        delegate.atomStore = AtomRegistry()
        let notificationsBefore = delegate.atomStore.inboxNotification.notifications

        delegate.recordPersistenceRecovery(
            .init(
                store: .sidebarCache,
                workspaceId: UUID(),
                recovery: .quarantinedAndReset,
                quarantinedFilename: "workspace.sidebar-cache.corrupt.json"
            )
        )
        delegate.recordPersistenceRecovery(
            .init(store: .workspace, workspaceId: UUID(), recovery: .saveFailed)
        )

        #expect(delegate.atomStore.inboxNotification.notifications == notificationsBefore)
    }
}
