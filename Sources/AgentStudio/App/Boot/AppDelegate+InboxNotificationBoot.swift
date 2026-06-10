import Foundation
import Observation

extension AppDelegate {
    func bootLoadInboxNotificationStore(persistor: WorkspacePersistor) async {
        let workspaceId = store.identityAtom.workspaceId
        let fileURL = persistor.notificationInboxFileURL(for: workspaceId)
        let hadLegacyInboxFile = FileManager.default.fileExists(atPath: fileURL.path)
        let sqliteAdapter = workspaceSQLiteDatastore.map {
            InboxNotificationSQLiteDatastoreAdapter(workspaceId: workspaceId, datastore: $0)
        }
        let sqliteBootDecision = await makeInboxNotificationSQLiteBootDecision(adapter: sqliteAdapter)
        for recoveryEvent in sqliteBootDecision.recoveryEvents {
            recordPersistenceRecovery(recoveryEvent)
        }
        inboxNotificationStore = InboxNotificationStore(
            inboxAtom: atomStore.inboxNotification,
            prefsAtom: atomStore.inboxNotificationPrefs,
            sidebarState: atomStore.inboxSidebarState,
            fileURL: fileURL,
            recoveryReporter: { [weak self] event in
                self?.recordPersistenceRecovery(event)
            },
            sqliteAdapter: sqliteAdapter,
            allowLegacyFilePersistence: sqliteBootDecision.allowLegacyFilePersistence,
            allowLegacyFileImport: sqliteBootDecision.allowLegacyFileImport
        )
        var didLoadInboxStore = false
        var inboxLoadOutcome: InboxNotificationStore.LoadOutcome?
        do {
            inboxLoadOutcome = try await inboxNotificationStore.loadAsync()
            didLoadInboxStore = true
        } catch {
            appLogger.warning("Inbox notification store load failed: \(error.localizedDescription)")
        }
        canArchiveLegacyInboxFile = InboxNotificationLegacyArchiveReadiness.canArchiveLegacyFile(
            hadLegacyFile: hadLegacyInboxFile,
            didLoadStore: didLoadInboxStore,
            hasSQLiteRepository: sqliteAdapter != nil,
            hasWorkspaceLocalSQLiteBackend: workspaceSQLiteDatastore != nil,
            loadOutcome: inboxLoadOutcome,
            canArchiveAfterBlockedImport: sqliteBootDecision.canArchiveLegacyInboxFileAfterBlockedImport
        )
        observeInboxNotificationPersistence()
        hasLoadedInboxNotificationStore = true
        flushPersistenceRecoveryNotifications()
    }

    private func makeInboxNotificationSQLiteBootDecision(
        adapter: InboxNotificationSQLiteDatastoreAdapter?
    ) async -> InboxNotificationSQLiteBootDecision {
        guard let adapter else {
            return .init(
                allowLegacyFilePersistence: true,
                allowLegacyFileImport: true,
                canArchiveLegacyInboxFileAfterBlockedImport: false
            )
        }
        let decision = await adapter.bootDecision()
        return .init(
            allowLegacyFilePersistence: decision.allowLegacyFilePersistence,
            allowLegacyFileImport: decision.allowLegacyFileImport,
            canArchiveLegacyInboxFileAfterBlockedImport: decision.canArchiveLegacyInboxFileAfterBlockedImport,
            recoveryEvents: decision.recoveryEvents
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
    var allowLegacyFilePersistence: Bool
    var allowLegacyFileImport: Bool
    var canArchiveLegacyInboxFileAfterBlockedImport: Bool
    var recoveryEvents: [PersistenceRecoveryEvent] = []
}

enum InboxNotificationLegacyArchiveReadiness {
    static func canArchiveLegacyFile(
        hadLegacyFile: Bool,
        didLoadStore: Bool,
        hasSQLiteRepository: Bool,
        hasWorkspaceLocalSQLiteBackend: Bool,
        loadOutcome: InboxNotificationStore.LoadOutcome?,
        canArchiveAfterBlockedImport: Bool
    ) -> Bool {
        guard hadLegacyFile else { return true }
        guard didLoadStore else { return false }
        guard hasSQLiteRepository || !hasWorkspaceLocalSQLiteBackend else { return false }
        return loadOutcome?.hasMaterializedLegacyFile == true || canArchiveAfterBlockedImport
    }
}
