import Observation

@MainActor
@Observable
package final class ManagementLayerAtom {
    package private(set) var isActive = false

    package init() {}

    func activate() {
        isActive = true
    }

    package func deactivate() {
        isActive = false
    }

    package func toggle() {
        isActive.toggle()
    }
}
