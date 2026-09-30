import AgentStudioInfrastructure
import Foundation
import Observation

@MainActor
@Observable
package final class WorkspaceDrawerCursorAtom {
    var expandedDrawerId: UUID? { storedExpandedDrawerId }

    private var storedExpandedDrawerId: UUID?

    /// Committed presentation choices keyed by owning layout pane. A missing
    /// owner reads as `DrawerPresentationPreference.default` without inserting.
    @ObservationIgnored private let presentationPreferenceFamily = AtomFamily<UUID, DrawerPresentationPreference>(
        telemetryLabel: "workspace_drawer_presentation_preference",
        isContentEqual: ==
    )
    /// Bumps once per accepted preference change; persistence observes this.
    @ObservationIgnored private let presentationPreferenceCommitRevision = AtomRevision()

    package init(expandedDrawerId: UUID? = nil) {
        storedExpandedDrawerId = expandedDrawerId
    }

    func isExpanded(drawerId: UUID) -> Bool {
        storedExpandedDrawerId == drawerId
    }

    func toggleDrawer(drawerId: UUID) {
        storedExpandedDrawerId = storedExpandedDrawerId == drawerId ? nil : drawerId
    }

    func expandDrawer(drawerId: UUID) {
        storedExpandedDrawerId = drawerId
    }

    func collapseAllDrawers() {
        storedExpandedDrawerId = nil
    }

    func replaceExpandedDrawer(_ expandedDrawerId: UUID?) {
        storedExpandedDrawerId = expandedDrawerId
    }

    func prune(validDrawerIds: Set<UUID>) {
        guard let storedExpandedDrawerId, !validDrawerIds.contains(storedExpandedDrawerId) else { return }
        self.storedExpandedDrawerId = nil
    }

    // MARK: - Presentation preferences

    package var presentationPreferenceRevision: Int {
        presentationPreferenceCommitRevision.value
    }

    package var presentationPreferencesByOwnerPaneId: [UUID: DrawerPresentationPreference] {
        _ = presentationPreferenceCommitRevision.value
        return presentationPreferenceFamily.snapshot()
    }

    package func presentationPreference(forOwner ownerPaneId: UUID) -> DrawerPresentationPreference {
        presentationPreferenceFamily.value(for: ownerPaneId) ?? .default
    }

    package func setPresentationPreference(
        _ preference: DrawerPresentationPreference,
        forOwner ownerPaneId: UUID
    ) {
        let mutation = AtomMutationContext(aggregateRevision: presentationPreferenceCommitRevision)
        if presentationPreferenceFamily.snapshotValue(for: ownerPaneId) == nil, preference == .default {
            // Reading a missing owner already yields the default; do not insert a row.
            mutation.commit()
            return
        }
        presentationPreferenceFamily.setValue(preference, for: ownerPaneId, mutation: mutation)
        mutation.commit()
    }

    /// Hydration and composition replacement install the whole validated map.
    package func replacePresentationPreferences(_ preferences: [UUID: DrawerPresentationPreference]) {
        let mutation = AtomMutationContext(aggregateRevision: presentationPreferenceCommitRevision)
        presentationPreferenceFamily.replaceAll(preferences, mutation: mutation)
        mutation.commit()
    }
}
