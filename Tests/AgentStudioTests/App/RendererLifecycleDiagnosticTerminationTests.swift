import Foundation
import Testing

@testable import AgentStudio

@Suite("Renderer lifecycle diagnostic termination", .serialized)
@MainActor
struct RendererLifecycleDiagnosticTerminationTests {
    @Test("termination runs on the next AppKit run-loop drain")
    func terminationRunsOnNextAppKitRunLoopDrain() {
        var didInvokeTermination = false

        scheduleRendererLifecycleDiagnosticTermination {
            didInvokeTermination = true
            CFRunLoopStop(CFRunLoopGetMain())
        }

        #expect(!didInvokeTermination)
        CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 1, true)
        #expect(didInvokeTermination)
    }
}
