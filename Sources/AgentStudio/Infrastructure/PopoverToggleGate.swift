import Foundation

@MainActor
final class PopoverToggleGate {
    private let clock: any Clock<Duration>
    private let suppressionWindow: Duration
    private var resetTask: Task<Void, Never>?
    private var suppressNextToggle = false

    init(
        clock: any Clock<Duration> = ContinuousClock(),
        suppressionWindow: Duration = .milliseconds(150)
    ) {
        self.clock = clock
        self.suppressionWindow = suppressionWindow
    }

    deinit {
        resetTask?.cancel()
    }

    func toggle(isPresented: inout Bool) {
        if suppressNextToggle {
            suppressNextToggle = false
            return
        }

        isPresented.toggle()
    }

    func recordSystemDismissal() {
        suppressNextToggle = true
        resetTask?.cancel()

        let clock = self.clock
        let suppressionWindow = self.suppressionWindow
        resetTask = Task { @MainActor [weak self] in
            do {
                try await clock.sleep(for: suppressionWindow)
            } catch {
                return
            }

            self?.suppressNextToggle = false
        }
    }
}
