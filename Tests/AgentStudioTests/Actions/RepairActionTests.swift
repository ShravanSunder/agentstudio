import XCTest
@testable import AgentStudio

final class RepairActionTests: XCTestCase {

    // MARK: - Construction

    func test_reattachZmx_hasSessionId() {
        let sessionId = UUID()
        let action = RepairAction.reattachZmx(sessionId: sessionId)

        if case .reattachZmx(let id) = action {
            XCTAssertEqual(id, sessionId)
        } else {
            XCTFail("Expected reattachZmx")
        }
    }

    func test_recreateSurface_hasSessionId() {
        let sessionId = UUID()
        let action = RepairAction.recreateSurface(sessionId: sessionId)

        if case .recreateSurface(let id) = action {
            XCTAssertEqual(id, sessionId)
        } else {
            XCTFail("Expected recreateSurface")
        }
    }

    func test_createMissingView_hasSessionId() {
        let sessionId = UUID()
        let action = RepairAction.createMissingView(sessionId: sessionId)

        if case .createMissingView(let id) = action {
            XCTAssertEqual(id, sessionId)
        } else {
            XCTFail("Expected createMissingView")
        }
    }

    func test_markSessionFailed_hasSessionIdAndReason() {
        let sessionId = UUID()
        let action = RepairAction.markSessionFailed(sessionId: sessionId, reason: "zmx crash")

        if case .markSessionFailed(let id, let reason) = action {
            XCTAssertEqual(id, sessionId)
            XCTAssertEqual(reason, "zmx crash")
        } else {
            XCTFail("Expected markSessionFailed")
        }
    }

    func test_cleanupOrphan_hasSessionId() {
        let sessionId = UUID()
        let action = RepairAction.cleanupOrphan(sessionId: sessionId)

        if case .cleanupOrphan(let id) = action {
            XCTAssertEqual(id, sessionId)
        } else {
            XCTFail("Expected cleanupOrphan")
        }
    }

    // MARK: - Equatable

    func test_equatable_sameAction_areEqual() {
        let id = UUID()
        XCTAssertEqual(
            RepairAction.reattachZmx(sessionId: id),
            RepairAction.reattachZmx(sessionId: id)
        )
    }

    func test_equatable_differentCases_areNotEqual() {
        let id = UUID()
        XCTAssertNotEqual(
            RepairAction.reattachZmx(sessionId: id),
            RepairAction.recreateSurface(sessionId: id)
        )
    }

    func test_equatable_differentSessionIds_areNotEqual() {
        XCTAssertNotEqual(
            RepairAction.reattachZmx(sessionId: UUID()),
            RepairAction.reattachZmx(sessionId: UUID())
        )
    }

    // MARK: - Hashable

    func test_hashable_sameAction_sameHash() {
        let id = UUID()
        let a = RepairAction.reattachZmx(sessionId: id)
        let b = RepairAction.reattachZmx(sessionId: id)
        XCTAssertEqual(a.hashValue, b.hashValue)
    }

    func test_hashable_canBeUsedInSet() {
        let id = UUID()
        let set: Set<RepairAction> = [
            .reattachZmx(sessionId: id),
            .recreateSurface(sessionId: id),
            .reattachZmx(sessionId: id) // duplicate
        ]
        XCTAssertEqual(set.count, 2)
    }

    // MARK: - PaneAction Integration

    func test_paneAction_repairCase_wrapsRepairAction() {
        let sessionId = UUID()
        let repair = RepairAction.cleanupOrphan(sessionId: sessionId)
        let action = PaneAction.repair(repair)

        if case .repair(let wrapped) = action {
            XCTAssertEqual(wrapped, repair)
        } else {
            XCTFail("Expected .repair case")
        }
    }

    func test_paneAction_expireUndoEntry_hasSessionId() {
        let sessionId = UUID()
        let action = PaneAction.expireUndoEntry(sessionId: sessionId)

        if case .expireUndoEntry(let id) = action {
            XCTAssertEqual(id, sessionId)
        } else {
            XCTFail("Expected .expireUndoEntry case")
        }
    }
}
