import Foundation

/// Fact emitted when a persisted file is reset or rebuilt after a load failure.
///
/// Stores report this without knowing how the app will surface it. The App
/// composition layer turns it into user-visible UI.
struct PersistenceRecoveryEvent: Sendable, Equatable {
    struct LocalStateResetSummary: Sendable, Equatable {
        let drawersCollapsed: Int
        let cursorsDefaulted: Int
    }

    enum Store: String, Sendable, Codable, Equatable {
        case workspace
        case repoCache
        case workspaceSettings
        case uiState
        case sidebarCache
        case notificationInbox
    }

    enum Recovery: String, Sendable, Codable, Equatable {
        case resetToDefaults
        case rebuiltFromEvents
        case quarantinedAndReset
        case quarantineFailed
        case localStateRebuilt
        case saveFailed
    }

    let store: Store
    let workspaceId: UUID?
    let recovery: Recovery
    let quarantinedFilename: String?
    let localStateResetSummary: LocalStateResetSummary?

    init(
        store: Store,
        workspaceId: UUID?,
        recovery: Recovery,
        quarantinedFilename: String? = nil,
        localStateResetSummary: LocalStateResetSummary? = nil
    ) {
        self.store = store
        self.workspaceId = workspaceId
        self.recovery = recovery
        self.quarantinedFilename = quarantinedFilename
        self.localStateResetSummary = localStateResetSummary
    }
}

typealias PersistenceRecoveryReporter = @MainActor (PersistenceRecoveryEvent) -> Void
