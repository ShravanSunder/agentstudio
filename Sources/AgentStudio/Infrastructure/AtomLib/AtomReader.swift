@MainActor
struct AtomReader {
    func callAsFunction<Value>(_ keyPath: KeyPath<AtomStore, Value>) -> Value {
        AtomScope.store[keyPath: keyPath]
    }
}
