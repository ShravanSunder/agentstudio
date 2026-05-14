import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct PopoverToggleGateTests {
    @Test("button toggle opens when no dismissal suppression is active")
    func toggle_withoutRecentDismissal_opensPopover() {
        let gate = PopoverToggleGate()
        var isPresented = false

        gate.toggle(isPresented: &isPresented)

        #expect(isPresented == true)
    }

    @Test("system dismissal suppresses the immediately following button toggle")
    func recordSystemDismissal_suppressesImmediateToggle() async {
        let clock = TestPushClock()
        let gate = PopoverToggleGate(clock: clock)
        var isPresented = true

        gate.recordSystemDismissal()
        await clock.waitForPendingSleepCount()
        gate.toggle(isPresented: &isPresented)

        #expect(isPresented == true)
    }

    @Test("button toggle works again after the suppression window expires")
    func suppressionWindowExpiry_allowsToggleAgain() async {
        let clock = TestPushClock()
        let gate = PopoverToggleGate(clock: clock)
        var isPresented = true

        gate.recordSystemDismissal()
        await clock.waitForPendingSleepCount()
        gate.toggle(isPresented: &isPresented)
        #expect(isPresented == true)

        clock.advance(by: .milliseconds(150))
        for _ in 0..<5 {
            await Task.yield()
        }

        gate.toggle(isPresented: &isPresented)

        #expect(isPresented == false)
    }
}
