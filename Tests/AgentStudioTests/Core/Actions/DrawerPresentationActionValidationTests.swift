import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioCore

@Suite
struct DrawerPresentationActionValidationTests {
    private let tabId = UUID()
    private let ownerPaneId = UUIDv7.generate()
    private let otherPaneId = UUIDv7.generate()
    private let drawerChildId = UUIDv7.generate()

    private func snapshot(zoomSource: UUID?) -> ActionStateSnapshot {
        ActionStateSnapshot(
            tabs: [
                TabSnapshot(
                    id: tabId,
                    visiblePaneIds: [ownerPaneId, otherPaneId],
                    ownedPaneIds: [ownerPaneId, otherPaneId],
                    activePaneId: ownerPaneId
                )
            ],
            activeTabId: tabId,
            isManagementLayerActive: false,
            zoomSourcePaneIdByTabId: zoomSource.map { [tabId: $0] } ?? [:],
            drawerParentByPaneId: [drawerChildId: ownerPaneId]
        )
    }

    @Test("normal height commit validates a live owner and a finite ratio")
    func normalHeightCommitValidation() {
        let state = snapshot(zoomSource: nil)
        let valid = WorkspaceActionCommand.setDrawerNormalHeightRatio(parentPaneId: ownerPaneId, ratio: 0.45)
        #expect((try? WorkspaceCommandValidator.validate(valid, state: state).get())?.action == valid)

        let nonFinite = WorkspaceActionCommand.setDrawerNormalHeightRatio(parentPaneId: ownerPaneId, ratio: .nan)
        guard case .failure(.invalidRatio) = WorkspaceCommandValidator.validate(nonFinite, state: state) else {
            Issue.record("non-finite ratio must be rejected")
            return
        }

        let unknownOwner = WorkspaceActionCommand.setDrawerNormalHeightRatio(parentPaneId: UUID(), ratio: 0.5)
        guard case .failure(.paneNotFound) = WorkspaceCommandValidator.validate(unknownOwner, state: state) else {
            Issue.record("unknown owner must be rejected")
            return
        }

        let drawerChildOwner = WorkspaceActionCommand.setDrawerNormalHeightRatio(
            parentPaneId: drawerChildId,
            ratio: 0.5
        )
        guard case .failure(.paneNotFound) = WorkspaceCommandValidator.validate(drawerChildOwner, state: state)
        else {
            Issue.record("a drawer child is never a drawer owner")
            return
        }
    }

    @Test("Zoom split ratio validation enforces the terminal 30-60 percent bounds")
    func zoomSplitRatioRequiresBoundedTerminalShare() {
        let validAction = WorkspaceActionCommand.setZoomSplitRatio(tabId: tabId, ratio: 0.4)
        let validResult = WorkspaceCommandValidator.validate(
            validAction,
            state: snapshot(zoomSource: ownerPaneId)
        )
        #expect((try? validResult.get().action) == validAction)

        for ratio in [0.29, 0.61] {
            let action = WorkspaceActionCommand.setZoomSplitRatio(tabId: tabId, ratio: ratio)
            let result = WorkspaceCommandValidator.validate(
                action,
                state: snapshot(zoomSource: ownerPaneId)
            )
            #expect(result == .failure(.invalidRatio(ratio: ratio)))
        }
    }

    @Test("Zoom side commits only for the current Zoom source", arguments: DrawerZoomSide.allCases)
    func zoomSideRequiresZoomSource(side: DrawerZoomSide) {
        let action = WorkspaceActionCommand.setDrawerZoomSide(parentPaneId: ownerPaneId, side: side)

        let inZoom = WorkspaceCommandValidator.validate(action, state: snapshot(zoomSource: ownerPaneId))
        #expect((try? inZoom.get())?.action == action)

        let notZoomed = WorkspaceCommandValidator.validate(action, state: snapshot(zoomSource: nil))
        #expect(notZoomed == .failure(.drawerOwnerNotZoomSource(parentPaneId: ownerPaneId)))

        let otherSource = WorkspaceCommandValidator.validate(action, state: snapshot(zoomSource: otherPaneId))
        #expect(otherSource == .failure(.drawerOwnerNotZoomSource(parentPaneId: ownerPaneId)))
    }
}
