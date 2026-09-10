import AgentStudioCore
import AgentStudioInboxNotification
import AgentStudioTerminal
import Foundation
import Observation

extension AppDelegate {
    // Inbox presentation and ingestion are intentionally retired. Source and
    // persisted rows remain only for a later data-safe removal. Do not reconnect
    // these owners to App, command, toolbar, shortcut, IPC, or runtime-bus composition.
    func bootLoadInboxNotificationStore() async {
        let workspaceId = store.identityAtom.workspaceId
        guard let workspaceSQLiteDatastore else {
            preconditionFailure("workspace SQLite datastore unavailable during inbox boot")
        }
        let sqliteAdapter = InboxNotificationSQLiteDatastoreAdapter(
            workspaceId: workspaceId,
            datastore: workspaceSQLiteDatastore
        )
        inboxNotificationStore = InboxNotificationStore(
            inboxAtom: atomStore.inboxNotification,
            prefsAtom: atomStore.inboxNotificationPrefs,
            sidebarState: atomStore.inboxSidebarState,
            recoveryReporter: { [weak self] event in
                self?.recordPersistenceRecovery(event)
            },
            sqliteAdapter: sqliteAdapter
        )
        _ = await inboxNotificationStore.loadAsync()
        observeInboxNotificationPersistence()
    }

    func bootStartInboxNotificationRouter(bus: EventBus<RuntimeEnvelope>) {
        inboxPaneFocusTracker = PaneFocusTracker(
            attendedPane: atomStore.core.attendedPane,
            traceRuntime: traceRuntime
        )
        let terminalActivity = atomStore.terminalActivity
        inboxNotificationRouter = InboxNotificationRouter(
            bus: bus,
            inboxAtom: atomStore.inboxNotification,
            prefsAtom: atomStore.inboxNotificationPrefs,
            paneAtom: store.paneAtom,
            tabLayout: store.tabLayoutAtom,
            attendedPane: atomStore.core.attendedPane,
            focusTracker: inboxPaneFocusTracker,
            terminalIsPinnedToBottom: { paneId in
                terminalActivity.snapshot(for: paneId)?.isPinnedToBottom == true
            },
            terminalPinnedStateSnapshot: {
                Dictionary(
                    uniqueKeysWithValues: terminalActivity.snapshotsByPaneId.map { paneId, snapshot in
                        (paneId, snapshot.isPinnedToBottom)
                    }
                )
            },
            traceRuntime: traceRuntime,
            onPaneActivityObserved: { [weak self] paneId in
                self?.terminalActivityRouter.markUnseenActivityObserved(paneId: paneId)
            }
        )
        Task { @MainActor [weak self] in
            await self?.inboxNotificationRouter.start()
        }
    }

    private func observeInboxNotificationPersistence() {
        withObservationTracking {
            _ = atomStore.inboxNotification.notifications
            _ = atomStore.inboxSidebarState.collapsedGroups
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.inboxNotificationStore.scheduleDebouncedSave()
                self.observeInboxNotificationPersistence()
            }
        }
    }

    func recordPersistenceRecovery(_ event: PersistenceRecoveryEvent) {
        appLogger.warning(
            "Persistence recovery: store=\(event.store.rawValue) recovery=\(event.recovery.rawValue)"
        )
    }

    private func appendPersistenceRecoveryNotificationIfNeeded(for event: PersistenceRecoveryEvent) {
        let notification = InboxNotification.persistenceRecovery(event)
        let alreadyHasUnreadMatchingNotification = atomStore.inboxNotification.notifications.contains { existing in
            existing.kind == .persistenceRecovery
                && existing.title == notification.title
                && existing.body == notification.body
                && !existing.isRead
                && !existing.isDismissedFromPaneInbox
        }
        guard !alreadyHasUnreadMatchingNotification else { return }
        atomStore.inboxNotification.append(notification)
    }

}
