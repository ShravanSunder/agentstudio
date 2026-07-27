import Foundation

/// Fact emitted when a persisted file is reset or rebuilt after a load failure.
///
/// Stores report this without knowing how the app will surface it. The App
/// composition layer turns it into user-visible UI.
package struct PersistenceRecoveryEvent: Sendable, Equatable {
    package enum Store: String, Sendable, Codable, Equatable {
        case workspace
        case repoCache
        case workspaceSettings
        case uiState
        case sidebarCache
        case notificationInbox
    }

    package enum Recovery: String, Sendable, Codable, Equatable {
        case resetToDefaults
        case rebuiltFromEvents
        case quarantinedAndReset
        case quarantineFailed
        case localStateRebuilt
        case saveFailed
    }

    package let store: Store
    package let workspaceId: UUID?
    package let recovery: Recovery
    package let quarantinedFilename: String?

    package init(
        store: Store,
        workspaceId: UUID?,
        recovery: Recovery,
        quarantinedFilename: String? = nil
    ) {
        self.store = store
        self.workspaceId = workspaceId
        self.recovery = recovery
        self.quarantinedFilename = quarantinedFilename
    }
}

package typealias PersistenceRecoveryReporter = @MainActor (PersistenceRecoveryEvent) -> Void
