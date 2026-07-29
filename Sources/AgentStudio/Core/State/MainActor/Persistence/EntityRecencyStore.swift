import AgentStudioInfrastructure
import Foundation
import Observation

@MainActor
package final class EntityRecencyStore {
    private let applicationAtom: ApplicationEntityRecencyAtom
    private let workspaceAtom: WorkspaceEntityRecencyAtom
    private let sqliteDatastore: WorkspaceSQLiteDatastore
    private let persistDebounceDuration: Duration
    private let delay: AsyncDelay

    private var applicationSaveTask: Task<Void, Never>?
    private var workspaceSaveTask: Task<Void, Never>?
    private var isObservationArmed = false
    private var isObservingApplication = false
    private var isObservingWorkspace = false
    private var isRestoringApplication = false
    private var isRestoringWorkspace = false

    package private(set) var isApplicationHydrated = false
    package private(set) var hydratedWorkspaceID: UUID?

    package var isApplicationObservationActive: Bool {
        isObservingApplication
    }

    package var isWorkspaceObservationActive: Bool {
        isObservingWorkspace
    }

    package init(
        applicationAtom: ApplicationEntityRecencyAtom,
        workspaceAtom: WorkspaceEntityRecencyAtom,
        sqliteDatastore: WorkspaceSQLiteDatastore,
        persistDebounceDuration: Duration = .milliseconds(500),
        clock: (any Clock<Duration> & Sendable)? = nil
    ) {
        self.applicationAtom = applicationAtom
        self.workspaceAtom = workspaceAtom
        self.sqliteDatastore = sqliteDatastore
        self.persistDebounceDuration = persistDebounceDuration
        delay = clock.map(AsyncDelay.clock) ?? .taskSleep
    }

    package func restoreApplicationAsync() async {
        guard !isApplicationHydrated else { return }
        applicationSaveTask?.cancel()
        applicationSaveTask = nil
        isRestoringApplication = true
        switch await sqliteDatastore.loadApplicationEntityRecency() {
        case .loaded(let recentEntities):
            applicationAtom.hydrate(recentEntities)
        case .unavailable:
            applicationAtom.clear()
        }
        isRestoringApplication = false
        isApplicationHydrated = true
        observeApplicationIfReady()
    }

    package func restoreWorkspaceAsync(for workspaceID: UUID) async {
        workspaceSaveTask?.cancel()
        workspaceSaveTask = nil

        if let previousWorkspaceID = hydratedWorkspaceID, previousWorkspaceID != workspaceID {
            try? await flushWorkspaceAsync(for: previousWorkspaceID)
        }

        isRestoringWorkspace = true
        workspaceAtom.clear()
        switch await sqliteDatastore.loadWorkspaceEntityRecency(workspaceId: workspaceID) {
        case .loaded(let recentEntities):
            workspaceAtom.hydrate(workspaceID: workspaceID, recentEntities: recentEntities)
        case .unavailable:
            workspaceAtom.hydrate(workspaceID: workspaceID, recentEntities: [])
        }
        hydratedWorkspaceID = workspaceID
        isRestoringWorkspace = false
        observeWorkspaceIfReady()
    }

    package func startObserving() {
        isObservationArmed = true
        observeApplicationIfReady()
        observeWorkspaceIfReady()
    }

    package func flushApplicationAsync() async throws {
        guard isApplicationHydrated else { return }
        applicationSaveTask?.cancel()
        applicationSaveTask = nil
        try await sqliteDatastore.saveApplicationEntityRecency(applicationAtom.recentEntities)
    }

    package func flushWorkspaceAsync(for workspaceID: UUID) async throws {
        guard hydratedWorkspaceID == workspaceID, workspaceAtom.workspaceID == workspaceID else {
            return
        }
        workspaceSaveTask?.cancel()
        workspaceSaveTask = nil
        try await sqliteDatastore.saveWorkspaceEntityRecency(
            workspaceAtom.recentEntities,
            workspaceId: workspaceID
        )
    }

    package func flushAllAsync() async throws {
        var applicationFlushError: (any Error)?
        var workspaceFlushError: (any Error)?
        do {
            try await flushApplicationAsync()
        } catch {
            applicationFlushError = error
        }

        if let workspaceID = hydratedWorkspaceID {
            do {
                try await flushWorkspaceAsync(for: workspaceID)
            } catch {
                workspaceFlushError = error
            }
        }
        if let applicationFlushError {
            throw applicationFlushError
        }
        if let workspaceFlushError {
            throw workspaceFlushError
        }
    }

    private func observeApplicationIfReady() {
        guard
            isObservationArmed,
            isApplicationHydrated,
            !isObservingApplication
        else { return }

        isObservingApplication = true
        withObservationTracking {
            _ = applicationAtom.recentEntities
        } onChange: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                let shouldIgnore = self.isRestoringApplication
                self.isObservingApplication = false
                self.observeApplicationIfReady()
                guard !shouldIgnore else { return }
                self.scheduleApplicationSave()
            }
        }
    }

    private func observeWorkspaceIfReady() {
        guard
            isObservationArmed,
            hydratedWorkspaceID != nil,
            !isObservingWorkspace
        else { return }

        isObservingWorkspace = true
        withObservationTracking {
            _ = workspaceAtom.workspaceID
            _ = workspaceAtom.recentEntities
        } onChange: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                let shouldIgnore = self.isRestoringWorkspace
                self.isObservingWorkspace = false
                self.observeWorkspaceIfReady()
                guard !shouldIgnore else { return }
                self.scheduleWorkspaceSave()
            }
        }
    }

    private func scheduleApplicationSave() {
        applicationSaveTask?.cancel()
        let delay = self.delay
        let persistDebounceDuration = self.persistDebounceDuration
        applicationSaveTask = Task { @MainActor [weak self, delay, persistDebounceDuration] in
            try? await delay.wait(persistDebounceDuration)
            guard !Task.isCancelled, let self else { return }
            try? await self.flushApplicationAsync()
        }
    }

    private func scheduleWorkspaceSave() {
        guard let workspaceID = hydratedWorkspaceID else { return }
        workspaceSaveTask?.cancel()
        let delay = self.delay
        let persistDebounceDuration = self.persistDebounceDuration
        workspaceSaveTask = Task { @MainActor [weak self, delay, persistDebounceDuration, workspaceID] in
            try? await delay.wait(persistDebounceDuration)
            guard !Task.isCancelled, let self else { return }
            try? await self.flushWorkspaceAsync(for: workspaceID)
        }
    }

}
