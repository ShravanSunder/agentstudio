import CoreGraphics
import XCTest

@testable import AgentStudio

final class DeferredStartupReadinessTests: XCTestCase {
    func test_canSchedule_true_whenReady() {
        XCTAssertTrue(
            DeferredStartupReadiness.canSchedule(
                hasSent: false,
                deferredStartupCommand: "zmx attach test",
                hasWindow: true,
                contentSize: CGSize(width: 1200, height: 700)
            )
        )
    }

    func test_canSchedule_false_whenAlreadySent() {
        XCTAssertFalse(
            DeferredStartupReadiness.canSchedule(
                hasSent: true,
                deferredStartupCommand: "zmx attach test",
                hasWindow: true,
                contentSize: CGSize(width: 1200, height: 700)
            )
        )
    }

    func test_canSchedule_false_whenCommandMissingOrEmpty() {
        XCTAssertFalse(
            DeferredStartupReadiness.canSchedule(
                hasSent: false,
                deferredStartupCommand: nil,
                hasWindow: true,
                contentSize: CGSize(width: 1200, height: 700)
            )
        )
        XCTAssertFalse(
            DeferredStartupReadiness.canSchedule(
                hasSent: false,
                deferredStartupCommand: "",
                hasWindow: true,
                contentSize: CGSize(width: 1200, height: 700)
            )
        )
    }

    func test_canSchedule_false_whenWindowMissing() {
        XCTAssertFalse(
            DeferredStartupReadiness.canSchedule(
                hasSent: false,
                deferredStartupCommand: "zmx attach test",
                hasWindow: false,
                contentSize: CGSize(width: 1200, height: 700)
            )
        )
    }

    func test_canSchedule_false_whenSizeInvalid() {
        XCTAssertFalse(
            DeferredStartupReadiness.canSchedule(
                hasSent: false,
                deferredStartupCommand: "zmx attach test",
                hasWindow: true,
                contentSize: .zero
            )
        )
        XCTAssertFalse(
            DeferredStartupReadiness.canSchedule(
                hasSent: false,
                deferredStartupCommand: "zmx attach test",
                hasWindow: true,
                contentSize: CGSize(width: 1200, height: 0)
            )
        )
    }

    func test_canExecute_false_whenProcessExited() {
        XCTAssertFalse(
            DeferredStartupReadiness.canExecute(
                hasSent: false,
                deferredStartupCommand: "zmx attach test",
                hasWindow: true,
                contentSize: CGSize(width: 1200, height: 700),
                processExited: true
            )
        )
    }

    func test_canExecute_false_whenScheduleConditionsFail() {
        XCTAssertFalse(
            DeferredStartupReadiness.canExecute(
                hasSent: false,
                deferredStartupCommand: "zmx attach test",
                hasWindow: false,
                contentSize: CGSize(width: 1200, height: 700),
                processExited: false
            )
        )
    }

    func test_canExecute_true_whenReadyAndProcessAlive() {
        XCTAssertTrue(
            DeferredStartupReadiness.canExecute(
                hasSent: false,
                deferredStartupCommand: "zmx attach test",
                hasWindow: true,
                contentSize: CGSize(width: 1200, height: 700),
                processExited: false
            )
        )
    }
}
