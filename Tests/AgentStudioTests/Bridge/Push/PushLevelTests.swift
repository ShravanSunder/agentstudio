import XCTest
@testable import AgentStudio

final class PushLevelTests: XCTestCase {
    func test_hot_debounce_is_zero() {
        XCTAssertEqual(PushLevel.hot.debounce, .zero)
    }

    func test_warm_debounce_is_12ms() {
        XCTAssertEqual(PushLevel.warm.debounce, .milliseconds(12))
    }

    func test_cold_debounce_is_32ms() {
        XCTAssertEqual(PushLevel.cold.debounce, .milliseconds(32))
    }

    func test_pushOp_rawValues() {
        XCTAssertEqual(PushOp.merge.rawValue, "merge")
        XCTAssertEqual(PushOp.replace.rawValue, "replace")
    }

    func test_storeKey_rawValues() {
        XCTAssertEqual(StoreKey.diff.rawValue, "diff")
        XCTAssertEqual(StoreKey.review.rawValue, "review")
        XCTAssertEqual(StoreKey.agent.rawValue, "agent")
        XCTAssertEqual(StoreKey.connection.rawValue, "connection")
    }
}
