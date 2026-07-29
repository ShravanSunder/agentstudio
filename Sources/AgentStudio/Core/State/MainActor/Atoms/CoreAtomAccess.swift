@MainActor
package func atom<Value>(_ keyPath: KeyPath<CoreAtoms, Value>) -> Value {
    CoreAtomScope.store[keyPath: keyPath]
}
