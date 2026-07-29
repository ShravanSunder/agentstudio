struct BadInfrastructureAtomAccess<Value> {
    let coreAtoms: CoreAtoms
    let scope: CoreAtomScope
    let appKeyPath: KeyPath<AtomRegistry, Value>
}
