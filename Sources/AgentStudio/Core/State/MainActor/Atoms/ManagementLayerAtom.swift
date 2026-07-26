import Observation

@MainActor
@Observable
package final class ManagementLayerAtom {
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
