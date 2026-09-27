import Foundation
import Testing

@testable import AgentStudioCore

@Suite(.serialized)
final class RepairActionTests {

    // MARK: - Equatable

    @Test

    func test_equatable_sameAction_areEqual() {
        let id = UUID()
        let lhs = RepairAction.reattachZmx(paneId: id)
        let rhs = RepairAction.reattachZmx(paneId: id)
        #expect(lhs == rhs)
    }

    @Test

    func test_equatable_differentCases_areNotEqual() {
        let id = UUID()
        #expect(RepairAction.reattachZmx(paneId: id) != RepairAction.recreateSurface(paneId: id))
    }

    @Test

    func test_equatable_differentPaneIds_areNotEqual() {
        let firstPaneId = UUID()
        let secondPaneId = UUID()
        #expect(RepairAction.reattachZmx(paneId: firstPaneId) != RepairAction.reattachZmx(paneId: secondPaneId))
    }

    // MARK: - Hashable

    @Test

    func test_hashable_sameAction_sameHash() {
        let id = UUID()
        let a = RepairAction.reattachZmx(paneId: id)
        let b = RepairAction.reattachZmx(paneId: id)
        #expect(a.hashValue == b.hashValue)
    }

    @Test

    func test_hashable_canBeUsedInSet() {
        let id = UUID()
        let set: Set<RepairAction> = [
            .reattachZmx(paneId: id),
            .recreateSurface(paneId: id),
            .reattachZmx(paneId: id),  // duplicate
        ]
        #expect(set.count == 2)
    }

    // MARK: - WorkspaceActionCommand Integration

    @Test

    func test_paneAction_repairCase_wrapsRepairAction() {
        let paneId = UUID()
        let repair = RepairAction.cleanupOrphan(paneId: paneId)
        let action = WorkspaceActionCommand.repair(repair)

        if case .repair(let wrapped) = action {
            #expect(wrapped == repair)
        } else {
            Issue.record("Expected .repair case")
        }
    }

    @Test

    func test_paneAction_expireUndoEntry_hasPaneId() {
        let paneId = UUID()
        let action = WorkspaceActionCommand.expireUndoEntry(paneId: paneId)

        if case .expireUndoEntry(let id) = action {
            #expect(id == paneId)
        } else {
            Issue.record("Expected .expireUndoEntry case")
        }
    }
}
