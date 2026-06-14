import Observation

@MainActor
@Observable
final class AtomRevision {
    private(set) var value: Int

    init(value: Int = 0) {
        self.value = value
    }

    func bump() {
        value += 1
    }
}
