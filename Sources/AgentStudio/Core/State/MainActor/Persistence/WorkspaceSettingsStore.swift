import Foundation
import Observation
import os.log

private let workspaceSettingsStoreLogger = Logger(
    subsystem: "com.agentstudio",
    category: "WorkspaceSettingsStore"
)

@MainActor
final class WorkspaceSettingsStore {
    private let editorPreferenceAtom: EditorPreferenceAtom
    private let repoExplorerSidebarPrefsAtom: RepoExplorerSidebarPrefsAtom
    private let inboxNotificationPrefsAtom: InboxNotificationPrefsAtom
    private let sqliteDatastore: WorkspaceSQLiteDatastore
    private let persistDebounceDuration: Duration
    private let delay: AsyncDelay
    private let recoveryReporter: PersistenceRecoveryReporter?
    private var debouncedSaveTask: Task<Void, Never>?
    private var isObservingSettings = false
    private var isRestoringSettings = false
    private var activeWorkspaceId: UUID?

    var isAutosaveObservationActive: Bool {
        isObservingSettings
    }

    init(
        editorPreferenceAtom: EditorPreferenceAtom,
        repoExplorerSidebarPrefsAtom: RepoExplorerSidebarPrefsAtom,
        inboxNotificationPrefsAtom: InboxNotificationPrefsAtom,
        sqliteDatastore: WorkspaceSQLiteDatastore,
        persistDebounceDuration: Duration = .milliseconds(500),
        clock: (any Clock<Duration> & Sendable)? = nil,
        recoveryReporter: PersistenceRecoveryReporter? = nil
    ) {
        self.editorPreferenceAtom = editorPreferenceAtom
        self.repoExplorerSidebarPrefsAtom = repoExplorerSidebarPrefsAtom
        self.inboxNotificationPrefsAtom = inboxNotificationPrefsAtom
        self.sqliteDatastore = sqliteDatastore
        self.persistDebounceDuration = persistDebounceDuration
        delay = clock.map(AsyncDelay.clock) ?? .taskSleep
        self.recoveryReporter = recoveryReporter
    }

    func startObserving() {
        observeSettings()
    }

    func restoreAsync(for workspaceId: UUID) async {
        debouncedSaveTask?.cancel()
        debouncedSaveTask = nil
        activeWorkspaceId = workspaceId

        switch await sqliteDatastore.loadWorkspaceSettings(workspaceId: workspaceId) {
        case .loaded(let payload):
            reportRecoveryEvents(payload.recoveryEvents)
            isRestoringSettings = true
            hydrate(
                editor: payload.editor,
                repoExplorer: payload.repoExplorer,
                inboxNotification: payload.inboxNotification
            )
            isRestoringSettings = false
        case .unavailable(_, let recoveryEvents):
            reportRecoveryEvents(recoveryEvents)
            isRestoringSettings = true
            hydrateDefaults()
            isRestoringSettings = false
            recoveryReporter?(
                .init(store: .workspaceSettings, workspaceId: workspaceId, recovery: .resetToDefaults)
            )
        }
    }

    func flush(for workspaceId: UUID) async throws {
        activeWorkspaceId = workspaceId
        debouncedSaveTask?.cancel()
        debouncedSaveTask = nil
        try await persistNow(for: workspaceId)
    }

    func waitForPendingAutosave() async {
        await debouncedSaveTask?.value
    }

