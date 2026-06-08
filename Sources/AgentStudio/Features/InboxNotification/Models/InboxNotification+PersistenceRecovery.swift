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
        if recovery == .saveFailed {
            return saveFailureNotificationTitle
        }
        if recovery == .localStateRebuilt {
            return "Workspace local state rebuilt"
        }

        return switch store {
        case .workspace:
            "Workspace reset"
        case .repoCache:
            "Repository cache rebuilt"
        case .workspaceSettings:
            "Workspace settings reset"
        case .uiState:
            "UI state reset"
        case .sidebarCache:
            "Sidebar cache reset"
        case .notificationInbox:
            "Notification inbox reset"
        }
    }

    private var saveFailureNotificationTitle: String {
        switch store {
        case .workspace:
            "Workspace save failed"
        case .repoCache:
            "Repository cache save failed"
        case .workspaceSettings:
            "Workspace settings save failed"
        case .uiState:
            "UI state save failed"
        case .sidebarCache:
            "Sidebar cache save failed"
        case .notificationInbox:
            "Notification inbox save failed"
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
            case .quarantineFailed:
                "The saved file could not be loaded, and moving it aside failed. Defaults were used."
            case .localStateRebuilt:
                "The workspace graph was restored, but local focus and window state were rebuilt."
            case .saveFailed:
                "The app could not save this state file. Recent changes may not be restored after restart."
            }

        var details: [String] = []
        if let workspaceId {
            details.append("Workspace: \(workspaceId.uuidString)")
        }
        if let quarantinedFilename {
            details.append("Quarantined file: \(quarantinedFilename)")
        }
        guard !details.isEmpty else { return action }
        return "\(action) \(details.joined(separator: " "))"
    }
}
