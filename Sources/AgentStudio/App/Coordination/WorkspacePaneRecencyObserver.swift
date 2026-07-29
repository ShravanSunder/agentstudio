import AgentStudioCore
import Foundation
import Observation

/// Records eligible attended-pane identity transitions into workspace recency.
@MainActor
final class WorkspacePaneRecencyObserver {
    private let store: WorkspaceStore
    private let attendedPane: AttendedPaneDerived
    private let recencyAtom: WorkspaceEntityRecencyAtom
    private let now: @MainActor () -> Date
    private var lastNonNilAttendedPaneID: UUID?
    private var postChangeDeliveryTask: Task<Void, Never>?
    private var observationGeneration = 0
    private var isStopped = false

    init(
        store: WorkspaceStore,
        attendedPane: AttendedPaneDerived,
        recencyAtom: WorkspaceEntityRecencyAtom,
        now: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.store = store
        self.attendedPane = attendedPane
        self.recencyAtom = recencyAtom
        self.now = now
        self.lastNonNilAttendedPaneID = attendedPane.attendedPaneId
        observeAttendedPane()
    }

    func stop() {
        recordTransitionIfNeeded()
        isStopped = true
        observationGeneration += 1
        postChangeDeliveryTask?.cancel()
        postChangeDeliveryTask = nil
    }

    private func observeAttendedPane() {
        guard !isStopped else { return }
        observationGeneration += 1
        let generation = observationGeneration
        withObservationTracking {
            _ = attendedPane.attendedPaneId
        } onChange: { [weak self] in
            MainActor.assumeIsolated {
                guard
                    let self,
                    !self.isStopped,
                    self.observationGeneration == generation
                else {
                    return
                }
                // Observation changes are delivered before the mutation. Recording
                // the old value preserves an intermediate transition when another
                // mutation arrives before the post-change task can run.
                self.recordTransitionIfNeeded()
                self.observeAttendedPane()
                self.schedulePostChangeDelivery()
            }
        }
    }

    private func schedulePostChangeDelivery() {
        guard postChangeDeliveryTask == nil else { return }
        postChangeDeliveryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            self.postChangeDeliveryTask = nil
            guard !self.isStopped else { return }
            self.recordTransitionIfNeeded()
            // Re-arm after the mutation so derived-state short-circuit branches
            // track the dependencies of the new attended-pane state.
            self.observeAttendedPane()
        }
    }

    private func recordTransitionIfNeeded() {
        guard let paneID = attendedPane.attendedPaneId else { return }
        guard paneID != lastNonNilAttendedPaneID else { return }

        let capturedWorkspaceID = store.identityAtom.workspaceId
        guard isEligible(paneID: paneID, workspaceID: capturedWorkspaceID) else { return }
        lastNonNilAttendedPaneID = paneID
        guard
            let recency = try? WorkspaceEntityRecency(
                workspaceID: capturedWorkspaceID,
                entity: .pane(paneID: paneID),
                interaction: .focused,
                lastInteractedAt: now()
            )
        else {
            return
        }
        recencyAtom.record(recency)
    }

    private func isEligible(paneID: UUID, workspaceID: UUID) -> Bool {
        WorkspacePaneRecencyEligibility.isEligibleForRecording(
            pane: store.paneAtom.pane(paneID),
            workspaceMatches: recencyAtom.workspaceID == workspaceID,
            tabs: store.tabLayoutAtom.tabs,
            targetableTabID: store.tabLayoutAtom.tabContaining(paneId: paneID)?.id
        )
    }

}

extension AppDelegate {
    func startWorkspacePaneRecencyObservation() {
        workspacePaneRecencyObserver?.stop()
        workspacePaneRecencyObserver = WorkspacePaneRecencyObserver(
            store: store,
            attendedPane: atomStore.core.attendedPane,
            recencyAtom: atomStore.core.workspaceEntityRecency
        )
    }

    func stopWorkspacePaneRecencyObservation() {
        workspacePaneRecencyObserver?.stop()
        workspacePaneRecencyObserver = nil
    }
}
