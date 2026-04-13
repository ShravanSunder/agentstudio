@MainActor
func atom<Value>(_ keyPath: KeyPath<AtomRegistry, Value>) -> Value {
    AtomScope.store[keyPath: keyPath]
}

@MainActor
@propertyWrapper
struct Atom<Value> {
    private let keyPath: KeyPath<AtomRegistry, Value>

    init(_ keyPath: KeyPath<AtomRegistry, Value>) {
        self.keyPath = keyPath
    }

    var wrappedValue: Value {
        AtomScope.store[keyPath: keyPath]
    }
}
