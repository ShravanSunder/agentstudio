import XCTest

@testable import AgentStudio

@MainActor
final class RevisionClockTests: XCTestCase {
    func test_next_starts_at_one() {
        let clock = RevisionClock()
        XCTAssertEqual(clock.next(for: .diff), 1)
    }

    func test_next_increments_per_store() {
        let clock = RevisionClock()
        XCTAssertEqual(clock.next(for: .diff), 1)
        XCTAssertEqual(clock.next(for: .diff), 2)
        XCTAssertEqual(clock.next(for: .diff), 3)
    }

    func test_stores_are_independent() {
        let clock = RevisionClock()
        XCTAssertEqual(clock.next(for: .diff), 1)
        XCTAssertEqual(clock.next(for: .review), 1)
        XCTAssertEqual(clock.next(for: .diff), 2)
        XCTAssertEqual(clock.next(for: .review), 2)
    }

    func test_monotonic_across_all_four_stores() {
        let clock = RevisionClock()
        for store in [StoreKey.diff, .review, .agent, .connection] {
            XCTAssertEqual(clock.next(for: store), 1)
        }
        for store in [StoreKey.diff, .review, .agent, .connection] {
            XCTAssertEqual(clock.next(for: store), 2)
        }
    }
}