    private func observeSettings() {
        guard !isObservingSettings else { return }
        isObservingSettings = true
        withObservationTracking {
            _ = editorPreferenceAtom.bookmarkedEditorId
            _ = repoExplorerSidebarPrefsAtom.groupingMode
            _ = repoExplorerSidebarPrefsAtom.sortOrder
            _ = repoExplorerSidebarPrefsAtom.repoVisibilityMode
            _ = inboxNotificationPrefsAtom.grouping
            _ = inboxNotificationPrefsAtom.sort
            _ = inboxNotificationPrefsAtom.bellEnabled
            _ = inboxNotificationPrefsAtom.globalInboxContentMode
            _ = inboxNotificationPrefsAtom.globalInboxRowStateFilter
            _ = inboxNotificationPrefsAtom.paneInboxContentMode
            _ = inboxNotificationPrefsAtom.paneInboxRowStateFilter
        } onChange: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                let shouldIgnore = self.isRestoringSettings
                self.isObservingSettings = false
                self.observeSettings()
                guard !shouldIgnore else { return }
                self.schedulePersist()
            }
        }
    }

    private func schedulePersist() {
        guard let workspaceId = activeWorkspaceId else { return }
        debouncedSaveTask?.cancel()
        let delay = self.delay
        let persistDebounceDuration = self.persistDebounceDuration
        debouncedSaveTask = Task { @MainActor [weak self, delay, persistDebounceDuration] in
            try? await delay.wait(persistDebounceDuration)
            guard !Task.isCancelled, let self else { return }
            do {
                try await self.persistNow(for: workspaceId)
            } catch {
                workspaceSettingsStoreLogger.warning(
                    "Workspace settings autosave failed: \(error.localizedDescription)"
                )
            }
        }
    }

    private func persistNow(for workspaceId: UUID) async throws {
        do {
            try await sqliteDatastore.saveWorkspaceSettings(
                editor: currentEditorPreferences(),
                repoExplorer: currentRepoExplorerPreferences(),
                inboxNotification: currentInboxNotificationPreferences(),
                workspaceId: workspaceId
            )
        } catch {
            recoveryReporter?(.init(store: .workspaceSettings, workspaceId: workspaceId, recovery: .saveFailed))
            throw error
        }
    }

    private func currentEditorPreferences() -> WorkspaceLocalRepository.EditorPreferencesRecord {
        .init(bookmarkedEditorId: editorPreferenceAtom.bookmarkedEditorId?.rawValue)
    }

    private func currentRepoExplorerPreferences() -> WorkspaceLocalRepository.RepoExplorerPreferencesRecord {
        .init(
            groupingMode: repoExplorerSidebarPrefsAtom.groupingMode,
            sortOrder: repoExplorerSidebarPrefsAtom.sortOrder,
            visibilityMode: repoExplorerSidebarPrefsAtom.repoVisibilityMode
        )
    }

    private func currentInboxNotificationPreferences()
        -> WorkspaceLocalRepository.InboxNotificationPreferencesRecord
    {
        .init(
            grouping: inboxNotificationPrefsAtom.grouping,
            sortOrder: inboxNotificationPrefsAtom.sort,
            bellEnabled: inboxNotificationPrefsAtom.bellEnabled,
            globalContentMode: inboxNotificationPrefsAtom.globalInboxContentMode,
            globalRowStateFilter: inboxNotificationPrefsAtom.globalInboxRowStateFilter,
            paneContentMode: inboxNotificationPrefsAtom.paneInboxContentMode,
            paneRowStateFilter: inboxNotificationPrefsAtom.paneInboxRowStateFilter
        )
    }

    private func hydrate(
        editor: WorkspaceLocalRepository.EditorPreferencesRecord,
        repoExplorer: WorkspaceLocalRepository.RepoExplorerPreferencesRecord,
        inboxNotification: WorkspaceLocalRepository.InboxNotificationPreferencesRecord
    ) {
        editorPreferenceAtom.hydrate(bookmarkedEditorId: editor.bookmarkedEditorId.map(EditorTargetId.init(rawValue:)))
        repoExplorerSidebarPrefsAtom.hydrate(
            groupingMode: repoExplorer.groupingMode,
            sortOrder: repoExplorer.sortOrder,
            repoVisibilityMode: repoExplorer.visibilityMode
        )
        inboxNotificationPrefsAtom.setGrouping(inboxNotification.grouping)
        inboxNotificationPrefsAtom.setSort(inboxNotification.sortOrder)
        inboxNotificationPrefsAtom.setBellEnabled(inboxNotification.bellEnabled)
        inboxNotificationPrefsAtom.setGlobalInboxContentMode(inboxNotification.globalContentMode)
        inboxNotificationPrefsAtom.setGlobalInboxRowStateFilter(inboxNotification.globalRowStateFilter)
        inboxNotificationPrefsAtom.setPaneInboxContentMode(inboxNotification.paneContentMode)
        inboxNotificationPrefsAtom.setPaneInboxRowStateFilter(inboxNotification.paneRowStateFilter)
    }

    private func hydrateDefaults() {
        hydrate(
            editor: .default,
            repoExplorer: .default,
            inboxNotification: .default
        )
    }

    private func reportRecoveryEvents(_ recoveryEvents: [PersistenceRecoveryEvent]) {
        guard let recoveryReporter else { return }
        for recoveryEvent in recoveryEvents {
            recoveryReporter(recoveryEvent)
        }
    }
}
