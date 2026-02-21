import Testing
import Foundation

@testable import AgentStudio

@Suite(.serialized)
final class RepairActionTests {

    // MARK: - Construction

    @Test

    func test_reattachZmx_hasPaneId() {
        let paneId = UUID()
        let action = RepairAction.reattachZmx(paneId: paneId)

        if case .reattachZmx(let id) = action {
            #expect(id == paneId)
        } else {
            Issue.record("Expected reattachZmx")
        }
    }

    @Test

    func test_recreateSurface_hasPaneId() {
        let paneId = UUID()
        let action = RepairAction.recreateSurface(paneId: paneId)

        if case .recreateSurface(let id) = action {
            #expect(id == paneId)
        } else {
            Issue.record("Expected recreateSurface")
        }
    }

    @Test

    func test_createMissingView_hasPaneId() {
        let paneId = UUID()
        let action = RepairAction.createMissingView(paneId: paneId)

        if case .createMissingView(let id) = action {
            #expect(id == paneId)
        } else {
            Issue.record("Expected createMissingView")
        }
    }

    @Test

    func test_markSessionFailed_hasPaneIdAndReason() {
        let paneId = UUID()
        let action = RepairAction.markSessionFailed(paneId: paneId, reason: "zmx crash")

        if case .markSessionFailed(let id, let reason) = action {
            #expect(id == paneId)
            #expect(reason == "zmx crash")
        } else {
            Issue.record("Expected markSessionFailed")
        }
    }

    @Test

    func test_cleanupOrphan_hasPaneId() {
        let paneId = UUID()
        let action = RepairAction.cleanupOrphan(paneId: paneId)

        if case .cleanupOrphan(let id) = action {
            #expect(id == paneId)
        } else {
            Issue.record("Expected cleanupOrphan")
        }
    }

    // MARK: - Equatable

    @Test

    func test_equatable_sameAction_areEqual() {
        let id = UUID()
        #expect(RepairAction.reattachZmx(paneId: id) == RepairAction.reattachZmx(paneId: id))
    }

    @Test

    func test_equatable_differentCases_areNotEqual() {
        let id = UUID()
        #expect(RepairAction.reattachZmx(paneId: id) != RepairAction.recreateSurface(paneId: id))
    }

    @Test

    func test_equatable_differentPaneIds_areNotEqual() {
        #expect(RepairAction.reattachZmx(paneId: UUID()) != RepairAction.reattachZmx(paneId: UUID()))
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

    // MARK: - PaneAction Integration

    @Test

    func test_paneAction_repairCase_wrapsRepairAction() {
        let paneId = UUID()
        let repair = RepairAction.cleanupOrphan(paneId: paneId)
        let action = PaneAction.repair(repair)

        if case .repair(let wrapped) = action {
            #expect(wrapped == repair)
        } else {
            Issue.record("Expected .repair case")
        }
    }

    @Test

    func test_paneAction_expireUndoEntry_hasPaneId() {
        let paneId = UUID()
        let action = PaneAction.expireUndoEntry(paneId: paneId)

        if case .expireUndoEntry(let id) = action {
            #expect(id == paneId)
        } else {
            Issue.record("Expected .expireUndoEntry case")
        }
    }
}
