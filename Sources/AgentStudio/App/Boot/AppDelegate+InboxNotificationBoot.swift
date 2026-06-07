import Foundation
import Observation

extension AppDelegate {
    func bootLoadInboxNotificationStore(persistor: WorkspacePersistor) {
        let workspaceId = store.identityAtom.workspaceId
        let fileURL = persistor.notificationInboxFileURL(for: workspaceId)
        let hadLegacyInboxFile = FileManager.default.fileExists(atPath: fileURL.path)
        let sqliteBootDecision = makeInboxNotificationSQLiteRepository(workspaceId: workspaceId)
        inboxNotificationStore = InboxNotificationStore(
            inboxAtom: atomStore.inboxNotification,
            prefsAtom: atomStore.inboxNotificationPrefs,
            sidebarState: atomStore.inboxSidebarState,
            fileURL: fileURL,
            recoveryReporter: { [weak self] event in
                self?.recordPersistenceRecovery(event)
            },
            sqliteRepository: sqliteBootDecision.repository,
            allowLegacyFilePersistence: sqliteBootDecision.allowLegacyFilePersistence,
            allowLegacyFileImport: sqliteBootDecision.allowLegacyFileImport
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
            || (didLoadInboxStore
                && (sqliteBootDecision.repository != nil || workspaceLocalSQLiteStoreBackend == nil)
                && (sqliteBootDecision.allowLegacyFileImport
                    || sqliteBootDecision.canArchiveLegacyInboxFileAfterBlockedImport))
        observeInboxNotificationPersistence()
        hasLoadedInboxNotificationStore = true
        flushPersistenceRecoveryNotifications()
    }

    private func makeInboxNotificationSQLiteRepository(
        workspaceId: UUID
    ) -> InboxNotificationSQLiteBootDecision {
        guard let workspaceLocalSQLiteStoreBackend else {
            return .init(
                repository: nil,
                allowLegacyFilePersistence: true,
                allowLegacyFileImport: true,
                canArchiveLegacyInboxFileAfterBlockedImport: false
            )
        }
        let localRepository: WorkspaceLocalRepository
        do {
            localRepository = try workspaceLocalSQLiteStoreBackend.restoreRepository(for: workspaceId)
        } catch {
            appLogger.warning("Inbox notification SQLite repository unavailable: \(error.localizedDescription)")
            recordPersistenceRecovery(
                .init(
                    store: .notificationInbox,
                    workspaceId: workspaceId,
                    recovery: .resetToDefaults
                )
            )
            return .init(
                repository: nil,
                allowLegacyFilePersistence: false,
                allowLegacyFileImport: false,
                canArchiveLegacyInboxFileAfterBlockedImport: false
            )
        }
        let legacyImportDecision: WorkspaceLocalSQLiteLegacyImportDecision
        do {
            legacyImportDecision = try workspaceLocalSQLiteStoreBackend.legacyImportDecision(
                for: workspaceId,
                lane: .local
            )
        } catch {
            appLogger.warning(
                "Inbox notification legacy import permission check failed: \(error.localizedDescription)"
            )
            legacyImportDecision = .blockReplayBlockArchive
        }
        return .init(
            repository: InboxNotificationSQLiteRepository(
                workspaceId: workspaceId,
                databaseWriter: localRepository.databaseWriter
            ),
            allowLegacyFilePersistence: true,
            allowLegacyFileImport: legacyImportDecision.allowsLegacyImport,
            canArchiveLegacyInboxFileAfterBlockedImport: legacyImportDecision.canArchiveLegacyFile
        )
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

private struct InboxNotificationSQLiteBootDecision {
    var repository: InboxNotificationSQLiteRepository?
    var allowLegacyFilePersistence: Bool
    var allowLegacyFileImport: Bool
    var canArchiveLegacyInboxFileAfterBlockedImport: Bool
}
