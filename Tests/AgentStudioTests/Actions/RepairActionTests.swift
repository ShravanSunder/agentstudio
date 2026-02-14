import XCTest
@testable import AgentStudio

final class RepairActionTests: XCTestCase {

    // MARK: - Construction

    func test_reattachZmx_hasPaneId() {
        let paneId = UUID()
        let action = RepairAction.reattachZmx(paneId: paneId)

        if case .reattachZmx(let id) = action {
            XCTAssertEqual(id, paneId)
        } else {
            XCTFail("Expected reattachZmx")
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
        let action = RepairAction.markSessionFailed(paneId: paneId, reason: "zmx crash")

        if case .markSessionFailed(let id, let reason) = action {
            XCTAssertEqual(id, paneId)
            XCTAssertEqual(reason, "zmx crash")
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
            RepairAction.reattachZmx(paneId: id),
            RepairAction.reattachZmx(paneId: id)
        )
    }

    func test_equatable_differentCases_areNotEqual() {
        let id = UUID()
        XCTAssertNotEqual(
            RepairAction.reattachZmx(paneId: id),
            RepairAction.recreateSurface(paneId: id)
        )
    }

    func test_equatable_differentPaneIds_areNotEqual() {
        XCTAssertNotEqual(
            RepairAction.reattachZmx(paneId: UUID()),
            RepairAction.reattachZmx(paneId: UUID())
        )
    }

    // MARK: - Hashable

    func test_hashable_sameAction_sameHash() {
        let id = UUID()
        let a = RepairAction.reattachZmx(paneId: id)
        let b = RepairAction.reattachZmx(paneId: id)
        XCTAssertEqual(a.hashValue, b.hashValue)
    }

    func test_hashable_canBeUsedInSet() {
        let id = UUID()
        let set: Set<RepairAction> = [
            .reattachZmx(paneId: id),
            .recreateSurface(paneId: id),
            .reattachZmx(paneId: id) // duplicate
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
