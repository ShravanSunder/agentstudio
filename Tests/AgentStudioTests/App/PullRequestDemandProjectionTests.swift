import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudio

@Suite("PullRequestDemandProjection")
struct PullRequestDemandProjectionTests {
    @Test("visible sidebar rows union with non-minimized panes in the active arrangement")
    func sidebarAndActiveArrangementUnion() {
        let sidebarWorktreeId = UUIDv7.generate()
        let visiblePaneId = UUIDv7.generate()
        let visiblePaneWorktreeId = UUIDv7.generate()
        let minimizedPaneId = UUIDv7.generate()
        let minimizedPaneWorktreeId = UUIDv7.generate()

        let demand = PullRequestDemandProjection.worktreeIds(
            from: .init(
                windowPresentation: .visible,
                sidebarWorktreeIds: [sidebarWorktreeId],
                activeLayoutPaneIds: [visiblePaneId, minimizedPaneId],
                minimizedLayoutPaneIds: [minimizedPaneId],
                isManagementLayerActive: false,
                expandedDrawer: nil,
                zoom: nil,
                worktreeIdByPaneId: [
                    visiblePaneId: visiblePaneWorktreeId,
                    minimizedPaneId: minimizedPaneWorktreeId,
                ]
            )
        )

        #expect(demand == [sidebarWorktreeId, visiblePaneWorktreeId])
    }

    @Test("management mode renders minimized layout and expanded drawer panes")
    func managementModeIncludesMinimizedPanes() {
        let layoutPaneId = UUIDv7.generate()
        let layoutWorktreeId = UUIDv7.generate()
        let drawerPaneId = UUIDv7.generate()
        let drawerWorktreeId = UUIDv7.generate()

        let demand = PullRequestDemandProjection.worktreeIds(
            from: .init(
                windowPresentation: .visible,
                sidebarWorktreeIds: [],
                activeLayoutPaneIds: [layoutPaneId],
                minimizedLayoutPaneIds: [layoutPaneId],
                isManagementLayerActive: true,
                expandedDrawer: .init(
                    parentPaneId: layoutPaneId,
                    paneIds: [drawerPaneId],
                    minimizedPaneIds: [drawerPaneId]
                ),
                zoom: nil,
                worktreeIdByPaneId: [
                    layoutPaneId: layoutWorktreeId,
                    drawerPaneId: drawerWorktreeId,
                ]
            )
        )

        #expect(demand == [layoutWorktreeId, drawerWorktreeId])
    }

    @Test("zoom replaces arrangement demand with its source and visible companion")
    func zoomUsesSourceAndVisibleCompanion() {
        let sourcePaneId = UUIDv7.generate()
        let sourceWorktreeId = UUIDv7.generate()
        let excludedPaneId = UUIDv7.generate()
        let excludedWorktreeId = UUIDv7.generate()
        let companionWorktreeId = UUIDv7.generate()

        let demand = PullRequestDemandProjection.worktreeIds(
            from: .init(
                windowPresentation: .visible,
                sidebarWorktreeIds: [],
                activeLayoutPaneIds: [sourcePaneId, excludedPaneId],
                minimizedLayoutPaneIds: [],
                isManagementLayerActive: false,
                expandedDrawer: nil,
                zoom: .init(
                    sourcePaneId: sourcePaneId,
                    visibleCompanionWorktreeId: companionWorktreeId
                ),
                worktreeIdByPaneId: [
                    sourcePaneId: sourceWorktreeId,
                    excludedPaneId: excludedWorktreeId,
                ]
            )
        )

        #expect(demand == [sourceWorktreeId, companionWorktreeId])
    }

    @Test(arguments: [
        PullRequestDemandProjection.WindowPresentation.hidden,
        .miniaturized,
        .occluded,
    ])
    func unavailableWindowProducesNoDemand(windowPresentation: PullRequestDemandProjection.WindowPresentation) {
        let sidebarWorktreeId = UUIDv7.generate()
        let paneId = UUIDv7.generate()
        let paneWorktreeId = UUIDv7.generate()

        let demand = PullRequestDemandProjection.worktreeIds(
            from: .init(
                windowPresentation: windowPresentation,
                sidebarWorktreeIds: [sidebarWorktreeId],
                activeLayoutPaneIds: [paneId],
                minimizedLayoutPaneIds: [],
                isManagementLayerActive: false,
                expandedDrawer: nil,
                zoom: nil,
                worktreeIdByPaneId: [paneId: paneWorktreeId]
            )
        )

        #expect(demand.isEmpty)
    }
}
