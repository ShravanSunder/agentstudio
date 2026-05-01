import Foundation

extension InboxNotification {
    static func persistenceRecovery(_ event: PersistenceRecoveryEvent) -> InboxNotification {
        InboxNotification(
            id: UUID(),
            timestamp: Date(),
            kind: .persistenceRecovery,
            title: event.notificationTitle,
            body: event.notificationBody,
            source: .global,
            isRead: false,
            isDismissedFromPaneInbox: false
        )
    }
}

extension PersistenceRecoveryEvent {
    fileprivate var notificationTitle: String {
        switch store {
        case .workspace:
            "Workspace reset"
        case .repoCache:
            "Repository cache rebuilt"
        case .uiState:
            "UI state reset"
        case .sidebarCache:
            "Sidebar cache reset"
        case .notificationInbox:
            "Notification inbox reset"
        }
    }

    fileprivate var notificationBody: String {
        let action =
            switch recovery {
            case .resetToDefaults:
                "The saved file could not be loaded, so defaults were used."
            case .rebuiltFromEvents:
                "The saved cache could not be loaded, so it will rebuild from runtime events."
            case .quarantinedAndReset:
                "The saved file could not be loaded, so it was moved aside and defaults were used."
            }

        guard let quarantinedFilename else { return action }
        return "\(action) Quarantined file: \(quarantinedFilename)"
    }
}
