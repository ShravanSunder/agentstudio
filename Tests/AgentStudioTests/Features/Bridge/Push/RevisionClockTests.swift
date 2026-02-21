import Testing
import Foundation

@testable import AgentStudio

@MainActor
@Suite(.serialized)
final class RevisionClockTests {
    @Test
    func test_next_starts_at_one() {
        let clock = RevisionClock()
        #expect(clock.next(for: .diff) == 1)
    }

    @Test
    func test_next_increments_per_store() {
        let clock = RevisionClock()
        #expect(clock.next(for: .diff) == 1)
        #expect(clock.next(for: .diff) == 2)
        #expect(clock.next(for: .diff) == 3)
    }

    @Test
    func test_stores_are_independent() {
        let clock = RevisionClock()
        #expect(clock.next(for: .diff) == 1)
        #expect(clock.next(for: .review) == 1)
        #expect(clock.next(for: .diff) == 2)
        #expect(clock.next(for: .review) == 2)
    }

    @Test
    func test_monotonic_across_all_four_stores() {
        let clock = RevisionClock()
        for store in [StoreKey.diff, .review, .agent, .connection] {
            #expect(clock.next(for: store) == 1)
        }
        for store in [StoreKey.diff, .review, .agent, .connection] {
            #expect(clock.next(for: store) == 2)
        }
    }
}
