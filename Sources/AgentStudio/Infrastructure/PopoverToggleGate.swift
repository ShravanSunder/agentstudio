import Foundation

@MainActor
package final class PopoverToggleGate {
    private let delay: AsyncDelay
    private let suppressionWindow: Duration
    private var resetTask: Task<Void, Never>?
    private var suppressNextToggle = false

    package init(
        clock: (any Clock<Duration> & Sendable)? = nil,
        suppressionWindow: Duration = .milliseconds(150)
    ) {
        delay = clock.map(AsyncDelay.clock) ?? .taskSleep
        self.suppressionWindow = suppressionWindow
    }

    deinit {
        resetTask?.cancel()
    }

    package func toggle(isPresented: inout Bool) {
        if suppressNextToggle {
            suppressNextToggle = false
            return
        }

        isPresented.toggle()
    }

    package func recordSystemDismissal() {
        suppressNextToggle = true
        resetTask?.cancel()

        let delay = self.delay
        let suppressionWindow = self.suppressionWindow
        resetTask = Task { @MainActor [weak self] in
            do {
                try await delay.wait(suppressionWindow)
            } catch {
                return
            }

            self?.suppressNextToggle = false
        }
    }
}
