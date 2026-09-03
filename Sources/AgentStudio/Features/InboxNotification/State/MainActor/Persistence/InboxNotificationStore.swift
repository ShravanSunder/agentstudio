import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioSharedComponents
import Foundation
import os.log

private let inboxNotificationStoreLogger = Logger(
    subsystem: "com.agentstudio",
    category: "InboxNotificationStore"
)

/// Main-actor persistence wrapper for the notification inbox's typed local SQLite lane.
///
/// The atoms remain the live state owners. This store captures bounded immutable snapshots,
/// delegates database work to `WorkspaceSQLiteDatastore`, and applies restored values.
/// Inbox presentation and ingestion are intentionally retired.
/// Source and persisted rows remain only for a later data-safe removal.
/// Do not reconnect these owners to App, command, toolbar, shortcut, IPC, or runtime-bus composition without a new product decision.
@MainActor
package final class InboxNotificationStore {
    let inboxAtom: InboxNotificationAtom
    let prefsAtom: InboxNotificationPrefsAtom
    let sidebarState: InboxSidebarState

    private let delay: AsyncDelay
    private let debounceDuration: Duration
    private let recoveryReporter: PersistenceRecoveryReporter?
    private let sqliteAdapter: InboxNotificationSQLiteDatastoreAdapter
    private var debouncedSaveTask: Task<Void, Never>?

    package enum LoadOutcome: Equatable {
        case sqliteSnapshot
        case defaulted
    }

    struct SQLiteSnapshot: Equatable, Sendable {
        var notifications: [InboxNotification]
        var collapsedGroups: Set<InboxNotificationGroupKey>
    }

    package init(
        inboxAtom: InboxNotificationAtom,
        prefsAtom: InboxNotificationPrefsAtom,
        sidebarState: InboxSidebarState = .init(),
        clock: (any Clock<Duration> & Sendable)? = nil,
        debounceDuration: Duration = .milliseconds(500),
        recoveryReporter: PersistenceRecoveryReporter? = nil,
        sqliteAdapter: InboxNotificationSQLiteDatastoreAdapter
    ) {
        self.inboxAtom = inboxAtom
        self.prefsAtom = prefsAtom
        self.sidebarState = sidebarState
        delay = clock.map(AsyncDelay.clock) ?? .taskSleep
        self.debounceDuration = debounceDuration
        self.recoveryReporter = recoveryReporter
        self.sqliteAdapter = sqliteAdapter
    }

    @discardableResult
    package func loadAsync() async -> LoadOutcome {
        switch await sqliteAdapter.load() {
        case .loaded(let snapshot):
            apply(snapshot)
            return .sqliteSnapshot
        case .unavailable:
            applyDefaults()
            reportLoadFailed()
            return .defaulted
        }
    }

    package func save() async throws {
        cancelPendingDebouncedSave()
        try await persistCurrentSnapshot()
    }

    package func scheduleDebouncedSave() {
        debouncedSaveTask?.cancel()
        let delay = self.delay
        let debounceDuration = self.debounceDuration
        debouncedSaveTask = Task { [weak self, delay, debounceDuration] in
            do {
                try await delay.wait(debounceDuration)
            } catch is CancellationError {
                return
            } catch {
                inboxNotificationStoreLogger.error(
                    "Inbox notification debounce failed; saving immediately: \(error)"
                )
            }
            guard !Task.isCancelled, let self else { return }
            do {
                try await persistCurrentSnapshot()
            } catch {
                inboxNotificationStoreLogger.error("Inbox notification save failed: \(error)")
            }
        }
    }

    private func cancelPendingDebouncedSave() {
        debouncedSaveTask?.cancel()
        debouncedSaveTask = nil
    }

    private func persistCurrentSnapshot() async throws {
        let snapshot = SQLiteSnapshot(
            notifications: inboxAtom.notifications,
            collapsedGroups: sidebarState.collapsedGroups
        )
        do {
            try await sqliteAdapter.save(snapshot)
        } catch {
            reportSaveFailed()
            throw error
        }
    }

    private func apply(_ snapshot: SQLiteSnapshot) {
        inboxAtom.replaceAll(snapshot.notifications)
        sidebarState.hydrate(collapsedGroups: snapshot.collapsedGroups)
    }

    private func applyDefaults() {
        inboxAtom.replaceAll([])
        sidebarState.hydrate(collapsedGroups: [])
    }

    private func reportSaveFailed() {
        recoveryReporter?(
            .init(store: .notificationInbox, workspaceId: nil, recovery: .saveFailed)
        )
    }

    private func reportLoadFailed() {
        recoveryReporter?(
            .init(store: .notificationInbox, workspaceId: nil, recovery: .resetToDefaults)
        )
    }

}
