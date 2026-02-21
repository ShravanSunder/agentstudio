import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)

final class PushLevelTests {
    @Test
    func test_hot_debounce_is_zero() {
        #expect(PushLevel.hot.debounce == .zero)
    }

    @Test
    func test_warm_debounce_is_12ms() {
        #expect(PushLevel.warm.debounce == .milliseconds(12))
    }

    @Test
    func test_cold_debounce_is_32ms() {
        #expect(PushLevel.cold.debounce == .milliseconds(32))
    }

    @Test
    func test_pushOp_rawValues() {
        #expect(PushOp.merge.rawValue == "merge")
        #expect(PushOp.replace.rawValue == "replace")
    }

    @Test
    func test_storeKey_rawValues() {
        #expect(StoreKey.diff.rawValue == "diff")
        #expect(StoreKey.review.rawValue == "review")
        #expect(StoreKey.agent.rawValue == "agent")
        #expect(StoreKey.connection.rawValue == "connection")
    }
}
