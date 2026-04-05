@MainActor
func atom<Value>(_ keyPath: KeyPath<AtomStore, Value>) -> Value {
    AtomScope.store[keyPath: keyPath]
}

@MainActor
@propertyWrapper
struct Atom<Value> {
    private let keyPath: KeyPath<AtomStore, Value>

    init(_ keyPath: KeyPath<AtomStore, Value>) {
        self.keyPath = keyPath
    }

    var wrappedValue: Value {
        AtomScope.store[keyPath: keyPath]
    }
}
