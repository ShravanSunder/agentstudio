import Foundation
import Observation

extension AppDelegate {
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
        hasLoadedInboxNotificationStore = true
        flushPersistenceRecoveryNotifications()
    }

    func bootStartInboxNotificationRouter(bus: EventBus<RuntimeEnvelope>) {
        inboxPaneFocusTracker = PaneFocusTracker(
            attendedPane: atomStore.attendedPane,
            traceRuntime: traceRuntime
        )
        inboxNotificationRouter = InboxNotificationRouter(
            bus: bus,
            inboxAtom: atomStore.inboxNotification,
            prefsAtom: atomStore.inboxNotificationPrefs,
            paneAtom: store.paneAtom,
            tabLayout: store.tabLayoutAtom,
            attendedPane: atomStore.attendedPane,
            focusTracker: inboxPaneFocusTracker,
            terminalActivity: atomStore.terminalActivity,
            traceRuntime: traceRuntime,
            onPaneActivityObserved: { [weak self] paneId in
                self?.terminalActivityRouter.markUnseenActivityObserved(paneId: paneId)
            }
        )
        Task { @MainActor [weak self] in
            await self?.inboxNotificationRouter.start()
        }
    }

    func bootStartTerminalActivityRouter(bus: EventBus<RuntimeEnvelope>) {
        terminalActivityRouter = TerminalActivityRouter(
            bus: bus,
            activityAtom: atomStore.terminalActivity,
            attendedPane: atomStore.attendedPane,
            traceRuntime: traceRuntime,
            startupTraceRecorder: startupTraceRecorder,
            isPaneCurrentlyAttended: { [weak self] paneId in
                self?.isPaneCurrentlyAttendedForNotifications(paneId) ?? false
            },
            isPaneAgentClassified: { [weak self] paneId, paneKind in
                if paneKind == .agent { return true }
                return self?.store.paneAtom.pane(paneId)?.metadata.contentType == .agent
            }
        )
        Task { @MainActor [weak self] in
            await self?.terminalActivityRouter.start()
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
        guard hasLoadedInboxNotificationStore else {
            pendingPersistenceRecoveryEvents.append(event)
            return
        }
        appendPersistenceRecoveryNotificationIfNeeded(for: event)
    }

    func flushPersistenceRecoveryNotifications() {
        guard hasLoadedInboxNotificationStore else { return }
        let pendingEvents = pendingPersistenceRecoveryEvents
        pendingPersistenceRecoveryEvents.removeAll()
        for event in pendingEvents {
            appendPersistenceRecoveryNotificationIfNeeded(for: event)
        }
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

    private func isPaneCurrentlyAttendedForNotifications(_ paneId: UUID) -> Bool {
        PaneObservationResolver.isPaneCurrentlyAttended(
            paneId: paneId,
            attendedPaneId: atomStore.attendedPane.attendedPaneId,
            pane: { store.paneAtom.pane($0) }
        )
    }
}
