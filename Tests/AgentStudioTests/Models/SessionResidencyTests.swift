import XCTest
@testable import AgentStudio

final class SessionResidencyTests: XCTestCase {

    // MARK: - Convenience Properties

    func test_isActive_activeCase_returnsTrue() {
        XCTAssertTrue(SessionResidency.active.isActive)
    }

    func test_isActive_pendingUndoCase_returnsFalse() {
        let residency = SessionResidency.pendingUndo(expiresAt: Date())
        XCTAssertFalse(residency.isActive)
    }

    func test_isActive_backgroundedCase_returnsFalse() {
        XCTAssertFalse(SessionResidency.backgrounded.isActive)
    }

    func test_isPendingUndo_pendingUndoCase_returnsTrue() {
        let residency = SessionResidency.pendingUndo(expiresAt: Date())
        XCTAssertTrue(residency.isPendingUndo)
    }

    func test_isPendingUndo_activeCase_returnsFalse() {
        XCTAssertFalse(SessionResidency.active.isPendingUndo)
    }

    func test_isPendingUndo_backgroundedCase_returnsFalse() {
        XCTAssertFalse(SessionResidency.backgrounded.isPendingUndo)
    }

    // MARK: - Equatable

    func test_equatable_sameActive_areEqual() {
        XCTAssertEqual(SessionResidency.active, SessionResidency.active)
    }

    func test_equatable_sameBackgrounded_areEqual() {
        XCTAssertEqual(SessionResidency.backgrounded, SessionResidency.backgrounded)
    }

    func test_equatable_samePendingUndo_areEqual() {
        let date = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(
            SessionResidency.pendingUndo(expiresAt: date),
            SessionResidency.pendingUndo(expiresAt: date)
        )
    }

    func test_equatable_differentPendingUndoDates_areNotEqual() {
        let date1 = Date(timeIntervalSince1970: 1_000_000)
        let date2 = Date(timeIntervalSince1970: 2_000_000)
        XCTAssertNotEqual(
            SessionResidency.pendingUndo(expiresAt: date1),
            SessionResidency.pendingUndo(expiresAt: date2)
        )
    }

    func test_equatable_activeVsBackgrounded_areNotEqual() {
        XCTAssertNotEqual(SessionResidency.active, SessionResidency.backgrounded)
    }

    // MARK: - Codable Round-Trip

    func test_codable_active_roundTrips() throws {
        let data = try JSONEncoder().encode(SessionResidency.active)
        let decoded = try JSONDecoder().decode(SessionResidency.self, from: data)
        XCTAssertEqual(decoded, .active)
    }

    func test_codable_backgrounded_roundTrips() throws {
        let data = try JSONEncoder().encode(SessionResidency.backgrounded)
        let decoded = try JSONDecoder().decode(SessionResidency.self, from: data)
        XCTAssertEqual(decoded, .backgrounded)
    }

    func test_codable_pendingUndo_roundTrips() throws {
        let expiresAt = Date(timeIntervalSince1970: 1_500_000)
        let residency = SessionResidency.pendingUndo(expiresAt: expiresAt)
        let data = try JSONEncoder().encode(residency)
        let decoded = try JSONDecoder().decode(SessionResidency.self, from: data)
        XCTAssertEqual(decoded, residency)
    }
}
