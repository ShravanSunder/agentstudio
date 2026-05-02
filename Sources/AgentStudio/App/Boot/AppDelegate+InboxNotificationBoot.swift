import Foundation
import Observation

extension AppDelegate {
    func bootLoadInboxNotificationStore(persistor: WorkspacePersistor) {
        let fileURL = persistor.notificationInboxFileURL(for: store.metadataAtom.workspaceId)
        inboxNotificationStore = InboxNotificationStore(
            inboxAtom: inboxNotificationAtom,
            prefsAtom: inboxNotificationPrefsAtom,
            fileURL: fileURL,
            recoveryReporter: { [weak self] event in
                self?.recordPersistenceRecovery(event)
            }
        )
        do {
            try inboxNotificationStore.load()
        } catch {
            appLogger.warning("Inbox notification store load failed: \(error.localizedDescription)")
        }
        observeInboxNotificationPersistence()
        hasLoadedInboxNotificationStore = true
        flushPersistenceRecoveryNotifications()
    }

    func bootStartInboxNotificationRouter(bus: EventBus<RuntimeEnvelope>) {
        inboxPaneFocusTracker = PaneFocusTracker(attendedPane: atomStore.attendedPane)
        inboxNotificationRouter = InboxNotificationRouter(
            bus: bus,
            inboxAtom: inboxNotificationAtom,
            prefsAtom: inboxNotificationPrefsAtom,
            paneAtom: store.paneAtom,
            tabLayout: store.tabLayoutAtom,
            attendedPane: atomStore.attendedPane,
            focusTracker: inboxPaneFocusTracker
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
            traceRuntime: traceRuntime
        )
        Task { @MainActor [weak self] in
            await self?.terminalActivityRouter.start()
        }
    }

    private func observeInboxNotificationPersistence() {
        withObservationTracking {
            _ = inboxNotificationAtom.notifications
            _ = inboxNotificationPrefsAtom.grouping
            _ = inboxNotificationPrefsAtom.sort
            _ = inboxNotificationPrefsAtom.bellEnabled
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
        inboxNotificationAtom.append(.persistenceRecovery(event))
    }

    func flushPersistenceRecoveryNotifications() {
        guard hasLoadedInboxNotificationStore else { return }
        let pendingEvents = pendingPersistenceRecoveryEvents
        pendingPersistenceRecoveryEvents.removeAll()
        for event in pendingEvents {
            inboxNotificationAtom.append(.persistenceRecovery(event))
        }
    }

}
