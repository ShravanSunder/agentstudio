import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
struct ActionValidatorVisiblePanePairTests {
    private func makeSnapshot(tabs: [TabSnapshot]) -> ActionStateSnapshot {
        ActionStateSnapshot(tabs: tabs, activeTabId: nil, isManagementLayerActive: false)
    }

    @Test
    func validCollapsedRunSucceeds() {
        let tabId = UUID()
        let paneIds = [UUIDv7.generate(), UUIDv7.generate(), UUIDv7.generate()]
        let tab = TabSnapshot(
            id: tabId,
            visiblePaneIds: [paneIds[0], paneIds[2]],
            layoutPaneIds: paneIds,
            ownedPaneIds: paneIds,
            minimizedPaneIds: [paneIds[1]],
            activePaneId: paneIds[0],
            isLayoutSplit: true
        )

        let result = WorkspaceCommandValidator.validate(
            .resizeVisiblePanePair(tabId: tabId, leftPaneId: paneIds[0], rightPaneId: paneIds[2], ratio: 0.5),
            state: makeSnapshot(tabs: [tab])
        )

        #expect((try? result.get()) != nil)
    }

    @Test
    func invalidRatioFails() {
        let tabId = UUID()
        let paneIds = [UUIDv7.generate(), UUIDv7.generate(), UUIDv7.generate()]
        let tab = TabSnapshot(
            id: tabId,
            visiblePaneIds: [paneIds[0], paneIds[2]],
            layoutPaneIds: paneIds,
            ownedPaneIds: paneIds,
            minimizedPaneIds: [paneIds[1]],
            activePaneId: paneIds[0],
            isLayoutSplit: true
        )

        let result = WorkspaceCommandValidator.validate(
            .resizeVisiblePanePair(tabId: tabId, leftPaneId: paneIds[0], rightPaneId: paneIds[2], ratio: 0.95),
            state: makeSnapshot(tabs: [tab])
        )

        if case .failure(.invalidRatio) = result { return }
        Issue.record("Expected invalidRatio error")
    }

    @Test
    func missingTabFails() {
        let tabId = UUID()
        let paneIds = [UUIDv7.generate(), UUIDv7.generate(), UUIDv7.generate()]

        let result = WorkspaceCommandValidator.validate(
            .resizeVisiblePanePair(tabId: tabId, leftPaneId: paneIds[0], rightPaneId: paneIds[2], ratio: 0.5),
            state: makeSnapshot(tabs: [])
        )

        if case .failure(.tabNotFound(tabId)) = result { return }
        Issue.record("Expected tabNotFound error")
    }

    @Test
    func adjacentVisiblePairFails() {
        let tabId = UUID()
        let paneIds = [UUIDv7.generate(), UUIDv7.generate()]
        let tab = TabSnapshot(
            id: tabId,
            visiblePaneIds: paneIds,
            layoutPaneIds: paneIds,
            ownedPaneIds: paneIds,
            activePaneId: paneIds[0]
        )

        let result = WorkspaceCommandValidator.validate(
            .resizeVisiblePanePair(tabId: tabId, leftPaneId: paneIds[0], rightPaneId: paneIds[1], ratio: 0.5),
            state: makeSnapshot(tabs: [tab])
        )

        if case .failure(.invalidVisiblePanePair) = result { return }
        Issue.record("Expected invalidVisiblePanePair error")
    }

    @Test
    func visibleEndpointWithoutPartnerFails() {
        let tabId = UUID()
        let paneIds = [UUIDv7.generate(), UUIDv7.generate(), UUIDv7.generate()]
        let tab = TabSnapshot(
            id: tabId,
            visiblePaneIds: [paneIds[0], paneIds[1]],
            layoutPaneIds: paneIds,
            ownedPaneIds: paneIds,
            minimizedPaneIds: [paneIds[2]],
            activePaneId: paneIds[0],
            isLayoutSplit: true
        )

        let result = WorkspaceCommandValidator.validate(
            .resizeVisiblePanePair(tabId: tabId, leftPaneId: paneIds[1], rightPaneId: paneIds[2], ratio: 0.5),
            state: makeSnapshot(tabs: [tab])
        )

        if case .failure(.invalidVisiblePanePair) = result { return }
        Issue.record("Expected invalidVisiblePanePair error")
    }

    @Test
    func minimizedEndpointFails() {
        let tabId = UUID()
        let paneIds = [UUIDv7.generate(), UUIDv7.generate(), UUIDv7.generate()]
        let tab = TabSnapshot(
            id: tabId,
            visiblePaneIds: [paneIds[0], paneIds[2]],
            layoutPaneIds: paneIds,
            ownedPaneIds: paneIds,
            minimizedPaneIds: [paneIds[1]],
            activePaneId: paneIds[0],
            isLayoutSplit: true
        )

        let result = WorkspaceCommandValidator.validate(
            .resizeVisiblePanePair(tabId: tabId, leftPaneId: paneIds[1], rightPaneId: paneIds[2], ratio: 0.5),
            state: makeSnapshot(tabs: [tab])
        )

        if case .failure(.invalidVisiblePanePair) = result { return }
        Issue.record("Expected invalidVisiblePanePair error")
    }
}
