final class CoreAtoms {
    let goodCoreAtom = GoodCoreAtom()
}

enum CoreAtomScope {}

func readCoreAtom<Value>(_ keyPath: KeyPath<CoreAtoms, Value>) -> Value? {
    nil
}
