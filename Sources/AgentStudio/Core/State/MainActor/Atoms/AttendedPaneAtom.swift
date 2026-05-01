import Foundation
import Observation

/// Derived attended-pane state for consumers that care about current user attention.
///
/// This is not canonical mutable state. It republishes the active pane only when the
/// workspace window is key and the management layer is inactive.
@MainActor
@Observable
final class AttendedPaneAtom {
    // Do not add a setter: attended state must be derived from the input atoms
    // so background windows and management layers cannot masquerade as attention.
    private(set) var attendedPaneId: UUID?

    // AsyncStream is a single-consumer coordinator feed; add explicit fan-out
    // before introducing another long-lived consumer.
    let transitions: AsyncStream<UUID?>
    private let continuation: AsyncStream<UUID?>.Continuation

    private let tabLayout: WorkspaceTabLayoutAtom
    private let windowLifecycle: WindowLifecycleAtom
    private let managementLayer: ManagementLayerAtom
    private var isStopped = false

    init(
        tabLayout: WorkspaceTabLayoutAtom,
        windowLifecycle: WindowLifecycleAtom,
        managementLayer: ManagementLayerAtom
    ) {
        self.tabLayout = tabLayout
        self.windowLifecycle = windowLifecycle
        self.managementLayer = managementLayer
        let (stream, continuation) = AsyncStream.makeStream(of: UUID?.self)
        self.transitions = stream
        self.continuation = continuation
        self.attendedPaneId = currentAttendedPaneId()
        observe()
    }

    func stop() {
        guard !isStopped else { return }
        refresh()
        isStopped = true
        continuation.finish()
    }

    private func observe() {
        guard !isStopped else { return }
        withObservationTracking {
            _ = tabLayout.tabs
            _ = tabLayout.activeTabId
            _ = windowLifecycle.isWorkspaceWindowKey
            _ = managementLayer.isActive
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, !self.isStopped else { return }
                self.refresh()
                self.observe()
            }
        }
    }

    private func refresh() {
        let updatedAttendedPaneId = currentAttendedPaneId()
        guard updatedAttendedPaneId != attendedPaneId else { return }
        attendedPaneId = updatedAttendedPaneId
        continuation.yield(updatedAttendedPaneId)
    }

    private func currentAttendedPaneId() -> UUID? {
        guard windowLifecycle.isWorkspaceWindowKey else { return nil }
        guard !managementLayer.isActive else { return nil }
        return tabLayout.activeTab?.activePaneId
    }
}
