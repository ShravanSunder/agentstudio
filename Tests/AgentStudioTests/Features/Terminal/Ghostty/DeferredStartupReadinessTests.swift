import CoreGraphics
import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)

final class DeferredStartupReadinessTests {
    @Test
    func test_canSchedule_true_whenReady() {
        #expect(
            DeferredStartupReadiness.canSchedule(
                hasSent: false,
                deferredStartupCommand: "zmx attach test",
                hasWindow: true,
                contentSize: CGSize(width: 1200, height: 700)
            ))
    }

    @Test
    func test_canSchedule_false_whenAlreadySent() {
        #expect(
            !(DeferredStartupReadiness.canSchedule(
                hasSent: true,
                deferredStartupCommand: "zmx attach test",
                hasWindow: true,
                contentSize: CGSize(width: 1200, height: 700)
            )))
    }

    @Test
    func test_canSchedule_false_whenCommandMissingOrEmpty() {
        #expect(
            !(DeferredStartupReadiness.canSchedule(
                hasSent: false,
                deferredStartupCommand: nil,
                hasWindow: true,
                contentSize: CGSize(width: 1200, height: 700)
            )))
        #expect(
            !(DeferredStartupReadiness.canSchedule(
                hasSent: false,
                deferredStartupCommand: "",
                hasWindow: true,
                contentSize: CGSize(width: 1200, height: 700)
            )))
    }

    @Test
    func test_canSchedule_false_whenWindowMissing() {
        #expect(
            !(DeferredStartupReadiness.canSchedule(
                hasSent: false,
                deferredStartupCommand: "zmx attach test",
                hasWindow: false,
                contentSize: CGSize(width: 1200, height: 700)
            )))
    }

    @Test
    func test_canSchedule_false_whenSizeInvalid() {
        #expect(
            !(DeferredStartupReadiness.canSchedule(
                hasSent: false,
                deferredStartupCommand: "zmx attach test",
                hasWindow: true,
                contentSize: .zero
            )))
        #expect(
            !(DeferredStartupReadiness.canSchedule(
                hasSent: false,
                deferredStartupCommand: "zmx attach test",
                hasWindow: true,
                contentSize: CGSize(width: 1200, height: 0)
            )))
    }

    @Test
    func test_canExecute_false_whenProcessExited() {
        #expect(
            !(DeferredStartupReadiness.canExecute(
                hasSent: false,
                deferredStartupCommand: "zmx attach test",
                hasWindow: true,
                contentSize: CGSize(width: 1200, height: 700),
                processExited: true
            )))
    }

    @Test
    func test_canExecute_false_whenScheduleConditionsFail() {
        #expect(
            !(DeferredStartupReadiness.canExecute(
                hasSent: false,
                deferredStartupCommand: "zmx attach test",
                hasWindow: false,
                contentSize: CGSize(width: 1200, height: 700),
                processExited: false
            )))
    }

    @Test
    func test_canExecute_true_whenReadyAndProcessAlive() {
        #expect(
            DeferredStartupReadiness.canExecute(
                hasSent: false,
                deferredStartupCommand: "zmx attach test",
                hasWindow: true,
                contentSize: CGSize(width: 1200, height: 700),
                processExited: false
            ))
    }
}
