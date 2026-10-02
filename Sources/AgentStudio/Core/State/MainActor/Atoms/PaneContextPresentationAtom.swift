import Observation

@MainActor
@Observable
package final class PaneContextPresentationAtom {
    package init() {}

    package func value(for paneId: PaneId) -> PaneContextDisplay? { nil }
    package func apply(_ batch: [PaneId: PaneContextPublication]) {}
    package func remove(_ paneIds: [PaneId]) {}
}
