import XCTest
@testable import AgentStudio

final class RepairActionTests: XCTestCase {

    // MARK: - Construction

    func test_reattachTmux_hasPaneId() {
        let paneId = UUID()
        let action = RepairAction.reattachTmux(paneId: paneId)

        if case .reattachTmux(let id) = action {
            XCTAssertEqual(id, paneId)
        } else {
            XCTFail("Expected reattachTmux")
        }
    }

    func test_recreateSurface_hasPaneId() {
        let paneId = UUID()
        let action = RepairAction.recreateSurface(paneId: paneId)

        if case .recreateSurface(let id) = action {
            XCTAssertEqual(id, paneId)
        } else {
            XCTFail("Expected recreateSurface")
        }
    }

    func test_createMissingView_hasPaneId() {
        let paneId = UUID()
        let action = RepairAction.createMissingView(paneId: paneId)

        if case .createMissingView(let id) = action {
            XCTAssertEqual(id, paneId)
        } else {
            XCTFail("Expected createMissingView")
        }
    }

    func test_markSessionFailed_hasPaneIdAndReason() {
        let paneId = UUID()
        let action = RepairAction.markSessionFailed(paneId: paneId, reason: "tmux crash")

        if case .markSessionFailed(let id, let reason) = action {
            XCTAssertEqual(id, paneId)
            XCTAssertEqual(reason, "tmux crash")
        } else {
            XCTFail("Expected markSessionFailed")
        }
    }

    func test_cleanupOrphan_hasPaneId() {
        let paneId = UUID()
        let action = RepairAction.cleanupOrphan(paneId: paneId)

        if case .cleanupOrphan(let id) = action {
            XCTAssertEqual(id, paneId)
        } else {
            XCTFail("Expected cleanupOrphan")
        }
    }

    // MARK: - Equatable

    func test_equatable_sameAction_areEqual() {
        let id = UUID()
        XCTAssertEqual(
            RepairAction.reattachTmux(paneId: id),
            RepairAction.reattachTmux(paneId: id)
        )
    }

    func test_equatable_differentCases_areNotEqual() {
        let id = UUID()
        XCTAssertNotEqual(
            RepairAction.reattachTmux(paneId: id),
            RepairAction.recreateSurface(paneId: id)
        )
    }

    func test_equatable_differentPaneIds_areNotEqual() {
        XCTAssertNotEqual(
            RepairAction.reattachTmux(paneId: UUID()),
            RepairAction.reattachTmux(paneId: UUID())
        )
    }

    // MARK: - Hashable

    func test_hashable_sameAction_sameHash() {
        let id = UUID()
        let a = RepairAction.reattachTmux(paneId: id)
        let b = RepairAction.reattachTmux(paneId: id)
        XCTAssertEqual(a.hashValue, b.hashValue)
    }

    func test_hashable_canBeUsedInSet() {
        let id = UUID()
        let set: Set<RepairAction> = [
            .reattachTmux(paneId: id),
            .recreateSurface(paneId: id),
            .reattachTmux(paneId: id) // duplicate
        ]
        XCTAssertEqual(set.count, 2)
    }

    // MARK: - PaneAction Integration

    func test_paneAction_repairCase_wrapsRepairAction() {
        let paneId = UUID()
        let repair = RepairAction.cleanupOrphan(paneId: paneId)
        let action = PaneAction.repair(repair)

        if case .repair(let wrapped) = action {
            XCTAssertEqual(wrapped, repair)
        } else {
            XCTFail("Expected .repair case")
        }
    }

    func test_paneAction_expireUndoEntry_hasPaneId() {
        let paneId = UUID()
        let action = PaneAction.expireUndoEntry(paneId: paneId)

        if case .expireUndoEntry(let id) = action {
            XCTAssertEqual(id, paneId)
        } else {
            XCTFail("Expected .expireUndoEntry case")
        }
    }
}
