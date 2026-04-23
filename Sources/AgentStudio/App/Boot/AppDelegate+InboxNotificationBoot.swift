import Foundation
import Observation

extension AppDelegate {
    func bootLoadInboxNotificationStore(persistor: WorkspacePersistor) {
        let fileURL = persistor.workspacesDir.appending(
            path: "\(store.metadataAtom.workspaceId.uuidString).notification-inbox.json"
        )
        inboxNotificationStore = InboxNotificationStore(
            inboxAtom: inboxNotificationAtom,
            prefsAtom: inboxNotificationPrefsAtom,
            fileURL: fileURL
        )
        do {
            try inboxNotificationStore.load()
        } catch {
            appLogger.warning("Inbox notification store load failed: \(error.localizedDescription)")
        }
        observeInboxNotificationPersistence()
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

    func openDrawerInboxForActiveDrawer() {
        guard let drawerPaneIds = store.visiblePaneIdsForActiveExpandedDrawer() else { return }

        inboxNotificationDrawerPresenter.open(forDrawerPaneIds: drawerPaneIds)
    }
}
