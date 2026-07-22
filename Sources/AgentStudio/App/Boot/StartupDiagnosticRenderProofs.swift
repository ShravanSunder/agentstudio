import Foundation

struct CrossTabMoveGeometrySmokeFixture {
    let sourceTabId: UUID
    let destinationTabId: UUID
    let movedPaneId: UUID
    let sourceLeftPaneId: UUID
    let targetPaneId: UUID
    let otherDestinationPaneId: UUID

    var paneIds: [UUID] {
        [movedPaneId, sourceLeftPaneId, targetPaneId, otherDestinationPaneId]
    }

    var expectedVisiblePaneIdsAfterMove: [UUID] {
        [movedPaneId, targetPaneId, otherDestinationPaneId]
    }
}

struct CrossTabMoveGeometrySmokeRenderProof: Equatable {
    let expectedVisiblePaneCount: Int
    let terminalViewCount: Int
    let surfaceIdCount: Int
    let mountedSurfaceCount: Int
    let validGeometryCount: Int

    var succeeded: Bool {
        expectedVisiblePaneCount > 0
            && terminalViewCount == expectedVisiblePaneCount
            && mountedSurfaceCount == expectedVisiblePaneCount
            && validGeometryCount == expectedVisiblePaneCount
    }

    var attributes: [String: AgentStudioTraceValue] {
        [
            "agentstudio.startup_diagnostic.expected_visible_pane.count": .int(expectedVisiblePaneCount),
            "agentstudio.startup_diagnostic.fixture.terminal_view.count": .int(terminalViewCount),
            "agentstudio.startup_diagnostic.fixture.surface_reference.count": .int(surfaceIdCount),
            "agentstudio.startup_diagnostic.fixture.surface.count": .int(mountedSurfaceCount),
            "agentstudio.startup_diagnostic.fixture.valid_geometry.count": .int(validGeometryCount),
            "agentstudio.startup_diagnostic.render_proof.succeeded": .bool(succeeded),
        ]
    }
}
