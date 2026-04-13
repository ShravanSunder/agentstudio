@MainActor
struct AtomReader {
    func callAsFunction<Value>(_ keyPath: KeyPath<AtomRegistry, Value>) -> Value {
        AtomScope.store[keyPath: keyPath]
    }
}
