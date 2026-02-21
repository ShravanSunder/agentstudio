import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
final class SessionResidencyTests {

    // MARK: - Convenience Properties

    @Test

    func test_isActive_activeCase_returnsTrue() {
        #expect(SessionResidency.active.isActive)
    }

    @Test

    func test_isActive_pendingUndoCase_returnsFalse() {
        let residency = SessionResidency.pendingUndo(expiresAt: Date())
        #expect(!(residency.isActive))
    }

    @Test

    func test_isActive_backgroundedCase_returnsFalse() {
        #expect(!(SessionResidency.backgrounded.isActive))
    }

    @Test

    func test_isPendingUndo_pendingUndoCase_returnsTrue() {
        let residency = SessionResidency.pendingUndo(expiresAt: Date())
        #expect(residency.isPendingUndo)
    }

    @Test

    func test_isPendingUndo_activeCase_returnsFalse() {
        #expect(!(SessionResidency.active.isPendingUndo))
    }

    @Test

    func test_isPendingUndo_backgroundedCase_returnsFalse() {
        #expect(!(SessionResidency.backgrounded.isPendingUndo))
    }

    // MARK: - Equatable

    @Test

    func test_equatable_sameActive_areEqual() {
        let expected = SessionResidency.active
        let actual = SessionResidency.active
        #expect(actual == expected)
    }

    @Test

    func test_equatable_sameBackgrounded_areEqual() {
        let expected = SessionResidency.backgrounded
        let actual = SessionResidency.backgrounded
        #expect(actual == expected)
    }

    @Test

    func test_equatable_samePendingUndo_areEqual() {
        let date = Date(timeIntervalSince1970: 1_000_000)
        let expected = SessionResidency.pendingUndo(expiresAt: date)
        let actual = SessionResidency.pendingUndo(expiresAt: date)
        #expect(actual == expected)
    }

    @Test

    func test_equatable_differentPendingUndoDates_areNotEqual() {
        let date1 = Date(timeIntervalSince1970: 1_000_000)
        let date2 = Date(timeIntervalSince1970: 2_000_000)
        #expect(SessionResidency.pendingUndo(expiresAt: date1) != SessionResidency.pendingUndo(expiresAt: date2))
    }

    @Test

    func test_equatable_activeVsBackgrounded_areNotEqual() {
        #expect(SessionResidency.active != SessionResidency.backgrounded)
    }

    // MARK: - Codable Round-Trip

    @Test

    func test_codable_active_roundTrips() throws {
        let data = try JSONEncoder().encode(SessionResidency.active)
        let decoded = try JSONDecoder().decode(SessionResidency.self, from: data)
        #expect(decoded == .active)
    }

    @Test

    func test_codable_backgrounded_roundTrips() throws {
        let data = try JSONEncoder().encode(SessionResidency.backgrounded)
        let decoded = try JSONDecoder().decode(SessionResidency.self, from: data)
        #expect(decoded == .backgrounded)
    }

    @Test

    func test_codable_pendingUndo_roundTrips() throws {
        let expiresAt = Date(timeIntervalSince1970: 1_500_000)
        let residency = SessionResidency.pendingUndo(expiresAt: expiresAt)
        let data = try JSONEncoder().encode(residency)
        let decoded = try JSONDecoder().decode(SessionResidency.self, from: data)
        #expect(decoded == residency)
    }
}
