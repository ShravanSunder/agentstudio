import Foundation
import Observation

extension AppDelegate {
    func bootLoadInboxNotificationStore(persistor: WorkspacePersistor) {
        let workspaceId = store.identityAtom.workspaceId
        let fileURL = persistor.notificationInboxFileURL(for: workspaceId)
        let hadLegacyInboxFile = FileManager.default.fileExists(atPath: fileURL.path)
        let (sqliteRepository, allowLegacyFilePersistence) = makeInboxNotificationSQLiteRepository(
            workspaceId: workspaceId
        )
        inboxNotificationStore = InboxNotificationStore(
            inboxAtom: atomStore.inboxNotification,
            prefsAtom: atomStore.inboxNotificationPrefs,
            sidebarState: atomStore.inboxSidebarState,
            fileURL: fileURL,
            recoveryReporter: { [weak self] event in
                self?.recordPersistenceRecovery(event)
            },
            sqliteRepository: sqliteRepository,
            allowLegacyFilePersistence: allowLegacyFilePersistence
        )
        var didLoadInboxStore = false
        do {
            try inboxNotificationStore.load()
            didLoadInboxStore = true
        } catch {
            appLogger.warning("Inbox notification store load failed: \(error.localizedDescription)")
        }
        canArchiveLegacyInboxFile =
            !hadLegacyInboxFile
            || (didLoadInboxStore && (sqliteRepository != nil || workspaceLocalSQLiteStoreBackend == nil))
        observeInboxNotificationPersistence()
        hasLoadedInboxNotificationStore = true
        flushPersistenceRecoveryNotifications()
    }

    private func makeInboxNotificationSQLiteRepository(
        workspaceId: UUID
    ) -> (InboxNotificationSQLiteRepository?, Bool) {
        guard let workspaceLocalSQLiteStoreBackend else { return (nil, true) }
        do {
            let localRepository = try workspaceLocalSQLiteStoreBackend.restoreRepository(for: workspaceId)
            return (
                InboxNotificationSQLiteRepository(
                    workspaceId: workspaceId,
                    databaseWriter: localRepository.databaseWriter
                ),
                true
            )
        } catch {
            appLogger.warning("Inbox notification SQLite repository unavailable: \(error.localizedDescription)")
            recordPersistenceRecovery(
                .init(
                    store: .notificationInbox,
                    workspaceId: workspaceId,
                    recovery: .resetToDefaults
                )
            )
            return (nil, false)
        }
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
            isPaneCurrentlyAttended: { [weak self] paneId in
                self?.isPaneCurrentlyAttendedForNotifications(paneId) ?? false
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
        atomStore.inboxNotification.append(.persistenceRecovery(event))
    }

    func flushPersistenceRecoveryNotifications() {
        guard hasLoadedInboxNotificationStore else { return }
        let pendingEvents = pendingPersistenceRecoveryEvents
        pendingPersistenceRecoveryEvents.removeAll()
        for event in pendingEvents {
            atomStore.inboxNotification.append(.persistenceRecovery(event))
        }
    }

    private func isPaneCurrentlyAttendedForNotifications(_ paneId: UUID) -> Bool {
        PaneObservationResolver.isPaneCurrentlyAttended(
            paneId: paneId,
            attendedPaneId: atomStore.attendedPane.attendedPaneId,
            pane: { store.paneAtom.pane($0) }
        )
    }
}
