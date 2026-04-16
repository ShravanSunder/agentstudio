import Observation

@MainActor
@Observable
final class ManagementLayerAtom {
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
