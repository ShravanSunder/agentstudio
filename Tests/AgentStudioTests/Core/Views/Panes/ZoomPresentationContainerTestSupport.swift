import AppKit

@testable import AgentStudio

@MainActor
struct ZoomPresentationContainerFixture {
    let sourcePaneId: UUID
    let companionPaneId: UUID
    let viewRegistry: ViewRegistry
    let sourcePaneSlot: ViewRegistry.PaneViewSlot
    let companionPaneSlot: ViewRegistry.PaneViewSlot
    let sourcePaneHost: PaneHostView
    let companionPaneHost: PaneHostView
    let recorder: ZoomPresentationContainerActionRecorder
}

struct MountedToolbarState {
    let accessibilityIdentifiers: [String]
    let toolbarControlFrames: [String: CGRect]
}

struct MountedPaneLeafState {
    let contentHeight: CGFloat
    let accessibilityIdentifiers: [String]
    let toolbarControlFrames: [String: CGRect]
}

@MainActor
final class ZoomPresentationContainerActionRecorder {
    private(set) var viewerSourcePaneIds: [UUID] = []
    private(set) var zoomSourcePaneIds: [UUID] = []

    func recordViewer(sourcePaneId: UUID) {
        viewerSourcePaneIds.append(sourcePaneId)
    }

    func recordZoom(sourcePaneId: UUID) {
        zoomSourcePaneIds.append(sourcePaneId)
    }
}
