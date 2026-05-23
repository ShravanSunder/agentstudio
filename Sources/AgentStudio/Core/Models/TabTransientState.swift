import Foundation

/// Non-persisted tab view state.
///
/// This state can affect presentation while the app is running but must not be
/// encoded into workspace persistence.
struct TabTransientState: Equatable, Hashable {
    var zoomedPaneId: UUID?

    init(zoomedPaneId: UUID? = nil) {
        self.zoomedPaneId = zoomedPaneId
    }
}
