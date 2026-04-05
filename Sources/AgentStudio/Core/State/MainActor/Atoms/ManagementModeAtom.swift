import Observation

@MainActor
@Observable
final class ManagementModeAtom {
    private(set) var isActive = false

    func activate() {
        isActive = true
    }

    func deactivate() {
        isActive = false
    }

    func toggle() {
        isActive.toggle()
    }
}
