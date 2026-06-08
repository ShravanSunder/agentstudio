import Foundation
import Testing

@testable import AgentStudio

@Suite("Inbox notification persistence recovery")
struct InboxNotificationPersistenceRecoveryTests {
    @Test("factory creates visible global recovery notification")
    func factoryCreatesVisibleGlobalRecoveryNotification() {
        let workspaceId = UUID()
        let event = PersistenceRecoveryEvent(
            store: .sidebarCache,
            workspaceId: workspaceId,
            recovery: .quarantinedAndReset,
            quarantinedFilename: "workspace.sidebar-cache.corrupt.json"
        )

        let notification = InboxNotification.persistenceRecovery(event)

        #expect(notification.kind == .persistenceRecovery)
        #expect(notification.source == .global)
        #expect(notification.title == "Sidebar cache reset")
        #expect(notification.body?.contains(workspaceId.uuidString) == true)
        #expect(notification.body?.contains("workspace.sidebar-cache.corrupt.json") == true)
        #expect(notification.isRead == false)
        #expect(notification.isDismissedFromPaneInbox == false)
    }

    @Test("factory describes save and quarantine failures")
    func factoryDescribesSaveAndQuarantineFailures() {
        let saveFailed = InboxNotification.persistenceRecovery(
            .init(store: .notificationInbox, workspaceId: nil, recovery: .saveFailed)
        )
        let quarantineFailed = InboxNotification.persistenceRecovery(
            .init(store: .workspace, workspaceId: nil, recovery: .quarantineFailed)
        )

        #expect(saveFailed.body?.contains("could not save") == true)
        #expect(quarantineFailed.body?.contains("moving it aside failed") == true)
    }

    @Test("workspace save failure is not titled as workspace reset")
    func workspaceSaveFailureIsNotTitledAsWorkspaceReset() {
        let notification = InboxNotification.persistenceRecovery(
            .init(store: .workspace, workspaceId: UUID(), recovery: .saveFailed)
        )

        #expect(notification.title == "Workspace save failed")
        #expect(notification.title != "Workspace reset")
        #expect(notification.body?.contains("could not save") == true)
    }

    @Test("workspace staged recovery is described as local state rebuild")
    func workspaceStagedRecoveryIsDescribedAsLocalStateRebuild() {
        let workspaceId = UUID()
        let notification = InboxNotification.persistenceRecovery(
            .init(store: .workspace, workspaceId: workspaceId, recovery: .localStateRebuilt)
        )

        #expect(notification.title == "Workspace local state rebuilt")
        #expect(notification.body?.contains("workspace graph was restored") == true)
        #expect(notification.body?.contains(workspaceId.uuidString) == true)
    }
}
