import Observation

@MainActor
@Observable
package final class AtomRevision {
    package private(set) var value: Int

    package init(value: Int = 0) {
        self.value = value
    }

    package func bump() {
        value += 1
    }
}
