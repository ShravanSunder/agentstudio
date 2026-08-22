import AgentStudioCore
import AgentStudioEditorChooser
import AgentStudioInfrastructure
import AgentStudioRepoExplorer
import Foundation
import Observation
import os.log

private let workspaceSettingsStoreLogger = Logger(
    subsystem: "com.agentstudio",
    category: "WorkspaceSettingsStore"
)

private enum WorkspaceSettingsStoreMappingError: Error {
    case unsupportedRepoExplorerPreferenceVocabulary
}

@MainActor
final class WorkspaceSettingsStore {
    private let editorPreferenceAtom: EditorPreferenceAtom
    private let repoExplorerSidebarPrefsAtom: RepoExplorerSidebarPrefsAtom
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
        sqliteDatastore: WorkspaceSQLiteDatastore,
        persistDebounceDuration: Duration = .milliseconds(500),
        clock: (any Clock<Duration> & Sendable)? = nil,
        recoveryReporter: PersistenceRecoveryReporter? = nil
    ) {
        self.editorPreferenceAtom = editorPreferenceAtom
        self.repoExplorerSidebarPrefsAtom = repoExplorerSidebarPrefsAtom
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
            isRestoringSettings = true
            hydrateEditor(payload.editor, workspaceId: workspaceId)
            hydrateRepoExplorer(payload.repoExplorer, workspaceId: workspaceId)
            isRestoringSettings = false
        case .unavailable:
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
            _ = repoExplorerSidebarPrefsAtom.sortOrder
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
                repoExplorer: try currentRepoExplorerPreferences(),
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

    private func currentRepoExplorerPreferences() throws
        -> WorkspaceLocalRepository.RepoExplorerPreferencesRecord
    {
        guard
            let preferences = WorkspaceLocalRepository.RepoExplorerPreferencesRecord.validated(
                sortOrder: repoExplorerSidebarPrefsAtom.sortOrder.rawValue,
                visibilityMode: SQLiteLocalUXStorage.repoExplorerVisibilityAll
            )
        else {
            throw WorkspaceSettingsStoreMappingError.unsupportedRepoExplorerPreferenceVocabulary
        }
        return preferences
    }

    private func hydrateDefaults() {
        editorPreferenceAtom.hydrate(bookmarkedEditorId: nil)
        hydrateRepoExplorerDefaults()
    }

    private func hydrateEditor(
        _ value: WorkspaceSQLiteDatastore.LocalSettingsValue<
            WorkspaceLocalRepository.EditorPreferencesRecord
        >,
        workspaceId: UUID
    ) {
        switch value {
        case .loaded(let editor):
            editorPreferenceAtom.hydrate(
                bookmarkedEditorId: editor.bookmarkedEditorId.map(EditorTargetId.init(rawValue:))
            )
        case .defaulted:
            editorPreferenceAtom.hydrate(bookmarkedEditorId: nil)
            reportResetToDefaults(workspaceId: workspaceId)
        }
    }

    private func hydrateRepoExplorer(
        _ value: WorkspaceSQLiteDatastore.LocalSettingsValue<
            WorkspaceLocalRepository.RepoExplorerPreferencesRecord
        >,
        workspaceId: UUID
    ) {
        switch value {
        case .loaded(let preferences):
            guard
                let sortOrder = RepoExplorerSortOrder(rawValue: preferences.sortOrder)
            else {
                hydrateRepoExplorerDefaults()
                reportResetToDefaults(workspaceId: workspaceId)
                return
            }
            repoExplorerSidebarPrefsAtom.hydrate(
                sortOrder: sortOrder
            )
        case .defaulted:
            hydrateRepoExplorerDefaults()
            reportResetToDefaults(workspaceId: workspaceId)
        }
    }

    private func hydrateRepoExplorerDefaults() {
        repoExplorerSidebarPrefsAtom.hydrate(
            sortOrder: .default
        )
    }

    private func reportResetToDefaults(workspaceId: UUID) {
        recoveryReporter?(
            .init(store: .workspaceSettings, workspaceId: workspaceId, recovery: .resetToDefaults)
        )
    }
}
